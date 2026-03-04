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
    _lastResult = null;
    notifyListeners();

    try {
      // Update patient ID from provider if available
      if (_patientProvider != null && _patientProvider!.foundPatient != null) {
        _currentPatientId = _patientProvider!.foundPatient!.id;
      }
      
      if (_currentPatientId == null) {
        throw Exception('Patient ID not available. Please ensure you are logged in and patient context is established.');
      }

      // Use the advanced GemmaRAGService if available
      if (_gemmaRAGService != null) {
        final ragResult = await _gemmaRAGService!.processQuery(query, _currentPatientId);
        
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
          final executionResult = await _gemmaRAGService!.executeQueryPlan(queryPlan, _currentPatientId!);
          
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
            // Fallback to MCP query logic
            await _fallbackToMCP(query, queryPlan);
            return;
          } else {
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
      
      // Fallback to simpler GemmaService if RAG failed or not available
      final interpretation = await gemmaService.interpretQueryWithContext(
        query,
        patientId: _currentPatientId,
      );
      
      final queryType = interpretation['queryType'] as String? ?? 'mcp';
      final localQuery = interpretation['localQuery'] as Map<String, dynamic>?;
      final mcpQuery = interpretation['mcpQuery'] as Map<String, dynamic>?;
      
      // Try local database first
      if ((queryType == 'local' || queryType == 'both') && 
          localQuery != null && 
          _localQueryService != null) {
        final resourceType = localQuery['resourceType'] as String?;
        final filters = localQuery['filters'] as Map<String, dynamic>?;
        
        if (resourceType != null) {
          final recordIndex = localQuery['recordIndex'] as int?;
          final localResources = await _localQueryService!.queryLocal(
            _currentPatientId!,
            resourceType,
            filters: filters,
            recordIndex: recordIndex,
          );
          
          if (localResources.isNotEmpty) {
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
      
      // Final fallback to MCP Gateway
      await _fallbackToMCP(query, interpretation['mcpQuery']);
      
    } catch (e) {
      debugPrint('QueryProvider error: $e');
      _error = 'Failed to process query: $e';
      _lastResult = null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> _fallbackToMCP(String query, Map<String, dynamic>? mcpQuery) async {
    try {
      Map<String, dynamic>? result;
      final tool = mcpQuery?['tool'] as String?;
      final params = mcpQuery?['params'] as Map<String, dynamic>?;
      
      if (tool != null && params != null) {
        result = await mcpClient.callTool(tool, params);
      } else {
        // Fallback to NLP service for generic interpretation
        final nlpInterpretation = await nlpService.interpretQuery(
          query,
          patientId: _currentPatientId,
        );
        result = await mcpClient.callTool(
          nlpInterpretation['tool'] as String,
          nlpInterpretation['params'] as Map<String, dynamic>,
        );
      }
      
      _lastResult = {
        'source': 'mcp',
        'result': result,
      };
      _error = null;
    } catch (e) {
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

