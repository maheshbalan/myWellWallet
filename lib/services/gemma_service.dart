import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_rag_service.dart';
import 'gemma_model_service.dart';
import 'log_service.dart';

/// Gemma LLM Service for local NLP processing
class GemmaService {
  final List<Map<String, String>> _conversationHistory = [];
  final LocalRAGService _ragService = LocalRAGService();
  bool _ragInitialized = false;

  void setContext(String context) {}

  void addToHistory(String role, String message) {
    _conversationHistory.add({'role': role, 'content': message});
    // Keep only last 10 turns to avoid hitting token limits
    if (_conversationHistory.length > 10) _conversationHistory.removeAt(0);
  }

  Future<Map<String, dynamic>> interpretQueryWithContext(String query, {String? patientId}) async {
    if (!_ragInitialized) {
      await _ragService.initialize();
      _ragInitialized = true;
    }
    final contextChunks = await _ragService.retrieveContext(query);
    return _interpretWithRAGContext(query, contextChunks, patientId);
  }

  Stream<String> generateStreamingResponse(String query, Map<String, dynamic>? fhirData) async* {
    if (fhirData == null || fhirData.isEmpty) {
      yield 'I couldn\'t find any matching health records. Please ensure your data is synced.';
      return;
    }

    final gemma = GemmaModelService.instance;
    final summary = _getSummaryList(fhirData);
    
    if (summary.isEmpty) {
      yield 'I found your health records, but they are in a format I\'m still learning to read. Here is a technical summary:\n\n${jsonEncode(fhirData).substring(0, 200)}...';
      return;
    }

    // Record user query in history BEFORE generating response
    addToHistory('user', query);

    if (gemma.isReady) {
      try {
        if (!_ragInitialized) {
          await _ragService.initialize();
          _ragInitialized = true;
        }
        final contextChunks = await _ragService.retrieveContext(query);
        final prompt = _buildResponsePrompt(query, summary, contextChunks);
        
        LogService.log('GemmaService: Sending prompt with history to local model...');
        
        bool receivedTokens = false;
        String fullResponse = '';
        await for (final token in gemma.generateStream(prompt)) {
          receivedTokens = true;
          fullResponse += token;
          yield token;
        }
        
        if (receivedTokens) {
          // Record model response in history
          addToHistory('model', fullResponse.trim());
        } else {
          final fallback = _formatSummaryAsMarkdown(summary);
          addToHistory('model', fallback);
          yield fallback;
        }
        return;
      } catch (e) {
        LogService.log('GemmaService: Error $e');
        final errSummary = 'AI Error. Here is a summary of your records:\n\n${_formatSummaryAsMarkdown(summary)}';
        addToHistory('model', errSummary);
        yield errSummary;
      }
    } else {
      final fallback = _formatSummaryAsMarkdown(summary);
      addToHistory('model', fallback);
      yield fallback;
    }
  }

  /// Recursively finds a list of resources/entries in a nested map
  List<dynamic> _findEntries(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return [];
    
    if (data.containsKey('entry') && data['entry'] is List) return data['entry'];
    if (data.containsKey('resources') && data['resources'] is List) return data['resources'];
    
    if (data.containsKey('result')) return _findEntries(data['result']);
    if (data.containsKey('response')) return _findEntries(data['response']);
    if (data.containsKey('structuredContent')) return _findEntries(data['structuredContent']);
    
    if (data.containsKey('resourceType') || data.containsKey('type')) return [data];
    
    return [];
  }

