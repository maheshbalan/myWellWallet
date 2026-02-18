import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_rag_service.dart';
import 'local_query_service.dart';
import 'database_service.dart';

/// Gemma RAG Service - Conversational query processing with RAG context
/// 
/// This service uses RAG (Retrieval-Augmented Generation) to provide Gemma
/// with relevant context from documentation, then uses Gemma to:
/// 1. Generate structured query plans from natural language
/// 2. Format results as human-readable markdown
/// 3. Ask clarifying questions when queries are ambiguous
class GemmaRAGService {
  final LocalRAGService _ragService = LocalRAGService();
  final LocalQueryService _queryService;
  final DatabaseService _databaseService;
  bool _initialized = false;
  
  // Conversation history for context
  final List<Map<String, String>> _conversationHistory = [];
  
  GemmaRAGService({
    required LocalQueryService queryService,
    required DatabaseService databaseService,
  }) : _queryService = queryService,
       _databaseService = databaseService;

  /// Initialize RAG service
  Future<void> initialize() async {
    if (_initialized) return;
    await _ragService.initialize();
    _initialized = true;
  }

  /// Process a user query with RAG context
  /// Returns either a query plan, a clarification question, or an error
  Future<Map<String, dynamic>> processQuery(
    String query,
    String? patientId,
  ) async {
    if (!_initialized) {
      await initialize();
    }

    // Add user query to conversation history
    _addToHistory('user', query);

    // Retrieve relevant context from RAG
    final contextChunks = await _ragService.retrieveContext(query);
    
    // Build comprehensive prompt for Gemma
    final prompt = _buildQueryGenerationPrompt(
      query,
      patientId,
      contextChunks,
    );

    // For now, use rule-based interpretation with RAG context
    // In production, this would call Gemma 2B model
    final interpretation = await _interpretQueryWithRAG(
      query,
      contextChunks,
      patientId,
    );

    // Check if clarification is needed
    if (interpretation['needsClarification'] == true) {
      return {
        'type': 'clarification',
        'question': interpretation['clarificationQuestion'] as String,
        'options': interpretation['clarificationOptions'] as List<String>?,
      };
    }

    // Generate query plan
    final queryPlan = interpretation['queryPlan'] as Map<String, dynamic>?;
    if (queryPlan == null) {
      return {
        'type': 'error',
        'message': 'Could not understand the query. Please try rephrasing.',
      };
    }

    return {
      'type': 'queryPlan',
      'queryPlan': queryPlan,
      'interpretation': interpretation,
    };
  }

  /// Execute a query plan and format results
  Future<Map<String, dynamic>> executeQueryPlan(
    Map<String, dynamic> queryPlan,
    String patientId,
  ) async {
    try {
      final resourceType = queryPlan['resourceType'] as String?;
      if (resourceType == null) {
        return {
          'type': 'error',
          'message': 'Invalid query plan: missing resourceType',
        };
      }

      // Query local database
      final filters = queryPlan['filters'] as Map<String, dynamic>?;
      final recordIndex = queryPlan['recordIndex'] as int?;
      
      final resources = await _queryService.queryLocal(
        patientId,
        resourceType,
        filters: filters,
        recordIndex: recordIndex,
      );

      if (resources.isEmpty) {
        // Check if we should query MCP Gateway
        final fallbackToMCP = queryPlan['fallbackToMCP'] as bool? ?? true;
        if (fallbackToMCP) {
          return {
            'type': 'fallbackToMCP',
            'queryPlan': queryPlan,
            'message': 'No local data found. Querying MCP Gateway...',
          };
        }
        
        return {
          'type': 'noResults',
          'message': 'No results found in local database.',
        };
      }

      // Format results using Gemma (with RAG context)
      final markdown = await _formatResultsWithGemma(
        resources,
        resourceType,
        queryPlan,
      );

      // Add assistant response to conversation history
      _addToHistory('assistant', markdown);

      return {
        'type': 'success',
        'resources': resources,
        'markdown': markdown,
        'count': resources.length,
      };
    } catch (e) {
      debugPrint('Error executing query plan: $e');
      return {
        'type': 'error',
        'message': 'Error executing query: $e',
      };
    }
  }

