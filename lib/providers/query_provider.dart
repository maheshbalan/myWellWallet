import 'package:flutter/foundation.dart';
import '../services/mcp_client.dart';
import '../services/nlp_service.dart';
import '../services/gemma_service.dart';

class QueryProvider with ChangeNotifier {
  final MCPClient mcpClient;
  final NLPService nlpService = NLPService();
  final GemmaService gemmaService = GemmaService();
  
  String? _lastQuery;
  Map<String, dynamic>? _lastResult;
  bool _isProcessing = false;
  String? _error;

  QueryProvider({required this.mcpClient});

  String? get lastQuery => _lastQuery;
  Map<String, dynamic>? get lastResult => _lastResult;
  bool get isProcessing => _isProcessing;
  String? get error => _error;

  /// Process a natural language query
  Future<void> processQuery(String query) async {
    if (query.trim().isEmpty) return;

    _isProcessing = true;
    _error = null;
    _lastQuery = query;
    notifyListeners();

    try {
      // Interpret the query using Gemma service with context awareness
      final interpretation = await gemmaService.interpretQueryWithContext(query);
      
      // Fallback to NLP service if Gemma doesn't provide tool
      if (interpretation['tool'] == null || interpretation['tool'] == 'request_generic_resource') {
        final nlpInterpretation = await nlpService.interpretQuery(query);
        interpretation['tool'] = nlpInterpretation['tool'];
        interpretation['params'] = nlpInterpretation['params'];
        interpretation['intent'] = nlpInterpretation['intent'];
      }
      
      // Call the appropriate MCP tool
      final result = await mcpClient.callTool(
        interpretation['tool'] as String,
        interpretation['params'] as Map<String, dynamic>,
      );

      _lastResult = {
        'interpretation': interpretation,
        'result': result,
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

