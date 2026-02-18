import 'package:flutter/foundation.dart';
import '../services/mcp_client.dart';
import '../services/nlp_service.dart';
import '../services/gemma_service.dart';
import '../services/local_query_service.dart';
import '../services/gemma_rag_service.dart';
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
    // Initialize GemmaRAGService when LocalQueryService is available
    if (_gemmaRAGService == null) {
      // We'll need DatabaseService - get it from LocalQueryService
      // For now, we'll initialize it in a different way
    }
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

    _isProcessing = true;
    _error = null;
    _lastQuery = query;
    notifyListeners();

    try {
      // Update patient ID from provider if available
      if (_patientProvider != null && _patientProvider!.foundPatient != null) {
        _currentPatientId = _patientProvider!.foundPatient!.id;
      }
      
      if (_currentPatientId == null) {
        throw Exception('Patient ID not available. Please ensure you are logged in and patient context is established.');
      }
      
      // Interpret the query using Gemma service with RAG context
      final interpretation = await gemmaService.interpretQueryWithContext(
        query,
        patientId: _currentPatientId,
      );
      
      // Determine query type (local-first approach)
      final queryType = interpretation['queryType'] as String? ?? 'mcp';
      final localQuery = interpretation['localQuery'] as Map<String, dynamic>?;
      final mcpQuery = interpretation['mcpQuery'] as Map<String, dynamic>?;
      
      Map<String, dynamic>? result;
      bool fromLocal = false;
      
      // Try local database first if query type is 'local' or 'both'
      if ((queryType == 'local' || queryType == 'both') && 
          localQuery != null && 
          _localQueryService != null) {
        try {
          final resourceType = localQuery['resourceType'] as String?;
          final filters = localQuery['filters'] as Map<String, dynamic>?;
          
          if (resourceType != null) {
            // Extract record index if specified
            final recordIndex = localQuery['recordIndex'] as int?;
            
            // Query local database
            final localResources = await _localQueryService!.queryLocal(
              _currentPatientId!,
              resourceType,
              filters: filters,
              recordIndex: recordIndex,
            );
            
            if (localResources.isNotEmpty) {
              // Format as markdown
              final markdown = _localQueryService!.formatAsMarkdown(
                localResources,
                resourceType,
              );
              
              result = {
                'source': 'local',
                'resourceType': resourceType,
                'count': localResources.length,
                'resources': localResources,
                'markdown': markdown,
              };
              fromLocal = true;
            }
          }
        } catch (e) {
          debugPrint('Error querying local database: $e');
          // Continue to MCP query if local fails
        }
      }
      
      // Fallback to MCP Gateway if local query failed or query type is 'mcp'
      if (!fromLocal && mcpQuery != null) {
        final tool = mcpQuery['tool'] as String?;
        final params = mcpQuery['params'] as Map<String, dynamic>?;
        
        if (tool != null && params != null) {
          result = await mcpClient.callTool(tool, params);
          result = {
            'source': 'mcp',
            'result': result,
          };
        } else {
          // Fallback to NLP service
          final nlpInterpretation = await nlpService.interpretQuery(
            query,
            patientId: _currentPatientId,
          );
          
          result = await mcpClient.callTool(
            nlpInterpretation['tool'] as String,
            nlpInterpretation['params'] as Map<String, dynamic>,
          );
          result = {
            'source': 'mcp',
            'result': result,
          };
        }
      }
      
      if (result == null) {
        throw Exception('Could not process query: No valid interpretation found');
      }

      _lastResult = {
        'interpretation': interpretation,
        'result': result,
        'queryType': queryType,
        'fromLocal': fromLocal,
      };
      _error = null;
    } catch (e) {
      _error = 'Failed to process query: $e';
      _lastResult = null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void clearResults() {
    _lastQuery = null;
    _lastResult = null;
    _error = null;
    notifyListeners();
  }
}

