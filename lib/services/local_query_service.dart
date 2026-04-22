import 'package:flutter/foundation.dart';
import 'database_service.dart';

/// Service for querying local SQLite database for FHIR resources
/// 
/// This service provides methods to query the local database first,
/// before falling back to MCP Gateway queries.
class LocalQueryService {
  final DatabaseService databaseService;

  LocalQueryService({required this.databaseService});

  /// Query local database for FHIR resources (EHR) merged with Apple Health when applicable.
  ///
  /// [queryPlan] may include `dataSources`: `ehr-fhir`, `apple-health`. If omitted,
  /// [Observation] defaults to both; other types use EHR only.
  /// [appUserId] must be set to merge Apple Health (`users.id`).
  Future<List<Map<String, dynamic>>> queryLocal(
    String patientId,
    String resourceType, {
    Map<String, dynamic>? filters,
    int? recordIndex,
    String? appUserId,
    Map<String, dynamic>? queryPlan,
  }) async {
    try {
      debugPrint(
        'Querying local database: patientId=$patientId, resourceType=$resourceType, '
        'appUserId=${appUserId != null ? "set" : "null"}',
      );

      final sources = _dataSourcesFromPlan(queryPlan, resourceType);
      final effFilters = _normalizeFilters(filters);

      final merged = <Map<String, dynamic>>[];

      if (sources.contains('ehr-fhir')) {
        final ehr = await databaseService.getPatientResources(patientId, resourceType);
        for (final raw in ehr) {
          merged.add(_ensureEhrProvenance(Map<String, dynamic>.from(raw)));
        }
        debugPrint('EHR $resourceType: ${ehr.length} rows');
      }

      if (sources.contains('apple-health') &&
          resourceType == 'Observation' &&
          appUserId != null &&
          appUserId.isNotEmpty) {
        final apple = await _appleHealthAsObservations(patientId, appUserId);
        merged.addAll(apple);
        debugPrint('Apple Health as Observation: ${apple.length} rows');
      }

      if (merged.isEmpty) {
        debugPrint('No local resources after merge');
        return [];
      }

      var filteredResources = merged;

      if (effFilters != null) {
        if (effFilters.containsKey('codeSearch')) {
          final codeSearch = effFilters['codeSearch'] as String?;
          if (codeSearch != null) {
            filteredResources = _filterByCodeSearch(filteredResources, codeSearch);
            debugPrint('Filtered to ${filteredResources.length} matching "$codeSearch"');
          }
        }

        if (effFilters.containsKey('sort')) {
          final sort = effFilters['sort'] as String?;
          if (sort != null) {
            filteredResources = _sortResources(filteredResources, sort);
          }
        }

        if (effFilters.containsKey('limit')) {
          final limit = _asInt(effFilters['limit']);
          if (limit != null && limit > 0) {
            filteredResources = filteredResources.take(limit).toList();
          }
        }

        if (effFilters.containsKey('status')) {
          final status = effFilters['status'] as String?;
          if (status != null) {
            filteredResources = filteredResources.where((resource) {
              final resourceStatus = resource['status'] as String?;
              return resourceStatus?.toLowerCase() == status.toLowerCase();
            }).toList();
          }
        }
      }

      if (recordIndex != null && recordIndex >= 0) {
        if (recordIndex < filteredResources.length) {
          filteredResources = [filteredResources[recordIndex]];
          debugPrint('Returning specific record at index $recordIndex');
        } else {
          debugPrint(
            'Record index $recordIndex out of range (${filteredResources.length} records available)',
          );
          return [];
        }
      }

      return filteredResources;
    } catch (e) {
      debugPrint('Error querying local database: $e');
      return [];
    }
  }

