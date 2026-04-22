import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mywellwallet/services/gemma_model_service.dart';
import 'package:mywellwallet/services/log_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Mocking some dependencies since we are running in a pure Dart/Console context
void main() async {
  print('--- Gemma Console Test ---');
  
  // Initialize logging
  // Note: LogService might fail because path_provider doesn't work in pure Dart CLI
  // So we skip it or mock it.
  
  try {
    final gemma = GemmaModelService.instance;
    
    print('Status: Initializing engine...');
    // We need to provide a mock/override for path_provider if needed, 
    // but gemma_model_service uses getApplicationSupportDirectory().
    // This will likely fail in a pure Dart script.
    
    print('Error: Running a Flutter app service in a pure Dart console script '
          'is difficult due to platform channel dependencies (path_provider).');
    print('Testing if the engine can at least be accessed...');
    
    // Instead of running the full service, let's just check the model file existence
    // using the knowledge of the path.
    final modelDir = '/home/eli/.local/share/com.mywellwallet.mywellwallet/models';
    final modelFile = File('$modelDir/gemma-2-2b-it.Q2_K.gguf');
    
    if (await modelFile.exists()) {
      print('SUCCESS: Model file found at ${modelFile.path}');
      print('File size: ${(await modelFile.length() / (1024 * 1024)).toStringAsFixed(1)} MB');
    } else {
      print('FAILURE: Model file NOT found at ${modelFile.path}');
      
      // Try the snap path just in case
      final snapModelDir = '/home/eli/snap/code/226/.local/share/com.mywellwallet.mywellwallet/models';
      final snapModelFile = File('$snapModelDir/gemma-2-2b-it.Q2_K.gguf');
      if (await snapModelFile.exists()) {
        print('SUCCESS: Model file found at ${snapModelFile.path}');
        print('File size: ${(await snapModelFile.length() / (1024 * 1024)).toStringAsFixed(1)} MB');
      }
    }
  } catch (e) {
    print('Error during test: $e');
  }
}
