import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/auth_provider.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  DateTime? _dateOfBirth;
  bool _isLoading = false;
  bool _showAuthChoice = false;
  String? _authMethod; // 'biometric' or 'pin'

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth')),
      );
      return;
    }

    // Show authentication method choice
    if (!_showAuthChoice) {
      setState(() {
        _showAuthChoice = true;
      });
      return;
    }

    // If auth method not selected, return
    if (_authMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an authentication method')),
      );
      return;
    }

    // If PIN method selected, validate PIN
    if (_authMethod == 'pin') {
      if (_pinController.text.trim().isEmpty || _pinController.text.trim().length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN must be at least 4 digits')),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      
      // Register user
      final success = await authProvider.register(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _dateOfBirth!,
      );

      if (!success) {
        throw Exception('Registration failed');
      }

      // Set up authentication method
      if (_authMethod == 'pin') {
        await authProvider.setPin(_pinController.text.trim());
        await authProvider.setAuthenticated(true);
      } else if (_authMethod == 'biometric') {
        // Try to set up biometric
        try {
          final biometricSuccess = await authProvider.authenticate();
          if (biometricSuccess) {
            await authProvider.setAuthenticated(true);
          } else {
            // Biometric setup failed, fall back to PIN
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Biometric setup failed. Please set up a PIN instead.'),
              ),
            );
            setState(() {
              _authMethod = 'pin';
              _isLoading = false;
            });
            return;
          }
        } catch (e) {
          // Biometric not available, fall back to PIN
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric not available. Please set up a PIN instead.'),
            ),
          );
          setState(() {
            _authMethod = 'pin';
            _isLoading = false;
          });
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Redirect to home
        context.go('/');
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                
                // Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    FontAwesomeIcons.userPlus,
                    size: 50,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Title
                Text(
                  'Create Your Account',
                  style: Theme.of(context).textTheme.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter your details to get started',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF7F8C8D),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter your full name',
                    prefixIcon: Icon(FontAwesomeIcons.user),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    if (value.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // Date of Birth Field
                InkWell(
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().subtract(const Duration(days: 365 * 30)),
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
                    ),
                    child: Text(
                      _dateOfBirth == null
                          ? 'Select your date of birth'
                          : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: _dateOfBirth == null 
                            ? Colors.grey[600] 
                            : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Email Field
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(FontAwesomeIcons.envelope),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final emailRegex = RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                    );
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 40),
                
                // Register Button or Auth Method Choice
                if (!_showAuthChoice) ...[
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegistration,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text('Continue'),
                  ),
                ] else ...[
                  // Authentication Method Selection
                  Text(
                    'Choose Authentication Method',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // Biometric Button
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _authMethod = 'biometric';
                      });
                    },
                    icon: Icon(
                      FontAwesomeIcons.fingerprint,
                      color: _authMethod == 'biometric' 
                          ? Colors.white 
                          : colorScheme.primary,
                    ),
                    label: const Text('Use Biometric'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      backgroundColor: _authMethod == 'biometric' 
                          ? colorScheme.primary 
                          : null,
                      foregroundColor: _authMethod == 'biometric' 
                          ? Colors.white 
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // PIN Button
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _authMethod = 'pin';
                      });
                    },
                    icon: Icon(
                      FontAwesomeIcons.lock,
                      color: _authMethod == 'pin' 
                          ? Colors.white 
                          : colorScheme.primary,
                    ),
                    label: const Text('Use PIN'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      backgroundColor: _authMethod == 'pin' 
                          ? colorScheme.primary 
                          : null,
                      foregroundColor: _authMethod == 'pin' 
                          ? Colors.white 
                          : null,
                    ),
                  ),
                  
                  // PIN Input (if PIN method selected)
                  if (_authMethod == 'pin') ...[
                    const SizedBox(height: 24),
                    TextField(
                      controller: _pinController,
                      decoration: const InputDecoration(
                        labelText: 'Enter PIN',
                        hintText: '4+ digits',
                        prefixIcon: Icon(FontAwesomeIcons.lock),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 10,
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  // Complete Registration Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegistration,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Create Account'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Back button
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showAuthChoice = false;
                        _authMethod = null;
                      });
                    },
                    child: const Text('Back'),
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

