import 'dart:convert';
import 'dart:math';

import 'database_service.dart';
import 'log_service.dart';
import 'oneup_auth_client.dart';
import 'oneup_fhir_client.dart';
import 'oneup_token_store.dart';
import '../config/oneup_config.dart';

class OneUpProviderChoice {
  const OneUpProviderChoice({
    required this.displayName,
    required this.kind,
    this.authorizeUrl = '',
  });

  final String displayName;
  final String kind;
  final String authorizeUrl;

  /// Sandbox lists only the demo plan. The search box filters this list.
  static const sandboxChoices = <OneUpProviderChoice>[
    OneUpProviderChoice(displayName: 'Demo Health Plan', kind: 'health-plan'),
  ];
}

class OneUpSyncResult {
  const OneUpSyncResult._({this.cancelled = false, this.message, this.status});

  const OneUpSyncResult.cancelled() : this._(cancelled: true);

  const OneUpSyncResult.ok(String status) : this._(status: status);

  const OneUpSyncResult.fail(String message) : this._(message: message);

  final bool cancelled;
  final String? message;
  final String? status;

  bool get succeeded => status == 'connected' || status == 'incomplete';
}

/// Connects one plan, stores the token in the Keychain, and writes FHIR rows
/// tagged for that connection.
class OneUpSyncService {
  OneUpSyncService({
    DatabaseService? database,
    OneUpAuthClient? auth,
    OneUpFhirClient? fhir,
    OneUpTokenStore? tokens,
  })  : _database = database ?? DatabaseService(),
        _auth = auth ?? OneUpAuthClient(),
        _fhir = fhir ?? OneUpFhirClient(),
        _tokens = tokens ?? OneUpTokenStore.instance;

  final DatabaseService _database;
  final OneUpAuthClient _auth;
  final OneUpFhirClient _fhir;
  final OneUpTokenStore _tokens;

  Future<OneUpSyncResult> connect({
    required String userId,
    required OneUpProviderChoice choice,
    String? existingConnectionId,
    int syncIntervalHours = 24,
  }) async {
    if (!OneUpConfig.hasCredentials) {
      return const OneUpSyncResult.fail(
        'This build has no 1up sandbox client. Copy config/oneup_local.example.json '
        'to config/oneup_local.json, fill in the client, and rebuild with '
        '--dart-define-from-file=config/oneup_local.json.',
      );
    }

    final state = _auth.newState();
    final uri = _auth.authorizeUri(state: state, authorizeUrl: choice.authorizeUrl);
    String callback;
    try {
      callback = await _auth.openAuthorize(uri);
    } on OneUpAuthCancelled {
      return const OneUpSyncResult.cancelled();
    } on OneUpAuthException catch (e) {
      return OneUpSyncResult.fail(e.message);
    }

    String code;
    try {
      code = _auth.codeFromCallback(callbackUrl: callback, expectedState: state);
    } on OneUpAuthException catch (e) {
      return OneUpSyncResult.fail(e.message);
    }

    OneUpToken token;
    try {
      final issued = await _auth.exchangeCode(code);
      final previous = existingConnectionId == null
          ? null
          : await _tokens.read(existingConnectionId);
      token = OneUpToken(
        accessToken: issued.accessToken,
        refreshToken: issued.refreshToken ?? previous?.refreshToken,
        expiresAt: issued.expiresAt,
      );
    } on OneUpAuthException catch (e) {
      return OneUpSyncResult.fail(e.message);
    }

    final connectionId = existingConnectionId ?? _newId();
    await _tokens.write(connectionId, token);
    await _database.upsertOneUpConnection(
      id: connectionId,
      userId: userId,
      displayName: choice.displayName,
      kind: choice.kind,
      authorizeUrl: choice.authorizeUrl.isEmpty ? OneUpConfig.authorizeUrl : choice.authorizeUrl,
      syncIntervalHours: syncIntervalHours,
      status: 'incomplete',
    );
    return _download(connectionId: connectionId, token: token);
  }

