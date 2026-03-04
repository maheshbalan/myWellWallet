import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_rag_service.dart';
import 'local_query_service.dart';
import 'database_service.dart';
import 'gemma_model_service.dart';
import 'log_service.dart';

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
    
    // Start Gemma model initialization (downloading if needed) in the background
    // We don't await it here so the app can still function with rule-based fallback
    unawaited(GemmaModelService.instance.ensureInitialized());
    
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
    
    Map<String, dynamic>? interpretation;

    // Try to use local Gemma for interpretation if ready
    final gemma = GemmaModelService.instance;
    if (gemma.isReady) {
      try {
        LogService.log('GemmaRAGService: Using local Gemma for interpretation.');
        final prompt = _buildQueryGenerationPrompt(query, patientId, contextChunks);
        final response = await gemma.generate(prompt);
        
        if (response != null) {
          interpretation = _parseGemmaJsonResponse(response);
          LogService.log('GemmaRAGService: Gemma interpretation: ${jsonEncode(interpretation)}');
        }
      } catch (e) {
        LogService.log('GemmaRAGService: Local Gemma interpretation failed: $e');
      }
    }

    // Fallback to rule-based interpretation if Gemma not ready or failed
    if (interpretation == null) {
      LogService.log('GemmaRAGService: Falling back to rule-based interpretation.');
      interpretation = await _interpretQueryWithRAG(
        query,
        contextChunks,
        patientId,
      );
    }

    // Check if clarification is needed
    if (interpretation['needsClarification'] == true) {
      return {
        'type': 'clarification',
        'question': interpretation['clarificationQuestion'] as String,
        'options': interpretation['clarificationOptions'] != null 
            ? List<String>.from(interpretation['clarificationOptions'] as List)
            : null,
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

  /// Parse JSON from Gemma's response (handles cases where Gemma adds extra text)
  Map<String, dynamic>? _parseGemmaJsonResponse(String response) {
    try {
      // Find the first '{' and last '}'
      final start = response.indexOf('{');
      final end = response.lastIndexOf('}');
      if (start == -1 || end == -1) return null;
      
      final jsonStr = response.substring(start, end + 1);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error parsing JSON from Gemma: $e');
      return null;
    }
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
            'message': 'No local data found for $resourceType. Querying FHIR server...',
          };
        }
        
        return {
          'type': 'noResults',
          'message': 'I couldn\'t find any $resourceType records in your local database. You might need to use the "Fetch My Health Data" feature first.',
        };
      }

      // Return raw resources so the UI can use the streaming GemmaService for summarization
      return {
        'type': 'success',
        'resources': resources,
        'resourceType': resourceType,
        'count': resources.length,
      };
    } catch (e) {
      LogService.log('Error executing query plan: $e');
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
    
    buffer.writeln('You are MyWellWallet, a healthcare data assistant. Convert natural language to structured JSON query plans.');
    buffer.writeln();
    
    buffer.writeln('## Available FHIR Resources:');
    buffer.writeln('- DiagnosticReport: Use for "test results", "lab results", "imaging", "reports".');
    buffer.writeln('- Observation: Use for "vital signs", "blood pressure", "glucose", "heart rate", "measurements", "lab values".');
    buffer.writeln('- Encounter: Use for "visits", "appointments", "checkups", "admissions".');
    buffer.writeln('- MedicationStatement: Use for "medications", "prescriptions", "drugs", "current meds".');
    buffer.writeln('- Immunization: Use for "vaccines", "shots", "vaccination record".');
    buffer.writeln('- Condition: Use for "diagnoses", "health problems", "illnesses", "medical conditions".');
    buffer.writeln('- Procedure: Use for "surgeries", "operations", "medical procedures".');
    buffer.writeln();

    if (contextChunks.isNotEmpty) {
      buffer.writeln('## Medical Reference Context:');
      for (var chunk in contextChunks.take(3)) {
        buffer.writeln(chunk);
      }
      buffer.writeln();
    }
    
    buffer.writeln('## User Query: "$query"');
    buffer.writeln();
    buffer.writeln('## Task:');
    buffer.writeln('Respond ONLY with a JSON object. Decide if the query is clear enough to map to a resource type.');
    buffer.writeln('1. If clear: {"needsClarification": false, "queryPlan": {"resourceType": "DiagnosticReport", "filters": {"sort": "-date"}}}');
    buffer.writeln('2. If ambiguous: {"needsClarification": true, "clarificationQuestion": "Would you like to see your lab results or your medical visits?"}');
    
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
    
    // Try to use on-device Gemma (via GemmaModelService) if configured.
    String? markdown;
    try {
      final gemma = GemmaModelService.instance;
      if (gemma.isConfigured) {
        markdown = await gemma.generate(prompt);
      }
    } catch (e, st) {
      debugPrint('GemmaRAGService: Gemma model formatting failed: $e');
      debugPrint('$st');
    }

    // Fallback to LocalQueryService formatting if Gemma is not available.
    markdown ??= _queryService.formatAsMarkdown(resources, resourceType);
    
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
    buffer.writeln('Format these $resourceType records as a concise markdown summary with dates and values:');
    buffer.writeln(jsonEncode(resources.take(3).toList()));
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
    final lowerQuery = query.toLowerCase();
    
    // 1. Try RAG service translation first (now more robust)
    // Check the whole query string first
    String? translated = _ragService.translateHumanTerm(lowerQuery);
    if (translated != null) return translated;

    // 2. Try individual words
    final words = lowerQuery.split(' ');
    for (var word in words) {
      if (word.length > 3) {
        translated = _ragService.translateHumanTerm(word);
        if (translated != null) return translated;
      }
    }
    
    // 3. Fallback to hardcoded keywords if RAG translation fails
    if (_matches(lowerQuery, ['visit', 'visits', 'appointment', 'encounter'])) {
      return 'Encounter';
    }
    if (_matches(lowerQuery, ['test result', 'test results', 'diagnostic report', 'lab report'])) {
      return 'DiagnosticReport';
    }
    if (_matches(lowerQuery, ['medication', 'medications', 'drug', 'prescription'])) {
      return 'MedicationStatement';
    }
    if (_matches(lowerQuery, ['immunization', 'vaccine', 'vaccination', 'shot'])) {
      return 'Immunization';
    }
    if (_matches(lowerQuery, ['observation', 'lab value', 'level', 'cholesterol', 'glucose', 'blood pressure'])) {
      return 'Observation';
    }
    if (_matches(lowerQuery, ['condition', 'diagnosis', 'problem'])) {
      return 'Condition';
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



