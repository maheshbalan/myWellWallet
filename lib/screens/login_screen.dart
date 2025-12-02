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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                         MediaQuery.of(context).padding.top - 
                         MediaQuery.of(context).padding.bottom - 48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              // App Icon - Clean Health UI Kit style
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.favorite_outline,
                  size: 56,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              
              // App Title
              Text(
                'MyWellWallet',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Welcome Text
              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              if (authProvider.currentUser != null) ...[
                const SizedBox(height: 8),
                Text(
                  authProvider.currentUser!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 48),
              
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text('Authenticating...'),
              ] else if (_showPinInput) ...[
                // PIN Input
                TextField(
                  controller: _pinController,
                  decoration: const InputDecoration(
                    labelText: 'Enter PIN',
                    hintText: '4+ digits',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 10,
                  onSubmitted: (_) => _authenticateWithPin(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _authenticateWithPin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Login with PIN'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showPinInput = false;
                    });
                  },
                  child: const Text('Use Biometric instead'),
                ),
              ] else ...[
                // Biometric Button
                ElevatedButton.icon(
                  onPressed: _tryBiometricAuth,
                  icon: const Icon(Icons.fingerprint_outlined),
                  label: const Text('Login with Biometric'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 16),
                // PIN Button
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showPinInput = true;
                    });
                  },
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Login with PIN'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],
              
              if (_errorMessage != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_outlined, color: colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.error),
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
    );
  }
}

