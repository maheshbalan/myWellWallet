import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:local_auth/local_auth.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _showPinInput = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricAuth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.authenticate();

      if (success && mounted) {
        context.go('/');
      } else if (mounted) {
        // Biometric failed, show PIN option
        setState(() {
          _showPinInput = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Biometric not available or failed, show PIN option
      if (mounted) {
        setState(() {
          _showPinInput = true;
          _isLoading = false;
          _errorMessage = 'Biometric authentication not available. Please use PIN.';
        });
      }
    }
  }

  Future<void> _authenticateWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty || pin.length < 4) {
      setState(() {
        _errorMessage = 'PIN must be at least 4 digits';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final storedPin = await authProvider.getStoredPin();
      
      if (storedPin == null) {
        // First time setting PIN
        await authProvider.setPin(pin);
        await authProvider.setAuthenticated(true);
        if (mounted) {
          context.go('/');
        }
      } else if (storedPin == pin) {
        await authProvider.setAuthenticated(true);
        if (mounted) {
          context.go('/');
        }
      } else {
        setState(() {
          _errorMessage = 'Incorrect PIN. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Authentication failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Card-style content area (light tint)
                Material(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(24),
                  elevation: 1,
                  shadowColor: Colors.black12,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE8E0F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 32,
                      ),
                      child: Column(
                        children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8E0F0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_outline,
                            size: 48,
                            color: Color(0xFF7B1FA2),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'MyWellWallet',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Welcome back',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (authProvider.currentUser != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            authProvider.currentUser!.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 32),
                        if (_isLoading) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text(
                            'Authenticating...',
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 15,
                            ),
                          ),
                        ] else if (_showPinInput) ...[
                          TextField(
                            controller: _pinController,
                            decoration: const InputDecoration(
                              labelText: 'Enter PIN',
                              hintText: '4+ digits',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 10,
                            onSubmitted: (_) => _authenticateWithPin(),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _authenticateWithPin,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text('Login with PIN'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              setState(() => _showPinInput = false);
                            },
                            child: const Text('Use biometric instead'),
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _tryBiometricAuth,
                              icon: const Icon(Icons.fingerprint_outlined, size: 22),
                              label: const Text('Login with Biometric'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _showPinInput = true);
                              },
                              icon: const Icon(Icons.lock_outline, size: 20),
                              label: const Text('Login with PIN'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.error.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: colorScheme.error,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

