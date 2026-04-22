/// NLP Service for interpreting natural language queries
/// This service interprets user queries and maps them to FHIR MCP Server tools
/// 
/// Current Implementation: Rule-based pattern matching
/// 
/// For Production: Integrate Gemma 2B local LLM model
/// 
/// To integrate Gemma 2B:
/// 1. Add gemma_2b package or use platform channels to call native LLM
/// 2. Replace interpretQuery method to use Gemma 2B for intent classification
/// 3. Use prompt engineering to map queries to FHIR tools
/// 
/// Example Gemma 2B integration:
/// ```dart
/// final response = await gemmaModel.generate(
///   prompt: 'Interpret this health query: "$query" and return JSON with tool name and params',
/// );
/// return parseGemmaResponse(response);
/// ```
class NLPService {
  /// Interpret a natural language query and return FHIR tool and parameters
  /// 
  /// Returns a map with:
  /// - 'tool': The FHIR MCP tool name to call
  /// - 'params': Parameters for the tool
  /// - 'intent': The detected intent (patient, observation, medication, etc.)
  /// 
  /// [patientId] - Optional patient ID to include in resource queries
  Future<Map<String, dynamic>> interpretQuery(String query, {String? patientId}) async {
    final lowerQuery = query.toLowerCase().trim();

    // Patient-related queries
    if (_matches(lowerQuery, ['patient', 'patients', 'list patients', 'show patients', 'all patients', 'get patients'])) {
      return {
        'tool': 'request_patient_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': '/Patient',
            'body': null,
          }
        },
        'intent': 'list_patients',
      };
    }

    // Get specific patient
    final patientIdMatch = RegExp(r'patient\s+(\w+)', caseSensitive: false).firstMatch(query);
    if (patientIdMatch != null) {
      final patientId = patientIdMatch.group(1);
      return {
        'tool': 'request_patient_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': '/Patient/$patientId',
            'body': null,
          }
        },
        'intent': 'get_patient',
        'patientId': patientId,
      };
    }

    // Helper to build path with patient filter
    String buildPath(String resource, {String? sort, int? count}) {
      String path = '/$resource';
      final params = <String>[];
      
      if (patientId != null) {
        params.add('subject=Patient/$patientId');
      }
      
      if (sort != null) {
        params.add('_sort=$sort');
      }
      
      if (count != null) {
        params.add('_count=$count');
      }
      
      if (params.isNotEmpty) {
        path += '?${params.join('&')}';
      }
      
      return path;
    }

    // Observations/Lab results
    if (_matches(lowerQuery, ['observation', 'observations', 'lab', 'lab results', 'test results', 'vitals', 'vital signs', 'blood test', 'lab test', 'recent tests'])) {
      return {
        'tool': 'request_observation_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': buildPath('Observation', sort: '-date', count: 10),
            'body': null,
          }
        },
        'intent': 'list_observations',
      };
    }

    // Medications
    if (_matches(lowerQuery, ['medication', 'medications', 'drugs', 'prescription', 'prescriptions', 'my medications', 'current medications'])) {
      return {
        'tool': 'request_medication_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': buildPath('MedicationStatement', sort: '-date', count: 10),
            'body': null,
          }
        },
        'intent': 'list_medications',
      };
    }

    // Conditions/Diagnoses
    if (_matches(lowerQuery, ['condition', 'conditions', 'diagnosis', 'diagnoses', 'problem', 'problems', 'diagnoses', 'medical conditions'])) {
      return {
        'tool': 'request_condition_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': buildPath('Condition', sort: '-onset-date', count: 10),
            'body': null,
          }
        },
        'intent': 'list_conditions',
      };
    }

    // Immunizations
    if (_matches(lowerQuery, ['immunization', 'immunizations', 'vaccine', 'vaccines', 'vaccination', 'vaccinations', 'shots'])) {
      return {
        'tool': 'request_immunization_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': buildPath('Immunization', sort: '-date', count: 10),
            'body': null,
          }
        },
        'intent': 'list_immunizations',
      };
    }

    // Encounters/Visits/Timeline
    if (_matches(lowerQuery, ['encounter', 'encounters', 'visit', 'visits', 'appointment', 'appointments', 'doctor visit', 'hospital visit', 'timeline', 'recent timeline', 'most recent timeline', 'history'])) {
      return {
        'tool': 'request_encounter_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': buildPath('Encounter', sort: '-date', count: 20),
            'body': null,
          }
        },
        'intent': 'list_encounters',
      };
    }

    // Allergies
    if (_matches(lowerQuery, ['allergy', 'allergies', 'allergic', 'allergic to'])) {
      return {
        'tool': 'request_allergy_intolerance_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': buildPath('AllergyIntolerance'),
            'body': null,
          }
        },
        'intent': 'list_allergies',
      };
    }

    // Family history
    if (_matches(lowerQuery, ['family history', 'family member', 'family', 'family health'])) {
      return {
        'tool': 'request_family_member_history_resource',
        'params': {
          'request': {
            'method': 'GET',
            'path': '/FamilyMemberHistory',
            'body': null,
          }
        },
        'intent': 'list_family_history',
      };
    }

    // Document search
    if (_matches(lowerQuery, ['document', 'documents', 'search', 'find document', 'search documents', 'find documents'])) {
      return {
        'tool': 'search_pinecone',
        'params': {
          'query': query,
        },
        'intent': 'search_documents',
      };
    }

    // LOINC codes
    if (_matches(lowerQuery, ['loinc', 'code', 'codes', 'standard code', 'loinc code'])) {
      return {
        'tool': 'get_loinc_codes',
        'params': {
          'query': query,
        },
        'intent': 'get_loinc_codes',
      };
    }

    // Default: try to search documents or return generic resource
    return {
      'tool': 'request_generic_resource',
      'params': {
        'request': {
          'method': 'GET',
          'path': '/',
          'body': null,
        }
      },
      'intent': 'generic_query',
      'originalQuery': query,
    };
  }

  bool _matches(String query, List<String> keywords) {
    return keywords.any((keyword) => query.contains(keyword));
  }
}
