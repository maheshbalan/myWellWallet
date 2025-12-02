import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

/// MCP Client for connecting to FHIR MCP Server via HTTP/SSE
class MCPClient {
  final String baseUrl;
  final String apiKey;
  String? _sessionId;
  bool _initialized = false;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  MCPClient({required this.baseUrl, required this.apiKey});

  bool get isInitialized => _initialized;

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
          'X-API-Key': apiKey,
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
        debugPrint('Init response headers: ${initResponse.headers}');
        
        // Check if session ID is in response headers (case-insensitive)
        String? sessionIdFromHeader;
        for (var key in initResponse.headers.keys) {
          if (key.toLowerCase() == 'mcp-session-id') {
            sessionIdFromHeader = initResponse.headers[key];
            break;
          }
        }
        if (sessionIdFromHeader != null && sessionIdFromHeader.isNotEmpty) {
          _sessionId = sessionIdFromHeader;
          debugPrint('MCP Session ID from header: $_sessionId');
        }
        
        // Try parsing as JSON first (non-SSE response)
        if (_sessionId == null) {
          try {
            final jsonData = jsonDecode(responseBody);
            debugPrint('Parsed JSON response: $jsonData');
            if (jsonData['result'] != null) {
              _sessionId = jsonData['result']['sessionId'] as String?;
              _sessionId ??= jsonData['result']['session_id'] as String?;
              if (_sessionId != null) {
                debugPrint('MCP Session ID from JSON result: $_sessionId');
              }
            }
            // Also check top level
            _sessionId ??= jsonData['sessionId'] as String?;
            _sessionId ??= jsonData['session_id'] as String?;
          } catch (e) {
            debugPrint('Error parsing as JSON: $e');
            // If not JSON, try parsing as SSE
            final lines = responseBody.split('\n');
            for (final line in lines) {
              if (line.startsWith('data: ')) {
                try {
                  final data = jsonDecode(line.substring(6));
                  debugPrint('Parsed SSE data: $data');
                  if (data['id'] != null && data['result'] != null) {
                    _sessionId = data['result']['sessionId'] as String?;
                    _sessionId ??= data['result']['session_id'] as String?;
                    _sessionId ??= data['sessionId'] as String?;
                    _sessionId ??= data['session_id'] as String?;
                    if (_sessionId != null) {
                      debugPrint('MCP Session ID from SSE: $_sessionId');
                      break;
                    }
                  }
                } catch (e) {
                  debugPrint('Error parsing SSE line: $e');
                }
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
          
          try {
            final notifyResponse = await http.post(
              Uri.parse('$baseUrl/mcp'),
              headers: initNotifyHeaders,
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'notifications/initialized',
              }),
            );
            debugPrint('Initialized notification sent. Status: ${notifyResponse.statusCode}');
            debugPrint('Initialized notification response: ${notifyResponse.body}');
            
            // Small delay to ensure server processes initialized notification
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint('Warning: Failed to send initialized notification: $e');
            // Continue anyway - some servers may not require this
          }
        } else {
          debugPrint('Warning: Session ID not found in init response');
          // Try to reinitialize
          _initialized = false;
          throw Exception('Session ID not received from server');
        }

        _initialized = true;
        debugPrint('MCP Client initialized successfully with session: $_sessionId');
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
    debugPrint('Calling tool: $toolName with arguments: $arguments');
    
    // Ensure we're initialized
    if (!_initialized || _sessionId == null) {
      await initialize();
    }
    
    final result = await _sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    
    debugPrint('Tool call result: $result');
    
    // Check for errors in response
    if (result['result'] != null && result['result']['isError'] == true) {
      final errorText = result['result']['content']?[0]?['text'] as String?;
      if (errorText != null) {
        throw Exception('Server error: $errorText');
      }
    }
    
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
      // Accept header must include both application/json and text/event-stream
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
        Map<String, dynamic>? foundResponse;
        
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            try {
              final data = jsonDecode(line.substring(6));
              // Match by request ID
              if (data['id'] != null && data['id'].toString() == requestId.toString()) {
                foundResponse = data;
                break;
              }
              // Also check if it's the only response
              if (foundResponse == null && data['id'] != null) {
                foundResponse = data;
              }
            } catch (e) {
              debugPrint('Error parsing SSE line: $e, line: $line');
            }
          }
        }
        
        if (foundResponse != null) {
          _pendingRequests.remove(requestId);
          if (foundResponse['error'] != null) {
            final errorMsg = foundResponse['error']['message'] ?? 'Unknown error';
            completer.completeError(Exception(errorMsg));
          } else {
            completer.complete(foundResponse);
          }
        } else {
          // No matching response found
          _pendingRequests.remove(requestId);
          completer.completeError(Exception('No response received for request $requestId'));
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

  /// Search patients using FHIR search parameters
  Future<List<Patient>> searchPatients({
    String? name,
    String? birthdate,
  }) async {
    String path = '/Patient';
    List<String> params = [];
    
    if (name != null && name.isNotEmpty) {
      params.add('name=$name');
    }
    if (birthdate != null && birthdate.isNotEmpty) {
      params.add('birthdate=$birthdate');
    }
    
    if (params.isNotEmpty) {
      path += '?${params.join('&')}';
    }
    
    debugPrint('Searching patients with path: $path');
    
    final result = await callTool('request_patient_resource', {
      'request': {
        'method': 'GET',
        'path': path,
        'body': null,
      }
    });

    // Parse result - server now returns structuredContent or content with text
    var resultData = result['result'];
    
    // Check for structuredContent first (new format)
    if (resultData is Map && resultData.containsKey('structuredContent')) {
      final structured = resultData['structuredContent'] as Map;
      if (structured.containsKey('result')) {
        resultData = structured['result'] as Map;
      }
    }
    
    // Fallback to content[0].text format
    if (resultData is Map && resultData.containsKey('content')) {
      final content = resultData['content'] as List;
      if (content.isNotEmpty) {
        final contentItem = content[0] as Map;
        // Check if text is a string or already parsed
        if (contentItem.containsKey('text')) {
          final textContent = contentItem['text'];
          if (textContent is String) {
            resultData = jsonDecode(textContent);
          } else if (textContent is Map) {
            resultData = textContent;
          }
        }
      }
    }

    // Extract response from resultData
    if (resultData is Map && resultData.containsKey('response')) {
      final response = resultData['response'] as Map;
      if (response.containsKey('entry')) {
        final entries = response['entry'] as List;
        return entries.map((entry) {
          try {
            final resource = entry['resource'] as Map<String, dynamic>;
            // Clean up the resource to ensure all fields are properly typed
            final cleanedResource = _cleanPatientResource(resource);
            return Patient.fromJson(cleanedResource);
          } catch (e) {
            debugPrint('Error parsing patient resource in searchPatients: $e');
            rethrow;
          }
        }).toList();
      }
    }

    return [];
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

    // Parse result - server now returns structuredContent or content with text
    var resultData = result['result'];
    
    // Check for structuredContent first (new format)
    if (resultData is Map && resultData.containsKey('structuredContent')) {
      final structured = resultData['structuredContent'] as Map;
      if (structured.containsKey('result')) {
        resultData = structured['result'] as Map;
      }
    }
    
    // Fallback to content[0].text format
    if (resultData is Map && resultData.containsKey('content')) {
      final content = resultData['content'] as List;
      if (content.isNotEmpty) {
        final contentItem = content[0] as Map;
        // Check if text is a string or already parsed
        if (contentItem.containsKey('text')) {
          final textContent = contentItem['text'];
          if (textContent is String) {
            resultData = jsonDecode(textContent);
          } else if (textContent is Map) {
            resultData = textContent;
          }
        }
      }
    }

    // Extract response from resultData
    if (resultData is Map && resultData.containsKey('response')) {
      final response = resultData['response'] as Map;
      if (response.containsKey('entry')) {
        final entries = response['entry'] as List;
        return entries.map((entry) {
          try {
            final resource = entry['resource'] as Map<String, dynamic>;
            // Clean up the resource to ensure all fields are properly typed
            final cleanedResource = _cleanPatientResource(resource);
            return Patient.fromJson(cleanedResource);
          } catch (e) {
            debugPrint('Error parsing patient resource in getPatients: $e');
            rethrow;
          }
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

    // Parse result - server now returns structuredContent or content with text
    var resultData = result['result'];
    
    // Check for structuredContent first (new format)
    if (resultData is Map && resultData.containsKey('structuredContent')) {
      final structured = resultData['structuredContent'] as Map;
      if (structured.containsKey('result')) {
        resultData = structured['result'] as Map;
      }
    }
    
    // Fallback to content[0].text format
    if (resultData is Map && resultData.containsKey('content')) {
      final content = resultData['content'] as List;
      if (content.isNotEmpty) {
        final contentItem = content[0] as Map;
        // Check if text is a string or already parsed
        if (contentItem.containsKey('text')) {
          final textContent = contentItem['text'];
          if (textContent is String) {
            resultData = jsonDecode(textContent);
          } else if (textContent is Map) {
            resultData = textContent;
          }
        }
      }
    }

    // Extract response - could be direct response or nested in response field
    Map<String, dynamic>? patientData;
    if (resultData is Map) {
      if (resultData.containsKey('response')) {
        patientData = resultData['response'] as Map<String, dynamic>;
      } else if (resultData.containsKey('resourceType') && resultData['resourceType'] == 'Patient') {
        // Direct patient resource
        patientData = resultData as Map<String, dynamic>;
      }
    }

    if (patientData != null) {
      try {
        // Clean up the resource to ensure all fields are properly typed
        final cleanedResource = _cleanPatientResource(patientData);
        return Patient.fromJson(cleanedResource);
      } catch (e) {
        debugPrint('Error parsing patient resource in getPatientDetails: $e');
        rethrow;
      }
    }

    throw Exception('Invalid patient data: No patient resource found in response');
  }

  /// Clean patient resource to handle FHIR complex types that might be Maps instead of Strings
  Map<String, dynamic> _cleanPatientResource(Map<String, dynamic> resource) {
    final cleaned = Map<String, dynamic>.from(resource);
    
    // Handle top-level fields that should be String but might be Map
    if (cleaned.containsKey('gender') && cleaned['gender'] is Map) {
      final genderMap = cleaned['gender'] as Map;
      cleaned['gender'] = genderMap['value'] ?? genderMap['code'] ?? null;
    }
    
    if (cleaned.containsKey('birthDate') && cleaned['birthDate'] is Map) {
      final birthDateMap = cleaned['birthDate'] as Map;
      cleaned['birthDate'] = birthDateMap['value'] ?? birthDateMap['date'] ?? null;
    }
    
    // Handle identifier.type which might be a CodeableConcept (Map) instead of String
    if (cleaned.containsKey('identifier') && cleaned['identifier'] is List) {
      final identifiers = (cleaned['identifier'] as List).map((id) {
        if (id is Map) {
          final idMap = Map<String, dynamic>.from(id);
          // If type is a Map (CodeableConcept), extract text or code
          if (idMap.containsKey('type') && idMap['type'] is Map) {
            final typeMap = idMap['type'] as Map;
            if (typeMap.containsKey('text')) {
              idMap['type'] = typeMap['text'] as String?;
            } else if (typeMap.containsKey('coding') && (typeMap['coding'] as List).isNotEmpty) {
              final coding = (typeMap['coding'] as List).first as Map;
              idMap['type'] = coding['display'] ?? coding['code'] ?? null;
            } else {
              idMap['type'] = null;
            }
          }
          return idMap;
        }
        return id;
      }).toList();
      cleaned['identifier'] = identifiers;
    }
    
    // Handle name array - ensure all fields are properly typed
    if (cleaned.containsKey('name') && cleaned['name'] is List) {
      final names = (cleaned['name'] as List).map((name) {
        if (name is Map) {
          final nameMap = Map<String, dynamic>.from(name);
          // Ensure use, family are strings
          if (nameMap.containsKey('use') && nameMap['use'] is Map) {
            nameMap['use'] = (nameMap['use'] as Map)['value'] ?? null;
          }
          if (nameMap.containsKey('family') && nameMap['family'] is Map) {
            nameMap['family'] = (nameMap['family'] as Map)['value'] ?? null;
          }
          // Ensure given is a List<String>
          if (nameMap.containsKey('given') && nameMap['given'] is List) {
            nameMap['given'] = (nameMap['given'] as List).map((g) {
              if (g is Map) {
                return (g as Map)['value'] ?? g['code'] ?? null;
              }
              return g;
            }).whereType<String>().toList();
          }
          return nameMap;
        }
        return name;
      }).toList();
      cleaned['name'] = names;
    }
    
    return cleaned;
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  void dispose() {
    // Cleanup if needed
  }
}


