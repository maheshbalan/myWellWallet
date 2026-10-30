import 'prompt_sanitizer.dart';

/// Schema and rules MedGemma uses to write one SQLite SELECT.
///
/// Kept compact so it fits the on-device context window. The model chooses
/// the tables and filters. The app does not map the question onto a preset.
String buildSqliteQueryPrompt({
  required String question,
  required String clinicalSource,
  required String userId,
  required List<String> patientIds,
  String history = '',
}) {
  final safeQuestion = sanitizeForPrompt(question);
  final safeHistory = history.isEmpty ? '' : sanitizeForPrompt(history);
  final ids = patientIds.isEmpty ? 'none yet' : patientIds.join(', ');
  final sourceRule = clinicalSource == 'oneup'
      ? 'Clinical source is 1up. From fhir_resources, keep rows whose resource_data contains 1up-patient-access. Do not read untagged EHR rows.'
      : 'Clinical source is the FHIR MCP server. From fhir_resources, exclude rows whose resource_data contains 1up-patient-access. Device vitals still come from the health_* tables.';

  return '''<start_of_turn>user
You are MyWellWallet. Write one SQLite SELECT that answers the question from the local health record. Reply with JSON only, no markdown:
{"sql":"SELECT ..."}
If the question cannot be answered from these tables, reply:
{"needsClarification":true,"question":"one short question"}

$sourceRule
This member's users.id is '$userId'. FHIR patient_id values on this phone: $ids.
Filter health_* with user_id. Filter fhir_resources with patient_id when an id is listed.
resource_data is FHIR JSON. Useful paths: \$.code.text, \$.code.coding[0].display, \$.valueQuantity.value, \$.valueQuantity.unit, \$.effectiveDateTime, \$.status, \$.medicationCodeableConcept.text.
Do not select fhir_bundle. One SELECT. No WITH, no comments, no second statement. Always include LIMIT 50 or less.

Tables:
users(id, name, email, date_of_birth, created_at, updated_at)
fhir_patients(patient_id, patient_name, connection_id, last_synced)
fhir_resources(patient_id, resource_type, resource_id, resource_data, connection_id, updated_at)
health_glucose(user_id, value_real, unit, recorded_at)
health_heart_rate(user_id, value_real, unit, recorded_at)
health_steps(user_id, count, distance_meters, start_at, end_at)
health_blood_pressure(user_id, systolic_real, diastolic_real, unit, recorded_at)
health_lab_results(user_id, name, loinc_code, value_numeric, value_string, unit, recorded_at)
oneup_connections(user_id, display_name, kind, fhir_patient_id, last_synced_at, status)
fetch_summaries(patient_id, total_resources, resource_counts, completed_at)

resource_type is a FHIR type such as Patient, Observation, Condition, MedicationRequest, MedicationStatement, AllergyIntolerance, Procedure, DiagnosticReport, Encounter, Immunization, Coverage, ExplanationOfBenefit.
Glucose, heart rate, steps, and blood pressure recorded on the phone are in the health_* tables, not only in fhir_resources.
Blood glucose uses value_real and recorded_at, for example: SELECT value_real, unit, recorded_at FROM health_glucose WHERE user_id = '$userId' AND recorded_at >= datetime('now', '-7 days') ORDER BY recorded_at DESC LIMIT 50. Quote every id. Use datetime('now', '-7 days'), never NOW() or INTERVAL.
oneup_connections has no tokens.

${safeHistory.isEmpty ? '' : 'Previous turns:\n$safeHistory\n'}
Question: "$safeQuestion"
<end_of_turn>
<start_of_turn>model
''';
}
