import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_rag_service.dart';
import 'local_query_service.dart';
import 'database_service.dart';
import 'gemma_model_service.dart';
import 'log_service.dart';
import 'prompt_sanitizer.dart';

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
    addToHistory('user', query);

    // Retrieve relevant context from RAG
    final contextChunks = await _ragService.retrieveContext(query);
    
    Map<String, dynamic>? interpretation;

    // 1. Try rule-based interpretation FIRST (it's instant and reliable for presets)
    LogService.log('GemmaRAGService: Attempting rule-based interpretation.');
    interpretation = await _interpretQueryWithRAG(
      query,
      contextChunks,
      patientId,
    );

    // 2. Use MedGemma ONLY if rule-based is unsure or needs clarification
    final gemma = GemmaModelService.instance;
    if ((interpretation == null || interpretation['needsClarification'] == true) && gemma.isReady) {
      try {
        LogService.log('GemmaRAGService: Rule-based unsure, using MedGemma 4B to generate clinical query plan...');
        final prompt = _buildQueryGenerationPrompt(query, patientId, contextChunks);
        
        // 15-second timeout for query generation
        final response = await gemma.generate(prompt).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            LogService.log('GemmaRAGService: MedGemma interpretation timed out.');
            return null;
          },
        );
        
        if (response != null) {
          final gemmaPlan = _parseGemmaJsonResponse(response);
          if (gemmaPlan != null && gemmaPlan['queryPlan'] != null) {
            interpretation = gemmaPlan;
            LogService.log('GemmaRAGService: MedGemma generated a specialized query plan.');
          }
        }
      } catch (e) {
        LogService.log('GemmaRAGService: MedGemma query generation failed: $e');
      }
    }

    // Check if clarification is needed
    if (interpretation == null) {
      return {
        'type': 'error',
        'message': 'Failed to interpret query.',
      };
    }

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

  /// Parse JSON from Gemma's response
  Map<String, dynamic>? _parseGemmaJsonResponse(String response) {
    try {
      // If we provided a prefix like '{"needsClarification":', Gemma might only return the rest.
      // We prepend the prefix if the response doesn't start with '{'
      String fullJson = response.trim();
      if (!fullJson.startsWith('{')) {
        fullJson = '{"needsClarification":' + fullJson;
      }

      // Find the first '{' and last '}'
      final start = fullJson.indexOf('{');
      final end = fullJson.lastIndexOf('}');
      if (start == -1 || end == -1) return null;

      final jsonStr = fullJson.substring(start, end + 1);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      LogService.log('Error parsing JSON from MedGemma: $e');
      return null;
    }
  }
  /// Execute a query plan and format results
  Future<Map<String, dynamic>> executeQueryPlan(
    Map<String, dynamic> queryPlan,
    String patientId, {
    String? appUserId,
  }) async {
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
        appUserId: appUserId,
        queryPlan: queryPlan,
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
String _formatHistory() {
  if (_conversationHistory.isEmpty) return '';
  final buffer = StringBuffer();
  // Use up to last 4 turns for context
  final recentHistory = _conversationHistory.length > 8
      ? _conversationHistory.sublist(_conversationHistory.length - 8)
      : _conversationHistory;

  // We don't include the very last entry if it's the current query
  final historyToInclude = recentHistory.isNotEmpty && recentHistory.last['role'] == 'user'
      ? recentHistory.sublist(0, recentHistory.length - 1)
      : recentHistory;

  if (historyToInclude.isEmpty) return '';

  buffer.writeln('\nPrevious conversation context:');
  for (var msg in historyToInclude) {
    final role = msg['role'] == 'user' ? 'User' : 'Assistant';
    // Sanitize content so a prior turn with injected control markers
    // can't corrupt the current prompt (WP1-06).
    final content = sanitizeForPrompt(msg['content'] ?? '');
    buffer.writeln('$role: $content');
  }
  buffer.writeln();
  return buffer.toString();
}

/// Build prompt for query generation
String _buildQueryGenerationPrompt(
  String query,
  String? patientId,
  List<String> contextChunks,
) {
  // Sanitize user input + history content before interpolating. Prevents
  // a user query containing Gemma control markers from escaping the user
  // turn in the query-generation prompt (WP1-06).
  final safeQuery = sanitizeForPrompt(query);
  final history = _formatHistory();
  final docContext = contextChunks.isEmpty
      ? ''
      : () {
          final j = contextChunks.take(8).join('\n---\n');
          final t = j.length > 8000 ? '${j.substring(0, 8000)}…' : j;
          return '\n\nRelevant documentation:\n$t\n';
        }();

  return '''<start_of_turn>user
You are a FHIR clinical agent. Convert this query into a FHIR JSON query plan.
$history
Patient ID: $patientId
User question: "$safeQuery"
$docContext
Guidelines:
...
- Use subject=Patient/$patientId for: Observation, Encounter, DiagnosticReport.
- Use patient=Patient/$patientId for: Immunization, MedicationStatement, Condition, AllergyIntolerance.
- Use request_generic_resource for resources not listed.
- Apple Health syncs into SQLite (health_glucose, health_heart_rate, health_steps, health_blood_pressure, health_lab_results) and is merged into FHIR-like Observations with meta.tag apple-health. LOINC examples: glucose 2339-0 / HbA1c 4548-4, steps 55423-8, heart rate 8867-4.
- For glucose/CGM/blood sugar/A1c questions you MUST narrow results so step counts do not dominate:
  "resourceType": "Observation", "filters": {"_count": 50, "_sort": "-date", "codeSearch": "glucose"}, "dataSources": ["ehr-fhir", "apple-health"]
- For steps/walking only: "codeSearch": "steps" with the same dataSources.
- For generic vitals without a single focus, still use "dataSources": ["ehr-fhir", "apple-health"] but omit codeSearch only if the user truly wants all vitals.

Response Format:
{"needsClarification": false, "queryPlan": {"resourceType": "TYPE", "filters": {"_count": 10, "_sort": "-date"}, "dataSources": ["ehr-fhir", "apple-health"]}}

Respond ONLY with valid JSON.
<end_of_turn>
<start_of_turn>model
{"needsClarification":''';
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

    // Use refined rule-based interpretation
    final result = _interpretWithRules(lowerQuery, contextChunks);
    if (result != null) {
      return result;
    }

    // Default fallback if everything else fails
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
    return false; // Let AI decide if it needs clarification via prompt
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

  /// Determine query plan from query using rule-based logic
  Map<String, dynamic>? _interpretWithRules(String query, List<String> contextChunks) {
    final lowerQuery = query.toLowerCase();
    LogService.log('GemmaRAGService: _interpretWithRules query: "$lowerQuery"');

    // 1. Glucose / CGM / A1c before generic Observation (avoids step-count rows crowding merged Apple Health data).
    if (_matchesGlucoseIntent(lowerQuery)) {
      LogService.log('GemmaRAGService: Preset match -> Observation (glucose / Apple Health + EHR)');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'Observation',
          'filters': {'_count': 50, '_sort': '-date', 'codeSearch': 'glucose'},
          'dataSources': ['ehr-fhir', 'apple-health'],
        },
      };
    }

    // 2. Steps / activity — use word boundaries so "step" does not match unrelated words.
    if (_matchesStepsIntent(lowerQuery)) {
      LogService.log('GemmaRAGService: Preset match -> Observation (steps / Apple Health)');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'Observation',
          'filters': {'_count': 30, '_sort': '-date', 'codeSearch': 'steps'},
          'dataSources': ['ehr-fhir', 'apple-health'],
        },
      };
    }
    if (_matches(lowerQuery, ['immunization', 'vaccine', 'vaccination', 'shot'])) {
      LogService.log('GemmaRAGService: Preset match -> Immunization');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'Immunization',
          'filters': {'_count': 10, '_sort': '-date'}
        }
      };
    }
    if (_matches(lowerQuery, ['visit', 'visits', 'appointment', 'encounter'])) {
      LogService.log('GemmaRAGService: Preset match -> Encounter');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'Encounter',
          'filters': {'_count': 10, '_sort': '-date'}
        }
      };
    }
    if (_matches(lowerQuery, ['test result', 'test results', 'diagnostic report', 'lab report'])) {
      LogService.log('GemmaRAGService: Preset match -> DiagnosticReport');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'DiagnosticReport',
          'filters': {'_count': 10, '_sort': '-date'}
        }
      };
    }
    if (_matches(lowerQuery, ['medication', 'medicine', 'drug', 'prescription', 'pill', 'rx'])) {
      LogService.log('GemmaRAGService: Preset match -> MedicationStatement');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'MedicationStatement',
          'filters': {'_count': 20, '_sort': '-date'}
        }
      };
    }
    if (_matches(lowerQuery, ['allergy', 'allergies', 'allergic'])) {
      LogService.log('GemmaRAGService: Preset match -> AllergyIntolerance');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'AllergyIntolerance',
          'filters': {'_count': 20, '_sort': '-date'}
        }
      };
    }
    if (_matches(lowerQuery, ['condition', 'diagnosis', 'diagnoses', 'diagnosed', 'chronic', 'disease', 'illness', 'problem list'])) {
      LogService.log('GemmaRAGService: Preset match -> Condition');
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'Condition',
          'filters': {'_count': 20, '_sort': '-date'}
        }
      };
    }
    if (_matches(lowerQuery, ['observation', 'lab value', 'level', 'cholesterol', 'blood pressure', 'vital', 'heart rate']) ||
        RegExp(r'\bhr\b').hasMatch(lowerQuery)) {
      LogService.log('GemmaRAGService: Keyword match -> Observation');
      final specific = _extractSpecificValue(lowerQuery);
      final filters = <String, dynamic>{
        '_count': specific != null ? 40 : 20,
        '_sort': '-date',
        if (specific != null) 'codeSearch': specific,
      };
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': 'Observation',
          'filters': filters,
          'dataSources': ['ehr-fhir', 'apple-health'],
        },
      };
    }

    // 3. Try RAG service translation
    String? translated = _ragService.translateHumanTerm(lowerQuery);
    if (translated == null) {
      final words = lowerQuery.split(' ');
      for (var word in words) {
        if (word.length > 3) {
          translated = _ragService.translateHumanTerm(word);
          if (translated != null) {
            LogService.log('GemmaRAGService: RAG translated word "$word" to $translated');
            break;
          }
        }
      }
    } else {
      LogService.log('GemmaRAGService: RAG translated full query to $translated');
    }

    if (translated != null) {
      if (translated == 'Observation') {
        final specific = _extractSpecificValue(lowerQuery);
        return {
          'needsClarification': false,
          'queryPlan': {
            'resourceType': 'Observation',
            'filters': {
              '_count': specific != null ? 40 : 20,
              '_sort': '-date',
              if (specific != null) 'codeSearch': specific,
            },
            'dataSources': ['ehr-fhir', 'apple-health'],
          },
        };
      }
      return {
        'needsClarification': false,
        'queryPlan': {
          'resourceType': translated,
          'filters': {'_count': 10, '_sort': '-date'}
        }
      };
    }
    
    LogService.log('GemmaRAGService: No rule-based match found.');
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

  static final RegExp _stepsIntent = RegExp(
    r'\b(steps?|walking|walked|step\s*count|activity\s+rings?)\b',
    caseSensitive: false,
  );

  bool _matchesStepsIntent(String q) => _stepsIntent.hasMatch(q);

  bool _matchesGlucoseIntent(String q) {
    if (RegExp(r'\b(glucose|glycemic)\b', caseSensitive: false).hasMatch(q)) {
      return true;
    }
    if (q.contains('blood sugar') || q.contains('blood glucose')) return true;
    if (RegExp(r'\b(cgm|dexcom|freestyle\s*libre|libre)\b', caseSensitive: false).hasMatch(q)) {
      return true;
    }
    if (RegExp(r'\b(a1c|hba1c|hemoglobin\s*a1c)\b', caseSensitive: false).hasMatch(q)) {
      return true;
    }
    return false;
  }

  /// Add message to conversation history
  void addToHistory(String role, String content) {
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



