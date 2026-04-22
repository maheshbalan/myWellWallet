import 'package:flutter/material.dart';
import 'package:mywellwallet/services/gemma_model_service.dart';
import 'package:mywellwallet/services/log_service.dart';

/// Standalone test for Gemma LLM.
/// Run this using: flutter run test/gemma_standalone_test.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.init();
  
  runApp(const MaterialApp(
    home: GemmaTestScreen(),
  ));
}

class GemmaTestScreen extends StatefulWidget {
  const GemmaTestScreen({super.key});

  @override
  State<GemmaTestScreen> createState() => _GemmaTestScreenState();
}

class _GemmaTestScreenState extends State<GemmaTestScreen> {
  String _status = 'Initializing...';
  String _output = '';
  final _controller = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initGemma();
  }

  Future<void> _initGemma() async {
    setState(() => _status = 'Loading Gemma (Checking model file)...');
    try {
      final gemma = GemmaModelService.instance;
      await gemma.ensureInitialized();
      setState(() => _status = gemma.isReady ? 'Gemma is READY' : 'Gemma failed to load.');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _runTest() async {
    if (_isProcessing) return;
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _output = 'Thinking...';
    });

    try {
      final result = await GemmaModelService.instance.generate(prompt);
      setState(() {
        _output = result ?? 'No output received from model.';
      });
    } catch (e) {
      setState(() {
        _output = 'Execution Error: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemma Standalone Test')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Enter a test prompt',
                hintText: 'e.g. Say hello!',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _runTest,
                child: Text(_isProcessing ? 'Generating...' : 'Send to Gemma'),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Model Output:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(_output),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
