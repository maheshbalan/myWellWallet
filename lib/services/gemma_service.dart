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
    final gemma = GemmaModelService.instance;
    final List<Map<String, dynamic>> summary = (fhirData != null && fhirData.isNotEmpty)
        ? _getSummaryList(fhirData, query)
        : <Map<String, dynamic>>[];
    
    // Record user query in history BEFORE generating response
    addToHistory('user', query);

    if (gemma.isReady) {
      try {
        if (!_ragInitialized) {
          await _ragService.initialize();
          _ragInitialized = true;
        }
        final contextChunks = await _ragService.retrieveContext(query);
        
        String prompt;
        if (fhirData == null || fhirData.isEmpty) {
          prompt = _buildNoDataResponsePrompt(query, contextChunks);
        } else if (summary.isEmpty) {
          prompt = _buildRawDataResponsePrompt(query, fhirData, contextChunks);
        } else {
          prompt = _buildResponsePrompt(query, summary, contextChunks);
        }
        
        LogService.log('GemmaService: Generating AI response...');
        
        bool receivedTokens = false;
        String fullResponse = '';
        
        // Use a 90-second timeout for the stream on CPU
        final stream = gemma.generateStream(prompt).timeout(
          const Duration(seconds: 90),
          onTimeout: (sink) {
            LogService.log('GemmaService: MedGemma stream timed out.');
            sink.close();
          },
        );

        await for (final token in stream) {
          receivedTokens = true;
          fullResponse += token;
          yield token;
        }
        
        if (receivedTokens) {
          addToHistory('model', fullResponse.trim());
        } else {
          LogService.log('GemmaService: AI yielded no tokens. Falling back to structured view.');
          if (summary.isNotEmpty) {
            yield _formatSummaryAsMarkdown(summary);
          } else {
            yield 'I processed your request but found no clinical records to display. Please ensure your data is synced with the Medplum server.';
          }
        }
        return;
      } catch (e) {
        LogService.log('GemmaService: AI Error: $e');
        if (summary.isNotEmpty) {
          yield 'I encountered an error. Here is a summary of your records:\n\n${_formatSummaryAsMarkdown(summary)}';
        } else {
          yield 'I encountered an error analyzing your health records.';
        }
      }
    } else {
      LogService.log('GemmaService: Model not ready, using structured fallback.');
      if (summary.isNotEmpty) {
        yield _formatSummaryAsMarkdown(summary);
      } else {
        yield 'MedGemma AI is still initializing (~2.5GB model). Please try again in a moment.';
      }
    }
  }

  String _buildNoDataResponsePrompt(String query, [List<String>? contextChunks]) {
    return '''<start_of_turn>user
You are MyWellWallet, a specialized medical AI assistant.
The user asked: "$query"

However, no health records were found in the local database or Medplum server for this specific request.

Instructions:
1. Explain clearly that no records were found matching their query.
2. Suggest that they may need to sync their data or that the records haven't been created yet.
3. Keep it professional, supportive, and concise.
4. Do not mention being an AI.
<end_of_turn>
<start_of_turn>model
''';
  }

  String _buildRawDataResponsePrompt(String query, Map<String, dynamic> rawData, [List<String>? contextChunks]) {
    // Truncate raw data if too large for prompt
    final rawJson = jsonEncode(rawData);
    final dataSubset = rawJson.length > 4000 ? rawJson.substring(0, 4000) : rawJson;

    return '''<start_of_turn>user
You are MyWellWallet, a specialized medical AI assistant.
The user asked: "$query"

Here is the RAW FHIR EHR data from the server. It may contain technical metadata (like "method", "path", "jsonrpc") which you should IGNORE. Focus ONLY on the clinical records found in the "response" or "entry" fields.

Data:
$dataSubset

Instructions:
1. Summarize the actual clinical information (vaccines, visits, test results) clearly for the patient.
2. If the clinical data is empty, explain that no matching records were found.
3. Use a professional, supportive medical tone.
4. Do not mention technical fields or being an AI.
<end_of_turn>
<start_of_turn>model
''';
  }

  String _buildResponsePrompt(String query, List<Map<String, dynamic>> summary, [List<String>? contextChunks]) {
    final recordsText = summary.map((s) => jsonEncode(s)).join('\n');
    final q = query.toLowerCase();
    final glucoseHint = (q.contains('glucose') ||
            q.contains('blood sugar') ||
            q.contains('cgm') ||
            q.contains('a1c') ||
            q.contains('hba1c'))
        ? '\n7. The user asked about glucose or CGM: summarize blood glucose and HbA1c-related lines only; ignore step counts or unrelated vitals unless none exist.'
        : '';

    return '''<start_of_turn>user
You are MyWellWallet, a specialized medical AI assistant.
The user asked: "$query"

Here are the specific EHR records retrieved for this request (may include Apple Health–synced Observations tagged in source data):
$recordsText

Instructions:
1. Summarize ONLY the records provided above.
2. If the records are Immunizations, focus on vaccines and dates. 
3. If the records are Observations, focus on lab values and vitals.
4. Mention specific names, values, and dates found in the data.
5. Use a professional and supportive medical tone.
6. Be concise and do not mention being an AI.$glucoseHint
<end_of_turn>
<start_of_turn>model
''';
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

  /// Recursively finds a list of resources/entries in a nested map
  List<dynamic> _findEntries(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return [];
    
    // 1. Peeling off common JSON-RPC and MCP wrappers FIRST
    if (data.containsKey('result')) {
      return _findEntries(data['result']);
    }
    if (data.containsKey('response')) {
      return _findEntries(data['response']);
    }
    if (data.containsKey('structuredContent')) {
      return _findEntries(data['structuredContent']);
    }

    // 2. Handle MCP tool call result format: content[0].text (which is a JSON string)
    if (data.containsKey('content')) {
      final content = data['content'];
      if (content is List && content.isNotEmpty) {
        final firstContent = content[0];
        if (firstContent is Map && firstContent.containsKey('text')) {
          final text = firstContent['text'];
          if (text is String && text.trim().startsWith('{')) {
            try {
              final decoded = jsonDecode(text);
              LogService.log('GemmaService: Decoded nested JSON from content.text');
              return _findEntries(decoded);
            } catch (e) {
              LogService.log('GemmaService: Failed to decode content.text: $e');
            }
          } else if (text is Map) {
            return _findEntries(text);
          }
        }
      }
    }

    // 3. Look for the actual data arrays
    if (data.containsKey('entry')) {
      final entry = data['entry'];
      return (entry is List) ? entry : [];
    }
    if (data.containsKey('resources')) {
      final resources = data['resources'];
      return (resources is List) ? resources : [];
    }
    
    // 4. If it's a single FHIR resource, return it as a list of one
    if (data.containsKey('resourceType')) {
      // If it's a Bundle with no entry, it's effectively empty
      if (data['resourceType'] == 'Bundle' && !data.containsKey('entry')) {
        return [];
      }
      return [data];
    }
    
    return [];
  }

  /// Re-order observations so the user's topic (e.g. glucose) is not buried under frequent step-count rows.
  List<dynamic> _prioritizeEntriesForUserQuestion(String userQuery, List<dynamic> entries) {
    final q = userQuery.toLowerCase();
    final wantGlucose = q.contains('glucose') ||
        q.contains('blood sugar') ||
        q.contains('blood glucose') ||
        RegExp(r'\b(cgm|dexcom|libre|a1c|hba1c)\b').hasMatch(q);
    final wantSteps =
        RegExp(r'\b(steps?|walking|walked|step\s*count)\b', caseSensitive: false).hasMatch(q);
    if (!wantGlucose && !wantSteps) return entries;

    final preferred = <dynamic>[];
    final rest = <dynamic>[];
    for (final entry in entries) {
      final res = entry is Map && entry.containsKey('resource') ? entry['resource'] : entry;
      if (res is! Map || res['resourceType'] != 'Observation') {
        rest.add(entry);
        continue;
      }
      final code = res['code'];
      String text = '';
      String? loinc;
      if (code is Map) {
        text = (code['text'] as String?)?.toLowerCase() ?? '';
        final coding = code['coding'];
        if (coding is List && coding.isNotEmpty && coding.first is Map) {
          loinc = (coding.first as Map)['code'] as String?;
        }
      }
      bool isGlucose = text.contains('glucose') ||
          text.contains('blood sugar') ||
          text.contains('a1c') ||
          text.contains('hba1c') ||
          loinc == '2339-0' ||
          loinc == '4548-4';
      bool isSteps =
          text.contains('step') || loinc == '55423-8' || loinc == '41950-7';

      if (wantGlucose && isGlucose) {
        preferred.add(entry);
      } else if (wantSteps && isSteps) {
        preferred.add(entry);
      } else {
        rest.add(entry);
      }
    }
    if (wantGlucose && preferred.isNotEmpty) return [...preferred, ...rest];
    if (wantSteps && preferred.isNotEmpty) return [...preferred, ...rest];
    return entries;
  }

  List<Map<String, dynamic>> _getSummaryList(Map<String, dynamic> fhirData, [String userQuery = '']) {
    try {
      final List<Map<String, dynamic>> summary = [];
      var entries = _findEntries(fhirData);
      if (userQuery.isNotEmpty) {
        entries = _prioritizeEntriesForUserQuestion(userQuery, entries);
      }

      for (var entry in entries.take(24)) {
        final res = entry is Map && entry.containsKey('resource') ? entry['resource'] : entry;
        if (res is! Map) continue;

        final type = (res['resourceType'] ?? res['type'] ?? 'Record').toString();
        final Map<String, dynamic> item = {'Type': type};

        final String date = _formatDateString(
          res['occurrenceDateTime'] ??
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
        } else if (type == 'Immunization') {
          item['Vaccine'] = res['vaccineCode']?['text'] ?? res['vaccineCode']?['coding']?[0]?['display'] ?? 'Vaccination';
          item['Status'] = res['status'] ?? 'Completed';
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
}
