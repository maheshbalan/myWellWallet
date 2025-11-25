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
        _isAuthenticated = true;
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Register a new user
  Future<bool> register(String name, String email) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Check if biometrics are available
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!isDeviceSupported) {
        throw Exception('Biometric authentication is not supported on this device');
      }

      // Create user
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

      // Register biometric credentials (passkey)
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Register your biometric for MyWellWallet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        await prefs.setBool('biometric_enabled', true);
        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        // User cancelled, but account is created - they'll need to authenticate later
        _isAuthenticated = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      throw Exception('Registration failed: $e');
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

  String _generateUserId() {
    return 'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }
}

