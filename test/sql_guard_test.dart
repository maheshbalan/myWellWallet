import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/sql_guard.dart';

void main() {
  test('allows a capped select and adds LIMIT when missing', () {
    final sql = SqlGuard.prepare(
      "SELECT value_real, recorded_at FROM health_glucose WHERE user_id = 'u1'",
    );
    expect(sql.endsWith('LIMIT 50'), isTrue);
  });

  test('keeps a valid LIMIT and allows created_at', () {
    final sql = SqlGuard.prepare(
      'SELECT created_at FROM users WHERE id = \'a\' ORDER BY created_at DESC LIMIT 10',
    );
    expect(sql, contains('LIMIT 10'));
    expect(sql, isNot(contains('LIMIT 50')));
  });

  test('rejects writes and unknown tables', () {
    expect(
      () => SqlGuard.prepare('DELETE FROM health_glucose'),
      throwsA(isA<SqlGuardException>()),
    );
    expect(
      () => SqlGuard.prepare('SELECT * FROM secrets LIMIT 1'),
      throwsA(isA<SqlGuardException>()),
    );
    expect(
      () => SqlGuard.prepare('SELECT fhir_bundle FROM fhir_patients LIMIT 1'),
      throwsA(isA<SqlGuardException>()),
    );
  });
}
