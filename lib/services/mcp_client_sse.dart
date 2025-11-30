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
  String? _sessionId;
  bool _initialized = false;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  Timer? _keepAliveTimer;

  MCPClientSSE({required this.baseUrl});

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
          final resource = entry['resource'] as Map<String, dynamic>;
          return Patient.fromJson(Map<String, dynamic>.from(resource));
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

