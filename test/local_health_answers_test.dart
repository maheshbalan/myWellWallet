import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/local_health_answers.dart';

void main() {
  test('creatinine is a lab token and matches a serum name', () {
    final tokens = LocalHealthAnswers.labTokens('what was my latest creatinine level');
    expect(tokens, ['creatinine']);
    expect(
      LocalHealthAnswers.labRowMatches(
        {'name': 'Creatinine [Mass/volume] in Serum or Plasma', 'loinc_code': '2160-0'},
        tokens,
      ),
      isTrue,
    );
  });

  test('a visit question is not treated as a creatinine match', () {
    final tokens = LocalHealthAnswers.labTokens('Show me my recent visits');
    expect(
      LocalHealthAnswers.labRowMatches(
        {'name': 'Creatinine', 'loinc_code': '2160-0'},
        tokens,
      ),
      isFalse,
    );
  });

  test('creatinine does not match an unrelated lab', () {
    expect(
      LocalHealthAnswers.labRowMatches(
        {'name': 'Hemoglobin A1c', 'loinc_code': '4548-4'},
        ['creatinine'],
      ),
      isFalse,
    );
  });
}