  /// Build prompt for query generation
  String _buildQueryGenerationPrompt(
    String query,
    String? patientId,
    List<String> contextChunks,
  ) {
    final buffer = StringBuffer();
    
    buffer.writeln('You are a healthcare data query assistant. Your task is to convert natural language queries into structured query plans for a local FHIR database.');
    buffer.writeln();
    
    // Add conversation history
    if (_conversationHistory.length > 1) {
      buffer.writeln('## Recent Conversation');
      final recentMessages = _conversationHistory.length > 4
          ? _conversationHistory.sublist(_conversationHistory.length - 4)
          : _conversationHistory;
      for (var msg in recentMessages) {
        buffer.writeln('${msg['role']}: ${msg['content']}');
      }
      buffer.writeln();
    }
    
    // Add RAG context
    if (contextChunks.isNotEmpty) {
      buffer.writeln('## Relevant Context');
      for (var chunk in contextChunks) {
        buffer.writeln(chunk);
        buffer.writeln();
      }
    }
    
    // Add database schema context
    buffer.writeln('## Database Schema');
    buffer.writeln('The database stores FHIR resources in a table called `fhir_resources` with:');
    buffer.writeln('- patient_id: Patient identifier');
    buffer.writeln('- resource_type: FHIR resource type (Observation, Encounter, DiagnosticReport, etc.)');
    buffer.writeln('- resource_data: JSON string of complete FHIR resource');
    buffer.writeln();
    
    // Add query examples
    buffer.writeln('## Query Examples');
    buffer.writeln('''
Example 1:
Query: "show me my cholesterol levels"
Plan: {
  "resourceType": "Observation",
  "filters": {
    "codeSearch": {
      "type": "loinc",
      "codes": ["2093-3", "2085-9", "2089-1", "2571-8"],
      "display": "cholesterol"
    },
    "sort": "-effectiveDateTime"
  },
  "fallbackToMCP": true
}

Example 2:
Query: "what are my recent visits"
Plan: {
  "resourceType": "Encounter",
  "filters": {
    "sort": "-period.start",
    "limit": 10
  },
  "fallbackToMCP": true
}

Example 3:
Query: "show me record 8 of my test results"
Plan: {
  "resourceType": "DiagnosticReport",
  "filters": {
    "sort": "-effectiveDateTime"
  },
  "recordIndex": 7,
  "fallbackToMCP": true
}
''');
    buffer.writeln();
    
    if (patientId != null) {
      buffer.writeln('Current Patient ID: $patientId');
      buffer.writeln();
    }
    
    buffer.writeln('## Current Query');
    buffer.writeln('User asks: "$query"');
    buffer.writeln();
    
    buffer.writeln('## Your Task');
    buffer.writeln('Generate a JSON query plan OR ask a clarifying question if the query is ambiguous.');
    buffer.writeln();
    buffer.writeln('If the query is clear, respond with JSON:');
    buffer.writeln('{');
    buffer.writeln('  "needsClarification": false,');
    buffer.writeln('  "queryPlan": {');
    buffer.writeln('    "resourceType": "Observation|Encounter|DiagnosticReport|...",');
    buffer.writeln('    "filters": {');
    buffer.writeln('      "codeSearch": { "type": "loinc", "codes": [...], "display": "..." },');
    buffer.writeln('      "sort": "-effectiveDateTime|period.start|...",');
    buffer.writeln('      "limit": 10');
    buffer.writeln('    },');
    buffer.writeln('    "recordIndex": null or 0-based index,');
    buffer.writeln('    "fallbackToMCP": true');
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('If the query is ambiguous, respond with:');
    buffer.writeln('{');
    buffer.writeln('  "needsClarification": true,');
    buffer.writeln('  "clarificationQuestion": "What would you like to know?",');
    buffer.writeln('  "clarificationOptions": ["Option 1", "Option 2", ...]');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('Think step by step and respond with JSON only:');
    
    return buffer.toString();
  }

