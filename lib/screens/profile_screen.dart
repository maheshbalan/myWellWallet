import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';
import '../models/patient.dart';
import '../widgets/info_section.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_bar_logo.dart';
import '../services/apple_health_service.dart';

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
  final _appleHealth = AppleHealthService();
  bool _healthConnected = false;
  Map<String, dynamic>? _healthSyncSettings;
  bool _isSyncing = false;
  int _selectedSyncIntervalHours = 24;
  bool _biometricEnabled = false;
  bool _hasBiometricHardware = false;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadPatientData();
    _loadSecurityState();
    if (Platform.isIOS) {
      AppleHealthService.configure();
      _loadHealthStatus();
    }
  }

  Future<void> _loadSecurityState() async {
    final auth = context.read<AuthProvider>();
    final bioOn = await auth.isBiometricEnabled();
    final hasHardware = await auth.hasBiometricHardware();
    final pin = await auth.getStoredPin();
    if (mounted) {
      setState(() {
        _biometricEnabled = bioOn;
        _hasBiometricHardware = hasHardware;
        _hasPin = pin != null && pin.isNotEmpty;
      });
    }
  }

  Future<void> _loadHealthStatus() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final connected = await _appleHealth.isConnected(user.id);
    final settings = await _appleHealth.getSyncSettings(user.id);
    if (mounted) {
      setState(() {
        _healthConnected = connected;
        _healthSyncSettings = settings;
        _selectedSyncIntervalHours = settings?['sync_interval_hours'] as int? ?? 24;
      });
    }
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

  Future<void> _connectAppleHealth() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _isSyncing = true);
    try {
      final ok = await _appleHealth.connectAndSync(
        userId: user.id,
        syncIntervalHours: _selectedSyncIntervalHours,
      );
      if (mounted) {
        await _loadHealthStatus();
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Apple Health connected. Data synced.')),
          );
        } else {
          _showAppleHealthPermissionDialog();
        }
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncNow() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _isSyncing = true);
    try {
      final result = await _appleHealth.syncFromHealth(user.id);
      if (mounted) {
        await _loadHealthStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? 'Synced: ${result.glucoseCount} glucose, ${result.heartRateCount} heart rate, ${result.stepsCount} steps, ${result.bloodPressureCount} blood pressure'
                : 'Sync failed: ${result.message}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showAppleHealthPermissionDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apple Health access needed'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MyWellWallet needs permission to read your health data (glucose, heart rate, steps, blood pressure) for your diabetes & heart health dashboard.',
                style: TextStyle(height: 1.4),
              ),
              SizedBox(height: 16),
              Text(
                'On iPhone:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '1. Tap "Open Settings" below.\n'
                '2. Tap Privacy & Security → Health.\n'
                '3. Find MyWellWallet and turn ON the data you want: Blood Glucose, Heart Rate, Steps, Blood Pressure.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'If MyWellWallet is not in the list, return to the app and tap "Connect to Apple Health" again so the permission prompt appears, then check Settings again.',
                style: TextStyle(height: 1.4, fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildAppleHealthSection() {
    return Card(
      color: const Color(0xFFE8F5E9),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFC8E6C9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC8E6C9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    FontAwesomeIcons.heartPulse,
                    size: 20,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Apple Health',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1B5E20),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_healthConnected) ...[
              Text(
                'Connect to sync glucose, heart rate, steps, and blood pressure for your diabetes & heart health dashboard.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF388E3C),
                    ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedSyncIntervalHours,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sync interval',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                  DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                  DropdownMenuItem(value: 24, child: Text('Every 24 hours')),
                  DropdownMenuItem(value: 168, child: Text('Every week')),
                ],
                onChanged: (v) => setState(() => _selectedSyncIntervalHours = v ?? 24),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _connectAppleHealth,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(FontAwesomeIcons.link),
                  label: Text(_isSyncing ? 'Connecting...' : 'Connect to Apple Health'),
                ),
              ),
            ] else ...[
              if (_healthSyncSettings != null) ...[
                InfoRow(
                  label: 'Last synced',
                  value: _healthSyncSettings!['last_synced_at'] != null
                      ? _formatDateTime(_healthSyncSettings!['last_synced_at'] as DateTime)
                      : 'Never',
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<int>(
                value: _selectedSyncIntervalHours,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sync interval',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                  DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                  DropdownMenuItem(value: 24, child: Text('Every 24 hours')),
                  DropdownMenuItem(value: 168, child: Text('Every week')),
                ],
                onChanged: (v) async {
                  final user = context.read<AuthProvider>().currentUser;
                  if (user == null) return;
                  setState(() => _selectedSyncIntervalHours = v ?? 24);
                  await _appleHealth.saveSyncSettings(user.id, v ?? 24);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSyncing ? null : _syncNow,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync, size: 20),
                      label: const Text('Sync now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/health'),
                      icon: const Icon(FontAwesomeIcons.chartLine, size: 20),
                      label: const Text('View Health'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildSecuritySection() {
    return Card(
      color: const Color(0xFFF5F3FF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8E0F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E0F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_outline, size: 22, color: Color(0xFF7B1FA2)),
                ),
                const SizedBox(width: 12),
                Text(
                  'Login & security',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_hasBiometricHardware) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Use biometric (Face ID / Touch ID)',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFF1E293B)),
                  ),
                  Switch.adaptive(
                    value: _biometricEnabled,
                    onChanged: (value) async {
                      await context.read<AuthProvider>().setBiometricEnabled(value);
                      if (mounted) setState(() => _biometricEnabled = value);
                    },
                    activeColor: const Color(0xFF7B1FA2),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              _hasPin ? 'You can change your PIN or keep using biometric.' : 'Set a PIN to log in with a code (or use biometric).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showSetPinDialog(),
                icon: Icon(_hasPin ? Icons.lock_reset : Icons.pin_outlined, size: 20),
                label: Text(_hasPin ? 'Change PIN' : 'Set PIN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7B1FA2),
                  side: const BorderSide(color: Color(0xFF7B1FA2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSetPinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(_hasPin ? 'Change PIN' : 'Set PIN'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_hasPin) ...[
                    TextField(
                      controller: currentPinController,
                      decoration: const InputDecoration(
                        labelText: 'Current PIN',
                        hintText: '4+ digits',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 10,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: newPinController,
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      hintText: '4+ digits',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 10,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPinController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new PIN',
                      hintText: '4+ digits',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 10,
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final newPin = newPinController.text.trim();
                  final confirm = confirmPinController.text.trim();
                  if (newPin.length < 4) {
                    setDialogState(() => errorText = 'PIN must be at least 4 digits');
                    return;
                  }
                  if (newPin != confirm) {
                    setDialogState(() => errorText = 'New PIN and confirm do not match');
                    return;
                  }
                  if (_hasPin) {
                    final auth = context.read<AuthProvider>();
                    final stored = await auth.getStoredPin();
                    if (stored != currentPinController.text.trim()) {
                      setDialogState(() => errorText = 'Current PIN is incorrect');
                      return;
                    }
                  }
                  await context.read<AuthProvider>().setPin(newPin);
                  if (mounted) {
                    await _loadSecurityState();
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_hasPin ? 'PIN updated.' : 'PIN set. You can use it to log in.')),
                    );
                  }
                },
                child: Text(_hasPin ? 'Update PIN' : 'Set PIN'),
              ),
            ],
          );
        },
      ),
    );
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
        leading: const AppBarLogo(showBackButton: false),
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 0,
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

            // Security / Login (PIN & Biometric)
            _buildSecuritySection(),
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

            if (Platform.isIOS) ...[
              const SizedBox(height: 24),
              _buildAppleHealthSection(),
            ],

            const SizedBox(height: 48),
            // Danger Zone
            const Divider(),
            const SizedBox(height: 24),
            Text(
              'Danger Zone',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Card(
              color: colorScheme.errorContainer.withOpacity(0.3),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.error.withOpacity(0.2)),
              ),
              child: ListTile(
                title: const Text('Delete Local Account'),
                subtitle: const Text('This will clear all local health data and reset the app.'),
                trailing: Icon(Icons.delete_forever_outlined, color: colorScheme.error),
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/profile'),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Local Account?'),
        content: const Text(
          'This will permanently delete your local profile and all synced FHIR health records. You will need to register again to use the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await context.read<AuthProvider>().resetApp();
              if (mounted) {
                context.go('/register');
              }
            },
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }
}

