import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'database_service.dart';

/// Apple Health (HealthKit) integration for iOS.
/// Fetches CGM, heart rate, steps, and blood pressure for diabetes & heart-centric dashboard.
/// Blood test / lab results (e.g. Quest, Sonora Quest) are stored in [health_lab_results].
/// When HealthKit Clinical Records (labResultRecord) is supported by the plugin or a platform
/// channel, request that type and insert into health_lab_results via [DatabaseService.insertHealthLabResults].
class AppleHealthService {
  AppleHealthService({DatabaseService? databaseService})
      : _db = databaseService ?? DatabaseService();

  final DatabaseService _db;
  static final Health _health = Health();

  /// Types we read (diabetes & heart relevant)
  static List<HealthDataType> get _dataTypes => [
        HealthDataType.BLOOD_GLUCOSE,
        HealthDataType.HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
      ];

  static List<HealthDataAccess> get _permissions => _dataTypes
      .map((_) => HealthDataAccess.READ)
      .toList();

  /// True if running on iOS (Apple Health available)
  static bool get isAvailable => Platform.isIOS;

  /// Configure plugin (call once at startup)
  static void configure() {
    if (Platform.isIOS) _health.configure();
  }

  /// Check if user has connected Apple Health (has sync settings)
  Future<bool> isConnected(String userId) async {
    final settings = await _db.getHealthSyncSettings(userId);
    return settings != null;
  }

  /// Get sync settings for the user (for UI)
  Future<Map<String, dynamic>?> getSyncSettings(String userId) async {
    return _db.getHealthSyncSettings(userId);
  }

  /// Request authorization and perform initial sync, then save settings.
  Future<bool> connectAndSync({
    required String userId,
    required int syncIntervalHours,
  }) async {
    if (!Platform.isIOS) return false;

    _health.configure();

    final hasPermissions = await _health.hasPermissions(
      _dataTypes,
      permissions: _permissions,
    );
    if (hasPermissions != true) {
      final granted = await _health.requestAuthorization(
        _dataTypes,
        permissions: _permissions,
      );
      if (!granted) return false;
    }

    await saveSyncSettings(userId, syncIntervalHours);
    await syncFromHealth(userId);
    return true;
  }

  /// Save or update sync settings (e.g. after connecting or changing interval)
  Future<void> saveSyncSettings(String userId, int syncIntervalHours) async {
    final existing = await _db.getHealthSyncSettings(userId);
    final connectedAt = existing != null
        ? (existing['connected_at'] as DateTime)
        : DateTime.now();
    await _db.saveHealthSyncSettings(
      userId: userId,
      syncIntervalHours: syncIntervalHours,
      lastSyncedAt: existing?['last_synced_at'] as DateTime?,
      connectedAt: connectedAt,
    );
  }

  /// Fetch data from HealthKit and store in local DB.
  Future<SyncResult> syncFromHealth(String userId) async {
    if (!Platform.isIOS) {
      return const SyncResult(success: false, message: 'Apple Health is only available on iOS');
    }

    final now = DateTime.now();
    // Fetch last 90 days for initial/sync
    final start = now.subtract(const Duration(days: 90));

    try {
      final points = await _health.getHealthDataFromTypes(
        types: _dataTypes,
        startTime: start,
        endTime: now,
      );
      final deduped = _health.removeDuplicates(points);

      final glucose = <Map<String, dynamic>>[];
      final heartRate = <Map<String, dynamic>>[];
      final steps = <Map<String, dynamic>>[];
      final systolic = <Map<String, dynamic>>[];
      final diastolic = <Map<String, dynamic>>[];

      for (final p in deduped) {
        final num? value = _numericValue(p);
        if (value == null) continue;

        final id = '${p.sourceId}_${p.dateFrom.millisecondsSinceEpoch}';
        final recorded = p.dateTo;

        switch (p.type) {
          case HealthDataType.BLOOD_GLUCOSE:
            glucose.add({
              'id': id,
              'value': value,
              'unit': 'mg/dL',
              'recorded_at': recorded,
              'source_bundle_id': p.sourceId,
            });
            break;
          case HealthDataType.HEART_RATE:
            heartRate.add({
              'id': id,
              'value': value,
              'unit': 'bpm',
              'recorded_at': recorded,
              'source_bundle_id': p.sourceId,
            });
            break;
          case HealthDataType.STEPS:
            steps.add({
              'id': id,
              'count': value.toInt(),
              'distance_meters': null,
              'start_at': p.dateFrom,
              'end_at': p.dateTo,
              'source_bundle_id': p.sourceId,
            });
            break;
          case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
            systolic.add({
              'id': '${id}_s',
              'systolic': value,
              'recorded_at': recorded,
              'source_bundle_id': p.sourceId,
            });
            break;
          case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
            diastolic.add({
              'id': '${id}_d',
              'diastolic': value,
              'recorded_at': recorded,
              'source_bundle_id': p.sourceId,
            });
            break;
          default:
            break;
        }
      }

      // Pair systolic/diastolic by time (within 1 minute)
      final bloodPressure = _pairBloodPressure(systolic, diastolic);

      await _db.insertHealthGlucose(userId, glucose);
      await _db.insertHealthHeartRate(userId, heartRate);
      await _db.insertHealthSteps(userId, steps);
      await _db.insertHealthBloodPressure(userId, bloodPressure);
      await _db.updateHealthLastSynced(userId);

      return SyncResult(
      success: true,
      glucoseCount: glucose.length,
      heartRateCount: heartRate.length,
      stepsCount: steps.length,
      bloodPressureCount: bloodPressure.length,
    );
    } catch (e, st) {
      debugPrint('AppleHealth sync error: $e');
      debugPrint('$st');
      return SyncResult(success: false, message: e.toString());
    }
  }

  num? _numericValue(HealthDataPoint p) {
    try {
      final v = p.value;
      if (v is NumericHealthValue) return v.numericValue;
    } catch (_) {}
    return null;
  }

  List<Map<String, dynamic>> _pairBloodPressure(
    List<Map<String, dynamic>> systolicList,
    List<Map<String, dynamic>> diastolicList,
  ) {
    final results = <Map<String, dynamic>>[];
    for (final s in systolicList) {
      final t = s['recorded_at'] as DateTime;
      Map<String, dynamic>? match;
      for (final d in diastolicList) {
        if ((d['recorded_at'] as DateTime).difference(t).inSeconds.abs() < 60) {
          match = d;
          break;
        }
      }
      results.add({
        'id': '${s['id']}_bp',
        'systolic': s['systolic'],
        'diastolic': match != null ? match['diastolic'] as num : 0.0,
        'unit': 'mmHg',
        'recorded_at': t,
        'source_bundle_id': s['source_bundle_id'],
      });
    }
    return results;
  }

  /// Whether a sync is due based on user's interval
  Future<bool> isSyncDue(String userId) async {
    final settings = await _db.getHealthSyncSettings(userId);
    if (settings == null) return false;
    final last = settings['last_synced_at'] as DateTime?;
    if (last == null) return true;
    final hours = settings['sync_interval_hours'] as int;
    return DateTime.now().difference(last).inHours >= hours;
  }
}

class SyncResult {
  const SyncResult({
    required this.success,
    this.message,
    this.glucoseCount = 0,
    this.heartRateCount = 0,
    this.stepsCount = 0,
    this.bloodPressureCount = 0,
  });
  final bool success;
  final String? message;
  final int glucoseCount;
  final int heartRateCount;
  final int stepsCount;
  final int bloodPressureCount;
}
