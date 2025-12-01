import 'package:flutter/foundation.dart';
import '../services/mcp_client.dart';
import '../services/nlp_service.dart';
import '../services/gemma_service.dart';
import '../providers/patient_provider.dart';

class QueryProvider with ChangeNotifier {
  final MCPClient mcpClient;
  final NLPService nlpService = NLPService();
  final GemmaService gemmaService = GemmaService();
  PatientProvider? _patientProvider;
  
  String? _lastQuery;
  Map<String, dynamic>? _lastResult;
  bool _isProcessing = false;
  String? _error;
  String? _currentPatientId;

  QueryProvider({required this.mcpClient});

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

  /// Process a natural language query
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
      
      // Interpret the query using Gemma service with context awareness
      final interpretation = await gemmaService.interpretQueryWithContext(query);
      
      // Fallback to NLP service if Gemma doesn't provide tool
      if (interpretation['tool'] == null || interpretation['tool'] == 'request_generic_resource') {
        final nlpInterpretation = await nlpService.interpretQuery(query, patientId: _currentPatientId);
        interpretation['tool'] = nlpInterpretation['tool'];
        interpretation['params'] = nlpInterpretation['params'];
        interpretation['intent'] = nlpInterpretation['intent'];
      } else {
        // Add patient context to interpretation params if available
        if (_currentPatientId != null && interpretation['params'] is Map) {
          final params = interpretation['params'] as Map<String, dynamic>;
          if (params.containsKey('request') && params['request'] is Map) {
            final request = params['request'] as Map<String, dynamic>;
            if (request.containsKey('path') && request['path'] is String) {
              final path = request['path'] as String;
              // Add patient filter to path if it's a resource query
              if (path.startsWith('/') && !path.contains('subject=') && !path.contains('patient=')) {
                final separator = path.contains('?') ? '&' : '?';
                request['path'] = '$path$separator subject=Patient/$_currentPatientId';
              }
            }
          }
        }
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