  static List<String> _dataSourcesFromPlan(
    Map<String, dynamic>? queryPlan,
    String resourceType,
  ) {
    final raw = queryPlan?['dataSources'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    if (resourceType == 'Observation') {
      return ['ehr-fhir', 'apple-health'];
    }
    return ['ehr-fhir'];
  }

  Map<String, dynamic>? _normalizeFilters(Map<String, dynamic>? filters) {
    if (filters == null) return null;
    final m = Map<String, dynamic>.from(filters);
    if (m.containsKey('_count') && !m.containsKey('limit')) {
      m['limit'] = _asInt(m['_count']);
    }
    if (m.containsKey('_sort') && !m.containsKey('sort')) {
      m['sort'] = m['_sort'];
    }
    return m;
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Map<String, dynamic> _ensureEhrProvenance(Map<String, dynamic> r) {
    if (_hasProvenanceCode(r, 'ehr-fhir')) return r;
    final meta = r['meta'] is Map
        ? Map<String, dynamic>.from(r['meta'] as Map)
        : <String, dynamic>{};
    final tags = <dynamic>[
      ...((meta['tag'] as List?) ?? const []),
      {
        'system': 'urn:mywellwallet:provenance',
        'code': 'ehr-fhir',
        'display': 'EHR / FHIR server',
      },
    ];
    meta['tag'] = tags;
    r['meta'] = meta;
    return r;
  }

  bool _hasProvenanceCode(Map<String, dynamic> r, String code) {
    final meta = r['meta'];
    if (meta is! Map) return false;
    final tags = meta['tag'];
    if (tags is! List) return false;
    for (final t in tags) {
      if (t is Map && t['code'] == code) return true;
    }
    return false;
  }

  Map<String, dynamic> _appleMeta() => {
        'source': 'https://apple.com/health',
        'tag': [
          {
            'system': 'urn:mywellwallet:provenance',
            'code': 'apple-health',
            'display': 'Apple Health',
          },
        ],
      };

  Future<List<Map<String, dynamic>>> _appleHealthAsObservations(
    String fhirPatientId,
    String userId,
  ) async {
    const cap = 150;
    final out = <Map<String, dynamic>>[];

    final glucose = await databaseService.getHealthGlucose(userId, limit: cap);
    for (final row in glucose) {
      final id = row['id'] as String;
      final dt = (row['recorded_at'] as DateTime).toIso8601String();
      out.add({
        'resourceType': 'Observation',
        'id': 'ah-glucose-$id',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '2339-0',
              'display': 'Glucose [Mass/volume] in Blood',
            },
          ],
          'text': 'Blood glucose (Apple Health)',
        },
        'subject': {'reference': 'Patient/$fhirPatientId'},
        'effectiveDateTime': dt,
        'valueQuantity': {
          'value': row['value'],
          'unit': row['unit'] ?? 'mg/dL',
        },
        'meta': _appleMeta(),
      });
    }

