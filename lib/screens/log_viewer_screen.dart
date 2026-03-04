import 'dart:io';
import 'package:flutter/material.dart';
import '../services/log_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _logContent = 'Loading logs...';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final path = LogService.logPath;
    if (path == null) {
      setState(() => _logContent = 'Log path not available.');
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() => _logContent = content);
      } else {
        setState(() => _logContent = 'Log file does not exist yet.');
      }
    } catch (e) {
      setState(() => _logContent = 'Error reading logs: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final path = LogService.logPath;
              if (path != null) {
                final file = File(path);
                if (await file.exists()) {
                  await file.writeAsString('--- Logs Cleared ---\n');
                  _loadLogs();
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _logContent,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
