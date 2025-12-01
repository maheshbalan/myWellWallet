import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../services/mcp_client.dart';
import '../services/database_service.dart';
import '../models/fetch_status.dart';
import 'dart:convert';

/// Service for synchronizing FHIR data from MCP Gateway to local database
class DataSyncService {
  final MCPClient mcpClient;
  final DatabaseService databaseService;
  
  // Callback for progress updates
  Function(FetchStatus)? onProgressUpdate;
  
  // List of FHIR resource types to fetch
  static const List<String> resourceTypes = [
    'Patient',
    'Encounter',
    'Observation',
    'MedicationStatement',
    'Condition',
    'AllergyIntolerance',
    'Immunization',
    'DiagnosticReport',
    'DocumentReference',
    'FamilyMemberHistory',
  ];

  DataSyncService({
    required this.mcpClient,
    required this.databaseService,
  });

  /// Fetch all data for a patient
  Future<FetchSummary> fetchAllData(String patientId) async {
    final statuses = <String, FetchStatus>{};
    final resourceCounts = <String, int>{};
    final errors = <String>[];

    // Initialize statuses
    for (var resourceType in resourceTypes) {
      statuses[resourceType] = FetchStatus(
        resourceType: resourceType,
        status: 'pending',
      );
    }

    try {
      // Step 1: Truncate local FHIR tables
      _updateStatus(statuses, 'Patient', 'in_progress', progress: 0.1);
      await _truncateFHIRTables(patientId);

      // Step 2: Fetch Patient resource
      _updateStatus(statuses, 'Patient', 'in_progress', progress: 0.2);
      final patientCount = await _fetchResource(
        patientId,
        'Patient',
        '/Patient/$patientId',
        statuses,
      );
      resourceCounts['Patient'] = patientCount;
      _updateStatus(statuses, 'Patient', 'completed', count: patientCount);

      // Step 3: Fetch other resources in sequence
      int stepIndex = 0;
      for (var resourceType in resourceTypes.skip(1)) {
        stepIndex++;
        final progress = 0.3 + (stepIndex / resourceTypes.length) * 0.7;
        
        _updateStatus(statuses, resourceType, 'in_progress', progress: progress);
        
        try {
          final count = await _fetchResourceForPatient(
            patientId,
            resourceType,
            statuses,
          );
          resourceCounts[resourceType] = count;
          _updateStatus(statuses, resourceType, 'completed', count: count);
        } catch (e) {
          errors.add('$resourceType: $e');
          _updateStatus(
            statuses,
            resourceType,
            'error',
            errorMessage: e.toString(),
          );
        }
      }

      return FetchSummary(
        resourceCounts: resourceCounts,
        totalResources: resourceCounts.values.fold(0, (a, b) => a + b),
        completedAt: DateTime.now(),
        errors: errors,
      );
    } catch (e) {
      debugPrint('Error in fetchAllData: $e');
      rethrow;
    }
  }

  /// Truncate all FHIR tables for a patient
  Future<void> _truncateFHIRTables(String patientId) async {
    try {
      await databaseService.deletePatientBundle(patientId);
      debugPrint('Truncated FHIR tables for patient: $patientId');
    } catch (e) {
      debugPrint('Error truncating tables: $e');
      rethrow;
    }
  }

  /// Fetch a specific resource for a patient
  Future<int> _fetchResourceForPatient(
    String patientId,
    String resourceType,
    Map<String, FetchStatus> statuses,
  ) async {
    // Map resource types to FHIR search paths
    final pathMap = {
      'Encounter': '/Encounter?subject=Patient/$patientId&_count=1000',
      'Observation': '/Observation?subject=Patient/$patientId&_count=1000',
      'MedicationStatement': '/MedicationStatement?subject=Patient/$patientId&_count=1000',
      'Condition': '/Condition?subject=Patient/$patientId&_count=1000',
      'AllergyIntolerance': '/AllergyIntolerance?patient=Patient/$patientId&_count=1000',
      'Immunization': '/Immunization?patient=Patient/$patientId&_count=1000',
      'DiagnosticReport': '/DiagnosticReport?subject=Patient/$patientId&_count=1000',
      'DocumentReference': '/DocumentReference?subject=Patient/$patientId&_count=1000',
      'FamilyMemberHistory': '/FamilyMemberHistory?patient=Patient/$patientId&_count=1000',
    };

    final path = pathMap[resourceType];
    if (path == null) {
      throw Exception('Unknown resource type: $resourceType');
    }

    return await _fetchResource(patientId, resourceType, path, statuses);
  }

