import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Local RAG Service for query interpretation
/// 
/// This service loads documentation from the docs/ directory and provides
/// context-aware query interpretation. It helps Gemma understand:
/// 1. How to query the local SQLite database
/// 2. How to query the FHIR MCP Gateway server
/// 3. Medical term translations (human language to FHIR terms)
class LocalRAGService {
  static const String _docsPath = 'docs';
  
  // Cached document content
  String? _fhirGlossary;
  String? _sqliteSchema;
  String? _mcpClientGuide;
  String? _mcpServerReadme;
  
  bool _initialized = false;

  /// Initialize by loading all documentation
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      debugPrint('Initializing LocalRAGService: Loading documentation...');
      
      // Load documents from assets (they should be in assets/docs/)
      // For now, we'll load them directly from the docs/ directory
      // In production, these should be bundled as assets
      
      _fhirGlossary = await _loadDocument('FHIR_MEDICAL_GLOSSARY.md');
      _sqliteSchema = await _loadDocument('SQLITE_SCHEMA.md');
      _mcpClientGuide = await _loadDocument('README_MOBILE_CLIENT.md');
      _mcpServerReadme = await _loadDocument('FHIR_MCP_SERVER_README.md');
      
      _initialized = true;
      debugPrint('LocalRAGService initialized successfully');
    } catch (e) {
      debugPrint('Error initializing LocalRAGService: $e');
      // Continue with empty documents - will use fallback
      _initialized = true;
    }
  }

  /// Load a document from the docs directory
  Future<String?> _loadDocument(String filename) async {
    try {
      // Try to load from assets first (if bundled)
      try {
        // In this app, docs are bundled directly under `docs/` (see pubspec.yaml).
        return await rootBundle.loadString('docs/$filename');
      } catch (e) {
        // If not in assets, try to read from file system (for development)
        try {
          final file = File('$_docsPath/$filename');
          if (await file.exists()) {
            return await file.readAsString();
          }
        } catch (e2) {
          debugPrint('Could not read file system: $e2');
        }
      }
    } catch (e) {
      debugPrint('Could not load document $filename: $e');
    }
    return null;
  }

  /// Retrieve relevant context for a query
  /// Returns relevant chunks from documentation that match the query
  Future<List<String>> retrieveContext(String query) async {
    if (!_initialized) {
      await initialize();
    }
    
    final lowerQuery = query.toLowerCase();
    final contextChunks = <String>[];
    
    // Extract keywords from query
    final keywords = _extractKeywords(lowerQuery);
    
    // 1. Check FHIR Medical Glossary for term translations
    if (_fhirGlossary != null) {
      final glossaryChunks = _findRelevantChunks(_fhirGlossary!, keywords);
      if (glossaryChunks.isNotEmpty) {
        contextChunks.add('=== FHIR Medical Glossary ===');
        contextChunks.addAll(glossaryChunks);
      }
    }
    
    // 2. Check SQLite Schema for database query patterns
    if (_sqliteSchema != null && _shouldQueryLocal(lowerQuery)) {
      final schemaChunks = _findRelevantChunks(_sqliteSchema!, keywords);
      if (schemaChunks.isNotEmpty) {
        contextChunks.add('=== SQLite Database Schema ===');
        contextChunks.addAll(schemaChunks);
      }
    }
    
    // 3. Check MCP Client Guide for server query syntax
    if (_mcpClientGuide != null && _shouldQueryMCP(lowerQuery)) {
      final mcpChunks = _findRelevantChunks(_mcpClientGuide!, keywords);
      if (mcpChunks.isNotEmpty) {
        contextChunks.add('=== MCP Gateway Query Syntax ===');
        contextChunks.addAll(mcpChunks);
      }
    }
    
    // 4. Add MCP Server README for tool information
    if (_mcpServerReadme != null) {
      final serverChunks = _findRelevantChunks(_mcpServerReadme!, keywords);
      if (serverChunks.isNotEmpty) {
        contextChunks.add('=== MCP Server Tools ===');
        contextChunks.addAll(serverChunks);
      }
    }
    
    return contextChunks;
  }

  /// Extract keywords from query
  List<String> _extractKeywords(String query) {
    // Common stop words to filter out
    const stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'my', 'me', 'i', 'show', 'what', 'when',
      'where', 'how', 'is', 'are', 'was', 'were', 'be', 'been', 'have', 'has',
      'had', 'do', 'does', 'did', 'will', 'would', 'can', 'could', 'should',
    };
    
    final words = query.split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .where((word) => !stopWords.contains(word.toLowerCase()))
        .toList();
    
    return words;
  }

  /// Find relevant chunks in a document based on keywords
  List<String> _findRelevantChunks(String document, List<String> keywords) {
    final chunks = <String>[];
    final lines = document.split('\n');
    
      // Look for sections that contain keywords
      final List<String> currentChunk = [];
    
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Check if line is a section header
      if (line.startsWith('#') || line.startsWith('##') || line.startsWith('###')) {
        // Save previous chunk if it's relevant
        if (currentChunk.isNotEmpty && _chunkContainsKeywords(currentChunk.join('\n'), keywords)) {
          chunks.add(currentChunk.join('\n'));
        }
        currentChunk.clear();
        currentChunk.add(line);
      } else if (line.trim().isNotEmpty) {
        currentChunk.add(line);
        
        // Limit chunk size (keep last 10 lines per chunk)
        if (currentChunk.length > 10) {
          currentChunk.removeAt(0);
        }
      }
      
      // Check if current line contains keywords
      if (_lineContainsKeywords(line, keywords)) {
        // Include surrounding context (3 lines before and after)
        final start = i > 3 ? i - 3 : 0;
        final end = i + 3 < lines.length ? i + 3 : lines.length;
        final context = lines.sublist(start, end + 1).join('\n');
        if (!chunks.contains(context)) {
          chunks.add(context);
        }
      }
    }
    
    // Save last chunk if relevant
    if (currentChunk.isNotEmpty && _chunkContainsKeywords(currentChunk.join('\n'), keywords)) {
      chunks.add(currentChunk.join('\n'));
    }
    
    // Return top 5 most relevant chunks
    return chunks.take(5).toList();
  }

  /// Check if a line contains any keywords
  bool _lineContainsKeywords(String line, List<String> keywords) {
    final lowerLine = line.toLowerCase();
    return keywords.any((keyword) => lowerLine.contains(keyword.toLowerCase()));
  }

  /// Check if a chunk contains keywords
  bool _chunkContainsKeywords(String chunk, List<String> keywords) {
    final lowerChunk = chunk.toLowerCase();
    return keywords.any((keyword) => lowerChunk.contains(keyword.toLowerCase()));
  }

  /// Determine if query should query local database first
  bool _shouldQueryLocal(String query) {
    // Queries that typically need local data first
    final localIndicators = [
      'my', 'recent', 'latest', 'current', 'show me', 'list', 'get',
      'timeline', 'history', 'record', 'data', 'information',
    ];
    return localIndicators.any((indicator) => query.contains(indicator));
  }

  /// Determine if query might need MCP Gateway
  bool _shouldQueryMCP(String query) {
    // Queries that might need server data
    final mcpIndicators = [
      'fetch', 'download', 'sync', 'update', 'get from server',
      'retrieve', 'pull', 'connect',
    ];
    return mcpIndicators.any((indicator) => query.contains(indicator));
  }

  /// Build a prompt for Gemma with RAG context
  String buildPrompt(
    String query,
    String? patientId,
    List<String> contextChunks,
  ) {
    final buffer = StringBuffer();
    
    buffer.writeln('You are a healthcare assistant that converts natural language queries to database queries and FHIR MCP Gateway queries.');
    buffer.writeln();
    
    if (contextChunks.isNotEmpty) {
      buffer.writeln('=== RELEVANT CONTEXT ===');
      for (var chunk in contextChunks) {
        buffer.writeln(chunk);
        buffer.writeln();
      }
    }
    
    buffer.writeln('=== QUERY INSTRUCTIONS ===');
    buffer.writeln('1. FIRST, try to answer the query using the LOCAL SQLite database.');
    buffer.writeln('2. If data is not found locally, THEN query the FHIR MCP Gateway server.');
    buffer.writeln('3. Use the context above to understand:');
    buffer.writeln('   - How to translate human terms to FHIR resource types');
    buffer.writeln('   - How to construct SQLite queries');
    buffer.writeln('   - How to construct MCP Gateway queries');
    buffer.writeln();
    
    if (patientId != null) {
      buffer.writeln('Current Patient ID: $patientId');
      buffer.writeln();
    }
    
    buffer.writeln('User Query: "$query"');
    buffer.writeln();
    buffer.writeln('Convert this query to a JSON object with:');
    buffer.writeln('{');
    buffer.writeln('  "queryType": "local" | "mcp" | "both",');
    buffer.writeln('  "localQuery": {');
    buffer.writeln('    "resourceType": "FHIR resource type (e.g., Encounter, Observation)",');
    buffer.writeln('    "sqlQuery": "SQL query for SQLite (optional, if needed)",');
    buffer.writeln('    "filters": { "key": "value" }');
    buffer.writeln('  },');
    buffer.writeln('  "mcpQuery": {');
    buffer.writeln('    "tool": "MCP tool name (e.g., request_encounter_resource)",');
    buffer.writeln('    "params": {');
    buffer.writeln('      "request": {');
    buffer.writeln('        "method": "GET",');
    buffer.writeln('        "path": "/ResourceType?search_params",');
    buffer.writeln('        "body": null');
    buffer.writeln('      }');
    buffer.writeln('    }');
    buffer.writeln('  },');
    buffer.writeln('  "intent": "user intent description"');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('Examples:');
    buffer.writeln('Query: "show me my recent visits"');
    buffer.writeln('Response: {"queryType": "local", "localQuery": {"resourceType": "Encounter", "filters": {"sort": "-date", "limit": 10}}, "intent": "recent_visits"}');
    buffer.writeln();
    buffer.writeln('Query: "show me my test results"');
    buffer.writeln('Response: {"queryType": "local", "localQuery": {"resourceType": "DiagnosticReport", "filters": {"sort": "-date"}}, "intent": "test_results"}');
    buffer.writeln();
    buffer.writeln('Query: "fetch my health data"');
    buffer.writeln('Response: {"queryType": "mcp", "mcpQuery": {"tool": "request_patient_resource", "params": {"request": {"method": "GET", "path": "/Patient/{patientId}", "body": null}}}, "intent": "fetch_data"}');
    buffer.writeln();
    buffer.writeln('Response (JSON only, no explanation):');
    
    return buffer.toString();
  }

  /// Get SQLite query examples for a resource type
  String? getSQLiteQueryExample(String resourceType) {
    if (_sqliteSchema == null) return null;
    
    // Extract relevant SQL examples from schema doc
    final lines = _sqliteSchema!.split('\n');
    final examples = <String>[];
    bool inExample = false;
    String? currentExample;
    
    for (var line in lines) {
      if (line.contains('```sql') || line.contains('```')) {
        if (inExample && currentExample != null) {
          if (currentExample.toLowerCase().contains(resourceType.toLowerCase())) {
            examples.add(currentExample);
          }
          currentExample = null;
        }
        inExample = !inExample;
      } else if (inExample) {
        currentExample = (currentExample ?? '') + line + '\n';
      }
    }
    
    return examples.isNotEmpty ? examples.first : null;
  }

  /// Get FHIR resource type from human term
  String? translateHumanTerm(String humanTerm) {
    if (_fhirGlossary == null) return null;
    
    final lowerTerm = humanTerm.toLowerCase();
    final lines = _fhirGlossary!.split('\n');
    
    // Look for mappings in the glossary
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.toLowerCase().contains(lowerTerm)) {
        // Look for FHIR Resource: pattern
        for (var j = i; j < i + 10 && j < lines.length; j++) {
          if (lines[j].contains('**FHIR Resource**:') || lines[j].contains('FHIR Resource:')) {
            final resourceLine = lines[j];
            final match = RegExp(r'`(\w+)`').firstMatch(resourceLine);
            if (match != null) {
              return match.group(1);
            }
          }
        }
      }
    }
    
    return null;
  }
}

