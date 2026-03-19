import 'package:flutter/foundation.dart';
import '../services/mcp_client.dart';
import '../services/nlp_service.dart';
import '../services/gemma_service.dart';
import '../services/local_query_service.dart';
import '../services/gemma_rag_service.dart';
import '../services/log_service.dart';
import '../providers/patient_provider.dart';

class QueryProvider with ChangeNotifier {
  final MCPClient mcpClient;
  final NLPService nlpService = NLPService();
  final GemmaService gemmaService = GemmaService();
  LocalQueryService? _localQueryService;
  GemmaRAGService? _gemmaRAGService;
  PatientProvider? _patientProvider;
  
  String? _lastQuery;
  Map<String, dynamic>? _lastResult;
  bool _isProcessing = false;
  String? _error;
  String? _currentPatientId;
  Map<String, dynamic>? _pendingClarification;

  QueryProvider({required this.mcpClient});

  void setLocalQueryService(LocalQueryService service) {
    _localQueryService = service;
  }
  
  void setGemmaRAGService(GemmaRAGService service) {
    _gemmaRAGService = service;
  }

  void setPatientProvider(PatientProvider provider) {
    _patientProvider = provider;
    // Update patient ID when found patient changes
    if (provider.foundPatient != null) {
      _currentPatientId = provider.foundPatient!.id;
    }
  }

  String? get lastQuery => _lastQuery;
  Map<String, dynamic>? get lastResult => _lastResult;
  bool get isProcessing => _isProcessing;
  String? get error => _error;

