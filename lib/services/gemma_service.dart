import 'dart:convert';
import 'local_rag_service.dart';

/// Gemma LLM Service for local NLP processing
/// 
/// This service provides context-aware query interpretation and response generation.
/// In production, this would integrate with a local Gemma 2B model.
/// 
/// For now, it provides enhanced context-aware interpretation that can be
/// replaced with actual Gemma 2B integration.
class GemmaService {
  final List<Map<String, String>> _conversationHistory = [];
  final LocalRAGService _ragService = LocalRAGService();
  bool _ragInitialized = false;

  /// Set conversation context (e.g., current patient, recent queries)
  void setContext(String context) {
    // Context is now handled via RAG service
    // This method is kept for backward compatibility
  }

  /// Add to conversation history
  void addToHistory(String role, String message) {
    _conversationHistory.add({'role': role, 'content': message});
    // Keep only last 10 messages for context
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeAt(0);
    }
  }

  /// Interpret query with context awareness using RAG
  Future<Map<String, dynamic>> interpretQueryWithContext(
    String query, {
    String? patientId,
  }) async {
    // Initialize RAG service if not already done
    if (!_ragInitialized) {
      await _ragService.initialize();
      _ragInitialized = true;
    }
    
    // Retrieve relevant context from RAG
    final contextChunks = await _ragService.retrieveContext(query);
    
    // In production, this would call Gemma 2B:
    // final prompt = _ragService.buildPrompt(query, patientId, contextChunks);
    // final response = await gemmaModel.generate(prompt: prompt);
    // return parseGemmaResponse(response);
    
    // For now, use enhanced rule-based interpretation with RAG context
    return _interpretWithRAGContext(query, contextChunks, patientId);
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

  Map<String, dynamic> _interpretWithRAGContext(
    String query,
    List<String> contextChunks,
    String? patientId,
  ) {
    final lowerQuery = query.toLowerCase().trim();
    
    // Parse query for specific patterns
    final recordNumber = _extractRecordNumber(lowerQuery);
    final specificValue = _extractSpecificValue(lowerQuery);
    final codeSearch = _extractCodeSearch(lowerQuery);
    
    // Use RAG context to translate human terms to FHIR terms
    String? resourceType;
    
    // Check for specific lab values (cholesterol, glucose, blood pressure, etc.)
    if (specificValue != null || codeSearch != null) {
      resourceType = 'Observation'; // Lab values are typically in Observation resources
    }
    // Check for common query patterns with RAG-enhanced understanding
    else if (_matches(lowerQuery, ['visit', 'visits', 'appointment', 'appointments', 'recent visits'])) {
      resourceType = 'Encounter';
    } else if (_matches(lowerQuery, ['medication', 'medications', 'drug', 'prescription'])) {
      resourceType = 'MedicationStatement';
    } else if (_matches(lowerQuery, ['test', 'tests', 'test results', 'lab', 'lab results', 'diagnostic report'])) {
      // "test results" could be DiagnosticReport or Observation
      if (_matches(lowerQuery, ['record', 'details'])) {
        resourceType = 'DiagnosticReport'; // "record 8 of test results" likely means DiagnosticReport
      } else {
        resourceType = 'DiagnosticReport';
      }
    } else if (_matches(lowerQuery, ['immunization', 'vaccine', 'vaccination', 'shot', 'shots'])) {
      resourceType = 'Immunization';
    } else if (_matches(lowerQuery, ['timeline', 'recent', 'latest', 'history', 'recent timeline'])) {
      resourceType = 'Encounter';
    } else if (_matches(lowerQuery, ['observation', 'vitals', 'vital signs', 'levels', 'value', 'values'])) {
      resourceType = 'Observation';
    } else if (_matches(lowerQuery, ['condition', 'diagnosis', 'problem'])) {
      resourceType = 'Condition';
    }
    
    // Try to use RAG service to translate human term
    if (resourceType == null) {
      // Extract potential human terms from query
      final words = lowerQuery.split(RegExp(r'\s+'));
      for (var word in words) {
        if (word.length > 3) {
          final translated = _ragService.translateHumanTerm(word);
          if (translated != null) {
            resourceType = translated;
            break;
          }
        }
      }
    }
    
    // Determine query type (local-first approach)
    final queryType = _shouldQueryLocal(lowerQuery) ? 'local' : 'mcp';
    
    if (resourceType != null) {
      // Build local query structure
      final localQuery = <String, dynamic>{
        'resourceType': resourceType,
        'filters': <String, dynamic>{},
      };
      
      // Add record number if specified
      if (recordNumber != null) {
        localQuery['recordIndex'] = recordNumber - 1; // Convert to 0-based index
      }
      
      // Add specific value/code search
      if (specificValue != null) {
        localQuery['filters'] = {
          ...localQuery['filters'] as Map<String, dynamic>,
          'codeSearch': specificValue,
        };
      }
      
      if (codeSearch != null) {
        localQuery['filters'] = {
          ...localQuery['filters'] as Map<String, dynamic>,
          'codeSearch': codeSearch,
        };
      }
      
      // Add sorting for "recent" queries
      if (_matches(lowerQuery, ['recent', 'latest', 'newest'])) {
        localQuery['filters'] = {
          ...localQuery['filters'] as Map<String, dynamic>,
          'sort': '-date',
          'limit': 10,
        };
      }
      
      // Build MCP query as fallback
      final mcpQuery = <String, dynamic>{
        'tool': _getMCPToolName(resourceType),
        'params': {
          'request': {
            'method': 'GET',
            'path': _buildMCPPath(resourceType, patientId),
            'body': null,
          }
        }
      };
      
      return {
        'queryType': queryType,
        'localQuery': localQuery,
        'mcpQuery': mcpQuery,
        'intent': _getIntent(lowerQuery, resourceType),
      };
    }
    
    // Fall back to generic query
    return {
      'queryType': 'mcp',
      'mcpQuery': {
        'tool': 'request_generic_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': '/',
            'body': null,
          }
        }
      },
      'intent': 'generic_query',
    };
  }
  
  /// Extract record number from query (e.g., "record 8", "number 5")
  int? _extractRecordNumber(String query) {
    final patterns = [
      RegExp(r'record\s+(\d+)', caseSensitive: false),
      RegExp(r'number\s+(\d+)', caseSensitive: false),
      RegExp(r'#(\d+)', caseSensitive: false),
      RegExp(r'(\d+)(?:st|nd|rd|th)\s+record', caseSensitive: false),
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }
  
  /// Extract specific value search from query (e.g., "cholesterol levels", "glucose")
  String? _extractSpecificValue(String query) {
    // Medical term mappings
    final medicalTerms = {
      'cholesterol': ['cholesterol', 'ldl', 'hdl', 'triglycerides'],
      'glucose': ['glucose', 'blood sugar', 'sugar'],
      'blood pressure': ['blood pressure', 'bp', 'systolic', 'diastolic'],
      'hemoglobin': ['hemoglobin', 'hgb', 'hba1c'],
      'creatinine': ['creatinine'],
      'sodium': ['sodium', 'na'],
      'potassium': ['potassium', 'k'],
    };
    
    for (var entry in medicalTerms.entries) {
      for (var term in entry.value) {
        if (query.contains(term)) {
          return entry.key;
        }
      }
    }
    
    return null;
  }
  
  /// Extract code search from query
  String? _extractCodeSearch(String query) {
    // Look for LOINC codes or common test names
    final loincPattern = RegExp(r'loinc[:\s]+(\w+)', caseSensitive: false);
    final match = loincPattern.firstMatch(query);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }
  
  bool _shouldQueryLocal(String query) {
    // Queries that should try local first
    final localIndicators = [
      'my', 'show me', 'list', 'get', 'recent', 'latest', 'current',
      'timeline', 'history', 'record', 'data', 'information',
    ];
    return localIndicators.any((indicator) => query.contains(indicator));
  }
  
  String _getMCPToolName(String resourceType) {
    final toolMap = {
      'Encounter': 'request_encounter_resource',
      'Observation': 'request_observation_resource',
      'MedicationStatement': 'request_medication_resource',
      'Condition': 'request_condition_resource',
      'DiagnosticReport': 'request_diagnostic_report_resource',
      'Immunization': 'request_immunization_resource',
      'Patient': 'request_patient_resource',
    };
    return toolMap[resourceType] ?? 'request_generic_resource';
  }
  
  String _buildMCPPath(String resourceType, String? patientId) {
    String path = '/$resourceType';
    final params = <String>[];
    
    if (patientId != null) {
      params.add('subject=Patient/$patientId');
    }
    
    params.add('_sort=-date');
    params.add('_count=10');
    
    if (params.isNotEmpty) {
      path += '?${params.join('&')}';
    }
    
    return path;
  }
  
  String _getIntent(String query, String resourceType) {
    if (query.contains('recent') || query.contains('latest')) {
      return 'recent_${resourceType.toLowerCase()}';
    }
    return 'list_${resourceType.toLowerCase()}';
  }

  String _generateSimpleResponse(String query, Map<String, dynamic> fhirData) {
    // Parse FHIR data and generate conversational response
    final lowerQuery = query.toLowerCase();
    
    // Try to extract actual data from the result
    var data = fhirData;
    if (data.containsKey('result')) {
      data = data['result'] as Map<String, dynamic>;
    }
    
    // Check for content array (MCP response format)
    if (data.containsKey('content') && data['content'] is List) {
      final content = data['content'] as List;
      if (content.isNotEmpty && content[0] is Map) {
        final firstContent = content[0] as Map<String, dynamic>;
        if (firstContent.containsKey('text')) {
          try {
            final textData = jsonDecode(firstContent['text'] as String);
            data = textData as Map<String, dynamic>;
          } catch (e) {
            // Not JSON, use as is
          }
        }
      }
    }
    
    // Parse based on query intent
    if (lowerQuery.contains('medication') || lowerQuery.contains('drug')) {
      if (data.containsKey('response') && data['response'] is Map) {
        final response = data['response'] as Map;
        if (response.containsKey('entry') && (response['entry'] as List).isNotEmpty) {
          final count = (response['entry'] as List).length;
          return 'I found $count medication${count > 1 ? 's' : ''} in your records. Would you like to see the details?';
        }
      }
      return 'I couldn\'t find any medications in your records at this time.';
    } else if (lowerQuery.contains('test') || lowerQuery.contains('lab')) {
      if (data.containsKey('response') && data['response'] is Map) {
        final response = data['response'] as Map;
        if (response.containsKey('entry') && (response['entry'] as List).isNotEmpty) {
          final count = (response['entry'] as List).length;
          return 'I found $count test result${count > 1 ? 's' : ''} in your records. Here\'s what I found.';
        }
      }
      return 'I couldn\'t find any test results in your records at this time.';
    } else if (lowerQuery.contains('timeline') || lowerQuery.contains('recent') || lowerQuery.contains('history')) {
      if (data.containsKey('response') && data['response'] is Map) {
        final response = data['response'] as Map;
        if (response.containsKey('entry') && (response['entry'] as List).isNotEmpty) {
          final count = (response['entry'] as List).length;
          return 'I found $count recent event${count > 1 ? 's' : ''} in your health timeline. Here\'s your recent activity.';
        }
      }
      return 'I couldn\'t find any recent events in your timeline at this time.';
    } else if (data.containsKey('response') || data.containsKey('entry') || data.containsKey('resourceType')) {
      return 'I found the information you requested in your health records. Here are the details.';
    }
    
    return 'I\'ve processed your request. How can I help you further?';
  }

  bool _matches(String query, List<String> keywords) {
    return keywords.any((keyword) => query.contains(keyword));
  }

  void clearContext() {
    _conversationHistory.clear();
  }
}

