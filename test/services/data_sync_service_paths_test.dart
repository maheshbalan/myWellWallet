// Unit tests for DataSyncService.pathFor / searchParamFor / toolFor.
//
// Covers WP1-01 (FHIR search params) and WP1-02 (DiagnosticReport MCP tool).
// Does not instantiate DataSyncService — the helpers are static pure
// functions, so the tests need neither a live MCP server nor a database.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/data_sync_service.dart';

void main() {
  const patientId = 'P123';

  group('DataSyncService.searchParamFor', () {
    // FHIR spec: these resource types reference the patient via `patient=`.
    const patientScopedTypes = [
      'MedicationStatement',
      'Condition',
      'AllergyIntolerance',
      'Immunization',
      'FamilyMemberHistory',
    ];

    // These reference via `subject=` (the generic FHIR reference field).
    const subjectScopedTypes = [
      'Encounter',
      'Observation',
      'DiagnosticReport',
      'DocumentReference',
    ];

    for (final type in patientScopedTypes) {
      test('$type uses patient=', () {
        expect(DataSyncService.searchParamFor(type), 'patient');
      });
    }

    for (final type in subjectScopedTypes) {
      test('$type uses subject=', () {
        expect(DataSyncService.searchParamFor(type), 'subject');
      });
    }

    test('unknown resource type falls back to subject by default', () {
      expect(DataSyncService.searchParamFor('SomethingExotic'), 'subject');
    });

    test('unknown resource type with orElse=null throws', () {
      expect(
        () => DataSyncService.searchParamFor('SomethingExotic', orElse: null),
        throwsArgumentError,
      );
    });
  });

  group('DataSyncService.pathFor', () {
    test('MedicationStatement path uses patient= — not subject=', () {
      final path = DataSyncService.pathFor('MedicationStatement', patientId);
      expect(path, contains('patient=Patient/$patientId'));
      expect(path, isNot(contains('subject=')));
    });

    test('Condition path uses patient= — not subject=', () {
      final path = DataSyncService.pathFor('Condition', patientId);
      expect(path, contains('patient=Patient/$patientId'));
      expect(path, isNot(contains('subject=')));
    });

    test('Observation path uses subject=', () {
      final path = DataSyncService.pathFor('Observation', patientId);
      expect(path, contains('subject=Patient/$patientId'));
    });

    test('DiagnosticReport path uses subject=', () {
      final path = DataSyncService.pathFor('DiagnosticReport', patientId);
      expect(path, contains('subject=Patient/$patientId'));
    });

    test('default count is 1000', () {
      expect(
        DataSyncService.pathFor('Observation', patientId),
        endsWith('&_count=1000'),
      );
    });

    test('count override flows through', () {
      expect(
        DataSyncService.pathFor('Observation', patientId, count: 25),
        endsWith('&_count=25'),
      );
    });

    test('unknown resource type throws', () {
      expect(
        () => DataSyncService.pathFor('Mystery', patientId),
        throwsArgumentError,
      );
    });
  });

  group('DataSyncService.toolFor', () {
    test('DiagnosticReport uses the generic resource tool — not the '
        'document_reference tool (WP1-02)', () {
      expect(
        DataSyncService.toolFor('DiagnosticReport'),
        'request_generic_resource',
      );
      expect(
        DataSyncService.toolFor('DiagnosticReport'),
        isNot('request_document_reference_resource'),
      );
    });

    test('DocumentReference still uses the document_reference tool', () {
      expect(
        DataSyncService.toolFor('DocumentReference'),
        'request_document_reference_resource',
      );
    });

    test('dedicated tools are wired for common resource types', () {
      expect(DataSyncService.toolFor('Patient'), 'request_patient_resource');
      expect(DataSyncService.toolFor('Observation'), 'request_observation_resource');
      expect(DataSyncService.toolFor('Condition'), 'request_condition_resource');
      expect(DataSyncService.toolFor('MedicationStatement'), 'request_medication_resource');
      expect(DataSyncService.toolFor('Immunization'), 'request_immunization_resource');
      expect(DataSyncService.toolFor('Encounter'), 'request_encounter_resource');
      expect(
        DataSyncService.toolFor('AllergyIntolerance'),
        'request_allergy_intolerance_resource',
      );
      expect(
        DataSyncService.toolFor('FamilyMemberHistory'),
        'request_family_member_history_resource',
      );
    });

    test('unknown types fall back to the generic tool', () {
      expect(
        DataSyncService.toolFor('SomethingExotic'),
        'request_generic_resource',
      );
    });
  });
}
