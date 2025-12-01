import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../models/user.dart';

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
      version: 2,
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
        updated_at TEXT NOT NULL
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
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database migrations here
    if (oldVersion < 2) {
      // Add fetch_summaries table
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

  // ========== FHIR Patient Bundle Methods ==========

  /// Save FHIR patient bundle
  Future<void> savePatientBundle({
    required String patientId,
    required String patientName,
    required Map<String, dynamic> fhirBundle,
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

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

