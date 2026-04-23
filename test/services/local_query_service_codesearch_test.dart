// Unit tests for WP1-07: tightened codeSearch matching.
//
// Drives LocalQueryService.filterByCodeSearch against the mixed Observation
// fixture, asserting word-boundary semantics (no more "test" matching
// "testicular") and confirming the LOINC fallback still picks up resources
// that have a code but no display text.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/local_query_service.dart';

import '../_fixtures/fhir_bundles.dart';

void main() {
  List<String> _ids(List<Map<String, dynamic>> rows) =>
      rows.map((r) => r['id'] as String).toList();

  group('LocalQueryService.filterByCodeSearch', () {
    test('glucose query returns glucose + HbA1c rows only (LOINC lookup)', () {
      final filtered =
          LocalQueryService.filterByCodeSearch(mixedObservationFixture, 'glucose');
      final ids = _ids(filtered);
      expect(ids, containsAll(<String>['obs-glucose-1', 'obs-hba1c-1']));
      expect(ids, isNot(contains('obs-steps-1')));
      expect(ids, isNot(contains('obs-hr-1')));
    });

    test('cholesterol query returns lipid-panel rows', () {
      final filtered = LocalQueryService.filterByCodeSearch(
          mixedObservationFixture, 'cholesterol');
      final ids = _ids(filtered);
      expect(ids, contains('obs-chol-total-1'));
      expect(ids, contains('obs-chol-ldl-1'));
      expect(ids, isNot(contains('obs-glucose-1')));
    });

    test('"test" does NOT match observations whose display contains '
        '"testicular" (word-boundary)', () {
      final filtered =
          LocalQueryService.filterByCodeSearch(mixedObservationFixture, 'test');
      final ids = _ids(filtered);
      expect(ids, isNot(contains('obs-testicular-1')),
          reason: 'testicular should not match "test" under word-boundary '
              'semantics');
    });

    test('LOINC fallback catches rows with no display name', () {
      final filtered =
          LocalQueryService.filterByCodeSearch(mixedObservationFixture, 'glucose');
      final ids = _ids(filtered);
      expect(ids, contains('obs-glucose-loinc-only'),
          reason: 'rows with a LOINC code but no display should still match '
              'via the medicalTermLoincCodes lookup');
    });

    test('synonyms resolve through medicalTermLoincCodes', () {
      final hba1c =
          LocalQueryService.filterByCodeSearch(mixedObservationFixture, 'hba1c');
      expect(_ids(hba1c), contains('obs-hba1c-1'));

      final a1c =
          LocalQueryService.filterByCodeSearch(mixedObservationFixture, 'a1c');
      expect(_ids(a1c), contains('obs-hba1c-1'));

      final bloodSugar = LocalQueryService.filterByCodeSearch(
          mixedObservationFixture, 'blood sugar');
      expect(_ids(bloodSugar), containsAll(<String>['obs-glucose-1', 'obs-hba1c-1']));
    });

    test('steps query returns step rows (and not heart rate)', () {
      final filtered =
          LocalQueryService.filterByCodeSearch(mixedObservationFixture, 'steps');
      final ids = _ids(filtered);
      expect(ids, contains('obs-steps-1'));
      expect(ids, isNot(contains('obs-hr-1')));
      expect(ids, isNot(contains('obs-glucose-1')));
    });

    test('heart rate query is tight — matches only the HR row', () {
      final filtered = LocalQueryService.filterByCodeSearch(
          mixedObservationFixture, 'heart rate');
      final ids = _ids(filtered);
      expect(ids, ['obs-hr-1']);
    });

    test('empty search yields an empty list', () {
      final filtered = LocalQueryService.filterByCodeSearch(
          mixedObservationFixture, '');
      expect(filtered, isEmpty);
    });

    test('unknown term with no LOINC entry still matches via text', () {
      final filtered = LocalQueryService.filterByCodeSearch(
          mixedObservationFixture, 'ldl');
      final ids = _ids(filtered);
      expect(ids, contains('obs-chol-ldl-1'));
    });
  });

  group('LocalQueryService.medicalTermLoincCodes', () {
    test('includes the common metabolic-panel terms', () {
      expect(LocalQueryService.medicalTermLoincCodes,
          containsPair('glucose', containsAll(<String>['2339-0', '4548-4'])));
      expect(LocalQueryService.medicalTermLoincCodes,
          containsPair('hba1c', containsAll(<String>['4548-4'])));
      expect(LocalQueryService.medicalTermLoincCodes,
          containsPair('cholesterol',
              containsAll(<String>['2093-3', '2085-9', '2089-1', '2571-8'])));
    });
  });
}
