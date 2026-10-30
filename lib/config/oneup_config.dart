/// 1up Patient Access endpoints and the sandbox client.
///
/// The client id and secret are compile-time values from
/// `config/oneup_local.json` (gitignored). They are not Dart literals in git.
/// A production build passes `--dart-define=LOCK_CLINICAL_TO_ONEUP=true`
/// so the Profile toggle is hidden and MCP is not started.
class OneUpConfig {
  static const clientId = String.fromEnvironment('ONEUP_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('ONEUP_CLIENT_SECRET');

  static const authorizeUrl = String.fromEnvironment(
    'ONEUP_AUTHORIZE_URL',
    defaultValue: 'https://auth.1uphealthdemo.com/oauth2/authorize/test',
  );

  static const tokenUrl = String.fromEnvironment(
    'ONEUP_TOKEN_URL',
    defaultValue: 'https://auth.1uphealthdemo.com/oauth2/token',
  );

  static const fhirBaseUrl = String.fromEnvironment(
    'ONEUP_FHIR_BASE',
    defaultValue: 'https://api.1uphealthdemo.com/r4',
  );

  /// Must match the redirect registered on the 1up client. Not percent-encoded.
  static const redirectUri = 'mywellwallet://1up/callback';

  static const callbackScheme = 'mywellwallet';

  /// Production lock. Sandbox builds leave this false.
  static const lockToOneUp = bool.fromEnvironment('LOCK_CLINICAL_TO_ONEUP');

  static bool get hasCredentials =>
      clientId.isNotEmpty && clientSecret.isNotEmpty;
}
