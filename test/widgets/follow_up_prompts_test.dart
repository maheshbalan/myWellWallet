// Unit tests for WP1-11: follow-up prompt chip selection.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/widgets/follow_up_prompts.dart';

void main() {
  group('followUpPromptsFor', () {
    test('medication query suggests cross-category chips', () {
      final chips = followUpPromptsFor('show my medications');
      expect(chips, containsAll(<String>[kSuggestConditions, kSuggestAllergies]));
      expect(chips, contains(kSuggestVisits));
    });

    test('allergy query suggests meds + conditions + visits', () {
      final chips = followUpPromptsFor('what am I allergic to');
      expect(chips, containsAll(<String>[
        kSuggestMedications,
        kSuggestConditions,
        kSuggestVisits,
      ]));
    });

    test('condition query suggests meds + allergies + tests', () {
      final chips = followUpPromptsFor('what chronic conditions do I have');
      expect(chips, containsAll(<String>[
        kSuggestMedications,
        kSuggestAllergies,
        kSuggestTestResults,
      ]));
    });

    test('visits query suggests immunization + tests + meds', () {
      final chips = followUpPromptsFor('show my recent visits');
      expect(chips, contains(kSuggestImmunizations));
      expect(chips, contains(kSuggestTestResults));
      expect(chips, contains(kSuggestMedications));
    });

    test('immunization query suggests visits + tests + meds', () {
      final chips = followUpPromptsFor('my vaccine history');
      expect(chips, contains(kSuggestVisits));
      expect(chips, contains(kSuggestTestResults));
      expect(chips, contains(kSuggestMedications));
    });

    test('test-results query suggests visits + immunization + meds', () {
      final chips = followUpPromptsFor('my latest lab results');
      expect(chips, contains(kSuggestVisits));
      expect(chips, contains(kSuggestImmunizations));
      expect(chips, contains(kSuggestMedications));
    });

    test('unmatched query returns the default triplet', () {
      final chips = followUpPromptsFor('tell me something else');
      expect(
        chips,
        [kSuggestVisits, kSuggestImmunizations, kSuggestTestResults],
      );
    });

    test('category matching is case-insensitive', () {
      expect(followUpPromptsFor('MY MEDICATIONS'),
          containsAll(<String>[kSuggestConditions, kSuggestAllergies]));
    });

    test('defensive: empty query returns default', () {
      expect(followUpPromptsFor(''),
          [kSuggestVisits, kSuggestImmunizations, kSuggestTestResults]);
    });
  });
}
