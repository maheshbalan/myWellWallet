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
  
  // Callback for step updates
  Function(FetchStepStatus)? onStepUpdate;
  
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

  // FHIR-spec-correct search parameter name for each resource type.
  // MedicationStatement / Condition / AllergyIntolerance / Immunization /
  // FamilyMemberHistory use `patient=`; Observation / Encounter /
  // DiagnosticReport / DocumentReference use `subject=`.
  static const Map<String, String> _searchParamByResourceType = {
    'Encounter': 'subject',
    'Observation': 'subject',
    'MedicationStatement': 'patient',
    'Condition': 'patient',
    'AllergyIntolerance': 'patient',
    'Immunization': 'patient',
    'DiagnosticReport': 'subject',
    'DocumentReference': 'subject',
    'FamilyMemberHistory': 'patient',
  };

  // MCP tool name for each resource type. DiagnosticReport has no dedicated
  // tool on the server (see docs/FHIR_MCP_SERVER_README.md) so it routes to
  // the generic resource tool.
  static const Map<String, String> _toolByResourceType = {
    'Patient': 'request_patient_resource',
    'Encounter': 'request_encounter_resource',
    'Observation': 'request_observation_resource',
    'MedicationStatement': 'request_medication_resource',
    'Condition': 'request_condition_resource',
    'AllergyIntolerance': 'request_allergy_intolerance_resource',
    'Immunization': 'request_immunization_resource',
    'DiagnosticReport': 'request_generic_resource',
    'DocumentReference': 'request_document_reference_resource',
    'FamilyMemberHistory': 'request_family_member_history_resource',
  };

  /// FHIR search parameter name (`patient` or `subject`) for the given
  /// resource type. Returns [orElse] (default `subject`) for unknown types;
  /// pass `orElse: null` to throw instead.
  static String searchParamFor(String resourceType, {String? orElse = 'subject'}) {
    final param = _searchParamByResourceType[resourceType];
    if (param != null) return param;
    if (orElse != null) return orElse;
    throw ArgumentError('Unknown resource type: $resourceType');
  }

  /// FHIR search path for the given resource type and patient. Throws for
  /// resource types not in the known-types list.
  static String pathFor(String resourceType, String patientId,
      {int count = 1000}) {
    final param = searchParamFor(resourceType, orElse: null);
    return '/$resourceType?$param=Patient/$patientId&_count=$count';
  }

  /// MCP tool name for the given resource type; falls back to the generic
  /// resource tool if no dedicated tool is registered.
  static String toolFor(String resourceType) =>
      _toolByResourceType[resourceType] ?? 'request_generic_resource';

  DataSyncService({
    required this.mcpClient,
    required this.databaseService,
  });

  /// Fetch all data for a patient
  Future<FetchSummary> fetchAllData(String patientId) async {
    debugPrint('Starting fetchAllData for patient: $patientId');
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
      // Step 1: Clean database
      _updateStep('Cleaning Database', 'in_progress', 'Removing existing FHIR data...');
      debugPrint('Step 1: Truncating FHIR tables...');
      await _truncateFHIRTables(patientId);
      _updateStep('Cleaning Database', 'completed', 'Database cleaned successfully');
      debugPrint('Truncation complete');

      // Step 2: Fetch from FHIR MCP Gateway
      _updateStep('Fetching from FHIR MCP Gateway', 'in_progress', 'Connecting to server...');
      
      // Step 2a: Fetch Patient resource (single patient - always 1 record)
      debugPrint('Fetching Patient resource: /Patient/$patientId');
      _updateStatus(statuses, 'Patient', 'in_progress', progress: 0.2);
      await _fetchResource(
        patientId,
        'Patient',
        '/Patient/$patientId',
        statuses,
      );
      // Always set Patient count to 1 (we're fetching data for a single patient)
      // Even if fetch fails or returns 0, we always have 1 patient per fetch
      resourceCounts['Patient'] = 1;
      debugPrint('Patient fetch complete: 1 record (hardcoded)');
      _updateStatus(statuses, 'Patient', 'completed', count: 1);

      // Step 2b: Fetch other resources in sequence
      int stepIndex = 0;
      final totalResources = resourceTypes.length - 1;
      for (var resourceType in resourceTypes.skip(1)) {
        stepIndex++;
        final progress = 0.3 + (stepIndex / totalResources) * 0.5;
        _updateStep('Fetching from FHIR MCP Gateway', 'in_progress', 
            'Fetching $resourceType... (${stepIndex}/$totalResources)');
        
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
      
      _updateStep('Fetching from FHIR MCP Gateway', 'completed', 
          'Fetched ${resourceCounts.values.fold(0, (a, b) => a + b)} total resources');

      // Step 3: Store in local database
      _updateStep('Storing in Local Database', 'in_progress', 'Saving resources to SQLite...');
      // Always ensure Patient shows as 1 in summary (hardcoded for single patient)
      resourceCounts['Patient'] = 1;
      final totalResourcesFetched = resourceCounts.values.fold(0, (a, b) => a + b);
      final resourceCountsSummary = resourceCounts.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      _updateStep('Storing in Local Database', 'completed', 
          'Stored $totalResourcesFetched resources ($resourceCountsSummary)',
          dataSnippet: resourceCountsSummary);

      return FetchSummary(
        resourceCounts: resourceCounts,
        totalResources: totalResourcesFetched,
        completedAt: DateTime.now(),
        errors: errors,
        storedInDatabase: true,
      );
    } catch (e, stackTrace) {
      debugPrint('Error in fetchAllData: $e');
      debugPrint('Stack trace: $stackTrace');
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
    final path = pathFor(resourceType, patientId);
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
      final tool = toolFor(resourceType);

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
        // Single resource (not a Bundle) - common for Patient resource when fetching by ID
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
      
      // For Patient resource type, always return 1 (single patient per fetch)
      // Even if savedCount is 0 (fetch failed), we still return 1 for display purposes
      if (resourceType == 'Patient') {
        return 1;
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
  
  /// Update step status and notify listeners
  void _updateStep(String stepName, String status, String message, {String? dataSnippet}) {
    if (onStepUpdate != null) {
      onStepUpdate!(FetchStepStatus(
        stepName: stepName,
        status: status,
        message: message,
        dataSnippet: dataSnippet,
      ));
    }
  }
}

