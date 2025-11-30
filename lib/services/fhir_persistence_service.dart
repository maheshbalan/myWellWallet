import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'database_service.dart';
import '../models/patient.dart';

/// Service for persisting FHIR data retrieved from MCP server
class FHIRPersistenceService {
  final DatabaseService _database = DatabaseService();

  /// Save patient data from FHIR MCP server response
  Future<void> savePatientData({
    required Patient patient,
    required Map<String, dynamic> fhirResponse,
  }) async {
    try {
      debugPrint('Saving patient data to local database: ${patient.id}');
      
      // Extract bundle from response
      Map<String, dynamic> bundle;
      if (fhirResponse.containsKey('result')) {
        final result = fhirResponse['result'];
        if (result is Map && result.containsKey('content')) {
          final content = result['content'] as List;
          if (content.isNotEmpty) {
            final textContent = content[0]['text'] as String;
            bundle = jsonDecode(textContent) as Map<String, dynamic>;
          } else {
            bundle = fhirResponse;
          }
        } else if (result is Map && result.containsKey('response')) {
          // Wrap in bundle format
          bundle = {
            'resourceType': 'Bundle',
            'type': 'searchset',
            'entry': [
              {
                'resource': result['response'],
              }
            ],
          };
        } else {
          bundle = fhirResponse;
        }
      } else if (fhirResponse.containsKey('response')) {
        // Wrap in bundle format
        bundle = {
          'resourceType': 'Bundle',
          'type': 'searchset',
          'entry': [
            {
              'resource': fhirResponse['response'],
            }
          ],
        };
      } else {
        bundle = fhirResponse;
      }

      // Save patient bundle
      await _database.savePatientBundle(
        patientId: patient.id,
        patientName: patient.displayName,
        fhirBundle: bundle,
      );

      debugPrint('Patient data saved successfully');
    } catch (e) {
      debugPrint('Error saving patient data: $e');
      rethrow;
    }
  }

  /// Save list of patients from search results
  Future<void> savePatientsList({
    required List<Patient> patients,
    required Map<String, dynamic> fhirResponse,
  }) async {
    try {
      debugPrint('Saving ${patients.length} patients to local database');
      
      // Extract bundle from response
      Map<String, dynamic> bundle;
      if (fhirResponse.containsKey('result')) {
        final result = fhirResponse['result'];
        if (result is Map && result.containsKey('content')) {
          final content = result['content'] as List;
          if (content.isNotEmpty) {
            final textContent = content[0]['text'] as String;
            bundle = jsonDecode(textContent) as Map<String, dynamic>;
          } else {
            bundle = fhirResponse;
          }
        } else if (result is Map && result.containsKey('response')) {
          bundle = result['response'] as Map<String, dynamic>;
        } else {
          bundle = fhirResponse;
        }
      } else {
        bundle = fhirResponse;
      }

      // Save each patient
      if (bundle.containsKey('entry')) {
        final entries = bundle['entry'] as List;
        for (var i = 0; i < entries.length && i < patients.length; i++) {
          final entry = entries[i];
          final patient = patients[i];
          
          // Create individual bundle for each patient
          final patientBundle = {
            'resourceType': 'Bundle',
            'type': 'searchset',
            'entry': [entry],
          };

          await _database.savePatientBundle(
            patientId: patient.id,
            patientName: patient.displayName,
            fhirBundle: patientBundle,
          );
        }
      }

      debugPrint('Patients saved successfully');
    } catch (e) {
      debugPrint('Error saving patients list: $e');
      rethrow;
    }
  }

  /// Get patient bundle from local database
  Future<Map<String, dynamic>?> getPatientBundle(String patientId) async {
    try {
      return await _database.getPatientBundle(patientId);
    } catch (e) {
      debugPrint('Error getting patient bundle: $e');
      return null;
    }
  }

  /// Get patient resources of specific type
  Future<List<Map<String, dynamic>>> getPatientResources(
    String patientId,
    String resourceType,
  ) async {
    try {
      return await _database.getPatientResources(patientId, resourceType);
    } catch (e) {
      debugPrint('Error getting patient resources: $e');
      return [];
    }
  }

  /// Get all patient resources
  Future<List<Map<String, dynamic>>> getAllPatientResources(String patientId) async {
    try {
      return await _database.getAllPatientResources(patientId);
    } catch (e) {
      debugPrint('Error getting all patient resources: $e');
      return [];
    }
  }
}

