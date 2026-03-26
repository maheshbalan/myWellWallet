import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import 'log_service.dart';

/// GemmaModelService
///
/// Thin wrapper around a local MedGemma 4B GGUF model running
/// via the `llamadart` runtime.
///
/// **Memory caps (llamadart):** On iOS/Android we cap `contextSize`, GPU layers,
/// batch sizes, max new tokens, and prompt length to reduce peak RAM and avoid
/// jetsam. This is the closest equivalent to MLX `set_memory_limit` in pure Dart.
class GemmaModelService {
  GemmaModelService._internal();

  static final GemmaModelService instance = GemmaModelService._internal();

  /// Load-time caps: smaller KV / context and less GPU residency on phones.
  static ModelParams _modelParamsForPlatform() {
    if (Platform.isIOS) {
      return const ModelParams(
        contextSize: 2048,
        gpuLayers: 20,
        batchSize: 512,
        microBatchSize: 256,
      );
    }
    if (Platform.isAndroid) {
      return const ModelParams(
        contextSize: 3072,
        gpuLayers: 32,
        batchSize: 768,
        microBatchSize: 384,
      );
    }
    return const ModelParams(
      contextSize: 4096,
      gpuLayers: 0,
      batchSize: 1024,
      microBatchSize: 512,
    );
  }

  /// Generation caps: limit decode length so KV/active buffers stay bounded.
  static GenerationParams _generationParamsForPlatform() {
    if (Platform.isIOS) {
      return const GenerationParams(maxTokens: 640, temp: 0.7, topP: 0.9);
    }
    if (Platform.isAndroid) {
      return const GenerationParams(maxTokens: 1024, temp: 0.7, topP: 0.9);
    }
    return const GenerationParams(maxTokens: 2048, temp: 0.8, topP: 0.9);
  }

  static const int _iosMaxPromptChars = 2000;
  static const int _androidMaxPromptChars = 3500;

  /// MedGemma 4B Q4_K_M is ~2.5GB; used when CDN omits Content-Length (chunked).
  static const int _expectedApproxModelBytes = 2550 * 1024 * 1024;

  /// Dart [HttpClient] defaults to a 15s idle gap between chunks — too short for
  /// multi-GB Hugging Face CDN downloads on mobile (stream appears to “hang”).
  static const Duration _downloadIdleTimeout = Duration(minutes: 30);
  static const Duration _downloadConnectTimeout = Duration(seconds: 90);

  static const String _downloadUserAgent =
      'MyWellWallet/1.0 (MedGemma; Flutter; +https://github.com/)';

