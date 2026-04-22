import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

/// MCP Client with persistent session management for FHIR MCP Server
/// This follows the README_MOBILE_CLIENT.md recommendation for persistent session
/// Note: For mobile, we maintain session state via session ID in headers rather than true SSE stream
class MCPClientSSE {
  final String baseUrl;
  final String apiKey;
  String? _sessionId;
  bool _initialized = false;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  Timer? _keepAliveTimer;

  MCPClientSSE({required this.baseUrl, required this.apiKey});

  String? get sessionId => _sessionId;

  /// Initialize MCP session with persistent session management
  Future<void> initialize() async {
    if (_initialized && _sessionId != null) return;

    try {
      debugPrint('Initializing MCP SSE connection to: $baseUrl/mcp');
      
      // First, send initialize request via HTTP to get session ID
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
        // Extract session ID from headers
        String? sessionIdFromHeader;
        for (var key in initResponse.headers.keys) {
          if (key.toLowerCase() == 'mcp-session-id') {
            sessionIdFromHeader = initResponse.headers[key];
            break;
          }
        }
        
        if (sessionIdFromHeader == null || sessionIdFromHeader.isEmpty) {
          throw Exception('Session ID not received from server');
        }
        
        _sessionId = sessionIdFromHeader;
        debugPrint('Session ID received: $_sessionId');
        
        // Parse SSE response to get initialization result
        final lines = initResponse.body.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            try {
              final data = jsonDecode(line.substring(6));
              debugPrint('Initialize response: $data');
              break;
            } catch (e) {
              debugPrint('Error parsing init response: $e');
            }
          }
        }
        
        // Send initialized notification
        await http.post(
          Uri.parse('$baseUrl/mcp'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'X-API-Key': apiKey,
            'Mcp-Session-Id': _sessionId!,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          }),
        );
        
        // Session established - maintain it via keep-alive
        _startKeepAlive();
        
        _initialized = true;
        debugPrint('MCP Client initialized successfully with persistent session');
      } else {
        throw Exception('Failed to initialize: ${initResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      _initialized = false;
      rethrow;
    }
  }

  /// Start keep-alive to maintain session
  void _startKeepAlive() {
    // Start keep-alive timer (send ping every 30 seconds to maintain session)
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _sendKeepAlive();
    });
    debugPrint('Keep-alive timer started');
  }

  /// Handle incoming SSE events (from HTTP POST responses)
  void _handleSSEResponse(String responseBody, String requestId) {
    try {
      // Parse SSE format from response body
      final lines = responseBody.split('\n');
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final jsonData = jsonDecode(line.substring(6));
          final responseId = jsonData['id']?.toString();
          
          if (responseId == requestId && _pendingRequests.containsKey(requestId)) {
            final completer = _pendingRequests.remove(requestId);
            if (jsonData['error'] != null) {
              final errorMsg = jsonData['error']['message'] ?? 'Unknown error';
              completer?.completeError(Exception(errorMsg));
            } else {
              completer?.complete(jsonData);
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error handling SSE response: $e');
    }
  }

  // Note: Connection error/closed handlers removed as we're using HTTP POST approach
  // These would be used if we implement a true persistent SSE stream connection

  /// Reconnect (reinitialize session)
  Future<void> _reconnect() async {
    try {
      _initialized = false;
      _sessionId = null;
      _keepAliveTimer?.cancel();
      await Future.delayed(const Duration(seconds: 2));
      await initialize();
      debugPrint('Session reinitialized');
    } catch (e) {
      debugPrint('Failed to reconnect: $e');
    }
  }

  /// Send keep-alive ping to maintain session
  void _sendKeepAlive() {
    if (_sessionId != null) {
      // Send a simple ping to keep session alive
      http.post(
        Uri.parse('$baseUrl/mcp'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'X-API-Key': apiKey,
          'Mcp-Session-Id': _sessionId!,
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': _generateId(),
          'method': 'ping',
        }),
      ).catchError((e) {
        debugPrint('Keep-alive ping failed: $e');
        return http.Response('', 500); // Return a response to satisfy the type checker
      });
    }
  }

  /// Send MCP request (using persistent session)
  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!_initialized || _sessionId == null) {
      await initialize();
    }

    final requestId = _generateId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    try {
      // Send request via HTTP POST with session ID (maintaining persistent session)
      http.Response response;
      try {
        response = await http.post(
          Uri.parse('$baseUrl/mcp'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'X-API-Key': apiKey,
            'Mcp-Session-Id': _sessionId!,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': requestId,
            'method': method,
            'params': params,
          }),
        );
      } catch (error) {
        _pendingRequests.remove(requestId);
        throw Exception('Network error: $error');
      }

      if (response.statusCode != 200) {
        _pendingRequests.remove(requestId);
        throw Exception('HTTP error: ${response.statusCode}');
      }

      // Parse SSE response immediately
      _handleSSEResponse(response.body, requestId);
      
      // Wait for response with timeout
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(requestId);
          throw TimeoutException('Request timeout');
        },
      );
    } catch (e) {
      _pendingRequests.remove(requestId);
      rethrow;
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
    final result = await _sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    debugPrint('Tool call result: $result');
    return result;
  }

  /// Search patients using FHIR search parameters
  Future<List<Patient>> searchPatients({
    String? name,
    String? birthdate,
  }) async {
    String path = '/Patient';
    List<String> params = [];
    
    if (name != null && name.isNotEmpty) {
      params.add('name=${Uri.encodeComponent(name)}');
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
            debugPrint('Error parsing patient resource: $e');
            debugPrint('Entry data: ${entry.toString().substring(0, entry.toString().length > 500 ? 500 : entry.toString().length)}');
            rethrow;
          }
        }).toList();
      }
    }

    return [];
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
          final resource = entry['resource'] as Map<String, dynamic>;
          return Patient.fromJson(Map<String, dynamic>.from(resource));
        }).toList();
      }
    }

    return [];
  }

  /// Disconnect (cleanup)
  Future<void> _disconnect() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Dispose resources
  void dispose() {
    _disconnect();
    _pendingRequests.clear();
    _initialized = false;
    _sessionId = null;
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

