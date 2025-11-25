import 'package:flutter/foundation.dart';
import '../models/patient.dart';
import '../services/mcp_client.dart';

class PatientProvider with ChangeNotifier {
  final MCPClient mcpClient;
  
  List<Patient> _patients = [];
  Patient? _selectedPatient;
  bool _isLoading = false;
  String? _error;

  PatientProvider({required this.mcpClient});

  List<Patient> get patients => _patients;
  Patient? get selectedPatient => _selectedPatient;
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

  /// Clear selected patient
  void clearSelectedPatient() {
    _selectedPatient = null;
    notifyListeners();
  }
}

