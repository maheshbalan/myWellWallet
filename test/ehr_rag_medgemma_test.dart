import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:mywellwallet/config/app_config.dart';

/// EHR RAG COMPREHENSIVE AGENTIC TEST
void main() async {
  final modelPath = '/home/eli/snap/code/226/.local/share/com.mywellwallet.mywellwallet/models/medgemma-4b-it-Q4_K_M.gguf';
  
  try {
    print('--- EHR AGENTIC END-TO-END TEST ---');
    
    // 1. Initialize MCP Session
    print('Initializing MCP Session...');
    final initResponse = await http.post(
      Uri.parse('${AppConfig.mcpBaseUrl}/mcp'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'X-API-Key': AppConfig.mcpApiKey,
      },
      body: jsonEncode({
        'jsonrpc': '2.0', 'id': 'test', 'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'capabilities': {},
          'clientInfo': {'name': 'tester', 'version': '1.0.0'}
        }
      }),
    );

    String? sessionId = initResponse.headers['mcp-session-id'];
    if (sessionId == null) return;

    print('\n--- Initializing MedGemma 4B ---');
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(modelPath, modelParams: const ModelParams(gpuLayers: 0));

    final presets = [
      'Show me my immunization record',
      'Show me my recent visits',
      'Show me my Test Results'
    ];

    String patientId = '14171df9-ec64-4993-abbf-341e8f57c2a7';

    for (var query in presets) {
      print('\n' + '='*60);
      print('USER QUERY: "$query"');
      print('='*60);

      // STEP 1: Select Data Retrieval Tool
      final agentPrompt = _buildAgenticQueryPrompt(query, patientId);
      String agentDecision = '';
      stdout.write('AI Selecting Tool...');
      await for (final token in engine.generate(agentPrompt)) {
        agentDecision += token;
      }
      final decisionJson = '{"tool":' + agentDecision;
      print('\nAI Data Decision: $decisionJson');

      final decoded = jsonDecode(decisionJson);
      final toolName = decoded['tool'];
      final toolArgs = decoded['arguments'];

      // STEP 2: Fetch Data
      print('\n[Step 2: Fetching Data]');
      final dataResult = await _callMcpTool(sessionId, toolName, toolArgs);

      // Extraction & Distillation
      final entries = _findEntries(dataResult);
      print('Entries found: ${entries.length}');
      
      final distilled = _distillClinicalRecords(entries.take(5).toList());
      print('Distilled Data: ${jsonEncode(distilled)}');

      // PHASE 3: Summary
      print('\n[Step 3: AI Summary]');
      final summPrompt = _buildSummarizationPrompt(query, distilled);
      
      stdout.write('MedGemma Assistant: ');
      await for (final token in engine.generate(summPrompt)) {
        stdout.write(token);
      }
      print('\n');
    }

    await engine.dispose();
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}

Future<dynamic> _callMcpTool(String sessionId, String toolName, dynamic arguments) async {
  final response = await http.post(
    Uri.parse('${AppConfig.mcpBaseUrl}/mcp'),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'X-API-Key': AppConfig.mcpApiKey,
      'Mcp-Session-Id': sessionId,
    },
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 'call',
      'method': 'tools/call',
      'params': {
        'name': toolName,
        'arguments': arguments
      }
    }),
  );

  final lines = response.body.split('\n');
  for (var line in lines) {
    if (line.startsWith('data: ')) {
      final data = jsonDecode(line.substring(6));
      final text = data['result']?['content']?[0]?['text'];
      if (text != null) {
        return text is String ? jsonDecode(text) : text;
      }
    }
  }
  return null;
}

List<dynamic> _findEntries(dynamic data) {
  if (data == null) return [];
  if (data is List) return data;
  if (data is! Map) return [];
  if (data.containsKey('result')) return _findEntries(data['result']);
  if (data.containsKey('response')) return _findEntries(data['response']);
  if (data.containsKey('entry')) return data['entry'] is List ? data['entry'] : [];
  if (data.containsKey('resources')) return data['resources'] is List ? data['resources'] : [];
  if (data.containsKey('resourceType')) {
    if (data['resourceType'] == 'Bundle' && !data.containsKey('entry')) return [];
    return [data];
  }
  return [];
}

List<Map<String, dynamic>> _distillClinicalRecords(List<dynamic> resources) {
  return resources.map((entry) {
    final res = entry is Map && entry.containsKey('resource') ? entry['resource'] : entry;
    final type = res['resourceType'] ?? 'Record';
    final Map<String, dynamic> distilled = {'type': type};

    final date = res['occurrenceDateTime'] ?? res['effectiveDateTime'] ?? res['period']?['start'] ?? res['date'];
    if (date != null) distilled['date'] = date.toString().split('T')[0];

    if (type == 'Immunization') {
      distilled['vaccine'] = res['vaccineCode']?['text'] ?? 'Vaccine';
    } else if (type == 'Observation') {
      distilled['name'] = res['code']?['text'] ?? 'Test';
      distilled['value'] = '${res['valueQuantity']?['value'] ?? ''} ${res['valueQuantity']?['unit'] ?? ''}'.trim();
    } else if (type == 'Encounter') {
      distilled['reason'] = res['reasonCode']?[0]?['text'] ?? res['type']?[0]?['text'] ?? 'Visit';
    }
    
    return distilled;
  }).toList();
}

String _buildAgenticQueryPrompt(String query, String patientId) {
  return '''<start_of_turn>user
You are a FHIR agent. Select one of these allowed tools for the query: "$query"
Patient ID: $patientId

Allowed Tools:
- request_observation_resource: Use for labs, vitals (subject=Patient/ID)
- request_encounter_resource: Use for medical visits (subject=Patient/ID)
- request_immunization_resource: Use for vaccines (patient=Patient/ID)
- request_condition_resource: Use for medical problems (patient=Patient/ID)
- request_generic_resource: Use for DiagnosticReport, other (subject=Patient/ID)

Task: Provide the tool name and JSON arguments.
Format: {"tool": "TOOL_NAME", "arguments": {"request": {"method": "GET", "path": "/RESOURCE?FILTER=Patient/$patientId"}}}
<end_of_turn>
<start_of_turn>model
{"tool":''';
}

String _buildSummarizationPrompt(String query, List<Map<String, dynamic>> distilledData) {
  final recordsText = distilledData.isEmpty ? "NO RECORDS FOUND" : jsonEncode(distilledData);
  return '''<start_of_turn>user
Summarize these records for: "$query"

Data:
$recordsText

Instructions:
- Mention specific names and dates found.
- Be supportive and concise.
<end_of_turn>
<start_of_turn>model
''';
}
