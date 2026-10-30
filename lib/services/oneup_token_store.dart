import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access token and refresh token for one 1up connection.
/// Stored in the iOS Keychain. Never written to SQLite or logs.
class OneUpToken {
  const OneUpToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get expiresSoon {
    final at = expiresAt;
    if (at == null) return false;
    return at.isBefore(DateTime.now().add(const Duration(minutes: 10)));
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  static OneUpToken? fromJson(Map<String, dynamic> json) {
    final access = json['access_token'];
    if (access is! String || access.isEmpty) return null;
    final refresh = json['refresh_token'];
    final expires = json['expires_at'];
    return OneUpToken(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
    );
  }
}

class OneUpTokenStore {
  OneUpTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static final OneUpTokenStore instance = OneUpTokenStore();

  final FlutterSecureStorage _storage;

  String _key(String connectionId) => 'oneup.connection.$connectionId';

  Future<void> write(String connectionId, OneUpToken token) {
    return _storage.write(key: _key(connectionId), value: jsonEncode(token.toJson()));
  }

  Future<OneUpToken?> read(String connectionId) async {
    final raw = await _storage.read(key: _key(connectionId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OneUpToken.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String connectionId) {
    return _storage.delete(key: _key(connectionId));
  }

  Future<void> deleteAll() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith('oneup.connection.')) {
        await _storage.delete(key: key);
      }
    }
  }
}
