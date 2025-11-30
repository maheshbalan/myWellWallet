import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

/// MCP Client for connecting to FHIR MCP Server via HTTP/SSE
class MCPClient {
  final String baseUrl;
  String? _sessionId;
  bool _initialized = false;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  MCPClient({required this.baseUrl});

  /// Initialize MCP session
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Send initialize request
      final initResponse = await http.post(
        Uri.parse('$baseUrl/mcp'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': _generateId(),
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-06-18',
            'capabilities': {},
            'clientInfo': {'name': 'mywellwallet', 'version': '1.0.0'}
          }
        }),
      );

      if (initResponse.statusCode == 200) {
        // Parse SSE response or JSON response
        String responseBody = initResponse.body;
        debugPrint('Init response body: $responseBody');
        
        // Try parsing as JSON first (non-SSE response)
        try {
          final jsonData = jsonDecode(responseBody);
          if (jsonData['result'] != null) {
            _sessionId = jsonData['result']['sessionId'] as String?;
            if (_sessionId != null) {
              debugPrint('MCP Session initialized with ID: $_sessionId');
            }
          }
        } catch (e) {
          // If not JSON, try parsing as SSE
          final lines = responseBody.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              try {
                final data = jsonDecode(line.substring(6));
                if (data['id'] != null && data['result'] != null) {
                  _sessionId = data['result']['sessionId'] as String?;
                  if (_sessionId == null) {
                    // Try alternative paths
                    _sessionId = data['result']?['session_id'] as String?;
                    _sessionId ??= data['sessionId'] as String?;
                  }
                  if (_sessionId != null) {
                    debugPrint('MCP Session initialized with ID: $_sessionId');
                  }
                  break;
                }
              } catch (e) {
                debugPrint('Error parsing SSE line: $e');
              }
            }
          }
        }

        // Send initialized notification with session ID
        // Notifications don't have 'id' field in JSON-RPC 2.0
        if (_sessionId != null) {
          final initNotifyHeaders = <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'Mcp-Session-Id': _sessionId!,
          };
          
          await http.post(
            Uri.parse('$baseUrl/mcp'),
            headers: initNotifyHeaders,
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'notifications/initialized',
              'params': {'sessionId': _sessionId},
            }),
          );
          debugPrint('Initialized notification sent with session ID: $_sessionId');
        } else {
          debugPrint('Warning: Session ID not found in init response');
          // Try to reinitialize
          _initialized = false;
          throw Exception('Session ID not received from server');
        }

        _initialized = true;
      } else {
        debugPrint('Init failed with status: ${initResponse.statusCode}, body: ${initResponse.body}');
        throw Exception('Failed to initialize: ${initResponse.statusCode}');
      }
    } catch (e) {
      throw Exception('Initialization error: $e');
    }
  }

  /// List available tools
  Future<List<Map<String, dynamic>>> listTools() async {
    final result = await _sendRequest('tools/list', {});
    return List<Map<String, dynamic>>.from(result['result']?['tools'] ?? []);
  }

  /// Call an MCP tool
  Future<Map<String, dynamic>> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    return result;
  }

  /// Send MCP request
  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!_initialized) {
      await initialize();
    }

    // Ensure we have a session ID
    if (_sessionId == null) {
      await initialize();
    }

    final requestId = _generateId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    try {
      // Build headers with session ID - REQUIRED for all requests after initialize
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      };
      
      // Session ID is REQUIRED in header for all requests after initialization
      if (_sessionId == null) {
        throw Exception('Session ID is required but not available. Please reinitialize.');
      }
      
      // Add session ID to header - this is the primary method per MCP spec
      headers['Mcp-Session-Id'] = _sessionId!;
      debugPrint('Sending $method request with session ID in header: $_sessionId');

      // Build request body - don't add sessionId to params/arguments
      // The server should read it from the header
      final requestParams = Map<String, dynamic>.from(params);

      final response = await http.post(
        Uri.parse('$baseUrl/mcp'),
        headers: headers,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': method,
          'params': requestParams,
        }),
      );

      if (response.statusCode == 200) {
        // Parse SSE response
        final lines = response.body.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            try {
              final data = jsonDecode(line.substring(6));
              if (data['id'] == requestId) {
                _pendingRequests.remove(requestId);
                if (data['error'] != null) {
                  final errorMsg = data['error']['message'] ?? 'Unknown error';
                  completer.completeError(Exception(errorMsg));
                } else {
                  completer.complete(data);
                }
                break;
              }
            } catch (e) {
              // Continue parsing
            }
          }
        }

        // Wait for response with timeout
        return await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            _pendingRequests.remove(requestId);
            throw TimeoutException('Request timeout');
          },
        );
      } else {
        _pendingRequests.remove(requestId);
        // Try to parse error response
        try {
          final errorData = jsonDecode(response.body);
          final errorMsg = errorData['error']?['message'] ?? 
                         'HTTP error: ${response.statusCode}';
          throw Exception(errorMsg);
        } catch (e) {
          throw Exception('HTTP error: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  /// Get list of patients
  Future<List<Patient>> getPatients() async {
    final result = await callTool('request_patient_resource', {
      'request': {
        'method': 'GET',
        'path': '/Patient',
        'body': null,
      }
    });

    // Parse result
    var resultData = result['result'];
    if (resultData is Map && resultData.containsKey('content')) {
      final content = resultData['content'] as List;
      if (content.isNotEmpty) {
        final textContent = content[0]['text'] as String;
        resultData = jsonDecode(textContent);
      }
    }

    if (resultData is Map && resultData.containsKey('response')) {
      final response = resultData['response'] as Map;
      if (response.containsKey('entry')) {
        final entries = response['entry'] as List;
        return entries.map((entry) {
          final resource = entry['resource'] as Map<String, dynamic>;
          return Patient.fromJson(Map<String, dynamic>.from(resource));
        }).toList();
      }
    }

    return [];
  }

  /// Get patient details by ID
  Future<Patient> getPatientDetails(String patientId) async {
    final result = await callTool('request_patient_resource', {
      'request': {
        'method': 'GET',
        'path': '/Patient/$patientId',
        'body': null,
      }
    });

    // Parse result
    var resultData = result['result'];
    if (resultData is Map && resultData.containsKey('content')) {
      final content = resultData['content'] as List;
      if (content.isNotEmpty) {
        final textContent = content[0]['text'] as String;
        resultData = jsonDecode(textContent);
      }
    }

    if (resultData is Map && resultData.containsKey('response')) {
      final patientData = resultData['response'] as Map<String, dynamic>;
      return Patient.fromJson(Map<String, dynamic>.from(patientData));
    }

    throw Exception('Invalid patient data');
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  void dispose() {
    // Cleanup if needed
  }
}

