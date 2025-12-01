import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';
import '../services/data_sync_service.dart';
import '../services/mcp_client.dart';
import '../services/database_service.dart';
import '../models/fetch_status.dart';

class FetchDataScreen extends StatefulWidget {
  const FetchDataScreen({super.key});

  @override
  State<FetchDataScreen> createState() => _FetchDataScreenState();
}

class _FetchDataScreenState extends State<FetchDataScreen> {
  final Map<String, FetchStatus> _statuses = {};
  FetchSummary? _summary;
  bool _isFetching = false;
  String? _error;
  DataSyncService? _dataSyncService;

  @override
  void initState() {
    super.initState();
    _initializeStatuses();
  }

  void _initializeStatuses() {
    for (var resourceType in DataSyncService.resourceTypes) {
      _statuses[resourceType] = FetchStatus(
        resourceType: resourceType,
        status: 'pending',
      );
    }
  }

  Future<void> _fetchAllData() async {
    final authProvider = context.read<AuthProvider>();
    final patientProvider = context.read<PatientProvider>();
    final user = authProvider.currentUser;

    if (user == null) {
      setState(() {
        _error = 'Please login first';
      });
      return;
    }

    // Ensure patient is found
    if (patientProvider.foundPatient == null) {
      // Try to find patient
      try {
        if (user.dateOfBirth != null) {
          await patientProvider.searchPatientByNameAndDOB(
            user.name,
            user.dateOfBirth!,
          );
        } else {
          await patientProvider.searchPatientByName(user.name);
        }
      } catch (e) {
        setState(() {
          _error = 'Could not find patient: $e';
        });
        return;
      }
    }

    final patient = patientProvider.foundPatient;
    if (patient == null || patient.id == null) {
      setState(() {
        _error = 'Patient not found. Please check your profile.';
      });
      return;
    }

    setState(() {
      _isFetching = true;
      _error = null;
      _summary = null;
      _initializeStatuses();
    });

    try {
      // Initialize data sync service
      final mcpClient = MCPClient(baseUrl: 'https://mcp-fhir-server.com');
      await mcpClient.initialize();
      
      final databaseService = DatabaseService();
      _dataSyncService = DataSyncService(
        mcpClient: mcpClient,
        databaseService: databaseService,
      );

      // Set up progress callback
      _dataSyncService!.onProgressUpdate = (status) {
        if (mounted) {
          setState(() {
            _statuses[status.resourceType] = status;
          });
        }
      };

      // Fetch all data
      final summary = await _dataSyncService!.fetchAllData(patient.id!);

      if (mounted) {
        setState(() {
          _summary = summary;
          _isFetching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error fetching data: $e';
          _isFetching = false;
        });
      }
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return FontAwesomeIcons.circleCheck;
      case 'in_progress':
        return FontAwesomeIcons.circleNotch;
      case 'error':
        return FontAwesomeIcons.circleExclamation;
      default:
        return FontAwesomeIcons.circle;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch My Health Data'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      FontAwesomeIcons.download,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Fetch All Health Data',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Download all your health records from connected EHR systems',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Fetch Button
            ElevatedButton.icon(
              onPressed: _isFetching ? null : _fetchAllData,
              icon: Icon(_isFetching 
                  ? FontAwesomeIcons.circleNotch 
                  : FontAwesomeIcons.download),
              label: Text(_isFetching ? 'Fetching Data...' : 'Fetch All Data'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
            const SizedBox(height: 24),

            // Error Message
            if (_error != null)
              Card(
                color: colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(FontAwesomeIcons.triangleExclamation, 
                          color: colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_error != null) const SizedBox(height: 24),

            // Progress Section
            if (_isFetching || _summary != null) ...[
              Text(
                'Progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ...DataSyncService.resourceTypes.map((resourceType) {
                final status = _statuses[resourceType] ?? FetchStatus(
                  resourceType: resourceType,
                  status: 'pending',
                );
                return _buildProgressCard(status, colorScheme);
              }),
              const SizedBox(height: 24),
            ],

            // Summary Section
            if (_summary != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            FontAwesomeIcons.circleCheck,
                            color: Colors.green,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Data Fetch Completed',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Total Resources: ${_summary!.totalResources}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ..._summary!.resourceCounts.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(entry.key),
                              Text(
                                '${entry.value}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (_summary!.errors.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Errors:',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ..._summary!.errors.map((error) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '• $error',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(FetchStatus status, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(status.status),
                  color: _getStatusColor(status.status),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status.resourceType,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (status.count != null)
                  Text(
                    '${status.count}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            if (status.status == 'in_progress') ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: status.progress,
                backgroundColor: Colors.grey.shade200,
              ),
            ],
            if (status.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                status.errorMessage!,
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