  /// Process a natural language query with local-first approach
  Future<void> processQuery(String query) async {
    if (query.trim().isEmpty) return;
    LogService.log('QueryProvider: Processing query: "$query"');

    _isProcessing = true;
    _error = null;
    _lastQuery = query;
    _lastResult = null;
    notifyListeners();

    try {
      // Update patient ID from provider if available
      if (_patientProvider != null && _patientProvider!.foundPatient != null) {
        _currentPatientId = _patientProvider!.foundPatient!.id;
        LogService.log('QueryProvider: Using patient context ID: $_currentPatientId');
      }
      
      if (_currentPatientId == null) {
        LogService.log('QueryProvider: ERROR - No patient context ID!');
        throw Exception('Patient ID not available. Please ensure you are logged in and patient context is established.');
      }

      // Use the advanced GemmaRAGService if available
      if (_gemmaRAGService != null) {
        LogService.log('QueryProvider: Calling GemmaRAGService.processQuery...');
        final ragResult = await _gemmaRAGService!.processQuery(query, _currentPatientId);
        LogService.log('QueryProvider: RAG result type: ${ragResult['type']}');
        
        if (ragResult['type'] == 'clarification') {
          _lastResult = {
            'source': 'rag',
            'type': 'clarification',
            'question': ragResult['question'],
            'options': ragResult['options'],
            'markdown': '### I need a bit more information\n\n${ragResult['question']}',
          };
          _error = null;
          return;
        }

        if (ragResult['type'] == 'queryPlan') {
          final queryPlan = ragResult['queryPlan'] as Map<String, dynamic>;
          LogService.log('QueryProvider: Executing query plan for ${queryPlan['resourceType']}');
          final executionResult = await _gemmaRAGService!.executeQueryPlan(queryPlan, _currentPatientId!);
          LogService.log('QueryProvider: Execution result type: ${executionResult['type']}');
          
          if (executionResult['type'] == 'success') {
            _lastResult = {
              'source': 'local',
              'type': 'success',
              'resourceType': queryPlan['resourceType'],
              'count': executionResult['count'],
              'resources': executionResult['resources'],
            };
            _error = null;
            return;
          }
 else if (executionResult['type'] == 'fallbackToMCP') {
            LogService.log('QueryProvider: No local data, falling back to MCP Gateway...');
            // Fallback to MCP query logic
            await _fallbackToMCP(query, queryPlan);
            return;
          } else {
            LogService.log('QueryProvider: No results from local execution.');
            // No results or error from execution
            _lastResult = {
              'source': 'local',
              'type': 'noResults',
              'markdown': executionResult['message'] ?? 'No records found matching your request.',
            };
            _error = null;
            return;
          }
        }
      }
      
      LogService.log('QueryProvider: Falling back to simple interpretation...');
      // Fallback to simpler GemmaService if RAG failed or not available
      final interpretation = await gemmaService.interpretQueryWithContext(
        query,
        patientId: _currentPatientId,
      );
      
      final queryType = interpretation['queryType'] as String? ?? 'mcp';
      LogService.log('QueryProvider: Simple interpretation type: $queryType');
      final localQuery = interpretation['localQuery'] as Map<String, dynamic>?;
      
      // Try local database first
      if ((queryType == 'local' || queryType == 'both') && 
          localQuery != null && 
          _localQueryService != null) {
        final resourceType = localQuery['resourceType'] as String?;
        final filters = localQuery['filters'] as Map<String, dynamic>?;
        
        if (resourceType != null) {
          final recordIndex = localQuery['recordIndex'] as int?;
          LogService.log('QueryProvider: Querying local DB for $resourceType');
          final localResources = await _localQueryService!.queryLocal(
            _currentPatientId!,
            resourceType,
            filters: filters,
            recordIndex: recordIndex,
          );
          
          if (localResources.isNotEmpty) {
            LogService.log('QueryProvider: Found ${localResources.length} local resources');
            final markdown = _localQueryService!.formatAsMarkdown(localResources, resourceType);
            _lastResult = {
              'source': 'local',
              'resourceType': resourceType,
              'count': localResources.length,
              'resources': localResources,
              'markdown': markdown,
            };
            _error = null;
            return;
          }
        }
      }
      
      LogService.log('QueryProvider: Final fallback to MCP Gateway...');
      // Final fallback to MCP Gateway
      await _fallbackToMCP(query, interpretation['mcpQuery']);
      
    } catch (e) {
      LogService.log('QueryProvider CRITICAL ERROR: $e');
      _error = 'Failed to process query: $e';
      _lastResult = null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> _fallbackToMCP(String query, Map<String, dynamic>? queryPlan) async {
    try {
      final resourceType = queryPlan?['resourceType'] as String?;
      if (resourceType == null) {
        throw Exception('Cannot fallback to MCP: No resourceType in query plan');
      }

      // 1. Determine correct tool name
      String toolName;
      final knownTools = [
        'Patient', 'Observation', 'Condition', 'AllergyIntolerance', 
        'Encounter', 'Immunization', 'Medication', 'DocumentReference', 
        'FamilyMemberHistory'
      ];
      
      if (knownTools.contains(resourceType)) {
        toolName = 'request_${resourceType.toLowerCase()}_resource';
      } else {
        toolName = 'request_generic_resource';
      }

      // 2. Determine correct filter name (subject vs patient)
      final usePatientFilter = [
        'Immunization', 'MedicationStatement', 'Condition', 'AllergyIntolerance'
      ].contains(resourceType);
      final filterName = usePatientFilter ? 'patient' : 'subject';

      // 3. Build path with filters
      final filters = queryPlan?['filters'] as Map<String, dynamic>?;
      String path = '/$resourceType?$filterName=Patient/$_currentPatientId';
      if (filters != null) {
        filters.forEach((key, value) {
          if (!key.startsWith('_') && key != filterName) {
            path += '&$key=$value';
          }
        });
        // Add sorting if specified
        if (filters.containsKey('_sort')) {
          path += '&_sort=${filters['_sort']}';
        }
        if (filters.containsKey('_count')) {
          path += '&_count=${filters['_count']}';
        }
      }

      LogService.log('QueryProvider: Calling MCP tool $toolName with path $path');
      
      final result = await mcpClient.callTool(toolName, {
        'request': {
          'method': 'GET',
          'path': path,
        }
      });
      
      _lastResult = {
        'source': 'mcp',
        'result': result,
      };
      _error = null;
    } catch (e) {
      LogService.log('QueryProvider: MCP Fallback error: $e');
      _error = 'Local data not found and server query failed: $e';
      _lastResult = null;
      rethrow;
    }
  }

  void clearResults() {
    _lastQuery = null;
    _lastResult = null;
    _error = null;
    notifyListeners();
  }
}

