import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/mcp_client_sse.dart';
import '../models/patient.dart';

/// Test screen for MCP SSE connection with hardcoded values
class MCPSSETestScreen extends StatefulWidget {
  const MCPSSETestScreen({super.key});

  @override
  State<MCPSSETestScreen> createState() => _MCPSSETestScreenState();
}

class _MCPSSETestScreenState extends State<MCPSSETestScreen> {
  final MCPClientSSE _client = MCPClientSSE(
    baseUrl: 'https://mcp-fhir-server.com',
  );
  
  bool _isRunning = false;
  final List<TestStep> _steps = [
    TestStep(
      name: '1. Initialize Connection',
      status: 'pending',
    ),
    TestStep(
      name: '2. List Available Tools',
      status: 'pending',
    ),
    TestStep(
      name: '3. Test Tool Call',
      status: 'pending',
    ),
    TestStep(
      name: '4. Search Patient',
      status: 'pending',
    ),
  ];

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _runConnectTest() async {
    if (_isRunning) return;
    
    setState(() {
      _isRunning = true;
      // Reset all steps
      for (var step in _steps) {
        step.status = 'pending';
        step.message = null;
        step.dataSnippet = null;
      }
    });

    try {
      // Step 1: Initialize
      _updateStep(0, 'in_progress', 'Connecting to MCP server...');
      await _client.initialize();
      final sessionId = _client.sessionId;
      _updateStep(0, 'completed', 'Connection established successfully', 
          dataSnippet: sessionId != null 
              ? 'Session ID: ${sessionId.substring(0, 20)}...' 
              : 'Connected to: ${_client.baseUrl}');

      // Step 2: List Tools
      _updateStep(1, 'in_progress', 'Fetching available tools...');
      final tools = await _client.listTools();
      final toolNames = tools.take(5).map((t) => t['name'] as String).join(', ');
      _updateStep(1, 'completed', 'Found ${tools.length} tools', 
          dataSnippet: toolNames + (tools.length > 5 ? '...' : ''));

      // Step 3: Test Tool Call
      _updateStep(2, 'in_progress', 'Testing patient resource request...');
      final result = await _client.callTool('request_patient_resource', {
        'request': {
          'method': 'GET',
          'path': '/Patient?name=Ruben688 Waters156&birthdate=1972-08-02',
          'body': null,
        }
      });
      final resultStr = result.toString();
      final snippet = resultStr.length > 100 
          ? resultStr.substring(0, 100) + '...' 
          : resultStr;
      _updateStep(2, 'completed', 'Tool call successful', dataSnippet: snippet);

      // Step 4: Search Patient
      _updateStep(3, 'in_progress', 'Searching for patient...');
      final patients = await _client.searchPatients(
        name: 'Ruben688 Waters156',
        birthdate: '1972-08-02',
      );
      
      if (patients.isEmpty) {
        _updateStep(3, 'error', 'No patients found');
      } else {
        final patient = patients.first;
        _updateStep(3, 'completed', 'Found ${patients.length} patient(s)', 
            dataSnippet: 'Name: ${patient.displayName}, ID: ${patient.id}');
      }
    } catch (e) {
      // Find first pending or in_progress step and mark as error
      for (var i = 0; i < _steps.length; i++) {
        if (_steps[i].status == 'in_progress' || _steps[i].status == 'pending') {
          _updateStep(i, 'error', 'Error: ${e.toString()}');
          break;
        }
      }
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _updateStep(int index, String status, String message, {String? dataSnippet}) {
    setState(() {
      _steps[index].status = status;
      _steps[index].message = message;
      _steps[index].dataSnippet = dataSnippet;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP SSE Connection Test'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connect Test Button
            ElevatedButton.icon(
              onPressed: _isRunning ? null : _runConnectTest,
              icon: Icon(_isRunning 
                  ? FontAwesomeIcons.circleNotch 
                  : FontAwesomeIcons.plug),
              label: Text(_isRunning ? 'Running Test...' : 'Connect Test'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
            const SizedBox(height: 24),
            
            // Steps
            ..._steps.map((step) => _buildStepCard(step, colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard(TestStep step, ColorScheme colorScheme) {
    IconData icon;
    Color iconColor;
    
    switch (step.status) {
      case 'completed':
        icon = FontAwesomeIcons.circleCheck;
        iconColor = Colors.green;
        break;
      case 'in_progress':
        icon = FontAwesomeIcons.circleNotch;
        iconColor = Colors.blue;
        break;
      case 'error':
        icon = FontAwesomeIcons.circleExclamation;
        iconColor = Colors.red;
        break;
      default:
        icon = FontAwesomeIcons.circle;
        iconColor = Colors.grey;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step.status == 'in_progress')
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                ),
              )
            else
              Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (step.message != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      step.message!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (step.dataSnippet != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        step.dataSnippet!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TestStep {
  final String name;
  String status; // 'pending', 'in_progress', 'completed', 'error'
  String? message;
  String? dataSnippet;

  TestStep({
    required this.name,
    required this.status,
    this.message,
    this.dataSnippet,
  });
}
