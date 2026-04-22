import 'dart:io';
import 'package:llamadart/llamadart.dart';

void main() async {
  final modelPath = '/home/eli/snap/code/226/.local/share/com.mywellwallet.mywellwallet/models/gemma-2-2b-it.Q2_K.gguf';
  
  if (!File(modelPath).existsSync()) {
    print('Error: Model file not found at $modelPath');
    return;
  }

  print('--- Loading Gemma 2B locally ---');
  print('Model: $modelPath');
  
  try {
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(modelPath);
    print('Engine loaded. Generating response...');
    print('------------------------------------');

    final prompt = 'User: Describe quantum mechanics in two sentences.\nAssistant:';
    
    await for (final token in engine.generate(prompt)) {
      stdout.write(token);
    }
    
    print('\n------------------------------------');
    await engine.dispose();
  } catch (e) {
    print('Error during generation: $e');
  }
}
