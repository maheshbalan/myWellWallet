import 'package:flutter/material.dart';
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
    baseUrl: 'https://mcp-fhir-server-maheshbalan1.replit.app',
  );
  
  bool _isInitialized = false;
  bool _isLoading = false;
  String _status = 'Not initialized';
  final List<String> _logs = [];
  List<Patient> _patients = [];

  @override
  void initState() {
    super.initState();
    _addLog('Test screen initialized');
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)}: $message');
      if (_logs.length > 50) {
        _logs.removeAt(0);
      }
    });
    debugPrint(message);
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _status = 'Initializing...';
    });
    _addLog('Starting initialization...');

    try {
      await _client.initialize();
      setState(() {
        _isInitialized = true;
        _status = 'Initialized successfully';
        _isLoading = false;
      });
      _addLog('✓ Initialized successfully');
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _status = 'Initialization failed: $e';
        _isLoading = false;
      });
      _addLog('✗ Initialization failed: $e');
    }
  }

  Future<void> _listTools() async {
    if (!_isInitialized) {
      _addLog('Please initialize first');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Listing tools...';
    });
    _addLog('Listing tools...');

    try {
      final tools = await _client.listTools();
      setState(() {
        _status = 'Found ${tools.length} tools';
        _isLoading = false;
      });
      _addLog('✓ Found ${tools.length} tools');
      for (var tool in tools) {
        _addLog('  - ${tool['name']}');
      }
    } catch (e) {
      setState(() {
        _status = 'Failed to list tools: $e';
        _isLoading = false;
      });
      _addLog('✗ Failed to list tools: $e');
    }
  }

  Future<void> _searchPatient() async {
    if (!_isInitialized) {
      _addLog('Please initialize first');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Searching for patient...';
    });
    _addLog('Searching for patient: Ruben688 Waters156, DOB: 1972-08-02');

    try {
      final patients = await _client.searchPatients(
        name: 'Ruben688 Waters156',
        birthdate: '1972-08-02',
      );
      
      setState(() {
        _patients = patients;
        _status = patients.isEmpty 
            ? 'No patients found' 
            : 'Found ${patients.length} patient(s)';
        _isLoading = false;
      });
      
      if (patients.isEmpty) {
        _addLog('✗ No patients found');
      } else {
        _addLog('✓ Found ${patients.length} patient(s)');
        for (var patient in patients) {
          _addLog('  - ${patient.displayName} (ID: ${patient.id})');
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Search failed: $e';
        _isLoading = false;
      });
      _addLog('✗ Search failed: $e');
    }
  }

  Future<void> _testToolCall() async {
    if (!_isInitialized) {
      _addLog('Please initialize first');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Testing tool call...';
    });
    _addLog('Testing tool call: request_patient_resource');

    try {
      final result = await _client.callTool('request_patient_resource', {
        'request': {
          'method': 'GET',
          'path': '/Patient?name=Ruben688 Waters156&birthdate=1972-08-02',
          'body': null,
        }
      });
      
      setState(() {
        _status = 'Tool call successful';
        _isLoading = false;
      });
      _addLog('✓ Tool call successful');
      _addLog('Result: ${result.toString().substring(0, result.toString().length > 200 ? 200 : result.toString().length)}...');
    } catch (e) {
      setState(() {
        _status = 'Tool call failed: $e';
        _isLoading = false;
      });
      _addLog('✗ Tool call failed: $e');
    }
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP SSE Connection Test'),
        backgroundColor: Colors.blue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Status Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isInitialized ? Icons.check_circle : Icons.error,
                        color: _isInitialized ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Test Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _initialize,
                  child: const Text('1. Initialize'),
                ),
                ElevatedButton(
                  onPressed: _isLoading || !_isInitialized ? null : _listTools,
                  child: const Text('2. List Tools'),
                ),
                ElevatedButton(
                  onPressed: _isLoading || !_isInitialized ? null : _testToolCall,
                  child: const Text('3. Test Tool Call'),
                ),
                ElevatedButton(
                  onPressed: _isLoading || !_isInitialized ? null : _searchPatient,
                  child: const Text('4. Search Patient'),
                ),
              ],
            ),
          ),
          
          // Patients List
          if (_patients.isNotEmpty)
            Expanded(
              flex: 1,
              child: Card(
                margin: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Found Patients:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _patients.length,
                        itemBuilder: (context, index) {
                          final patient = _patients[index];
                          return ListTile(
                            title: Text(patient.displayName),
                            subtitle: Text('ID: ${patient.id}'),
                            leading: const Icon(Icons.person),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Logs
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Logs:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            _logs[_logs.length - 1 - index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