  /// Interpret query with RAG context (rule-based for now, will use Gemma later)
  Future<Map<String, dynamic>> _interpretQueryWithRAG(
    String query,
    List<String> contextChunks,
    String? patientId,
  ) async {
    final lowerQuery = query.toLowerCase().trim();
    
    // Check for ambiguous queries that need clarification
    if (_isAmbiguous(lowerQuery)) {
      return _generateClarificationQuestion(lowerQuery);
    }
    
    // Extract query components
    final recordNumber = _extractRecordNumber(lowerQuery);
    final specificValue = _extractSpecificValue(lowerQuery);
    final resourceType = _determineResourceType(lowerQuery, contextChunks);
    
    if (resourceType == null) {
      return {
        'needsClarification': true,
        'clarificationQuestion': 'I\'m not sure what you\'re looking for. Are you asking about:',
        'clarificationOptions': [
          'Recent visits or appointments',
          'Test results or lab reports',
          'Medications',
          'Lab values (like cholesterol, glucose)',
          'Immunizations',
        ],
      };
    }
    
    // Build query plan
    final queryPlan = <String, dynamic>{
      'resourceType': resourceType,
      'filters': <String, dynamic>{},
      'fallbackToMCP': true,
    };
    
    // Add code search for medical terms
    if (specificValue != null) {
      queryPlan['filters'] = {
        ...queryPlan['filters'] as Map<String, dynamic>,
        'codeSearch': {
          'type': 'loinc',
          'term': specificValue,
        },
      };
    }
    
    // Add record index
    if (recordNumber != null) {
      queryPlan['recordIndex'] = recordNumber - 1;
    }
    
    // Add sorting
    if (_shouldSortByDate(lowerQuery)) {
      final sortField = _getSortField(resourceType);
      queryPlan['filters'] = {
        ...queryPlan['filters'] as Map<String, dynamic>,
        'sort': '-$sortField',
      };
    }
    
    // Add limit for "recent" queries
    if (_isRecentQuery(lowerQuery)) {
      queryPlan['filters'] = {
        ...queryPlan['filters'] as Map<String, dynamic>,
        'limit': 10,
      };
    }
    
    return {
      'needsClarification': false,
      'queryPlan': queryPlan,
    };
  }

  /// Format results using Gemma with RAG context
  Future<String> _formatResultsWithGemma(
    List<Map<String, dynamic>> resources,
    String resourceType,
    Map<String, dynamic> queryPlan,
  ) async {
    // Build prompt for result formatting
    final prompt = _buildFormattingPrompt(resources, resourceType, queryPlan);
    
    // For now, use LocalQueryService formatting
    // In production, this would call Gemma 2B
    final markdown = _queryService.formatAsMarkdown(resources, resourceType);
    
    // Enhance with conversational context
    return _enhanceMarkdownWithContext(markdown, resources, resourceType);
  }

  /// Build prompt for result formatting
  String _buildFormattingPrompt(
    List<Map<String, dynamic>> resources,
    String resourceType,
    Map<String, dynamic> queryPlan,
  ) {
    final buffer = StringBuffer();
    
    buffer.writeln('You are a healthcare assistant. Format the following FHIR resources as human-readable markdown.');
    buffer.writeln();
    buffer.writeln('Resource Type: $resourceType');
    buffer.writeln('Number of Resources: ${resources.length}');
    buffer.writeln();
    buffer.writeln('Resources (JSON):');
    buffer.writeln(jsonEncode(resources));
    buffer.writeln();
    buffer.writeln('Format as markdown with:');
    buffer.writeln('- Clear headings');
    buffer.writeln('- Human-readable dates');
    buffer.writeln('- Explanations of values');
    buffer.writeln('- Normal ranges where applicable');
    buffer.writeln('- Contextual insights');
    buffer.writeln();
    buffer.writeln('Generate markdown:');
    
    return buffer.toString();
  }

  /// Enhance markdown with conversational context
  String _enhanceMarkdownWithContext(
    String markdown,
    List<Map<String, dynamic>> resources,
    String resourceType,
  ) {
    final buffer = StringBuffer();
    
    // Add friendly introduction
    if (resources.length == 1) {
      buffer.writeln('Here\'s the information you requested:\n');
    } else {
      buffer.writeln('I found ${resources.length} records. Here\'s what I found:\n');
    }
    
    buffer.writeln(markdown);
    
    // Add helpful context based on resource type
    if (resourceType == 'Observation') {
      buffer.writeln('\n---\n');
      buffer.writeln('*Note: Lab values should be interpreted by your healthcare provider. Normal ranges may vary.*');
    }
    
    return buffer.toString();
  }

