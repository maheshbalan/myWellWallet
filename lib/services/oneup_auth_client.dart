import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../config/oneup_config.dart';
import 'oneup_token_store.dart';

class OneUpAuthException implements Exception {
  OneUpAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OneUpAuthCancelled implements Exception {}

/// Opens 1up in the system browser and trades the one-time code for a token.
///
/// The member's password and member id stay on 1up's page. This client only
/// sees the callback code and the token JSON.
class OneUpAuthClient {
  OneUpAuthClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// 32 random bytes, hex. Held only for the in-flight session.
  String newState() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uri authorizeUri({required String state, String? authorizeUrl}) {
    final base = (authorizeUrl == null || authorizeUrl.isEmpty)
        ? OneUpConfig.authorizeUrl
        : authorizeUrl;
    final encodedRedirect = Uri.encodeComponent(OneUpConfig.redirectUri);
    final joiner = base.contains('?') ? '&' : '?';
    return Uri.parse(
      '$base${joiner}client_id=${Uri.encodeQueryComponent(OneUpConfig.clientId)}'
      '&redirect_uri=$encodedRedirect'
      '&state=${Uri.encodeQueryComponent(state)}',
    );
  }

  /// Returns the callback URL, or throws [OneUpAuthCancelled] if the sheet is closed.
  Future<String> openAuthorize(Uri url) async {
    try {
      return await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: OneUpConfig.callbackScheme,
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );
    } on PlatformException catch (e) {
      final code = e.code.toUpperCase();
      if (code.contains('CANCEL')) throw OneUpAuthCancelled();
      throw OneUpAuthException(e.message ?? 'Sign-in did not finish.');
    }
  }

  /// Checks [state] and returns the authorization code. Does not log the URL.
  String codeFromCallback({required String callbackUrl, required String expectedState}) {
    final uri = Uri.parse(callbackUrl);
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final description = uri.queryParameters['error_description'];
      throw OneUpAuthException(
        (description != null && description.isNotEmpty) ? description : error,
      );
    }
    final state = uri.queryParameters['state'];
    if (state != expectedState) {
      throw OneUpAuthException('The sign-in session did not match. Try again.');
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw OneUpAuthException('1up did not return a code.');
    }
    return code;
  }

  Future<OneUpToken> exchangeCode(String code) {
    return _tokenPost({
      'client_id': OneUpConfig.clientId,
      'client_secret': OneUpConfig.clientSecret,
      'grant_type': 'authorization_code',
      'code': code,
    });
  }

  Future<OneUpToken> refresh(String refreshToken) {
    return _tokenPost({
      'client_id': OneUpConfig.clientId,
      'client_secret': OneUpConfig.clientSecret,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
  }

  Future<OneUpToken> _tokenPost(Map<String, String> fields) async {
    final response = await _http.post(
      Uri.parse(OneUpConfig.tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: fields,
    );
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      json = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || json == null) {
      throw OneUpAuthException('Token request failed (${response.statusCode}).');
    }
    final access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw OneUpAuthException('Token request failed (${response.statusCode}).');
    }
    final refreshValue = json['refresh_token'];
    final expiresIn = json['expires_in'];
    DateTime? expiresAt;
    if (expiresIn is num) {
      expiresAt = DateTime.now().add(Duration(seconds: expiresIn.round()));
    }
    return OneUpToken(
      accessToken: access,
      refreshToken: refreshValue is String && refreshValue.isNotEmpty ? refreshValue : null,
      expiresAt: expiresAt,
    );
  }
}
