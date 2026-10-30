import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/oneup_config.dart';

class OneUpUnauthorized implements Exception {}

class OneUpUnsupported implements Exception {
  OneUpUnsupported(this.resourceType);
  final String resourceType;
}

class OneUpHttpFailure implements Exception {
  OneUpHttpFailure(this.resourceType, this.statusCode);
  final String resourceType;
  final int statusCode;

  @override
  String toString() => '$resourceType failed ($statusCode).';
}

/// Reads FHIR R4 from the 1up demo host with the member's bearer token.
class OneUpFhirClient {
  OneUpFhirClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const requiredTypes = <String>[
    'Patient',
    'Coverage',
    'ExplanationOfBenefit',
    'Organization',
    'Practitioner',
    'Location',
  ];

  static const optionalTypes = <String>[
    'Observation',
    'Condition',
    'MedicationRequest',
    'AllergyIntolerance',
    'Procedure',
    'DiagnosticReport',
    'Encounter',
    'Immunization',
  ];

  /// Every resource of [type], following `link.relation = next`.
  /// A 404 or OperationOutcome throws [OneUpUnsupported].
  Future<List<Map<String, dynamic>>> readAll(String type, String accessToken) async {
    final resources = <Map<String, dynamic>>[];
    var next = '${OneUpConfig.fhirBaseUrl}/$type';
    var pages = 0;
    while (next.isNotEmpty && pages < 20) {
      pages++;
      final response = await _http.get(
        Uri.parse(next),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/fhir+json',
        },
      );
      if (response.statusCode == 401) throw OneUpUnauthorized();
      if (response.statusCode == 404) throw OneUpUnsupported(type);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OneUpHttpFailure(type, response.statusCode);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw OneUpHttpFailure(type, response.statusCode);
      final body = Map<String, dynamic>.from(decoded);
      if (body['resourceType'] == 'OperationOutcome') throw OneUpUnsupported(type);
      if (body['resourceType'] == 'Bundle') {
        final entries = body['entry'];
        if (entries is List) {
          for (final entry in entries) {
            if (entry is! Map) continue;
            final resource = entry['resource'];
            if (resource is! Map) continue;
            final map = Map<String, dynamic>.from(resource);
            if (map['resourceType'] == 'OperationOutcome') continue;
            resources.add(map);
          }
        }
        next = _nextLink(body) ?? '';
      } else if (body['resourceType'] is String) {
        resources.add(body);
        next = '';
      } else {
        next = '';
      }
    }
    return resources;
  }

  String? _nextLink(Map<String, dynamic> bundle) {
    final links = bundle['link'];
    if (links is! List) return null;
    for (final link in links) {
      if (link is Map && link['relation'] == 'next' && link['url'] is String) {
        return link['url'] as String;
      }
    }
    return null;
  }
}
