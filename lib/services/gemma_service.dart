import 'dart:convert';

/// Gemma LLM Service for local NLP processing
/// 
/// This service provides context-aware query interpretation and response generation.
/// In production, this would integrate with a local Gemma 2B model.
/// 
/// For now, it provides enhanced context-aware interpretation that can be
/// replaced with actual Gemma 2B integration.
class GemmaService {
  String? _currentContext;
  final List<Map<String, String>> _conversationHistory = [];

  /// Set conversation context (e.g., current patient, recent queries)
  void setContext(String context) {
    _currentContext = context;
  }

  /// Add to conversation history
  void addToHistory(String role, String message) {
    _conversationHistory.add({'role': role, 'content': message});
    // Keep only last 10 messages for context
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeAt(0);
    }
  }

  /// Interpret query with context awareness
  Future<Map<String, dynamic>> interpretQueryWithContext(String query) async {
    // Build context prompt (for future Gemma 2B integration)
    // String contextPrompt = '';
    // if (_currentContext != null) {
    //   contextPrompt = 'Context: $_currentContext\n';
    // }
    // 
    // if (_conversationHistory.isNotEmpty) {
    //   contextPrompt += 'Recent conversation:\n';
    //   final recentMessages = _conversationHistory.length > 3
    //       ? _conversationHistory.sublist(_conversationHistory.length - 3)
    //       : _conversationHistory;
    //   for (var msg in recentMessages) {
    //     contextPrompt += '${msg['role']}: ${msg['content']}\n';
    //   }
    // }
    // 
    // contextPrompt += 'User query: $query\n';
    // contextPrompt += 'Interpret this query and map it to a FHIR resource type. '
    //     'Return JSON with: tool (FHIR MCP tool name), params (tool parameters), intent (user intent).';

    // In production, this would call Gemma 2B:
    // final response = await gemmaModel.generate(prompt: contextPrompt);
    // return parseGemmaResponse(response);
    
    // For now, use enhanced rule-based interpretation with context
    return _interpretWithContext(query);
  }

  /// Generate conversational response from FHIR data
  Future<String> generateResponse(
    String query,
    Map<String, dynamic> fhirData,
  ) async {
    // Build prompt for response generation (for future Gemma 2B integration)
    // String prompt = 'Context: $_currentContext\n';
    // prompt += 'User asked: $query\n';
    // prompt += 'FHIR Data: ${jsonEncode(fhirData)}\n';
    // prompt += 'Generate a friendly, conversational response explaining this health data '
    //     'in simple terms. Be concise and helpful.';

    // In production, this would call Gemma 2B:
    // final response = await gemmaModel.generate(prompt: prompt);
    // return response;

    // For now, generate a simple conversational response
    return _generateSimpleResponse(query, fhirData);
  }

  /// Generate follow-up prompts based on context
  List<String> generateFollowUpPrompts(String lastQuery, Map<String, dynamic>? lastResult) {
    final prompts = <String>[];
    
    if (lastQuery.toLowerCase().contains('medication')) {
      prompts.addAll([
        'Show me potential drug interactions',
        'What are the side effects?',
        'When should I take these?',
      ]);
    } else if (lastQuery.toLowerCase().contains('test') || 
               lastQuery.toLowerCase().contains('lab')) {
      prompts.addAll([
        'What do these results mean?',
        'Are these results normal?',
        'Show me previous test results',
      ]);
    } else if (lastQuery.toLowerCase().contains('timeline') ||
               lastQuery.toLowerCase().contains('recent')) {
      prompts.addAll([
        'Show me my medications',
        'What are my upcoming appointments?',
        'Show me my latest diagnostic reports',
      ]);
    } else {
      prompts.addAll([
        'Show me the most recent timeline',
        'Show me my medications',
        'Show me the recent tests',
        'Show me the latest diagnostic reports',
      ]);
    }
    
    return prompts;
  }

  Map<String, dynamic> _interpretWithContext(String query) {
    final lowerQuery = query.toLowerCase().trim();
    
    // Enhanced interpretation with context awareness
    if (_currentContext != null && _currentContext!.contains('patient')) {
      // If we have patient context, queries are about that patient
      if (_matches(lowerQuery, ['timeline', 'recent', 'latest', 'history'])) {
        return {
          'tool': 'request_encounter_resource',
          'params': {
            'request': {
              'method': 'GET',
              'path': '/Encounter?_sort=-date&_count=10',
              'body': null,
            }
          },
          'intent': 'recent_timeline',
        };
      }
    }
    
    // Fall back to standard interpretation
    // (This would be handled by the NLPService)
    return {
      'tool': 'request_generic_resource',
      'params': {
        'request': {
          'method': 'GET',
          'path': '/',
          'body': null,
        }
      },
      'intent': 'generic_query',
    };
  }

  String _generateSimpleResponse(String query, Map<String, dynamic> fhirData) {
    // Simple response generation - in production, Gemma 2B would do this
    if (fhirData.containsKey('entry') || fhirData.containsKey('resourceType')) {
      return 'I found the information you requested. Here are the details from your health records.';
    }
    return 'I\'ve retrieved your health information. How can I help you further?';
  }

  bool _matches(String query, List<String> keywords) {
    return keywords.any((keyword) => query.contains(keyword));
  }

  void clearContext() {
    _currentContext = null;
    _conversationHistory.clear();
  }
}

