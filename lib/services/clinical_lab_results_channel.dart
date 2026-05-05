import 'dart:io';

import 'package:flutter/services.dart';

/// Platform channel for iOS HealthKit **Clinical Records** (`labResultRecord`)
/// FHIR payloads. Regular `health` plugin types do not cover institution labs (e.g. Quest / Sonora Quest).
class ClinicalLabResultsChannel {
  ClinicalLabResultsChannel._();
  static const MethodChannel _ch =
      MethodChannel('com.mywellwallet/clinical_lab_results');

  static Future<bool> isHealthRecordsAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      final v = await _ch.invokeMethod<bool>('isHealthRecordsAvailable');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Triggers Apple's permission sheet for Clinical **Lab Results** read access (if applicable).
  static Future<bool> requestAuthorization() async {
    if (!Platform.isIOS) return false;
    try {
      final v = await _ch.invokeMethod<dynamic>('requestAuthorization');
      if (v is bool) return v;
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns rows compatible with [DatabaseService.insertHealthLabResults].
  static Future<List<Map<String, dynamic>>> syncLabResults({int days = 730}) async {
    if (!Platform.isIOS) return [];
    try {
      final raw = await _ch.invokeMethod<List<dynamic>?>(
        'syncLabResults',
        <String, dynamic>{'days': days},
      );
      if (raw == null) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    } catch (_) {
      return [];
    }
  }
}
