// Follow-up prompt chip selection. Pure function, unit-testable without
// pumping the whole HomeScreen widget tree (WP1-11).
//
// The returned list is the set of suggestion chips shown under the last
// assistant reply. Categories are matched loosely by keyword so "what
// medications am I taking?" and "medication history" both fall in the
// same bucket.

/// Canonical suggestion strings. Keeping them in one place so adding a
/// new category in [followUpPromptsFor] stays one-step.
const String kSuggestVisits = 'Show me my recent visits';
const String kSuggestImmunizations = 'Show me my immunization record';
const String kSuggestTestResults = 'Show me my Test Results';
const String kSuggestMedications = 'What medications am I taking?';
const String kSuggestConditions = 'What conditions do I have?';
const String kSuggestAllergies = 'What am I allergic to?';

/// The default triplet shown when the query didn't match any known
/// category (or for the welcome message's first-turn prompt).
const List<String> _defaultSuggestions = [
  kSuggestVisits,
  kSuggestImmunizations,
  kSuggestTestResults,
];

/// Pure selector — returns the follow-up chip list for the category a
/// [query] falls into. Cross-category suggestions: after meds we offer
/// conditions/allergies/visits rather than re-asking about meds.
List<String> followUpPromptsFor(String query) {
  final q = query.toLowerCase();
  bool has(List<String> keys) => keys.any(q.contains);

  if (has(['medication', 'medicine', 'drug', 'prescription', 'pill', 'rx'])) {
    return [kSuggestConditions, kSuggestAllergies, kSuggestVisits];
  }
  if (has(['allergy', 'allergies', 'allergic'])) {
    return [kSuggestMedications, kSuggestConditions, kSuggestVisits];
  }
  if (has(['condition', 'diagnosis', 'diagnoses', 'diagnosed', 'chronic',
      'disease', 'illness', 'problem list'])) {
    return [kSuggestMedications, kSuggestAllergies, kSuggestTestResults];
  }
  if (has(['visit', 'visits', 'appointment', 'encounter'])) {
    return [kSuggestImmunizations, kSuggestTestResults, kSuggestMedications];
  }
  if (has(['immunization', 'vaccine', 'vaccination', 'shot'])) {
    return [kSuggestVisits, kSuggestTestResults, kSuggestMedications];
  }
  if (has(['test result', 'test results', 'lab report', 'diagnostic',
      'result'])) {
    return [kSuggestVisits, kSuggestImmunizations, kSuggestMedications];
  }
  return List<String>.of(_defaultSuggestions);
}