  /// Fetch a resource using MCP tool
  Future<int> _fetchResource(
    String patientId,
    String resourceType,
    String path,
    Map<String, FetchStatus> statuses,
  ) async {
    try {
      // Determine the appropriate MCP tool based on resource type
      final toolMap = {
        'Patient': 'request_patient_resource',
        'Encounter': 'request_encounter_resource',
        'Observation': 'request_observation_resource',
        'MedicationStatement': 'request_medication_resource',
        'Condition': 'request_condition_resource',
        'AllergyIntolerance': 'request_allergy_intolerance_resource',
        'Immunization': 'request_immunization_resource',
        'DiagnosticReport': 'request_document_reference_resource', // May need generic
        'DocumentReference': 'request_document_reference_resource',
        'FamilyMemberHistory': 'request_family_member_history_resource',
      };

      String tool = toolMap[resourceType] ?? 'request_generic_resource';

      // Call MCP tool
      final result = await mcpClient.callTool(tool, {
        'request': {
          'method': 'GET',
          'path': path,
          'body': null,
        }
      });

      // Parse response
      var resultData = result['result'];
      
      // Handle structuredContent or content format
      if (resultData is Map && resultData.containsKey('structuredContent')) {
        final structured = resultData['structuredContent'] as Map;
        if (structured.containsKey('result')) {
          resultData = structured['result'] as Map;
        }
      }
      
      if (resultData is Map && resultData.containsKey('content')) {
        final content = resultData['content'] as List;
        if (content.isNotEmpty) {
          final contentItem = content[0] as Map;
          if (contentItem.containsKey('text')) {
            final textContent = contentItem['text'];
            if (textContent is String) {
              resultData = jsonDecode(textContent);
            } else if (textContent is Map) {
              resultData = textContent;
            }
          }
        }
      }

      // Extract Bundle entries
      List<Map<String, dynamic>> resources = [];
      if (resultData is Map && resultData.containsKey('response')) {
        final response = resultData['response'] as Map;
        if (response.containsKey('entry')) {
          final entries = response['entry'] as List;
          resources = entries.map((entry) {
            return entry['resource'] as Map<String, dynamic>;
          }).toList();
        }
      } else if (resultData is Map && resultData.containsKey('resourceType')) {
        // Single resource (not a Bundle)
        resources = [resultData as Map<String, dynamic>];
      }

      // Save resources to database
      int savedCount = 0;
      for (var resource in resources) {
        try {
          await _saveResource(patientId, resource);
          savedCount++;
        } catch (e) {
          debugPrint('Error saving resource: $e');
        }
      }

      // Handle pagination if needed
      // TODO: Implement pagination for large result sets

      return savedCount;
    } catch (e) {
      debugPrint('Error fetching $resourceType: $e');
      rethrow;
    }
  }

  /// Save a single FHIR resource to database
  Future<void> _saveResource(
    String patientId,
    Map<String, dynamic> resource,
  ) async {
    final resourceType = resource['resourceType'] as String?;
    final resourceId = resource['id'] as String?;

    if (resourceType == null || resourceId == null) {
      throw Exception('Invalid resource: missing resourceType or id');
    }

    final db = await databaseService.database;
    final now = DateTime.now().toIso8601String();

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

  /// Update status and notify listeners
  void _updateStatus(
    Map<String, FetchStatus> statuses,
    String resourceType,
    String status, {
    int? count,
    String? errorMessage,
    double? progress,
  }) {
    final current = statuses[resourceType];
    if (current != null) {
      statuses[resourceType] = current.copyWith(
        status: status,
        count: count,
        errorMessage: errorMessage,
        progress: progress,
      );
      
      // Notify progress callback
      if (onProgressUpdate != null) {
        onProgressUpdate!(statuses[resourceType]!);
      }
    }
  }
}

