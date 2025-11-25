import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../providers/patient_provider.dart';
import '../widgets/info_section.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatientProvider>().loadPatientDetails(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/patients'),
        ),
      ),
      body: Consumer<PatientProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.selectedPatient == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Loading patient details...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF7F8C8D),
                    ),
                  ),
                ],
              ),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.error.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        FontAwesomeIcons.triangleExclamation,
                        size: 40,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Error',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      provider.error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF7F8C8D),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => provider.loadPatientDetails(widget.patientId),
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final patient = provider.selectedPatient;
          if (patient == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      FontAwesomeIcons.user,
                      size: 40,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Patient not found',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Patient Header Card - Bauhaus geometric design
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              patient.displayName.isNotEmpty
                                  ? patient.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patient.displayName,
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              if (patient.id != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'ID: ${patient.id}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w500,
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
                ),
                const SizedBox(height: 24),

                // Personal Information
                if (patient.gender != null || patient.birthDate != null)
                  InfoSection(
                    title: 'Personal Information',
                    icon: FontAwesomeIcons.user,
                    children: [
                      if (patient.gender != null)
                        InfoRow(
                          label: 'Gender',
                          value: patient.gender!.toUpperCase(),
                        ),
                      if (patient.birthDate != null)
                        InfoRow(
                          label: 'Birth Date',
                          value: _formatDate(patient.birthDate!),
                        ),
                    ],
                  ),

                // Identifiers
                if (patient.identifier != null && patient.identifier!.isNotEmpty)
                  InfoSection(
                    title: 'Identifiers',
                    icon: FontAwesomeIcons.idCard,
                    children: patient.identifier!.map((identifier) {
                      return InfoRow(
                        label: identifier.system ?? 'Unknown',
                        value: identifier.value ?? 'N/A',
                      );
                    }).toList(),
                  ),

                // Address
                if (patient.address != null && patient.address!.isNotEmpty)
                  InfoSection(
                    title: 'Address',
                    icon: FontAwesomeIcons.locationDot,
                    children: [
                      InfoRow(
                        label: 'Address',
                        value: patient.fullAddress,
                      ),
                    ],
                  ),

                // Contact Information
                if (patient.telecom != null && patient.telecom!.isNotEmpty)
                  InfoSection(
                    title: 'Contact Information',
                    icon: FontAwesomeIcons.phone,
                    children: patient.telecom!.map((contact) {
                      return InfoRow(
                        label: '${contact.system?.toUpperCase()} (${contact.use ?? "N/A"})',
                        value: contact.value ?? 'N/A',
                      );
                    }).toList(),
                  ),
                
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }
}