  /// Refresh on a connection row. Uses the refresh token when expiry is close.
  Future<OneUpSyncResult> refreshConnection(String connectionId) async {
    final row = await _database.getOneUpConnection(connectionId);
    if (row == null) {
      return const OneUpSyncResult.fail('That provider is no longer on this phone.');
    }
    try {
      final token = await _tokenForDownload(connectionId);
      return _download(connectionId: connectionId, token: token);
    } on _NeedsReconnect {
      await _markReconnect(connectionId);
      return const OneUpSyncResult.fail('Sign in to this provider again.');
    } on OneUpAuthException catch (e) {
      return OneUpSyncResult.fail(e.message);
    }
  }

  /// On resume: download again when a connection is older than its interval.
  Future<void> syncIfDue(String userId) async {
    final rows = await _database.listOneUpConnections(userId);
    final now = DateTime.now();
    for (final row in rows) {
      final status = row['status'] as String? ?? '';
      if (status == 'needs_reconnect') continue;
      final last = DateTime.tryParse(row['last_synced_at'] as String? ?? '');
      final hours = row['sync_interval_hours'] as int? ?? 24;
      final due = last == null || now.difference(last) >= Duration(hours: hours);
      if (!due) continue;
      final id = row['id'] as String;
      try {
        await refreshConnection(id);
      } catch (e) {
        LogService.log('1up sync skipped for a connection: $e');
      }
    }
  }

  Future<OneUpSyncResult> _download({
    required String connectionId,
    required OneUpToken token,
  }) async {
    var access = token.accessToken;
    List<Map<String, dynamic>> patients;
    try {
      patients = await _readWithRefresh(connectionId, 'Patient', access, (next) => access = next);
    } on _NeedsReconnect {
      await _markReconnect(connectionId);
      return const OneUpSyncResult.fail('Sign in to this provider again.');
    } catch (e) {
      LogService.log('1up Patient read failed.');
      await _database.updateOneUpStatus(connectionId, status: 'incomplete');
      return const OneUpSyncResult.fail('Could not read the member record. Use Refresh to try again.');
    }

    final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['resourceType'] == 'Patient' && r?['id'] is String,
          orElse: () => null,
        );
    if (patient == null) {
      await _database.updateOneUpStatus(connectionId, status: 'incomplete');
      return const OneUpSyncResult.fail('1up did not return a Patient. Use Refresh to try again.');
    }
    final patientId = patient['id'] as String;
    final patientName = _patientName(patient);

    var incomplete = false;
    await _storeType(
      connectionId: connectionId,
      patientId: patientId,
      resourceType: 'Patient',
      resources: patients.where((r) => r['resourceType'] == 'Patient').toList(),
    );

    for (final type in OneUpFhirClient.requiredTypes.skip(1)) {
      try {
        final rows = await _readWithRefresh(connectionId, type, access, (next) => access = next);
        await _storeType(
          connectionId: connectionId,
          patientId: patientId,
          resourceType: type,
          resources: rows,
        );
      } on _NeedsReconnect {
        await _markReconnect(connectionId);
        return const OneUpSyncResult.fail('Sign in to this provider again.');
      } catch (e) {
        LogService.log('1up required read failed for $type.');
        incomplete = true;
        break;
      }
    }

    if (!incomplete) {
      for (final type in OneUpFhirClient.optionalTypes) {
        try {
          final rows = await _readWithRefresh(connectionId, type, access, (next) => access = next);
          await _storeType(
            connectionId: connectionId,
            patientId: patientId,
            resourceType: type,
            resources: rows,
          );
        } on _NeedsReconnect {
          await _markReconnect(connectionId);
          return const OneUpSyncResult.fail('Sign in to this provider again.');
        } on OneUpUnsupported {
          continue;
        } catch (e) {
          LogService.log('1up optional read skipped for $type.');
        }
      }
    }