    final hr = await databaseService.getHealthHeartRate(userId, limit: cap);
    for (final row in hr) {
      final id = row['id'] as String;
      final dt = (row['recorded_at'] as DateTime).toIso8601String();
      out.add({
        'resourceType': 'Observation',
        'id': 'ah-hr-$id',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '8867-4',
              'display': 'Heart rate',
            },
          ],
          'text': 'Heart rate (Apple Health)',
        },
        'subject': {'reference': 'Patient/$fhirPatientId'},
        'effectiveDateTime': dt,
        'valueQuantity': {
          'value': row['value'],
          'unit': row['unit'] ?? '/min',
        },
        'meta': _appleMeta(),
      });
    }

    final bp = await databaseService.getHealthBloodPressure(userId, limit: cap);
    for (final row in bp) {
      final id = row['id'] as String;
      final dt = (row['recorded_at'] as DateTime).toIso8601String();
      out.add({
        'resourceType': 'Observation',
        'id': 'ah-bp-$id',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '85354-9',
              'display': 'Blood pressure panel',
            },
          ],
          'text': 'Blood pressure (Apple Health)',
        },
        'subject': {'reference': 'Patient/$fhirPatientId'},
        'effectiveDateTime': dt,
        'component': [
          {
            'code': {
              'coding': [
                {'system': 'http://loinc.org', 'code': '8480-6', 'display': 'Systolic'},
              ],
            },
            'valueQuantity': {
              'value': row['systolic'],
              'unit': row['unit'] ?? 'mmHg',
            },
          },
          {
            'code': {
              'coding': [
                {'system': 'http://loinc.org', 'code': '8462-4', 'display': 'Diastolic'},
              ],
            },
            'valueQuantity': {
              'value': row['diastolic'],
              'unit': row['unit'] ?? 'mmHg',
            },
          },
        ],
        'meta': _appleMeta(),
      });
    }

    final steps = await databaseService.getHealthSteps(userId, limit: cap);
    for (final row in steps) {
      final id = row['id'] as String;
      final start = (row['start_at'] as DateTime).toIso8601String();
      final end = (row['end_at'] as DateTime).toIso8601String();
      out.add({
        'resourceType': 'Observation',
        'id': 'ah-steps-$id',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '55423-8',
              'display': 'Number of steps in 24 hour Measured',
            },
          ],
          'text': 'Step count (Apple Health)',
        },
        'subject': {'reference': 'Patient/$fhirPatientId'},
        'effectiveDateTime': end,
        'effectivePeriod': {
          'start': start,
          'end': end,
        },
        'valueQuantity': {
          'value': row['count'],
          'unit': 'steps',
        },
        'meta': _appleMeta(),
      });
    }

    final labs = await databaseService.getHealthLabResults(userId, limit: cap);
    for (final row in labs) {
      final id = row['id'] as String;
      final dt = (row['recorded_at'] as DateTime).toIso8601String();
      final loinc = row['loinc_code'] as String?;
      final coding = <Map<String, dynamic>>[];
      if (loinc != null && loinc.isNotEmpty) {
        coding.add({
          'system': 'http://loinc.org',
          'code': loinc,
          'display': row['name'] as String,
        });
      }
      final obs = <String, dynamic>{
        'resourceType': 'Observation',
        'id': 'ah-lab-$id',
        'status': 'final',
        'code': {
          if (coding.isNotEmpty) 'coding': coding,
          'text': row['name'] as String,
        },
        'subject': {'reference': 'Patient/$fhirPatientId'},
        'effectiveDateTime': dt,
        'meta': _appleMeta(),
      };
      if (row['value_numeric'] != null) {
        obs['valueQuantity'] = {
          'value': row['value_numeric'],
          'unit': row['unit'],
        };
      } else if (row['value_string'] != null) {
        obs['valueString'] = row['value_string'];
      }
      out.add(obs);
    }

    return out;
  }
  
  /// Filter resources by code search (for Observations)
  List<Map<String, dynamic>> _filterByCodeSearch(
    List<Map<String, dynamic>> resources,
    String searchTerm,
  ) {
    final lowerSearch = searchTerm.toLowerCase();
    
    // Medical term to LOINC code mappings
    final codeMappings = {
      'cholesterol': ['2093-3', '2085-9', '2089-1', '2571-8'], // Total, LDL, HDL, Triglycerides
      'glucose': ['2339-0', '4548-4'], // Glucose, HbA1c
      'blood sugar': ['2339-0', '4548-4'],
      'cgm': ['2339-0', '4548-4'],
      'hba1c': ['4548-4'],
      'a1c': ['4548-4'],
      'blood pressure': ['85354-9', '8480-6', '8462-4'], // BP, Systolic, Diastolic
      'hemoglobin': ['718-7', '4548-4'], // HGB, HbA1c
      'creatinine': ['2160-0'],
      'sodium': ['2951-2'],
      'potassium': ['2823-3'],
      'steps': ['55423-8', '41950-7'],
      'walking': ['55423-8', '41950-7'],
    };
    
    final codesToSearch = codeMappings[lowerSearch] ?? [];
    
    return resources.where((resource) {
      // Check code.coding for LOINC codes
      final code = resource['code'] as Map<String, dynamic>?;
      if (code != null) {
        final coding = code['coding'] as List?;
        if (coding != null) {
          for (var c in coding) {
            if (c is Map) {
              final system = c['system'] as String?;
              final codeValue = c['code'] as String?;
              final display = c['display'] as String?;
              
              // Check LOINC codes
              if (system?.contains('loinc') == true && codesToSearch.contains(codeValue)) {
                return true;
              }
              
              // Check display name
              if (display != null && display.toLowerCase().contains(lowerSearch)) {
                return true;
              }
            }
          }
        }
        
        // Check code.text
        final text = code['text'] as String?;
        if (text != null && text.toLowerCase().contains(lowerSearch)) {
          return true;
        }
      }
      
      // Check resource text
      final resourceText = resource['text'] as Map<String, dynamic>?;
      if (resourceText != null) {
        final div = resourceText['div'] as String?;
        if (div != null && div.toLowerCase().contains(lowerSearch)) {
          return true;
        }
      }
      
      return false;
    }).toList();
  }

  /// Sort resources by a field
  List<Map<String, dynamic>> _sortResources(
    List<Map<String, dynamic>> resources,
    String sort,
  ) {
    // Parse sort string (e.g., "-date" or "date")
    final descending = sort.startsWith('-');
    final field = descending ? sort.substring(1) : sort;
    
    // Common date fields in FHIR resources
    final dateFields = ['date', 'effectiveDateTime', 'onsetDateTime', 'period.start', 'lastUpdated'];
    
    resources.sort((a, b) {
      dynamic aValue;
      dynamic bValue;
      
      // Try to extract date value
      for (var dateField in dateFields) {
        aValue = _extractField(a, dateField);
        bValue = _extractField(b, dateField);
        if (aValue != null && bValue != null) break;
      }
      
      // Fallback to other fields
      if (aValue == null) aValue = _extractField(a, field);
      if (bValue == null) bValue = _extractField(b, field);
      
      // Compare values
      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return descending ? 1 : -1;
      if (bValue == null) return descending ? -1 : 1;
      
      // Handle date strings
      if (aValue is String && bValue is String) {
        try {
          final aDate = DateTime.parse(aValue);
          final bDate = DateTime.parse(bValue);
          final comparison = aDate.compareTo(bDate);
          return descending ? -comparison : comparison;
        } catch (e) {
          // Not a date, do string comparison
          final comparison = aValue.compareTo(bValue);
          return descending ? -comparison : comparison;
        }
      }
      
      // Handle numbers
      if (aValue is num && bValue is num) {
        final comparison = aValue.compareTo(bValue);
        return descending ? -comparison : comparison;
      }
      
      // Default: string comparison
      final aStr = aValue.toString();
      final bStr = bValue.toString();
      final comparison = aStr.compareTo(bStr);
      return descending ? -comparison : comparison;
    });
    
    return resources;
  }

  /// Extract field value from nested map
  dynamic _extractField(Map<String, dynamic> resource, String field) {
    if (field.contains('.')) {
      // Handle nested fields (e.g., "period.start")
      final parts = field.split('.');
      dynamic value = resource;
      for (var part in parts) {
        if (value is Map && value.containsKey(part)) {
          value = value[part];
        } else {
          return null;
        }
      }
      return value;
    }
    
    return resource[field];
  }

  /// Check if local database has data for a patient
  Future<bool> hasLocalData(String patientId) async {
    try {
      final counts = await databaseService.getResourceCounts(patientId);
      return counts.values.fold(0, (a, b) => a + b) > 0;
    } catch (e) {
      debugPrint('Error checking local data: $e');
      return false;
    }
  }

  /// Get resource count for a specific type
  Future<int> getResourceCount(String patientId, String resourceType) async {
    try {
      final counts = await databaseService.getResourceCounts(patientId);
      return counts[resourceType] ?? 0;
    } catch (e) {
      debugPrint('Error getting resource count: $e');
      return 0;
    }
  }

  /// Format FHIR resources as markdown
  String formatAsMarkdown(
    List<Map<String, dynamic>> resources,
    String resourceType,
  ) {
    if (resources.isEmpty) {
      return 'No $resourceType records found in your local database.';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('# $resourceType Records');
    buffer.writeln();
    buffer.writeln('Found ${resources.length} record${resources.length > 1 ? 's' : ''}.');
    buffer.writeln();
    
    for (var i = 0; i < resources.length; i++) {
      final resource = resources[i];
      buffer.writeln('## Record ${i + 1}');
      buffer.writeln();
      
      // Format based on resource type
      switch (resourceType) {
        case 'Encounter':
          _formatEncounter(buffer, resource);
          break;
        case 'Observation':
          _formatObservation(buffer, resource);
          break;
        case 'MedicationStatement':
          _formatMedication(buffer, resource);
          break;
        case 'Condition':
          _formatCondition(buffer, resource);
          break;
        case 'DiagnosticReport':
          _formatDiagnosticReport(buffer, resource);
          break;
        case 'Immunization':
          _formatImmunization(buffer, resource);
          break;
        default:
          _formatGenericResource(buffer, resource);
      }
      
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  void _formatEncounter(StringBuffer buffer, Map<String, dynamic> resource) {
    final status = resource['status'] as String? ?? 'Unknown';
    final type = resource['type'] as List?;
    final period = resource['period'] as Map<String, dynamic>?;
    
    buffer.writeln('**Status**: $status');
    
    if (type != null && type.isNotEmpty) {
      final firstType = type[0] as Map<String, dynamic>?;
      final coding = firstType?['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final display = firstCoding?['display'] as String?;
        if (display != null) {
          buffer.writeln('**Type**: $display');
        }
      }
    }
    
    if (period != null) {
      final start = period['start'] as String?;
      final end = period['end'] as String?;
      if (start != null) {
        buffer.writeln('**Date**: ${_formatDate(start)}');
      }
      if (end != null) {
        buffer.writeln('**End Date**: ${_formatDate(end)}');
      }
    }
  }

  void _formatObservation(StringBuffer buffer, Map<String, dynamic> resource) {
    final status = resource['status'] as String? ?? 'Unknown';
    final code = resource['code'] as Map<String, dynamic>?;
    final valueQuantity = resource['valueQuantity'] as Map<String, dynamic>?;
    final valueString = resource['valueString'] as String?;
    final value = resource['value'];
    final effectiveDateTime = resource['effectiveDateTime'] as String?;
    
    buffer.writeln('**Status**: $status');
    
    if (code != null) {
      final text = code['text'] as String?;
      final coding = code['coding'] as List?;
      String? display = text;
      
      if (display == null && coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        display = firstCoding?['display'] as String?;
      }
      
      if (display != null) {
        buffer.writeln('**Test**: $display');
      }
    }
    
    if (valueQuantity != null) {
      final valueNum = valueQuantity['value'];
      final unit = valueQuantity['unit'] as String?;
      buffer.writeln('**Value**: $valueNum ${unit ?? ''}');
    } else if (valueString != null) {
      buffer.writeln('**Value**: $valueString');
    } else if (value != null) {
      buffer.writeln('**Value**: $value');
    }
    
    if (effectiveDateTime != null) {
      buffer.writeln('**Date**: ${_formatDate(effectiveDateTime)}');
    }
  }

  void _formatMedication(StringBuffer buffer, Map<String, dynamic> resource) {
    final status = resource['status'] as String? ?? 'Unknown';
    final medicationCodeableConcept = resource['medicationCodeableConcept'] as Map<String, dynamic>?;
    final medicationReference = resource['medicationReference'] as Map<String, dynamic>?;
    
    buffer.writeln('**Status**: $status');
    
    if (medicationCodeableConcept != null) {
      final text = medicationCodeableConcept['text'] as String?;
      final coding = medicationCodeableConcept['coding'] as List?;
      String? display = text;
      
      if (display == null && coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        display = firstCoding?['display'] as String?;
      }
      
      if (display != null) {
        buffer.writeln('**Medication**: $display');
      }
    } else if (medicationReference != null) {
      final display = medicationReference['display'] as String?;
      if (display != null) {
        buffer.writeln('**Medication**: $display');
      }
    }
    
    final effectivePeriod = resource['effectivePeriod'] as Map<String, dynamic>?;
    if (effectivePeriod != null) {
      final start = effectivePeriod['start'] as String?;
      if (start != null) {
        buffer.writeln('**Start Date**: ${_formatDate(start)}');
      }
    }
  }

  void _formatCondition(StringBuffer buffer, Map<String, dynamic> resource) {
    final clinicalStatus = resource['clinicalStatus'] as Map<String, dynamic>?;
    final code = resource['code'] as Map<String, dynamic>?;
    final onsetDateTime = resource['onsetDateTime'] as String?;
    
    if (clinicalStatus != null) {
      final text = clinicalStatus['text'] as String?;
      final coding = clinicalStatus['coding'] as List?;
      String? status = text;
      
      if (status == null && coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        status = firstCoding?['code'] as String? ?? firstCoding?['display'] as String?;
      }
      
      if (status != null) {
        buffer.writeln('**Status**: $status');
      }
    }
    
    if (code != null) {
      final text = code['text'] as String?;
      final coding = code['coding'] as List?;
      String? display = text;
      
      if (display == null && coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        display = firstCoding?['display'] as String?;
      }
      
      if (display != null) {
        buffer.writeln('**Condition**: $display');
      }
    }
    
    if (onsetDateTime != null) {
      buffer.writeln('**Onset Date**: ${_formatDate(onsetDateTime)}');
    }
  }

  void _formatDiagnosticReport(StringBuffer buffer, Map<String, dynamic> resource) {
    final status = resource['status'] as String? ?? 'Unknown';
    final code = resource['code'] as Map<String, dynamic>?;
    final effectiveDateTime = resource['effectiveDateTime'] as String?;
    final conclusion = resource['conclusion'] as String?;
    
    buffer.writeln('**Status**: $status');
    
    if (code != null) {
      final text = code['text'] as String?;
      final coding = code['coding'] as List?;
      String? display = text;
      
      if (display == null && coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        display = firstCoding?['display'] as String?;
      }
      
      if (display != null) {
        buffer.writeln('**Report Type**: $display');
      }
    }
    
    if (effectiveDateTime != null) {
      buffer.writeln('**Date**: ${_formatDate(effectiveDateTime)}');
    }
    
    if (conclusion != null) {
      buffer.writeln('**Conclusion**: $conclusion');
    }
  }

  void _formatImmunization(StringBuffer buffer, Map<String, dynamic> resource) {
    final status = resource['status'] as String? ?? 'Unknown';
    final vaccineCode = resource['vaccineCode'] as Map<String, dynamic>?;
    final occurrenceDateTime = resource['occurrenceDateTime'] as String?;
    
    buffer.writeln('**Status**: $status');
    
    if (vaccineCode != null) {
      final text = vaccineCode['text'] as String?;
      final coding = vaccineCode['coding'] as List?;
      String? display = text;
      
      if (display == null && coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        display = firstCoding?['display'] as String?;
      }
      
      if (display != null) {
        buffer.writeln('**Vaccine**: $display');
      }
    }
    
    if (occurrenceDateTime != null) {
      buffer.writeln('**Date**: ${_formatDate(occurrenceDateTime)}');
    }
  }

  void _formatGenericResource(StringBuffer buffer, Map<String, dynamic> resource) {
    buffer.writeln('**Resource Type**: ${resource['resourceType']}');
    buffer.writeln('**ID**: ${resource['id']}');
    
    if (resource.containsKey('status')) {
      buffer.writeln('**Status**: ${resource['status']}');
    }
    
    if (resource.containsKey('date') || resource.containsKey('effectiveDateTime')) {
      final date = resource['date'] ?? resource['effectiveDateTime'];
      if (date != null) {
        buffer.writeln('**Date**: ${_formatDate(date.toString())}');
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}

