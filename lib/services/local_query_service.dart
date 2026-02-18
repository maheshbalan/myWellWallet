import 'package:flutter/foundation.dart';
import 'database_service.dart';

/// Service for querying local SQLite database for FHIR resources
/// 
/// This service provides methods to query the local database first,
/// before falling back to MCP Gateway queries.
class LocalQueryService {
  final DatabaseService databaseService;

  LocalQueryService({required this.databaseService});

  /// Query local database for FHIR resources
  /// 
  /// [patientId] - Patient ID to query
  /// [resourceType] - FHIR resource type (e.g., "Encounter", "Observation")
  /// [filters] - Optional filters (e.g., {"sort": "-date", "limit": 10, "codeSearch": "cholesterol"})
  /// [recordIndex] - Optional specific record index (0-based)
  /// 
  /// Returns list of FHIR resources or empty list if not found
  Future<List<Map<String, dynamic>>> queryLocal(
    String patientId,
    String resourceType, {
    Map<String, dynamic>? filters,
    int? recordIndex,
  }) async {
    try {
      debugPrint('Querying local database: patientId=$patientId, resourceType=$resourceType');
      
      // Get resources from database
      final resources = await databaseService.getPatientResources(patientId, resourceType);
      
      if (resources.isEmpty) {
        debugPrint('No local resources found for $resourceType');
        return [];
      }
      
      debugPrint('Found ${resources.length} local resources for $resourceType');
      
      // Apply filters if provided
      var filteredResources = resources;
      
      if (filters != null) {
        // Filter by code search (for Observations - cholesterol, glucose, etc.)
        if (filters.containsKey('codeSearch')) {
          final codeSearch = filters['codeSearch'] as String?;
          if (codeSearch != null) {
            filteredResources = _filterByCodeSearch(filteredResources, codeSearch);
            debugPrint('Filtered to ${filteredResources.length} resources matching "$codeSearch"');
          }
        }
        
        // Sort by date if requested
        if (filters.containsKey('sort')) {
          final sort = filters['sort'] as String?;
          if (sort != null) {
            filteredResources = _sortResources(filteredResources, sort);
          }
        }
        
        // Limit results if requested
        if (filters.containsKey('limit')) {
          final limit = filters['limit'] as int?;
          if (limit != null && limit > 0) {
            filteredResources = filteredResources.take(limit).toList();
          }
        }
        
        // Filter by status if requested
        if (filters.containsKey('status')) {
          final status = filters['status'] as String?;
          if (status != null) {
            filteredResources = filteredResources.where((resource) {
              final resourceStatus = resource['status'] as String?;
              return resourceStatus?.toLowerCase() == status.toLowerCase();
            }).toList();
          }
        }
      }
      
      // Apply record index if specified (for "record 8" type queries)
      if (recordIndex != null && recordIndex >= 0) {
        if (recordIndex < filteredResources.length) {
          filteredResources = [filteredResources[recordIndex]];
          debugPrint('Returning specific record at index $recordIndex');
        } else {
          debugPrint('Record index $recordIndex out of range (${filteredResources.length} records available)');
          return [];
        }
      }
      
      return filteredResources;
    } catch (e) {
      debugPrint('Error querying local database: $e');
      return [];
    }
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
      'blood pressure': ['85354-9', '8480-6', '8462-4'], // BP, Systolic, Diastolic
      'hemoglobin': ['718-7', '4548-4'], // HGB, HbA1c
      'creatinine': ['2160-0'],
      'sodium': ['2951-2'],
      'potassium': ['2823-3'],
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
    final value = resource['valueQuantity'] ?? resource['valueString'] ?? resource['value'];
    final effectiveDateTime = resource['effectiveDateTime'] as String?;
    
    buffer.writeln('**Status**: $status');
    
    if (code != null) {
      final coding = code['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final display = firstCoding?['display'] as String?;
        if (display != null) {
          buffer.writeln('**Test**: $display');
        }
      }
    }
    
    if (value != null) {
      if (value is Map) {
        final valueQuantity = value as Map<String, dynamic>;
        final valueNum = valueQuantity['value'];
        final unit = valueQuantity['unit'] as String?;
        buffer.writeln('**Value**: $valueNum ${unit ?? ''}');
      } else {
        buffer.writeln('**Value**: $value');
      }
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
      final coding = medicationCodeableConcept['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final display = firstCoding?['display'] as String?;
        if (display != null) {
          buffer.writeln('**Medication**: $display');
        }
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
      final coding = clinicalStatus['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final code = firstCoding?['code'] as String?;
        if (code != null) {
          buffer.writeln('**Status**: $code');
        }
      }
    }
    
    if (code != null) {
      final coding = code['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final display = firstCoding?['display'] as String?;
        if (display != null) {
          buffer.writeln('**Condition**: $display');
        }
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
      final coding = code['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final display = firstCoding?['display'] as String?;
        if (display != null) {
          buffer.writeln('**Report Type**: $display');
        }
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
      final coding = vaccineCode['coding'] as List?;
      if (coding != null && coding.isNotEmpty) {
        final firstCoding = coding[0] as Map<String, dynamic>?;
        final display = firstCoding?['display'] as String?;
        if (display != null) {
          buffer.writeln('**Vaccine**: $display');
        }
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

