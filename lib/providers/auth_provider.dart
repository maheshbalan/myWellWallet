import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  final LocalAuthentication _localAuth = LocalAuthentication();
  User? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _loadUser();
  }

  /// Load user from local storage
  Future<void> _loadUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      
      if (userJson != null) {
        _currentUser = User.fromJson(jsonDecode(userJson));
        // Don't auto-authenticate - require login
        _isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set authenticated state (for PIN login)
  Future<void> setAuthenticated(bool value) async {
    _isAuthenticated = value;
    notifyListeners();
  }

  /// Get stored PIN
  Future<String?> getStoredPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_pin');
  }

  /// Set PIN
  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pin', pin);
  }

  /// Update user profile
  Future<void> updateUser(String name, String email) async {
    if (_currentUser == null) return;
    
    final updatedUser = _currentUser!.copyWith(
      name: name,
      email: email,
    );
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(updatedUser.toJson()));
    
    _currentUser = updatedUser;
    notifyListeners();
  }

  /// Register a new user
  Future<bool> register(String name, String email) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Create user first
      final user = User(
        id: _generateUserId(),
        name: name,
        email: email,
        createdAt: DateTime.now(),
      );

      // Save user locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(user.toJson()));

      _currentUser = user;

      // Try to register biometric credentials (passkey) - make it optional
      try {
        final isDeviceSupported = await _localAuth.isDeviceSupported();

        if (isDeviceSupported) {
          final availableBiometrics = await _localAuth.getAvailableBiometrics();
          
          if (availableBiometrics.isNotEmpty) {
            final didAuthenticate = await _localAuth.authenticate(
              localizedReason: 'Register your biometric for MyWellWallet',
              options: const AuthenticationOptions(
                biometricOnly: true,
                stickyAuth: true,
              ),
            );

            if (didAuthenticate) {
              await prefs.setBool('biometric_enabled', true);
              // Ask for PIN as backup
              _isAuthenticated = true;
              _isLoading = false;
              notifyListeners();
              return true;
            } else {
              // User cancelled biometric, ask for PIN setup
              debugPrint('User cancelled biometric registration');
              await prefs.setBool('biometric_enabled', false);
              _isAuthenticated = true; // Account created, will need PIN
              _isLoading = false;
              notifyListeners();
              return true;
            }
          } else {
            // No biometrics available, but account is created
            debugPrint('No biometrics available on device');
            await prefs.setBool('biometric_enabled', false);
            _isAuthenticated = true;
            _isLoading = false;
            notifyListeners();
            return true;
          }
        } else {
          // Device not supported, but account is created
          debugPrint('Biometric authentication not supported on this device');
          await prefs.setBool('biometric_enabled', false);
          _isAuthenticated = true;
          _isLoading = false;
          notifyListeners();
          return true;
        }
      } catch (biometricError) {
        // Biometric registration failed, but account is still created
        debugPrint('Biometric registration error: $biometricError');
        await prefs.setBool('biometric_enabled', false);
        _isAuthenticated = true; // Allow access without biometric
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Authenticate with passkey/biometrics
  Future<bool> authenticate() async {
    _isLoading = true;
    notifyListeners();

    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!isDeviceSupported) {
        throw Exception('Biometric authentication is not supported');
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access MyWellWallet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      throw Exception('Authentication failed: $e');
    }
  }

  /// Logout
  Future<void> logout() async {
    _isAuthenticated = false;
    _currentUser = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    await prefs.remove('biometric_enabled');
    
    notifyListeners();
  }

  /// Get SharedPreferences instance
  Future<SharedPreferences> getSharedPreferences() async {
    return await SharedPreferences.getInstance();
  }

  String _generateUserId() {
    return 'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }
}