  List<Map<String, dynamic>> _getSummaryList(Map<String, dynamic> fhirData) {
    try {
      final List<Map<String, dynamic>> summary = [];
      final List<dynamic> entries = _findEntries(fhirData);

      for (var entry in entries.take(10)) {
        final res = entry is Map && entry.containsKey('resource') ? entry['resource'] : entry;
        if (res is! Map) continue;

        final type = (res['resourceType'] ?? res['type'] ?? 'Record').toString();
        final Map<String, dynamic> item = {'Type': type};

        final String date = _formatDateString(
          res['effectiveDateTime'] ?? 
          res['period']?['start'] ?? 
          res['date'] ?? 
          res['issued'] ?? 
          res['recordedDate']
        );
        item['Date'] = date;

        if (type == 'Observation') {
          item['Test'] = res['code']?['text'] ?? res['code']?['coding']?[0]?['display'] ?? 'Lab Test';
          item['Result'] = '${res['valueQuantity']?['value'] ?? res['valueString'] ?? ''} ${res['valueQuantity']?['unit'] ?? ''}'.trim();
        } else if (type == 'Encounter') {
          item['Visit Reason'] = res['reasonCode']?[0]?['text'] ?? res['type']?[0]?['text'] ?? 'Medical Visit';
          item['Status'] = res['status'] ?? 'Completed';
        } else if (type.contains('Medication')) {
          item['Medication'] = res['medicationCodeableConcept']?['text'] ?? res['medicationReference']?['display'] ?? res['code']?['text'] ?? 'Prescription';
          item['Status'] = res['status'];
        } else {
          item['Details'] = res['id'] ?? 'N/A';
        }
        summary.add(item);
      }
      return summary;
    } catch (e) {
      LogService.log('Summary error: $e');
      return [];
    }
  }

  String _formatSummaryAsMarkdown(List<Map<String, dynamic>> summary) {
    final buffer = StringBuffer();
    for (var item in summary) {
      final type = item['Type'] ?? 'Record';
      final date = item['Date'] ?? 'Recent';
      buffer.writeln('### $type ($date)');
      item.forEach((k, v) {
        if (k != 'Type' && k != 'Date' && v != null && v.toString().isNotEmpty) {
          buffer.writeln('* **$k**: $v');
        }
      });
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _formatDateString(dynamic date) {
    if (date == null) return 'Recent';
    final s = date.toString();
    if (s.contains('T')) return s.split('T').first;
    return s;
  }

  String _buildResponsePrompt(String query, List<Map<String, dynamic>> summary, [List<String>? contextChunks]) {
    final recordsText = summary.map((s) => '- ${s.entries.map((e) => "${e.key}: ${e.value}").join(", ")}').join('\n');
    
    final buffer = StringBuffer();
    buffer.writeln('<start_of_turn>user');
    buffer.writeln('You are MyWellWallet, a friendly health assistant. Use the history and records below to answer.');
    buffer.writeln();

    // Add Conversation History (last 4 turns)
    if (_conversationHistory.isNotEmpty) {
      buffer.writeln('## RECENT CONVERSATION:');
      final recent = _conversationHistory.length > 4 
          ? _conversationHistory.sublist(_conversationHistory.length - 4) 
          : _conversationHistory;
      for (var msg in recent) {
        buffer.writeln('${msg['role'] == 'user' ? 'User' : 'Assistant'}: ${msg['content']}');
      }
      buffer.writeln();
    }

    buffer.writeln('## NEW RECORDS FOR THIS QUESTION:');
    buffer.writeln(recordsText);
    buffer.writeln();
    buffer.writeln('USER QUESTION: "$query"');
    buffer.writeln();
    buffer.writeln('INSTRUCTIONS:');
    buffer.writeln('- Speak like a friendly human expert.');
    buffer.writeln('- Be concise. No "AI" or "Based on data" disclaimers.');
    buffer.writeln('<end_of_turn>');
    buffer.writeln('<start_of_turn>model');

    return buffer.toString();
  }

  void clearContext() {
    _conversationHistory.clear();
  }

  Map<String, dynamic> _interpretWithRAGContext(String query, List<String> contextChunks, String? patientId) {
    final lower = query.toLowerCase();
    String resource = 'Observation';
    if (lower.contains('visit') || lower.contains('encounter')) resource = 'Encounter';
    if (lower.contains('med') || lower.contains('drug')) resource = 'MedicationStatement';
    return {
      'queryType': 'local',
      'localQuery': {'resourceType': resource, 'filters': {'limit': 10}},
      'intent': 'list_data'
    };
  }
}
