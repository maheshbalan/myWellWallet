import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
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
  static const int _desktopMaxPromptChars = 200000;

  static const String _downloadUserAgent =
      'MyWellWallet/1.0 (MedGemma; Flutter; +https://github.com/)';

  /// Platform-aware prompt character budget (iOS 2000 / Android 3500 /
  /// desktop 200k). Exposed so prompt builders can size their content ahead
  /// of the hard cap in [capPromptToBudget].
  static int promptBudgetForPlatform() {
    if (Platform.isIOS) return _iosMaxPromptChars;
    if (Platform.isAndroid) return _androidMaxPromptChars;
    return _desktopMaxPromptChars;
  }

  /// Trim [prompt] to fit within [budget] characters while preserving the
  /// trailing Gemma chat-turn marker (`<start_of_turn>model`). Naive
  /// substring truncation can chop the marker mid-string and leave the
  /// model with an un-terminated user turn, which produces garbage output
  /// or a stalled stream. This function clips the BODY of the prompt and
  /// always keeps the marker suffix intact.
  static String capPromptToBudget(String prompt, int budget) {
    if (prompt.length <= budget) return prompt;

    const modelMarker = '<start_of_turn>model';
    final markerIdx = prompt.lastIndexOf(modelMarker);
    if (markerIdx < 0) {
      LogService.log(
        'GemmaModelService: capPromptToBudget — no model marker found; '
        'clipping prompt from ${prompt.length} to $budget',
      );
      return prompt.substring(0, budget);
    }

    final tail = prompt.substring(markerIdx);
    if (tail.length >= budget) {
      // Degenerate: marker alone exceeds budget. Return it anyway so the
      // model sees at least a well-formed terminator.
      LogService.log(
        'GemmaModelService: capPromptToBudget — marker tail exceeds budget '
        '(${tail.length} > $budget); returning marker only',
      );
      return tail;
    }

    const truncationNotice = '\n...[truncated]...\n';
    final bodyBudget = budget - tail.length - truncationNotice.length;
    if (bodyBudget <= 0) {
      LogService.log(
        'GemmaModelService: capPromptToBudget — no room for body; '
        'returning marker only',
      );
      return tail;
    }

    final body = prompt.substring(0, markerIdx);
    final clippedBody = body.length > bodyBudget
        ? body.substring(0, bodyBudget) + truncationNotice
        : body;
    LogService.log(
      'GemmaModelService: capPromptToBudget — trimmed body from '
      '${body.length} to ${clippedBody.length} chars (budget $budget, '
      'marker preserved)',
    );
    return clippedBody + tail;
  }

  String _capPrompt(String prompt) =>
      capPromptToBudget(prompt, promptBudgetForPlatform());

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

      _preloadLlamaNativeDepsOnLinux();

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

  /// Validity is determined by a sibling `.done` sentinel written only after
  /// the download reaches [TaskStatus.complete]. The sentinel records the
  /// final byte count, so a later truncation or replacement of the model file
  /// is detected as invalid. Avoids baking a size threshold into the code and
  /// works for any future model swap (different name, different size).
  static File _sentinelFor(File modelFile) => File('${modelFile.path}.done');

  /// llamadart 0.6.4 ships `libllamadart.so` with a hardcoded CI RUNPATH
  /// (`/home/runner/work/llamadart-native/.../bin`) that doesn't exist on a
  /// user's machine, so its `libllama.so.0` and `libggml-base.so.0` siblings
  /// fail to load even though they're sitting next to it in the Flutter
  /// bundle's `lib/` directory. Preload them via absolute path so the dynamic
  /// linker finds them by SONAME when libllamadart is later dlopen'd from a
  /// worker isolate.
  static bool _llamaDepsPreloaded = false;
  static void _preloadLlamaNativeDepsOnLinux() {
    if (!Platform.isLinux || _llamaDepsPreloaded) return;
    final exec = Platform.resolvedExecutable;
    final libDir = '${exec.substring(0, exec.lastIndexOf('/'))}/lib';
    const deps = [
      'libggml-base.so.0',
      'libggml-cpu.so.0',
      'libggml.so.0',
      'libllama.so.0',
    ];
    for (final name in deps) {
      try {
        DynamicLibrary.open('$libDir/$name');
      } catch (e) {
        LogService.log('GemmaModelService: preload $name failed: $e');
      }
    }
    _llamaDepsPreloaded = true;
    LogService.log('GemmaModelService: preloaded llama native deps from $libDir');
  }

  Future<bool> _isValidModelFile(File file) async {
    if (!await file.exists()) return false;
    final sentinel = _sentinelFor(file);
    if (!await sentinel.exists()) return false;
    final recordedSize = int.tryParse((await sentinel.readAsString()).trim());
    if (recordedSize == null || recordedSize <= 0) return false;
    return await file.length() == recordedSize;
  }

  Future<void> _writeCompletionSentinel(File file) async {
    try {
      await _sentinelFor(file).writeAsString((await file.length()).toString());
    } catch (e) {
      LogService.log('GemmaModelService: failed to write sentinel: $e');
    }
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

  /// Interval between pause/resume checkpoints. Each checkpoint forces the
  /// library to flush ResumeData to disk so an abrupt app kill loses at most
  /// this much progress rather than restarting from zero.
  static const Duration _checkpointInterval = Duration(seconds: 60);

  Future<String> _downloadModelFile(File modelFile) {
    if (Platform.isIOS || Platform.isAndroid) {
      return _downloadWithBackgroundDownloader(modelFile);
    }
    return _downloadWithRangeResume(modelFile);
  }

  /// Desktop path. Writes directly to [modelFile], using an HTTP Range request
  /// to continue from whatever bytes are already on disk. The file itself is
  /// the resume state — no separate checkpoint database, no library-managed
  /// temp file — so progress honestly reflects `bytesOnDisk / totalBytes`
  /// whether you're starting fresh, resuming this session's download, or
  /// resuming a partial from a prior session.
  Future<String> _downloadWithRangeResume(File modelFile) async {
    final uri = Uri.parse(AppConfig.gemmaModelUrl);
    final existingBytes =
        await modelFile.exists() ? await modelFile.length() : 0;

    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 90)
      ..idleTimeout = const Duration(minutes: 30);

    HttpClientResponse response;
    try {
      var request = await httpClient.getUrl(uri);
      request.headers.set('User-Agent', _downloadUserAgent);
      if (existingBytes > 0) {
        request.headers.set('Range', 'bytes=$existingBytes-');
        LogService.log(
          'GemmaModelService: resuming from ${existingBytes ~/ (1024 * 1024)} MB',
        );
      }
      response = await request.close();

      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // File on disk is >= server's size — treat as corrupt, start over.
        await response.drain<void>(null);
        if (await modelFile.exists()) await modelFile.delete();
        request = await httpClient.getUrl(uri);
        request.headers.set('User-Agent', _downloadUserAgent);
        response = await request.close();
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>(null);
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final isPartial = response.statusCode == HttpStatus.partialContent;
      int? totalBytes;
      final contentRange = response.headers.value('content-range');
      if (contentRange != null) {
        final slash = contentRange.lastIndexOf('/');
        if (slash != -1 && slash < contentRange.length - 1) {
          totalBytes = int.tryParse(contentRange.substring(slash + 1).trim());
        }
      }
      if (totalBytes == null) {
        final clen = response.contentLength;
        if (clen > 0) {
          totalBytes = isPartial ? existingBytes + clen : clen;
        }
      }
      if (totalBytes == null || totalBytes <= 0) {
        await response.drain<void>(null);
        throw HttpException(
          'Could not determine total file size from server headers.',
          uri: uri,
        );
      }

      // Server ignored our Range and returned the full file. Start fresh.
      if (!isPartial && existingBytes > 0) {
        await modelFile.delete();
      }

      final sink = isPartial
          ? modelFile.openWrite(mode: FileMode.append)
          : modelFile.openWrite();

      var downloaded = isPartial ? existingBytes : 0;
      _currentProgress = (downloaded / totalBytes).clamp(0.0, 1.0);
      _progressController.add(_currentProgress);
      LogService.log(
        'GemmaModelService: HTTP ${response.statusCode}; '
        'total=${totalBytes ~/ (1024 * 1024)} MB, '
        'starting at ${downloaded ~/ (1024 * 1024)} MB '
        '(${(_currentProgress * 100).toStringAsFixed(1)}%)',
      );

      var lastEmitMs = 0;
      var lastLogBytes = downloaded;
      try {
        await for (final chunk in response) {
          downloaded += chunk.length;
          sink.add(chunk);

          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastEmitMs >= 250) {
            lastEmitMs = now;
            _currentProgress = (downloaded / totalBytes).clamp(0.0, 1.0);
            _progressController.add(_currentProgress);
          }

          if (downloaded - lastLogBytes >= 100 * 1024 * 1024) {
            lastLogBytes = downloaded;
            LogService.log(
              'GemmaModelService: ${downloaded ~/ (1024 * 1024)} MB '
              '(${(downloaded / totalBytes * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (downloaded != totalBytes) {
        throw HttpException(
          'Download ended at $downloaded / $totalBytes bytes',
          uri: uri,
        );
      }

      _currentProgress = 1.0;
      _progressController.add(1.0);
      await _writeCompletionSentinel(modelFile);
      return modelFile.path;
    } finally {
      httpClient.close();
    }
  }

  /// Mobile path. `background_downloader` handles OS-managed background
  /// transfer so a locked screen / backgrounded app doesn't kill the download.
  /// The library uses its own temp file separate from the final path, so
  /// progress reflects the library's state (which correctly accounts for a
  /// resumed task's starting byte, via its own ResumeData).
  Future<String> _downloadWithBackgroundDownloader(File modelFile) async {
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

    final uri = Uri.parse(AppConfig.gemmaModelUrl);
    final completer = Completer<TaskStatusUpdate>();
    final sub = FileDownloader().updates.listen((update) {
      if (update.task.taskId != task.taskId) return;
      if (update is TaskProgressUpdate) {
        _currentProgress = update.progress;
        _progressController.add(update.progress);
      } else if (update is TaskStatusUpdate) {
        LogService.log(
          'GemmaModelService: background download status: ${update.status.name}',
        );
        const terminal = {
          TaskStatus.complete,
          TaskStatus.failed,
          TaskStatus.canceled,
          TaskStatus.notFound,
        };
        if (update.status == TaskStatus.paused && !completer.isCompleted) {
          // Auto-resume from checkpoint pause. ResumeData is written to
          // storage asynchronously by the isolate, so we wait briefly before
          // calling resume() to avoid racing the storage write.
          final t = update.task;
          if (t is DownloadTask) {
            Future.delayed(const Duration(milliseconds: 400), () async {
              if (completer.isCompleted) return;
              final ok = await FileDownloader().resume(t);
              if (!ok && !completer.isCompleted) {
                LogService.log(
                  'GemmaModelService: checkpoint resume returned false; '
                  'enqueueing fresh task to continue',
                );
                await FileDownloader().enqueue(t);
              }
            });
          }
        } else if (terminal.contains(update.status) && !completer.isCompleted) {
          completer.complete(update);
        }
      }
    });

    Timer? checkpointTimer;
    try {
      final resumed = await FileDownloader().resume(task);
      if (resumed) {
        LogService.log(
          'GemmaModelService: resuming prior download (stored Range data found)',
        );
      } else {
        LogService.log(
          'GemmaModelService: no resume data; enqueueing fresh download',
        );
        final enqueued = await FileDownloader().enqueue(task);
        if (!enqueued) {
          throw HttpException('Failed to enqueue download task', uri: uri);
        }
      }

      checkpointTimer = Timer.periodic(_checkpointInterval, (_) async {
        if (completer.isCompleted) return;
        // Just trigger pause. The status listener calls resume() once it sees
        // TaskStatus.paused, which guarantees ResumeData is persisted first.
        try {
          await FileDownloader().pause(task);
        } catch (e) {
          LogService.log('GemmaModelService: checkpoint pause: $e');
        }
      });

      final result = await completer.future;
      if (result.status != TaskStatus.complete) {
        final detail = result.exception?.toString() ?? result.status.name;
        throw HttpException('Background download failed: $detail', uri: uri);
      }
      final path = await result.task.filePath();
      if (path != modelFile.path) {
        LogService.log(
          'GemmaModelService: model saved at $path (expected ${modelFile.path})',
        );
      }
      final saved = File(path);
      if (!await saved.exists()) {
        throw HttpException(
          'Background download finished but file is missing.',
          uri: uri,
        );
      }
      await _writeCompletionSentinel(saved);
      return path;
    } finally {
      checkpointTimer?.cancel();
      await sub.cancel();
    }
  }
}
