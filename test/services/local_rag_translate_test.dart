// Unit tests for WP1-08: tightened translateHumanTerm matching.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/local_rag_service.dart';

void main() {
  final service = LocalRAGService();

  group('translateHumanTerm — exact direct-mapping hits', () {
    const cases = <String, String>{
      'visit': 'Encounter',
      'visits': 'Encounter',
      'appointment': 'Encounter',
      'test result': 'DiagnosticReport',
      'test results': 'DiagnosticReport',
      'lab test': 'DiagnosticReport',
      'diagnostic report': 'DiagnosticReport',
      'medication': 'MedicationStatement',
      'medications': 'MedicationStatement',
      'drug': 'MedicationStatement',
      'vaccine': 'Immunization',
      'immunizations': 'Immunization',
      'glucose': 'Observation',
      'heart rate': 'Observation',
      'vitals': 'Observation',
    };
    cases.forEach((term, expected) {
      test('"$term" → $expected', () {
        expect(service.translateHumanTerm(term), expected);
      });
    });
  });

  group('translateHumanTerm — word-boundary phrase matches', () {
    test('"show my recent visits" matches "visits"', () {
      expect(service.translateHumanTerm('show my recent visits'), 'Encounter');
    });

    test('"my latest test results" matches "test results"', () {
      expect(service.translateHumanTerm('my latest test results'),
          'DiagnosticReport');
    });

    test('"can you list medications I am on" matches "medications"', () {
      expect(
        service.translateHumanTerm('can you list medications I am on'),
        'MedicationStatement',
      );
    });
  });

  group('translateHumanTerm — regressions prevented by word-boundary', () {
    test('"meditation" does NOT match "medication"', () {
      // Under the old substring matcher, "meditation".contains("medication")
      // is false, but "medication".contains("meditation") is also false —
      // the bug was reverse-direction. "meditation" should stay unresolved.
      expect(service.translateHumanTerm('meditation'), isNull);
    });

    test('"med" alone does NOT win against "medication" key', () {
      // Reverse direction: key.contains(term) was the old failure mode.
      // Now a bare "med" should not resolve to MedicationStatement.
      expect(service.translateHumanTerm('med'), isNull);
    });

    test('"testicular" does NOT false-match "test result"', () {
      expect(service.translateHumanTerm('testicular'), isNull);
    });

    test('"drugstore" does NOT match "drug"', () {
      // "\bdrug\b" requires a word boundary on both sides; "drugstore" has
      // no boundary between "drug" and "store" so it should not match.
      expect(service.translateHumanTerm('drugstore'), isNull);
    });
  });

  group('translateHumanTerm — multi-word mapping survives casing / surrounding text', () {
    test('"BLOOD PRESSURE reading" matches "blood pressure" case-insensitively', () {
      expect(service.translateHumanTerm('BLOOD PRESSURE reading'), 'Observation');
    });

    test('"heart rate variability" matches "heart rate"', () {
      expect(service.translateHumanTerm('heart rate variability'), 'Observation');
    });
  });
}