    await _database.savePatientBundle(
      patientId: patientId,
      patientName: patientName,
      fhirBundle: {
        'resourceType': 'Bundle',
        'type': 'collection',
        'entry': [
          {'resource': patient},
        ],
      },
      connectionId: connectionId,
    );

    final status = incomplete ? 'incomplete' : 'connected';
    await _database.updateOneUpStatus(
      connectionId,
      status: status,
      fhirPatientId: patientId,
      lastSyncedAt: DateTime.now(),
    );
    if (incomplete) {
      return const OneUpSyncResult.ok('incomplete');
    }
    return const OneUpSyncResult.ok('connected');
  }

  Future<List<Map<String, dynamic>>> _readWithRefresh(
    String connectionId,
    String type,
    String accessToken,
    void Function(String accessToken) onRotated,
  ) async {
    try {
      return await _fhir.readAll(type, accessToken);
    } on OneUpUnauthorized {
      final rotated = await _refreshOrThrow(connectionId);
      onRotated(rotated.accessToken);
      try {
        return await _fhir.readAll(type, rotated.accessToken);
      } on OneUpUnauthorized {
        throw _NeedsReconnect();
      }
    }
  }

  Future<OneUpToken> _tokenForDownload(String connectionId) async {
    final current = await _tokens.read(connectionId);
    if (current == null) throw _NeedsReconnect();
    if (!current.expiresSoon) return current;
    return _refreshOrThrow(connectionId);
  }

  Future<OneUpToken> _refreshOrThrow(String connectionId) async {
    final current = await _tokens.read(connectionId);
    final refreshToken = current?.refreshToken;
    if (current == null || refreshToken == null) throw _NeedsReconnect();
    try {
      final issued = await _auth.refresh(refreshToken);
      final merged = OneUpToken(
        accessToken: issued.accessToken,
        refreshToken: issued.refreshToken ?? current.refreshToken,
        expiresAt: issued.expiresAt ?? current.expiresAt,
      );
      await _tokens.write(connectionId, merged);
      return merged;
    } on OneUpAuthException {
      throw _NeedsReconnect();
    }
  }

  Future<void> _markReconnect(String connectionId) async {
    await _tokens.delete(connectionId);
    await _database.updateOneUpStatus(connectionId, status: 'needs_reconnect');
  }

  Future<void> _storeType({
    required String connectionId,
    required String patientId,
    required String resourceType,
    required List<Map<String, dynamic>> resources,
  }) async {
    final tagged = [for (final resource in resources) _tag(resource, connectionId)];
    await _database.replaceConnectionResources(
      connectionId: connectionId,
      patientId: patientId,
      resourceType: resourceType,
      resources: tagged,
    );
  }

  Map<String, dynamic> _tag(Map<String, dynamic> resource, String connectionId) {
    final copy = jsonDecode(jsonEncode(resource)) as Map<String, dynamic>;
    final meta = copy['meta'] is Map
        ? Map<String, dynamic>.from(copy['meta'] as Map)
        : <String, dynamic>{};
    meta['source'] = 'https://1up.health';
    final existing = meta['tag'];
    meta['tag'] = [
      if (existing is List) ...existing,
      {'system': 'urn:mywellwallet:provenance', 'code': '1up-patient-access'},
      {'system': 'urn:mywellwallet:connection', 'code': connectionId},
    ];
    copy['meta'] = meta;
    return copy;
  }

  String _patientName(Map<String, dynamic> patient) {
    final names = patient['name'];
    if (names is List && names.isNotEmpty && names.first is Map) {
      final name = Map<String, dynamic>.from(names.first as Map);
      final text = name['text'];
      if (text is String && text.trim().isNotEmpty) return text.trim();
      final given = name['given'];
      final givenText = given is List ? given.join(' ') : '';
      final family = name['family'] is String ? name['family'] as String : '';
      final combined = '$givenText $family'.trim();
      if (combined.isNotEmpty) return combined;
    }
    return 'Member';
  }

  String _newId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _NeedsReconnect implements Exception {}
