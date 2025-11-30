import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import '../models/user.dart';
import '../services/database_service.dart';

class AuthProvider with ChangeNotifier {
  final LocalAuthentication _localAuth = LocalAuthentication();
  User? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  final DatabaseService _database = DatabaseService();

  AuthProvider() {
    _loadUser();
  }

  /// Load user from database
  Future<void> _loadUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      final users = await _database.getAllUsers();
      if (users.isNotEmpty) {
        _currentUser = users.first;
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

  /// Check if user exists in database
  Future<bool> userExists() async {
    try {
      return await _database.userExists();
    } catch (e) {
      debugPrint('Error checking if user exists: $e');
      return false;
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
  Future<void> updateUser(String name, String email, DateTime? dateOfBirth) async {
    if (_currentUser == null) return;
    
    final updatedUser = _currentUser!.copyWith(
      name: name,
      email: email,
      dateOfBirth: dateOfBirth,
    );
    
    // Update in database
    await _database.saveUser(updatedUser);
    
    _currentUser = updatedUser;
    notifyListeners();
  }

  /// Register a new user
  Future<bool> register(String name, String email, DateTime dateOfBirth) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Check if user already exists
      final exists = await _database.userExists();
      if (exists) {
        throw Exception('User already exists. Please login instead.');
      }

      // Create user first
      final user = User(
        id: _generateUserId(),
        name: name,
        email: email,
        dateOfBirth: dateOfBirth,
        createdAt: DateTime.now(),
      );

      // Save user to database
      await _database.saveUser(user);
      _currentUser = user;

      // Get SharedPreferences for biometric flags (still needed for biometric state)
      final prefs = await SharedPreferences.getInstance();

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
    
    // Clear biometric flag from SharedPreferences (keep user in database)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('biometric_enabled');
    await prefs.remove('user_pin');
    
    notifyListeners();
  }

  /// Delete user account (removes from database)
  Future<void> deleteAccount() async {
    if (_currentUser == null) return;
    
    await _database.deleteUser(_currentUser!.id);
    _currentUser = null;
    _isAuthenticated = false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('biometric_enabled');
    await prefs.remove('user_pin');
    
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

