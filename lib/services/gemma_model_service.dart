import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

/// GemmaModelService
///
/// Thin wrapper around a local Gemma 2 2B (or Med-Gemma) GGUF model running
/// via the `llamadart` runtime. The model file is downloaded on first use
/// and cached on device; we keep the IPA size reasonable and still run
/// inference fully on-device.
///
/// NOTE: You must set [_modelUrl] to a valid URL for a Gemma 2 2B (or
/// Med-Gemma) GGUF model (e.g. Q2_K or Q3_K) that this app is allowed to
/// download and use.
class GemmaModelService {
  GemmaModelService._internal();

  static final GemmaModelService instance = GemmaModelService._internal();

  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  bool _initialized = false;
  bool _initializing = false;
  bool _downloading = false;
  String? _modelPath;

  // TODO: Set this to your hosted Gemma 2 2B / Med-Gemma GGUF URL.
  // For example, a signed URL or a proxy that serves:
  //   gemma-2-2b-it-Q2_K.gguf   (~700–900 MB)
  //
  // Keep this private; if you want it configurable, read from a secure
  // config instead of hard-coding.
  static const String _modelUrl = '';

  static const String _modelFileName = 'gemma-2-2b-it-q2_k.gguf';

  /// Returns true if a model file URL has been configured.
  bool get isConfigured => _modelUrl.isNotEmpty;

  /// Returns true if the model is currently loaded and ready.
  bool get isReady => _initialized;

  /// Ensure the model is downloaded and loaded into the LlamaEngine.
  ///
  /// If `_modelUrl` is not set, this is a no-op and the caller should
  /// fall back to rule-based behavior.
  Future<void> ensureInitialized() async {
    if (!isConfigured) {
      debugPrint('GemmaModelService: _modelUrl not set; skipping model init.');
      return;
    }
    if (_initialized) return;
    if (_initializing) {
      // Another caller is already initializing; wait until it completes.
      while (_initializing) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return;
    }

    _initializing = true;
    try {
      final path = await _ensureModelDownloaded();
      _modelPath = path;
      debugPrint('GemmaModelService: Loading model from $path');
      await _engine.loadModel(path);
      _initialized = true;
      debugPrint('GemmaModelService: Model loaded successfully.');
    } catch (e, st) {
      debugPrint('GemmaModelService: Failed to initialize model: $e');
      debugPrint('$st');
      _initialized = false;
    } finally {
      _initializing = false;
    }
  }

  /// Generate a completion for [prompt] using the Gemma model.
  ///
  /// This is a simple helper that collects all tokens into a single string.
  /// Callers that want streaming can use [generateStream] instead.
  Future<String?> generate(String prompt) async {
    await ensureInitialized();
    if (!_initialized) return null;

    final buffer = StringBuffer();
    try {
      await for (final token in _engine.generate(prompt)) {
        buffer.write(token);
      }
    } catch (e, st) {
      debugPrint('GemmaModelService: generate() failed: $e');
      debugPrint('$st');
      return null;
    }
    return buffer.toString();
  }

  /// Generate a stream of tokens for [prompt].
  ///
  /// The stream is empty if the model is not initialized.
  Stream<String> generateStream(String prompt) async* {
    await ensureInitialized();
    if (!_initialized) return;

    try {
      await for (final token in _engine.generate(prompt)) {
        yield token;
      }
    } catch (e, st) {
      debugPrint('GemmaModelService: generateStream() failed: $e');
      debugPrint('$st');
    }
  }

  /// Dispose the underlying engine (e.g., on app shutdown).
  Future<void> dispose() async {
    try {
      await _engine.dispose();
    } catch (e) {
      debugPrint('GemmaModelService: dispose() failed: $e');
    }
  }

  Future<String> _ensureModelDownloaded() async {
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    final modelFile = File('${modelsDir.path}/$_modelFileName');

    if (await modelFile.exists()) {
      debugPrint('GemmaModelService: Using cached model at ${modelFile.path}');
      return modelFile.path;
    }

    if (_downloading) {
      // Wait for existing download to finish.
      while (_downloading && !await modelFile.exists()) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (await modelFile.exists()) return modelFile.path;
    }

    if (_modelUrl.isEmpty) {
      throw StateError(
        'GemmaModelService: _modelUrl is empty; cannot download model. '
        'Set a valid URL for gemma-2-2b-it GGUF.',
      );
    }

    _downloading = true;
    debugPrint('GemmaModelService: Downloading model from $_modelUrl');

    try {
      final request = http.Request('GET', Uri.parse(_modelUrl));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode}',
          uri: Uri.parse(_modelUrl),
        );
      }

      final sink = modelFile.openWrite();
      int downloaded = 0;
      final total = response.contentLength ?? 0;

      await for (final chunk in response.stream) {
        downloaded += chunk.length;
        sink.add(chunk);
        if (total > 0 && downloaded % (5 * 1024 * 1024) < chunk.length) {
          final mb = downloaded / (1024 * 1024);
          final totalMb = total / (1024 * 1024);
          debugPrint(
            'GemmaModelService: Downloaded ${mb.toStringAsFixed(1)} MB '
            'of ${totalMb.toStringAsFixed(1)} MB',
          );
        }
      }
      await sink.flush();
      await sink.close();

      debugPrint('GemmaModelService: Model downloaded to ${modelFile.path}');
      return modelFile.path;
    } catch (e, st) {
      debugPrint('GemmaModelService: Error downloading model: $e');
      debugPrint('$st');
      if (await modelFile.exists()) {
        try {
          await modelFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _downloading = false;
    }
  }
}

