import 'package:flutter/foundation.dart';
import '../services/mcp_client.dart';
import '../services/nlp_service.dart';
import '../services/gemma_service.dart';
import '../services/gemma_rag_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'patient_provider.dart';
import 'query_concurrency.dart';

class QueryProvider with ChangeNotifier {
  final MCPClient mcpClient;
  final NLPService nlpService = NLPService();
  final GemmaService gemmaService = GemmaService();
  GemmaRAGService? _gemmaRAGService;
  PatientProvider? _patientProvider;
  AuthProvider? _authProvider;

  String? _lastQuery;
  Map<String, dynamic>? _lastResult;
  bool _isProcessing = false;
  String? _error;
  String? _currentPatientId;
  Map<String, dynamic>? _pendingClarification;

  QueryProvider({required this.mcpClient});

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

  void setAuthProvider(AuthProvider provider) {
    _authProvider = provider;
  }

  String? get lastQuery => _lastQuery;
  Map<String, dynamic>? get lastResult => _lastResult;
  bool get isProcessing => _isProcessing;
  String? get error => _error;

  /// Process a natural language query with local-first approach
  Future<void> processQuery(String query) async {
    if (!shouldAcceptNewQuery(
      isStreaming: false, // streaming lives in the UI layer
      isProcessing: _isProcessing,
      query: query,
    )) {
      LogService.log(
        'QueryProvider: Rejecting concurrent/empty query (isProcessing=$_isProcessing)',
      );
      return;
    }
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
      
      final userId = _authProvider?.currentUser?.id;
      if ((userId == null || userId.isEmpty) && _currentPatientId == null) {
        throw Exception('Sign in before asking about your records.');
      }

      if (_gemmaRAGService == null) {
        throw Exception('The on-device model is not available.');
      }

      LogService.log('QueryProvider: Asking MedGemma for a SQLite read...');
      final ragResult = await _gemmaRAGService!.processQuery(query, userId: userId);
      LogService.log('QueryProvider: RAG result type: ${ragResult['type']}');

      if (ragResult['type'] == 'clarification' || ragResult['type'] == 'message') {
        final text = (ragResult['question'] ?? ragResult['message'] ?? 'I need a bit more information.') as String;
        _lastResult = {
          'source': 'rag',
          'type': ragResult['type'],
          'markdown': text,
        };
        _error = null;
        return;
      }

      if (ragResult['type'] == 'rows') {
        _lastResult = {
          'source': 'local',
          'type': 'success',
          'count': ragResult['count'],
          'resources': ragResult['resources'],
        };
        _error = null;
        return;
      }

      if (ragResult['type'] == 'sql') {
        final sql = ragResult['sql'] as String;
        final executionResult = await _gemmaRAGService!.executeSql(sql);
        if (executionResult['type'] == 'success') {
          _lastResult = {
            'source': 'local',
            'type': 'success',
            'count': executionResult['count'],
            'resources': executionResult['resources'],
          };
          _error = null;
          return;
        }
        _lastResult = {
          'source': 'local',
          'type': executionResult['type'],
          'markdown': executionResult['message'] ?? 'No records found matching your request.',
        };
        _error = null;
        return;
      }

      _lastResult = {
        'source': 'rag',
        'type': 'message',
        'markdown': 'I could not query the records on this phone.',
      };
      _error = null;
    } catch (e) {
      LogService.log('QueryProvider CRITICAL ERROR: $e');
      _error = 'Failed to process query: $e';
      _lastResult = null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void addAssistantResponseToHistory(String response) {
    _gemmaRAGService?.addToHistory('model', response);
  }

  void clearResults() {
    _lastQuery = null;
    _lastResult = null;
    _error = null;
    _gemmaRAGService?.clearHistory();
    gemmaService.clearContext();
    notifyListeners();
  }
}

