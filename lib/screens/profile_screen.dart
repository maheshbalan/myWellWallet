import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';
import '../models/patient.dart';
import '../widgets/info_section.dart';
import '../widgets/app_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  DateTime? _dateOfBirth;
  bool _isEditing = false;
  bool _isLoadingPatient = false;
  Patient? _patientData;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadPatientData();
  }

  void _loadProfileData() {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _emailController.text = user.email;
      _dateOfBirth = user.dateOfBirth;
    }
  }

  Future<void> _loadPatientData() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingPatient = true;
    });

    try {
      final patientProvider = context.read<PatientProvider>();
      // Search for patient by name and DOB if available
      if (user.dateOfBirth != null) {
        await patientProvider.searchPatientByNameAndDOB(user.name, user.dateOfBirth!);
      } else {
        await patientProvider.searchPatientByName(user.name);
      }
      final patient = patientProvider.foundPatient;
      
      setState(() {
        _patientData = patient;
        _isLoadingPatient = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPatient = false;
      });
      debugPrint('Error loading patient data: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty || 
        _emailController.text.trim().isEmpty ||
        _dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields including date of birth')),
      );
      return;
    }

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.updateUser(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _dateOfBirth,
      );
      
      // Reload patient data with new name and DOB
      await _loadPatientData();
      
      setState(() {
        _isEditing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(FontAwesomeIcons.penToSquare),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header (light tint card)
            Card(
              color: const Color(0xFFF5F3FF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE8E0F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B1FA2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          user?.name.isNotEmpty == true
                              ? user!.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isEditing)
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                border: OutlineInputBorder(),
                              ),
                            )
                          else
                            Text(
                              user?.name ?? 'Unknown',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          if (!_isEditing) ...[
                            const SizedBox(height: 8),
                            Text(
                              user?.email ?? '',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF64748B),
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

            // Profile Information
            InfoSection(
              title: 'Profile Information',
              icon: FontAwesomeIcons.user,
              children: [
                if (_isEditing) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  // Date of Birth Field
                  InkWell(
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: _dateOfBirth ?? DateTime.now().subtract(const Duration(days: 365 * 30)),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          _dateOfBirth = pickedDate;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        hintText: _dateOfBirth == null 
                            ? 'Select your date of birth'
                            : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                        prefixIcon: const Icon(FontAwesomeIcons.calendar),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        _dateOfBirth == null
                            ? 'Select your date of birth'
                            : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: _dateOfBirth == null 
                              ? const Color(0xFF64748B) 
                              : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  InfoRow(
                    label: 'Name',
                    value: user?.name ?? 'N/A',
                  ),
                  InfoRow(
                    label: 'Email',
                    value: user?.email ?? 'N/A',
                  ),
                  InfoRow(
                    label: 'Date of Birth',
                    value: user?.dateOfBirth != null
                        ? '${user!.dateOfBirth!.year}-${user.dateOfBirth!.month.toString().padLeft(2, '0')}-${user.dateOfBirth!.day.toString().padLeft(2, '0')}'
                        : 'Not set',
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // Patient Information from FHIR
            if (_isLoadingPatient)
              const Center(child: CircularProgressIndicator())
            else if (_patientData != null)
              InfoSection(
                title: 'Patient Information (FHIR)',
                icon: FontAwesomeIcons.hospital,
                children: [
                  InfoRow(
                    label: 'Patient ID',
                    value: _patientData!.id ?? 'N/A',
                  ),
                  if (_patientData!.gender != null)
                    InfoRow(
                      label: 'Gender',
                      value: _patientData!.gender!.toUpperCase(),
                    ),
                  if (_patientData!.birthDate != null)
                    InfoRow(
                      label: 'Birth Date',
                      value: _patientData!.birthDate!,
                    ),
                  if (_patientData!.fullAddress != 'No address')
                    InfoRow(
                      label: 'Address',
                      value: _patientData!.fullAddress,
                    ),
                ],
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(
                        FontAwesomeIcons.circleExclamation,
                        size: 48,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No information available for this patient',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please check and input the correct name',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/profile'),
    );
  }
}

