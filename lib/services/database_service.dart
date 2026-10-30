import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../models/user.dart';
import '../models/fetch_status.dart';
import 'sql_guard.dart';

/// Database service for local persistence
/// Stores user profiles and FHIR patient bundles
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'mywellwallet.db');

    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // User profile table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        date_of_birth TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // FHIR Patient bundles table
    await db.execute('''
      CREATE TABLE fhir_patients (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        patient_name TEXT NOT NULL,
        fhir_bundle TEXT NOT NULL,
        last_synced TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        connection_id TEXT
      )
    ''');

    // FHIR Resources table (for storing individual resources from bundles)
    await db.execute('''
      CREATE TABLE fhir_resources (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        resource_type TEXT NOT NULL,
        resource_id TEXT NOT NULL,
        resource_data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        connection_id TEXT,
        UNIQUE(patient_id, resource_type, resource_id)
      )
    ''');

    // Fetch summaries table
    await db.execute('''
      CREATE TABLE fetch_summaries (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        total_resources INTEGER NOT NULL,
        resource_counts TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        errors TEXT,
        stored_in_database INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // Indexes for faster queries
    await db.execute('CREATE INDEX idx_fhir_patients_patient_id ON fhir_patients(patient_id)');
    await db.execute('CREATE INDEX idx_fhir_resources_patient_id ON fhir_resources(patient_id)');
    await db.execute('CREATE INDEX idx_fhir_resources_type ON fhir_resources(resource_type)');
    await db.execute('CREATE INDEX idx_fetch_summaries_patient_id ON fetch_summaries(patient_id)');

    await _createHealthTables(db);
    await _createOneUpTables(db);
  }

  Future<void> _createHealthTables(Database db) async {
    await db.execute('''
      CREATE TABLE health_glucose (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        value_real REAL NOT NULL,
        unit TEXT NOT NULL DEFAULT 'mg/dL',
        source_bundle_id TEXT,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE health_heart_rate (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        value_real REAL NOT NULL,
        unit TEXT NOT NULL DEFAULT 'bpm',
        source_bundle_id TEXT,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE health_steps (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        count INTEGER NOT NULL,
        distance_meters REAL,
        start_at TEXT NOT NULL,
        end_at TEXT NOT NULL,
        source_bundle_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE health_blood_pressure (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        systolic_real REAL NOT NULL,
        diastolic_real REAL NOT NULL,
        unit TEXT NOT NULL DEFAULT 'mmHg',
        source_bundle_id TEXT,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE health_sync_settings (
        user_id TEXT PRIMARY KEY,
        sync_interval_hours INTEGER NOT NULL DEFAULT 24,
        last_synced_at TEXT,
        connected_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_health_glucose_user_recorded ON health_glucose(user_id, recorded_at DESC)');
    await db.execute('CREATE INDEX idx_health_heart_rate_user_recorded ON health_heart_rate(user_id, recorded_at DESC)');
    await db.execute('CREATE INDEX idx_health_steps_user_created ON health_steps(user_id, created_at DESC)');
    await db.execute('CREATE INDEX idx_health_blood_pressure_user_recorded ON health_blood_pressure(user_id, recorded_at DESC)');

    // Blood test / lab results (e.g. from Apple Health Clinical Records, Quest/Sonora Quest, or FHIR)
    await db.execute('''
      CREATE TABLE health_lab_results (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        loinc_code TEXT,
        value_numeric REAL,
        value_string TEXT,
        unit TEXT,
        reference_range_low REAL,
        reference_range_high REAL,
        reference_range_text TEXT,
        source_name TEXT,
        source_bundle_id TEXT,
        specimen_type TEXT,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_health_lab_results_user_recorded ON health_lab_results(user_id, recorded_at DESC)');
  }

  Future<void> _createOneUpTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS oneup_connections (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        kind TEXT NOT NULL,
        system_id TEXT,
        authorize_url TEXT NOT NULL,
        fhir_patient_id TEXT,
        last_synced_at TEXT,
        sync_interval_hours INTEGER NOT NULL DEFAULT 24,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_oneup_connections_user ON oneup_connections(user_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS fetch_summaries (
          id TEXT PRIMARY KEY,
          patient_id TEXT NOT NULL,
          total_resources INTEGER NOT NULL,
          resource_counts TEXT NOT NULL,
          completed_at TEXT NOT NULL,
          errors TEXT,
          stored_in_database INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_fetch_summaries_patient_id ON fetch_summaries(patient_id)');
    }
    if (oldVersion < 3) {
      await _createHealthTables(db);
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS health_lab_results (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          name TEXT NOT NULL,
          loinc_code TEXT,
          value_numeric REAL,
          value_string TEXT,
          unit TEXT,
          reference_range_low REAL,
          reference_range_high REAL,
          reference_range_text TEXT,
          source_name TEXT,
          source_bundle_id TEXT,
          specimen_type TEXT,
          recorded_at TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_health_lab_results_user_recorded ON health_lab_results(user_id, recorded_at DESC)');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE fhir_patients ADD COLUMN connection_id TEXT');
      await db.execute('ALTER TABLE fhir_resources ADD COLUMN connection_id TEXT');
      await _createOneUpTables(db);
    }
  }

  // ========== User Profile Methods ==========

  /// Save or update user profile
  Future<void> saveUser(User user) async {
    final db = await database;
    await db.insert(
      'users',
      {
        'id': user.id,
        'name': user.name,
        'email': user.email,
        'date_of_birth': user.dateOfBirth?.toIso8601String(),
        'created_at': user.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get user profile by ID
  Future<User?> getUser(String userId) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      dateOfBirth: map['date_of_birth'] != null
          ? DateTime.parse(map['date_of_birth'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Get all users (should only be one for this app)
  Future<List<User>> getAllUsers() async {
    final db = await database;
    final maps = await db.query('users', orderBy: 'created_at DESC');

    return maps.map((map) => User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      dateOfBirth: map['date_of_birth'] != null
          ? DateTime.parse(map['date_of_birth'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    )).toList();
  }

  /// Check if user exists
  Future<bool> userExists() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  /// Delete user
  Future<void> deleteUser(String userId) async {
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  /// Delete all data from all tables (for app reset)
  Future<void> deleteAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('users');
      await txn.delete('fhir_patients');
      await txn.delete('fhir_resources');
      await txn.delete('fetch_summaries');
      await txn.delete('health_glucose');
      await txn.delete('health_heart_rate');
      await txn.delete('health_steps');
      await txn.delete('health_blood_pressure');
      await txn.delete('health_sync_settings');
      await txn.delete('health_lab_results');
      await txn.delete('oneup_connections');
    });
  }

  /// Run a SELECT chosen by MedGemma. Writes are rejected by [SqlGuard].
  Future<List<Map<String, dynamic>>> runReadOnlySelect(String sql) async {
    final safe = SqlGuard.prepare(sql);
    final db = await database;
    final rows = await db.rawQuery(safe);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<String>> listFhirPatientIds() async {
    final db = await database;
    final rows = await db.query('fhir_patients', columns: ['patient_id']);
    return [
      for (final row in rows)
        if (row['patient_id'] is String) row['patient_id'] as String,
    ];
  }

  /// Clinic rows of the given FHIR types. [oneUpOnly] keeps 1up-tagged rows;
  /// otherwise those tagged rows are left out.
  Future<List<Map<String, dynamic>>> fhirResourcesByTypes({
    required List<String> resourceTypes,
    required bool oneUpOnly,
    bool laboratoryObservations = false,
    int limit = 40,
  }) async {
    if (resourceTypes.isEmpty && !laboratoryObservations) return [];
    final db = await database;
    final args = <Object?>[];
    final parts = <String>[];
    if (resourceTypes.isNotEmpty) {
      final marks = List.filled(resourceTypes.length, '?').join(', ');
      parts.add('resource_type IN ($marks)');
      args.addAll(resourceTypes);
    }
    if (laboratoryObservations) {
      parts.add("(resource_type = 'Observation' AND resource_data LIKE '%laboratory%')");
    }
    var where = '(${parts.join(' OR ')})';
    if (oneUpOnly) {
      where += " AND resource_data LIKE ?";
      args.add('%1up-patient-access%');
    } else {
      where += " AND resource_data NOT LIKE ?";
      args.add('%1up-patient-access%');
    }
    args.add(limit);
    final rows = await db.rawQuery(
      'SELECT resource_data FROM fhir_resources WHERE $where ORDER BY updated_at DESC LIMIT ?',
      args,
    );
    final decoded = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['resource_data'];
      if (raw is! String) continue;
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) {
          decoded.add(value);
        } else if (value is Map) {
          decoded.add(Map<String, dynamic>.from(value));
        }
      } catch (_) {}
    }
    return decoded;
  }

  /// Observations and reports whose stored JSON mentions [needle].
  /// [needle] must be a single alphanumeric token, not a free-form question.
  Future<List<Map<String, dynamic>>> searchFhirByText({
    required String needle,
    required bool oneUpOnly,
    int limit = 15,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9]{3,40}$').hasMatch(needle)) return [];
    final db = await database;
    final args = <Object?>['%$needle%', limit];
    var where =
        "resource_type IN ('Observation', 'DiagnosticReport') AND resource_data LIKE ?";
    if (oneUpOnly) {
      where += " AND resource_data LIKE '%1up-patient-access%'";
    } else {
      where += " AND resource_data NOT LIKE '%1up-patient-access%'";
    }
    final rows = await db.rawQuery(
      'SELECT resource_data FROM fhir_resources WHERE $where ORDER BY updated_at DESC LIMIT ?',
      args,
    );
    final decoded = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['resource_data'];
      if (raw is! String) continue;
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) {
          decoded.add(value);
        } else if (value is Map) {
          decoded.add(Map<String, dynamic>.from(value));
        }
      } catch (_) {}
    }
    return decoded;
  }

  // ========== FHIR Patient Bundle Methods ==========

  /// Save FHIR patient bundle
  Future<void> savePatientBundle({
    required String patientId,
    required String patientName,
    required Map<String, dynamic> fhirBundle,
    String? connectionId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    
    await db.insert(
      'fhir_patients',
      {
        'id': patientId,
        'patient_id': patientId,
        'patient_name': patientName,
        'fhir_bundle': jsonEncode(fhirBundle),
        'last_synced': now,
        'created_at': now,
        'updated_at': now,
        'connection_id': connectionId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Also extract and save individual resources from the bundle
    await _saveResourcesFromBundle(patientId, fhirBundle);
  }

  /// Extract and save individual resources from FHIR bundle
  Future<void> _saveResourcesFromBundle(
    String patientId,
    Map<String, dynamic> bundle,
  ) async {
    if (bundle['entry'] == null) return;

    final db = await database;
    final now = DateTime.now().toIso8601String();
    final entries = bundle['entry'] as List;

    for (var entry in entries) {
      if (entry['resource'] == null) continue;

      final resource = entry['resource'] as Map<String, dynamic>;
      final resourceType = resource['resourceType'] as String?;
      final resourceId = resource['id'] as String?;

      if (resourceType == null || resourceId == null) continue;

      await db.insert(
        'fhir_resources',
        {
          'id': '${patientId}_${resourceType}_$resourceId',
          'patient_id': patientId,
          'resource_type': resourceType,
          'resource_id': resourceId,
          'resource_data': jsonEncode(resource),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Get patient bundle by patient ID
  Future<Map<String, dynamic>?> getPatientBundle(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'fhir_patients',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    return jsonDecode(map['fhir_bundle'] as String) as Map<String, dynamic>;
  }

  /// Get all resources of a specific type for a patient
  Future<List<Map<String, dynamic>>> getPatientResources(
    String patientId,
    String resourceType,
  ) async {
    final db = await database;
    final maps = await db.query(
      'fhir_resources',
      where: 'patient_id = ? AND resource_type = ?',
      whereArgs: [patientId, resourceType],
      orderBy: 'updated_at DESC',
    );

    return maps.map((map) {
      return jsonDecode(map['resource_data'] as String) as Map<String, dynamic>;
    }).toList();
  }

  /// Get all resources for a patient
  Future<List<Map<String, dynamic>>> getAllPatientResources(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'fhir_resources',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'resource_type, updated_at DESC',
    );

    return maps.map((map) {
      return jsonDecode(map['resource_data'] as String) as Map<String, dynamic>;
    }).toList();
  }

  /// Update patient bundle sync time
  Future<void> updatePatientSyncTime(String patientId) async {
    final db = await database;
    await db.update(
      'fhir_patients',
      {
        'last_synced': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
  }

  /// Delete patient bundle and all associated resources
  Future<void> deletePatientBundle(String patientId) async {
    final db = await database;
    await db.delete('fhir_patients', where: 'patient_id = ?', whereArgs: [patientId]);
    await db.delete('fhir_resources', where: 'patient_id = ?', whereArgs: [patientId]);
  }

  /// Truncate all FHIR data for a patient (clear before fresh fetch)
  Future<void> truncatePatientFHIRData(String patientId) async {
    await deletePatientBundle(patientId);
  }

  /// Save fetch summary
  Future<void> saveFetchSummary(String patientId, FetchSummary summary) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = '${patientId}_${summary.completedAt.toIso8601String()}';
    
    await db.insert(
      'fetch_summaries',
      {
        'id': id,
        'patient_id': patientId,
        'total_resources': summary.totalResources,
        'resource_counts': jsonEncode(summary.resourceCounts),
        'completed_at': summary.completedAt.toIso8601String(),
        'errors': summary.errors.isEmpty ? null : jsonEncode(summary.errors),
        'stored_in_database': summary.storedInDatabase ? 1 : 0,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get latest fetch summary for a patient
  Future<FetchSummary?> getLatestFetchSummary(String patientId) async {
    final db = await database;
    final results = await db.query(
      'fetch_summaries',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'completed_at DESC',
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    
    final row = results.first;
    return FetchSummary(
      resourceCounts: Map<String, int>.from(jsonDecode(row['resource_counts'] as String)),
      totalResources: row['total_resources'] as int,
      completedAt: DateTime.parse(row['completed_at'] as String),
      errors: row['errors'] != null 
          ? List<String>.from(jsonDecode(row['errors'] as String))
          : [],
      storedInDatabase: (row['stored_in_database'] as int) == 1,
    );
  }

  /// Get count of resources by type for a patient
  Future<Map<String, int>> getResourceCounts(String patientId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT resource_type, COUNT(*) as count 
      FROM fhir_resources 
      WHERE patient_id = ? 
      GROUP BY resource_type
    ''', [patientId]);

    final counts = <String, int>{};
    for (var map in maps) {
      counts[map['resource_type'] as String] = map['count'] as int;
    }
    return counts;
  }

  // ========== Apple Health Methods ==========

  /// Save or update health sync settings for a user
  Future<void> saveHealthSyncSettings({
    required String userId,
    required int syncIntervalHours,
    DateTime? lastSyncedAt,
    required DateTime connectedAt,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'health_sync_settings',
      {
        'user_id': userId,
        'sync_interval_hours': syncIntervalHours,
        'last_synced_at': lastSyncedAt?.toIso8601String(),
        'connected_at': connectedAt.toIso8601String(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get health sync settings for a user
  Future<Map<String, dynamic>?> getHealthSyncSettings(String userId) async {
    final db = await database;
    final maps = await db.query(
      'health_sync_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final m = maps.first;
    return {
      'user_id': m['user_id'],
      'sync_interval_hours': m['sync_interval_hours'] as int,
      'last_synced_at': m['last_synced_at'] != null ? DateTime.tryParse(m['last_synced_at'] as String) : null,
      'connected_at': DateTime.parse(m['connected_at'] as String),
      'updated_at': DateTime.parse(m['updated_at'] as String),
    };
  }

  /// Update last synced time for health
  Future<void> updateHealthLastSynced(String userId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'health_sync_settings',
      {'last_synced_at': now, 'updated_at': now},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Insert glucose readings (replace by id to avoid duplicates from Health)
  Future<void> insertHealthGlucose(String userId, List<Map<String, dynamic>> readings) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    for (final r in readings) {
      await db.insert(
        'health_glucose',
        {
          'id': r['id'] as String,
          'user_id': userId,
          'value_real': r['value'] as num,
          'unit': r['unit'] as String? ?? 'mg/dL',
          'source_bundle_id': r['source_bundle_id'],
          'recorded_at': (r['recorded_at'] as DateTime).toIso8601String(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Insert heart rate readings
  Future<void> insertHealthHeartRate(String userId, List<Map<String, dynamic>> readings) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    for (final r in readings) {
      await db.insert(
        'health_heart_rate',
        {
          'id': r['id'] as String,
          'user_id': userId,
          'value_real': r['value'] as num,
          'unit': r['unit'] as String? ?? 'bpm',
          'source_bundle_id': r['source_bundle_id'],
          'recorded_at': (r['recorded_at'] as DateTime).toIso8601String(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Insert steps entries
  Future<void> insertHealthSteps(String userId, List<Map<String, dynamic>> entries) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    for (final e in entries) {
      await db.insert(
        'health_steps',
        {
          'id': e['id'] as String,
          'user_id': userId,
          'count': e['count'] as int,
          'distance_meters': e['distance_meters'],
          'start_at': (e['start_at'] as DateTime).toIso8601String(),
          'end_at': (e['end_at'] as DateTime).toIso8601String(),
          'source_bundle_id': e['source_bundle_id'],
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Insert blood pressure readings
  Future<void> insertHealthBloodPressure(String userId, List<Map<String, dynamic>> readings) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    for (final r in readings) {
      await db.insert(
        'health_blood_pressure',
        {
          'id': r['id'] as String,
          'user_id': userId,
          'systolic_real': r['systolic'] as num,
          'diastolic_real': r['diastolic'] as num,
          'unit': r['unit'] as String? ?? 'mmHg',
          'source_bundle_id': r['source_bundle_id'],
          'recorded_at': (r['recorded_at'] as DateTime).toIso8601String(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Get latest glucose readings for user
  Future<List<Map<String, dynamic>>> getHealthGlucose(String userId, {int limit = 100}) async {
    final db = await database;
    final maps = await db.query(
      'health_glucose',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return maps.map((m) => {
      'id': m['id'],
      'value': m['value_real'] as num,
      'unit': m['unit'],
      'recorded_at': DateTime.parse(m['recorded_at'] as String),
    }).toList();
  }

  /// Get latest heart rate readings
  Future<List<Map<String, dynamic>>> getHealthHeartRate(String userId, {int limit = 100}) async {
    final db = await database;
    final maps = await db.query(
      'health_heart_rate',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return maps.map((m) => {
      'id': m['id'],
      'value': m['value_real'] as num,
      'unit': m['unit'],
      'recorded_at': DateTime.parse(m['recorded_at'] as String),
    }).toList();
  }

  /// Get steps entries (e.g. daily aggregates)
  Future<List<Map<String, dynamic>>> getHealthSteps(String userId, {int limit = 60}) async {
    final db = await database;
    final maps = await db.query(
      'health_steps',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'start_at DESC',
      limit: limit,
    );
    return maps.map((m) => {
      'id': m['id'],
      'count': m['count'] as int,
      'distance_meters': m['distance_meters'] != null ? (m['distance_meters'] as num).toDouble() : null,
      'start_at': DateTime.parse(m['start_at'] as String),
      'end_at': DateTime.parse(m['end_at'] as String),
    }).toList();
  }

  /// Get latest blood pressure readings
  Future<List<Map<String, dynamic>>> getHealthBloodPressure(String userId, {int limit = 100}) async {
    final db = await database;
    final maps = await db.query(
      'health_blood_pressure',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return maps.map((m) => {
      'id': m['id'],
      'systolic': m['systolic_real'] as num,
      'diastolic': m['diastolic_real'] as num,
      'unit': m['unit'],
      'recorded_at': DateTime.parse(m['recorded_at'] as String),
    }).toList();
  }

  /// Grouping key for one logical analyte (LOINC preferred over display name).
  static String labGroupingKey(Map<String, dynamic> row) {
    final lc = row['loinc_code'] as String?;
    final trim = lc?.trim();
    if (trim != null && trim.isNotEmpty) return 'lc:$trim';
    final n = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    return 'n:$n';
  }

  /// Latest row per analyte after scanning [maxScan] newest rows (newest-first order).
  Future<List<Map<String, dynamic>>> getHealthLabLatestPerTest(
    String userId, {
    int maxScan = 2000,
  }) async {
    final all = await getHealthLabResults(userId, limit: maxScan);
    final seen = <String>{};
    final latest = <Map<String, dynamic>>[];
    for (final r in all) {
      final k = labGroupingKey(r);
      if (seen.add(k)) latest.add(r);
    }
    latest.sort((a, b) =>
        (b['recorded_at'] as DateTime).compareTo(a['recorded_at'] as DateTime));
    return latest;
  }

  /// History for one test (last [limit] draws, newest first).
  Future<List<Map<String, dynamic>>> getHealthLabHistoryForTest(
    String userId, {
    required String testName,
    String? loincCode,
    int limit = 20,
  }) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    final trimmedLoinc = loincCode?.trim();
    if (trimmedLoinc != null && trimmedLoinc.isNotEmpty) {
      maps = await db.query(
        'health_lab_results',
        columns: null,
        where: 'user_id = ? AND loinc_code = ?',
        whereArgs: [userId, trimmedLoinc],
        orderBy: 'recorded_at DESC',
        limit: limit,
      );
    } else {
      maps = await db.query(
        'health_lab_results',
        columns: null,
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, testName],
        orderBy: 'recorded_at DESC',
        limit: limit,
      );
    }
    return maps.map((m) => {
      'id': m['id'],
      'name': m['name'] as String,
      'loinc_code': m['loinc_code'] as String?,
      'value_numeric': m['value_numeric'] != null ? (m['value_numeric'] as num).toDouble() : null,
      'value_string': m['value_string'] as String?,
      'unit': m['unit'] as String?,
      'reference_range_low': m['reference_range_low'] != null ? (m['reference_range_low'] as num).toDouble() : null,
      'reference_range_high': m['reference_range_high'] != null ? (m['reference_range_high'] as num).toDouble() : null,
      'reference_range_text': m['reference_range_text'] as String?,
      'source_name': m['source_name'] as String?,
      'source_bundle_id': m['source_bundle_id'] as String?,
      'specimen_type': m['specimen_type'] as String?,
      'recorded_at': DateTime.parse(m['recorded_at'] as String),
    }).toList();
  }

  /// Count rows per logical analyte (for badges like “4 readings”).
  Future<Map<String, int>> getHealthLabCountsByGroup(String userId, {int maxScan = 4000}) async {
    final all = await getHealthLabResults(userId, limit: maxScan);
    final m = <String, int>{};
    for (final r in all) {
      final k = labGroupingKey(r);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  /// Insert lab / blood test results (e.g. from Apple Health or FHIR Observation)
  Future<void> insertHealthLabResults(String userId, List<Map<String, dynamic>> results) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    for (final r in results) {
      await db.insert(
        'health_lab_results',
        {
          'id': r['id'] as String,
          'user_id': userId,
          'name': r['name'] as String,
          'loinc_code': r['loinc_code'],
          'value_numeric': r['value_numeric'],
          'value_string': r['value_string'],
          'unit': r['unit'],
          'reference_range_low': r['reference_range_low'],
          'reference_range_high': r['reference_range_high'],
          'reference_range_text': r['reference_range_text'],
          'source_name': r['source_name'],
          'source_bundle_id': r['source_bundle_id'],
          'specimen_type': r['specimen_type'],
          'recorded_at': (r['recorded_at'] is DateTime)
              ? (r['recorded_at'] as DateTime).toIso8601String()
              : r['recorded_at'] as String,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Get blood test / lab results for user in decreasing chronological order
  Future<List<Map<String, dynamic>>> getHealthLabResults(String userId, {int limit = 200}) async {
    final db = await database;
    final maps = await db.query(
      'health_lab_results',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return maps.map((m) => {
      'id': m['id'],
      'name': m['name'] as String,
      'loinc_code': m['loinc_code'] as String?,
      'value_numeric': m['value_numeric'] != null ? (m['value_numeric'] as num).toDouble() : null,
      'value_string': m['value_string'] as String?,
      'unit': m['unit'] as String?,
      'reference_range_low': m['reference_range_low'] != null ? (m['reference_range_low'] as num).toDouble() : null,
      'reference_range_high': m['reference_range_high'] != null ? (m['reference_range_high'] as num).toDouble() : null,
      'reference_range_text': m['reference_range_text'] as String?,
      'source_name': m['source_name'] as String?,
      'source_bundle_id': m['source_bundle_id'] as String?,
      'specimen_type': m['specimen_type'] as String?,
      'recorded_at': DateTime.parse(m['recorded_at'] as String),
    }).toList();
  }

  Future<void> upsertOneUpConnection({
    required String id,
    required String userId,
    required String displayName,
    required String kind,
    required String authorizeUrl,
    required int syncIntervalHours,
    required String status,
    String? systemId,
    String? fhirPatientId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await getOneUpConnection(id);
    await db.insert(
      'oneup_connections',
      {
        'id': id,
        'user_id': userId,
        'display_name': displayName,
        'kind': kind,
        'system_id': systemId ?? existing?['system_id'],
        'authorize_url': authorizeUrl,
        'fhir_patient_id': fhirPatientId ?? existing?['fhir_patient_id'],
        'last_synced_at': existing?['last_synced_at'],
        'sync_interval_hours': syncIntervalHours,
        'status': status,
        'created_at': existing?['created_at'] ?? now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getOneUpConnection(String id) async {
    final db = await database;
    final rows = await db.query(
      'oneup_connections',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, Object?>>> listOneUpConnections(String userId) async {
    final db = await database;
    return db.query(
      'oneup_connections',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateOneUpStatus(
    String id, {
    required String status,
    String? fhirPatientId,
    DateTime? lastSyncedAt,
  }) async {
    final db = await database;
    await db.update(
      'oneup_connections',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
        if (fhirPatientId != null) 'fhir_patient_id': fhirPatientId,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateOneUpInterval(String id, int hours) async {
    final db = await database;
    await db.update(
      'oneup_connections',
      {
        'sync_interval_hours': hours,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Replace one resource type for this connection. Other connections stay.
  Future<void> replaceConnectionResources({
    required String connectionId,
    required String patientId,
    required String resourceType,
    required List<Map<String, dynamic>> resources,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        'fhir_resources',
        where: 'connection_id = ? AND resource_type = ?',
        whereArgs: [connectionId, resourceType],
      );
      for (final resource in resources) {
        final resourceId = resource['id'];
        if (resourceId is! String || resourceId.isEmpty) continue;
        final type = resource['resourceType'] as String? ?? resourceType;
        await txn.insert(
          'fhir_resources',
          {
            'id': '${patientId}_${type}_${resourceId}_$connectionId',
            'patient_id': patientId,
            'resource_type': type,
            'resource_id': resourceId,
            'resource_data': jsonEncode(resource),
            'created_at': now,
            'updated_at': now,
            'connection_id': connectionId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

