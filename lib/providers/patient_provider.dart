import 'package:flutter/foundation.dart';
import '../models/patient.dart';
import '../services/mcp_client.dart';

class PatientProvider with ChangeNotifier {
  final MCPClient mcpClient;
  
  List<Patient> _patients = [];
  Patient? _selectedPatient;
  Patient? _foundPatient;
  bool _isLoading = false;
  String? _error;

  PatientProvider({required this.mcpClient});

  List<Patient> get patients => _patients;
  Patient? get selectedPatient => _selectedPatient;
  Patient? get foundPatient => _foundPatient;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load list of patients
  Future<void> loadPatients() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _patients = await mcpClient.getPatients();
      _error = null;
    } catch (e) {
      _error = 'Failed to load patients: $e';
      _patients = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load patient details
  Future<void> loadPatientDetails(String patientId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _selectedPatient = await mcpClient.getPatientDetails(patientId);
      _error = null;
    } catch (e) {
      _error = 'Failed to load patient details: $e';
      _selectedPatient = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search patient by name
  Future<void> searchPatientByName(String name) async {
    _isLoading = true;
    _error = null;
    _foundPatient = null;
    notifyListeners();

    try {
      // Get all patients and search by name
      final allPatients = await mcpClient.getPatients();
      
      // Try to find patient by name match
      final matchingPatient = allPatients.firstWhere(
        (patient) {
          final patientName = patient.displayName.toLowerCase();
          final searchName = name.toLowerCase();
          return patientName.contains(searchName) || searchName.contains(patientName);
        },
        orElse: () => throw Exception('No matching patient found'),
      );
      
      _foundPatient = matchingPatient;
      _error = null;
    } catch (e) {
      _error = 'Patient not found: $e';
      _foundPatient = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search patient by name and date of birth using FHIR search
  Future<void> searchPatientByNameAndDOB(String name, DateTime dateOfBirth) async {
    _isLoading = true;
    _error = null;
    _foundPatient = null;
    notifyListeners();

    try {
      // Use FHIR search with name and birthdate parameters
      final dobString = dateOfBirth.toIso8601String().split('T')[0]; // YYYY-MM-DD format
      
      // Search using FHIR search parameters
      final patients = await mcpClient.searchPatients(
        name: name,
        birthdate: dobString,
      );
      
      if (patients.isEmpty) {
        throw Exception('No patient found with name "$name" and DOB $dobString');
      }
      
      // If multiple results, try to find exact match
      Patient? matchingPatient;
      for (var patient in patients) {
        final patientName = patient.displayName.toLowerCase();
        final searchName = name.toLowerCase();
        final nameMatches = patientName.contains(searchName) || searchName.contains(patientName);
        
        bool dobMatches = true;
        if (patient.birthDate != null) {
          final patientDob = patient.birthDate!.split('T')[0];
          dobMatches = patientDob == dobString;
        }
        
        if (nameMatches && dobMatches) {
          matchingPatient = patient;
          break;
        }
      }
      
      if (matchingPatient == null && patients.isNotEmpty) {
        // Use first result if no exact match
        matchingPatient = patients.first;
      }
      
      _foundPatient = matchingPatient;
      _error = null;
    } catch (e) {
      _error = 'Patient not found: $e';
      _foundPatient = null;
      debugPrint('Error searching patient: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear selected patient
  void clearSelectedPatient() {
    _selectedPatient = null;
    notifyListeners();
  }
}

