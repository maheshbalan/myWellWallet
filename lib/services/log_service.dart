import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LogService {
  static File? _logFile;
  static final List<String> _buffer = [];
  static bool _initialized = false;

  static Future<void> init() async {
    try {
      final Directory docDir = await getApplicationSupportDirectory();
      final String logsPath = p.join(docDir.path, 'logs');
      final Directory logsDir = Directory(logsPath);
      
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      _logFile = File(p.join(logsPath, 'app.log'));
      
      // Rewrite per run (truncate existing content)
      await _logFile!.writeAsString('--- App Log Started at ${DateTime.now()} ---\n', mode: FileMode.write);
      
      _initialized = true;
      debugPrint('LogService: Logging to ${_logFile!.path}');
      
      // Flush buffer if any logs were recorded before init
      if (_buffer.isNotEmpty) {
        for (var log in _buffer) {
          await _writeToDisk(log);
        }
        _buffer.clear();
      }
    } catch (e) {
      debugPrint('LogService Error: $e');
    }
  }

  static void log(String message) {
    final String timestamp = DateTime.now().toIso8601String();
    final String formattedMessage = '[$timestamp] $message';
    
    // Always print to console
    debugPrint(formattedMessage);

    if (_initialized) {
      _writeToDisk(formattedMessage);
    } else {
      _buffer.add(formattedMessage);
    }
  }

  static Future<void> _writeToDisk(String message) async {
    try {
      await _logFile?.writeAsString('$message\n', mode: FileMode.append, flush: true);
    } catch (e) {
      // Avoid infinite recursion if debugPrint fails
    }
  }

  static String? get logPath => _logFile?.path;
}