  /// Check if query is ambiguous
  bool _isAmbiguous(String query) {
    final ambiguousPatterns = [
      'show me',
      'what',
      'tell me',
      'give me',
    ];
    
    // If query is too short or too generic
    if (query.split(' ').length < 3) {
      return true;
    }
    
    // If query doesn't contain specific terms
    final hasSpecificTerm = [
      'cholesterol', 'glucose', 'blood pressure', 'medication',
      'visit', 'test', 'result', 'immunization', 'vaccine',
      'record', 'level', 'value',
    ].any((term) => query.contains(term));
    
    return !hasSpecificTerm;
  }

  /// Generate clarification question
  Map<String, dynamic> _generateClarificationQuestion(String query) {
    // Analyze query to determine what might be unclear
    if (query.contains('test') || query.contains('result')) {
      return {
        'needsClarification': true,
        'clarificationQuestion': 'Are you looking for:',
        'clarificationOptions': [
          'Diagnostic reports (test results)',
          'Lab values (like cholesterol, glucose)',
          'A specific test result by number',
        ],
      };
    }
    
    if (query.contains('record') || query.contains('number')) {
      return {
        'needsClarification': true,
        'clarificationQuestion': 'Which type of record are you looking for?',
        'clarificationOptions': [
          'Test results',
          'Visits',
          'Medications',
          'Lab values',
        ],
      };
    }
    
    return {
      'needsClarification': true,
      'clarificationQuestion': 'I\'m not sure what you\'re looking for. Could you be more specific?',
      'clarificationOptions': null,
    };
  }

  /// Determine resource type from query
  String? _determineResourceType(String query, List<String> contextChunks) {
    // Check for specific resource indicators
    if (_matches(query, ['visit', 'visits', 'appointment', 'encounter'])) {
      return 'Encounter';
    }
    if (_matches(query, ['test result', 'test results', 'diagnostic report', 'lab report'])) {
      return 'DiagnosticReport';
    }
    if (_matches(query, ['medication', 'medications', 'drug', 'prescription'])) {
      return 'MedicationStatement';
    }
    if (_matches(query, ['immunization', 'vaccine', 'vaccination', 'shot'])) {
      return 'Immunization';
    }
    if (_matches(query, ['observation', 'lab value', 'level', 'cholesterol', 'glucose', 'blood pressure'])) {
      return 'Observation';
    }
    if (_matches(query, ['condition', 'diagnosis', 'problem'])) {
      return 'Condition';
    }
    
    // Try RAG service translation
    final words = query.split(' ');
    for (var word in words) {
      if (word.length > 3) {
        final translated = _ragService.translateHumanTerm(word);
        if (translated != null) {
          return translated;
        }
      }
    }
    
    return null;
  }

  /// Extract record number
  int? _extractRecordNumber(String query) {
    final patterns = [
      RegExp(r'record\s+(\d+)', caseSensitive: false),
      RegExp(r'number\s+(\d+)', caseSensitive: false),
      RegExp(r'#(\d+)', caseSensitive: false),
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  /// Extract specific value search term
  String? _extractSpecificValue(String query) {
    final medicalTerms = {
      'cholesterol': ['cholesterol', 'ldl', 'hdl', 'triglycerides'],
      'glucose': ['glucose', 'blood sugar', 'sugar', 'hba1c'],
      'blood pressure': ['blood pressure', 'bp', 'systolic', 'diastolic'],
      'hemoglobin': ['hemoglobin', 'hgb'],
      'creatinine': ['creatinine'],
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

  /// Check if should sort by date
  bool _shouldSortByDate(String query) {
    return _matches(query, ['recent', 'latest', 'newest', 'oldest', 'past', 'last']);
  }

  /// Get sort field for resource type
  String _getSortField(String resourceType) {
    switch (resourceType) {
      case 'Observation':
        return 'effectiveDateTime';
      case 'Encounter':
        return 'period.start';
      case 'DiagnosticReport':
        return 'effectiveDateTime';
      default:
        return 'date';
    }
  }

  /// Check if is recent query
  bool _isRecentQuery(String query) {
    return _matches(query, ['recent', 'latest', 'newest', 'last']);
  }

  /// Helper to match query against keywords
  bool _matches(String query, List<String> keywords) {
    return keywords.any((keyword) => query.contains(keyword));
  }

  /// Add message to conversation history
  void _addToHistory(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    // Keep only last 10 messages
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeAt(0);
    }
  }

  /// Clear conversation history
  void clearHistory() {
    _conversationHistory.clear();
  }

  /// Get conversation history
  List<Map<String, String>> get conversationHistory => List.unmodifiable(_conversationHistory);
}



