import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import 'log_service.dart';

/// GemmaModelService
///
/// Thin wrapper around a local Gemma 2 2B GGUF model running
/// via the `llamadart` runtime.
class GemmaModelService {
  GemmaModelService._internal();

  static final GemmaModelService instance = GemmaModelService._internal();

  LlamaEngine? _engine;
  bool _initialized = false;
  bool _initializing = false;
  bool _downloading = false;
  String? _modelPath;
  double _currentProgress = 0.0;

  // Stream for download progress (0.0 to 1.0)
  final _progressController = StreamController<double>.broadcast();
  Stream<double> get downloadProgress => _progressController.stream;
  double get currentProgress => _currentProgress;

  /// Returns true if a model file URL has been configured.
  bool get isConfigured => AppConfig.gemmaModelUrl.isNotEmpty;

  /// Returns true if the model is currently loaded and ready.
  bool get isReady => _initialized;

  /// Returns true if currently downloading.
  bool get isDownloading => _downloading;

  /// Ensure the model is downloaded and loaded into the LlamaEngine.
  Future<void> ensureInitialized() async {
    LogService.log('GemmaModelService: ensureInitialized called. isConfigured: $isConfigured, _initialized: $_initialized, _initializing: $_initializing');
    
    if (!isConfigured) {
      LogService.log('GemmaModelService: gemmaModelUrl not set; skipping model init.');
      return;
    }
    if (_initialized) {
      LogService.log('GemmaModelService: Already initialized.');
      return;
    }
    if (_initializing) {
      LogService.log('GemmaModelService: Already initializing, waiting...');
      while (_initializing) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return;
    }

    _initializing = true;
    try {
      final path = await _ensureModelDownloaded();
      _modelPath = path;
      LogService.log('GemmaModelService: Loading model into engine from $path');
      
      // Platform-aware backend selection
      final LlamaBackend backend;
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: Allow GPU acceleration (Vulkan/Metal) for high performance
        LogService.log('GemmaModelService: Mobile detected. Using high-performance GPU backend.');
        backend = LlamaBackend(); 
      } else {
        // Desktop: Force CPU to avoid conflicts with Flutter rendering engine (common on Linux)
        LogService.log('GemmaModelService: Desktop detected. Using stable CPU backend.');
        backend = LlamaBackend(); // No allowModules param in LlamaBackend factory
      }

      _engine = LlamaEngine(backend);
      
      // Load model with GPU layers set to 0 to force CPU execution on Desktop
      // Use ModelParams instead of LlamaModelParams (v0.6.4 API)
      final modelParams = ModelParams(
        gpuLayers: (Platform.isAndroid || Platform.isIOS) ? ModelParams.maxGpuLayers : 0,
      );
      
      await _engine!.loadModel(path, modelParams: modelParams);
      
      _initialized = true;
      LogService.log('GemmaModelService: Model loaded successfully into engine.');
    } catch (e, st) {
      final errorMsg = e.toString().replaceAll('\n', ' ');
      LogService.log('GemmaModelService: CRITICAL FAILURE during initialization: $errorMsg');
      LogService.log('Stack trace: $st');
      _initialized = false;
      _engine = null;
    } finally {
      _initializing = false;
    }
  }

  /// Generate a completion for [prompt] using the Gemma model.
  Future<String?> generate(String prompt) async {
    await ensureInitialized();
    if (!_initialized || _engine == null) return null;

    final buffer = StringBuffer();
    try {
      await for (final token in _engine!.generate(prompt)) {
        buffer.write(token);
      }
    } catch (e, st) {
      LogService.log('GemmaModelService: generate() failed: $e');
      return null;
    }
    return buffer.toString();
  }

  /// Generate a stream of tokens for [prompt].
  Stream<String> generateStream(String prompt) async* {
    await ensureInitialized();
    if (!_initialized || _engine == null) return;

    try {
      await for (final token in _engine!.generate(prompt)) {
        yield token;
      }
    } catch (e, st) {
      LogService.log('GemmaModelService: generateStream() failed: $e');
    }
  }

  /// Dispose the underlying engine.
  Future<void> dispose() async {
    try {
      await _progressController.close();
      await _engine?.dispose();
    } catch (e) {
      LogService.log('GemmaModelService: dispose() failed: $e');
    }
  }

  /// Helper to check if a model file exists and is of valid size (~1.2GB)
  Future<bool> _isValidModelFile(File file) async {
    if (!await file.exists()) return false;
    final size = await file.length();
    // The Q2_K model should be around 1.2GB. We accept anything > 1GB.
    return size > 1000 * 1024 * 1024;
  }

  Future<String> _ensureModelDownloaded() async {
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    final modelFile = File('${modelsDir.path}/${AppConfig.gemmaModelFileName}');

    // 1. Check primary path
    if (await _isValidModelFile(modelFile)) {
      LogService.log('GemmaModelService: Found valid model at primary path: ${modelFile.path}');
      _currentProgress = 1.0;
      _progressController.add(1.0);
      return modelFile.path;
    }

    // 2. Check alternative common paths
    final altPaths = [
      '/home/eli/snap/code/226/.local/share/com.mywellwallet.mywellwallet/models/${AppConfig.gemmaModelFileName}',
      '/home/eli/.local/share/com.mywellwallet.mywellwallet/models/${AppConfig.gemmaModelFileName}',
    ];

    for (var path in altPaths) {
      final altFile = File(path);
      if (await _isValidModelFile(altFile)) {
        LogService.log('GemmaModelService: Found valid model at alternative path: $path');
        LogService.log('GemmaModelService: Copying model to primary path...');
        await altFile.copy(modelFile.path);
        _currentProgress = 1.0;
        _progressController.add(1.0);
        return modelFile.path;
      }
    }

    // 3. Fallback to download
    if (_downloading) {
      LogService.log('GemmaModelService: Download already in progress, waiting...');
      while (_downloading && !await modelFile.exists()) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (await modelFile.exists()) return modelFile.path;
    }

    _downloading = true;
    _currentProgress = 0.0;
    _progressController.add(0.0);
    LogService.log('GemmaModelService: Starting download from ${AppConfig.gemmaModelUrl}');

    try {
      final request = http.Request('GET', Uri.parse(AppConfig.gemmaModelUrl));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode}',
          uri: Uri.parse(AppConfig.gemmaModelUrl),
        );
      }

      final sink = modelFile.openWrite();
      int downloaded = 0;
      final total = response.contentLength ?? 0;
      LogService.log('GemmaModelService: Expected total size: ${(total / (1024 * 1024)).toStringAsFixed(1)} MB');

      await for (final chunk in response.stream) {
        downloaded += chunk.length;
        sink.add(chunk);
        
        if (total > 0) {
          final progress = downloaded / total;
          _currentProgress = progress;
          _progressController.add(progress);
          
          if (downloaded % (25 * 1024 * 1024) < chunk.length) {
            LogService.log('GemmaModelService: Download progress: ${(progress * 100).toStringAsFixed(1)}%');
          }
        }
      }
      await sink.flush();
      await sink.close();

      _currentProgress = 1.0;
      _progressController.add(1.0);
      LogService.log('GemmaModelService: Download complete. Path: ${modelFile.path}');
      return modelFile.path;
    } catch (e, st) {
      LogService.log('GemmaModelService: Download FAILED: $e');
      _downloading = false;
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