  static int? _parseTotalBytesFromContentRange(String? header) {
    if (header == null || header.isEmpty) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0 || slash >= header.length - 1) return null;
    return int.tryParse(header.substring(slash + 1).trim());
  }

  static double _progressRatio(int downloaded, int? totalBytes) {
    if (totalBytes != null && totalBytes > 0) {
      return (downloaded / totalBytes).clamp(0.0, 1.0);
    }
    return (downloaded / _expectedApproxModelBytes).clamp(0.0, 0.99);
  }

  String _capPrompt(String prompt) {
    final limit = Platform.isIOS
        ? _iosMaxPromptChars
        : (Platform.isAndroid ? _androidMaxPromptChars : 200000);
    if (prompt.length > limit) {
      LogService.log(
        'GemmaModelService: Truncating prompt from ${prompt.length} to $limit chars.',
      );
      return prompt.substring(0, limit);
    }
    return prompt;
  }

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

      final modelParams = _modelParamsForPlatform();
      LogService.log(
        'GemmaModelService: Memory-capped ModelParams: contextSize=${modelParams.contextSize}, '
        'gpuLayers=${modelParams.gpuLayers}, batchSize=${modelParams.batchSize}, '
        'microBatchSize=${modelParams.microBatchSize}',
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
    prompt = _capPrompt(prompt);
    final genParams = _generationParamsForPlatform();

    final buffer = StringBuffer();
    try {
      await for (final token in _engine!.generate(prompt, params: genParams)) {
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
    prompt = _capPrompt(prompt);
    final genParams = _generationParamsForPlatform();

    try {
      await for (final token in _engine!.generate(prompt, params: genParams)) {
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

  /// Helper to check if a model file exists and is of valid size (~2.5GB)
  Future<bool> _isValidModelFile(File file) async {
    if (!await file.exists()) return false;
    final size = await file.length();
    // The MedGemma 4B Q4_K_M model should be around 2.5GB. We accept anything > 1.5GB.
    return size > 1500 * 1024 * 1024;
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
      final savedPath = await _downloadModelFile(modelFile);
      final savedFile = File(savedPath);
      if (!await _isValidModelFile(savedFile)) {
        throw HttpException(
          'Download ended but file is still too small (${(await savedFile.length()) ~/ (1024 * 1024)} MB). '
          'Try again — progress will resume if the server supports it.',
        );
      }
      _currentProgress = 1.0;
      _progressController.add(1.0);
      LogService.log('GemmaModelService: Download complete. Path: $savedPath');
      return savedPath;
    } catch (e, st) {
      LogService.log('GemmaModelService: Download FAILED: $e');
      _downloading = false;
      // Keep multi-GB partial files so the next attempt can resume via Range (unless nearly empty).
      if (await modelFile.exists()) {
        try {
          final len = await modelFile.length();
          if (len < 100 * 1024) {
            await modelFile.delete();
          }
        } catch (_) {}
      }
      rethrow;
    } finally {
      _downloading = false;
    }
  }

  /// iOS/Android: system background transfer (URLSession / DownloadWorker) so locking the device does not stop the download.
  Future<String> _downloadModelWithBackgroundDownloader(File modelFile) async {
    await FileDownloader().ready;
    final task = DownloadTask(
      taskId: 'mywellwallet_medgemma_4b_q4_k_m',
      url: AppConfig.gemmaModelUrl,
      filename: AppConfig.gemmaModelFileName,
      directory: 'models',
      baseDirectory: BaseDirectory.applicationSupport,
      headers: {'User-Agent': _downloadUserAgent},
      updates: Updates.statusAndProgress,
      retries: 4,
      allowPause: true,
      displayName: 'MedGemma 4B medical model',
    );

    final result = await FileDownloader().download(
      task,
      onProgress: (p) {
        _currentProgress = p;
        _progressController.add(p);
      },
      onStatus: (s) {
        LogService.log('GemmaModelService: background download status: $s');
      },
    );

    if (result.status != TaskStatus.complete) {
      final detail = result.exception?.toString() ?? result.status.name;
      throw HttpException(
        'Background download failed: $detail',
        uri: Uri.parse(AppConfig.gemmaModelUrl),
      );
    }

    final path = await result.task.filePath();
    if (path != modelFile.path) {
      LogService.log(
        'GemmaModelService: model saved at $path (expected ${modelFile.path})',
      );
    }
    final saved = File(path);
    if (!await _isValidModelFile(saved)) {
      throw HttpException(
        'Background download finished but file is missing or too small.',
        uri: Uri.parse(AppConfig.gemmaModelUrl),
      );
    }
    return path;
  }

  Future<String> _downloadModelFile(File modelFile) async {
    if (Platform.isIOS || Platform.isAndroid) {
      return _downloadModelWithBackgroundDownloader(modelFile);
    }
    await _downloadModelWithResilientClient(modelFile);
    return modelFile.path;
  }

  /// Desktop: long idle timeout, optional HTTP Range resume, progress when length unknown.
  Future<void> _downloadModelWithResilientClient(File modelFile) async {
    final uri = Uri.parse(AppConfig.gemmaModelUrl);
    var resumeFrom = 0;
    if (await modelFile.exists()) {
      resumeFrom = await modelFile.length();
      if (resumeFrom >= 1500 * 1024 * 1024) {
        return;
      }
    }

    final httpClient = HttpClient()
      ..connectionTimeout = _downloadConnectTimeout
      ..idleTimeout = _downloadIdleTimeout;
    final client = IOClient(httpClient);

    try {
      Future<http.StreamedResponse> sendOnce(int start) async {
        final request = http.Request('GET', uri);
        request.headers['User-Agent'] = _downloadUserAgent;
        if (start > 0) {
          request.headers['Range'] = 'bytes=$start-';
          LogService.log(
            'GemmaModelService: Resuming download from byte $start (${(start / (1024 * 1024)).toStringAsFixed(1)} MB)',
          );
        }
        return client.send(request);
      }

      var streamed = await sendOnce(resumeFrom);

      if (streamed.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        if (await _isValidModelFile(modelFile)) return;
        if (await modelFile.exists()) await modelFile.delete();
        resumeFrom = 0;
        streamed = await sendOnce(0);
      }

      if (streamed.statusCode != HttpStatus.ok &&
          streamed.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Failed to download model: HTTP ${streamed.statusCode}',
          uri: uri,
        );
      }

      final partial = streamed.statusCode == HttpStatus.partialContent;
      if (!partial && resumeFrom > 0) {
        await modelFile.delete();
        resumeFrom = 0;
      }

      final IOSink sink = partial
          ? modelFile.openWrite(mode: FileMode.append)
          : modelFile.openWrite();

      var downloaded = partial ? resumeFrom : 0;
      int? totalBytes = _parseTotalBytesFromContentRange(
        streamed.headers['content-range'],
      );
      final clen = streamed.contentLength;
      if (totalBytes == null && clen != null && clen > 0) {
        totalBytes = partial ? downloaded + clen : clen;
      }

      LogService.log(
        'GemmaModelService: HTTP ${streamed.statusCode}; '
        'totalBytes=${totalBytes != null ? (totalBytes / (1024 * 1024)).toStringAsFixed(1) : "?"} MB',
      );

      var lastEmitMs = 0;
      var lastLogBytes = downloaded;

      await for (final chunk in streamed.stream) {
        downloaded += chunk.length;
        sink.add(chunk);

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastEmitMs >= 250 || downloaded == totalBytes) {
          lastEmitMs = now;
          final p = _progressRatio(downloaded, totalBytes);
          _currentProgress = p;
          _progressController.add(p);
        }

        if (downloaded - lastLogBytes >= 50 * 1024 * 1024) {
          lastLogBytes = downloaded;
          LogService.log(
            'GemmaModelService: ${(downloaded / (1024 * 1024)).toStringAsFixed(0)} MB '
            '(${(_progressRatio(downloaded, totalBytes) * 100).toStringAsFixed(1)}%)',
          );
        }
      }

      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }
}
