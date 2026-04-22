// Live MCP smoke for WP1-01 / WP1-02.
//
// Hits the real FHIR MCP server from AppConfig (mcp-fhir-server.com) using
// DataSyncService.pathFor / toolFor, for a known Medplum patient
// (Ruben688 Waters156, id 14171df9-ec64-4993-abbf-341e8f57c2a7), and
// asserts every resource type returns a FHIR Bundle with at least some
// entries — confirming the patient=/subject= and tool-name fixes reach the
// server correctly.
//
// Opt-in: set SMOKE_LIVE=1 in the environment. Skipped by default so
// `flutter test` in CI doesn't fan out to a real network endpoint.
//
// Run:
//   SMOKE_LIVE=1 flutter test test/integration/data_sync_live_smoke_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/config/app_config.dart';
import 'package:mywellwallet/services/data_sync_service.dart';
import 'package:mywellwallet/services/mcp_client.dart';

const String _patientId = '14171df9-ec64-4993-abbf-341e8f57c2a7';
const String _patientLabel = 'Ruben688 Waters156';

bool get _runLive => Platform.environment['SMOKE_LIVE'] == '1';
String? get _skipReason =>
    _runLive ? null : 'set SMOKE_LIVE=1 to run live MCP smoke';

/// Extract the inner FHIR response payload from an MCP tool call result.
/// Shape: `{ result: { content: [{ text: "<json string>" }] } }` where the
/// decoded text has `{ method, path, response: { resourceType, entry: [...] } }`.
Map<String, dynamic>? _extractFhirResponse(Map<String, dynamic> toolResult) {
  final result = toolResult['result'];
  if (result is! Map) return null;
  final content = result['content'];
  if (content is! List || content.isEmpty) return null;
  final first = content.first;
  if (first is! Map) return null;
  final text = first['text'];
  if (text is! String) return null;
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) return null;
  final response = decoded['response'];
  if (response is Map<String, dynamic>) return response;
  return null;
}

Future<Map<String, dynamic>> _fetchResource(
  MCPClient client,
  String resourceType,
) async {
  final path = DataSyncService.pathFor(resourceType, _patientId, count: 50);
  final tool = DataSyncService.toolFor(resourceType);
  // ignore: avoid_print
  print('  → $resourceType: tool=$tool  path=$path');
  final raw = await client.callTool(tool, {
    'request': {
      'method': 'GET',
      'path': path,
      'body': null,
    }
  });
  return raw;
}

void main() {
  group(
    'Live MCP smoke — WP1-01 / WP1-02 fixes against production FHIR server',
    skip: _skipReason,
    () {
      late MCPClient client;

      setUpAll(() async {
        client = MCPClient(
          baseUrl: AppConfig.mcpBaseUrl,
          apiKey: AppConfig.mcpApiKey,
        );
        await client.initialize();
        expect(client.isInitialized, isTrue,
            reason: 'MCPClient must initialize against ${AppConfig.mcpBaseUrl}');
      });

      test('Patient search resolves $_patientLabel', () async {
        final raw = await client.callTool('request_patient_resource', {
          'request': {
            'method': 'GET',
            'path': '/Patient/$_patientId',
            'body': null,
          }
        });
        final response = _extractFhirResponse(raw);
        expect(response, isNotNull);
        expect(response!['resourceType'], 'Patient');
        expect(response['id'], _patientId);
      });

      // Resource-type expectations for Ruben688 Waters156.
      //
      // The "Bundle shape" assertion is the real smoke for the Phase 1 fix:
      // if the server accepted our filter param, it returns a searchset
      // Bundle. If the request were malformed, we'd see an OperationOutcome
      // or isError:true instead.
      //
      // `expectedNonEmpty` is a per-patient data fact: Ruben has data for
      // these resource types, so entries should be populated. Medplum does
      // not expose MedicationStatement or AllergyIntolerance data for this
      // patient at all — verified via direct probe — so we only assert the
      // Bundle shape there. (If a future patient has those, add to the
      // non-empty list.)
      const expectations = <String, bool>{
        // Patient-scoped (patient= filter)
        'MedicationStatement': false,
        'Condition': true,
        'AllergyIntolerance': false,
        'Immunization': true,
        // Subject-scoped (subject= filter)
        'Encounter': true,
        'Observation': true,
        'DiagnosticReport': true,
      };

      expectations.forEach((type, expectNonEmpty) {
        final expectedParam = DataSyncService.searchParamFor(type);
        test(
            '$type fetch hits server with $expectedParam= filter and returns a '
            'valid Bundle${expectNonEmpty ? ' with entries' : ' (entries optional)'}',
            () async {
          final raw = await _fetchResource(client, type);

          // The server should never return isError for a well-formed request.
          final result = raw['result'] as Map?;
          expect(result?['isError'], isNot(isTrue),
              reason: '$type request flagged isError; server rejected it');

          final response = _extractFhirResponse(raw);
          expect(response, isNotNull,
              reason: '$type response did not include a parseable FHIR payload');
          expect(response!['resourceType'], 'Bundle',
              reason:
                  '$type should return a searchset Bundle; anything else '
                  'means the server did not accept our request shape');

          // Confirm the echoed URL carries the expected search param. If the
          // old subject=/patient= bug were reintroduced, this would be the
          // first thing to catch it. The server may URL-encode the slash or
          // not, so accept either form.
          final content = result!['content'];
          String? echoedText;
          if (content is List && content.isNotEmpty) {
            final first = content.first;
            if (first is Map) {
              final text = first['text'];
              if (text is String) echoedText = text;
            }
          }
          if (echoedText != null) {
            final urlEncoded = '$expectedParam=Patient%2F$_patientId';
            final urlPlain = '$expectedParam=Patient/$_patientId';
            expect(
              echoedText.contains(urlEncoded) || echoedText.contains(urlPlain),
              isTrue,
              reason:
                  '$type: server echoed a URL that does not contain the '
                  'expected $expectedParam= filter. Phase 1 regression.',
            );
          }

          final entries = response['entry'];
          if (expectNonEmpty) {
            expect(entries, isA<List>(),
                reason: '$type Bundle missing entry[] for $_patientLabel');
            expect((entries as List).isNotEmpty, isTrue,
                reason:
                    '$type for $_patientLabel returned zero entries; either '
                    'the filter is not landing or the patient data vanished');
            final first = entries.first;
            if (first is Map && first['resource'] is Map) {
              final resource = first['resource'] as Map;
              expect(resource['resourceType'], type,
                  reason: 'Entries should be $type resources');
            }
          } else {
            // Empty Bundle is acceptable here — Ruben simply has none of these.
            // Just make sure the server returned a proper shape.
            // ignore: avoid_print
            print(
                '    (empty Bundle acceptable — $_patientLabel has no $type data)');
          }
        });
      });
    },
  );
}
