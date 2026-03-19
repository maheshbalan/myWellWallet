import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../models/patient.dart';
import '../providers/query_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';
import '../services/gemma_service.dart';
import '../services/gemma_model_service.dart';
import '../services/log_service.dart';
import '../widgets/conversation_message.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_bar_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final GemmaService _gemmaService = GemmaService();

  bool _isListening = false;
  bool _speechAvailable = false;
  final List<Map<String, dynamic>> _messages = [];
  List<String> _followUpPrompts = [];
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;
  bool _showScrollToBottom = false;
  Timer? _noSpeechTimer;
  bool _gemmaReady = false;
  StreamSubscription<double>? _downloadSubscription;
  bool _isDownloadDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _micAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _micAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );

    _scrollController.addListener(_onScroll);
    // Request microphone and speech (one place only) so the app appears in Settings > Privacy (iOS)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSpeech();
      _checkGemmaStatus();
      _listenToDownloadProgress();
      
      // If model is already downloading when we enter the screen, show the dialog
      if (GemmaModelService.instance.isDownloading) {
        _showDownloadProgressDialog(0.01); // Trigger dialog with initial small progress
      }
    });
    _checkAuthentication();
    _addWelcomeMessage();
  }

  void _listenToDownloadProgress() {
    final gemma = GemmaModelService.instance;
    
    // Check if already downloading when we start listening
    if (gemma.isDownloading) {
      _showDownloadProgressDialog(gemma.currentProgress);
    }

    _downloadSubscription = gemma.downloadProgress.listen((progress) {
      if (progress > 0.0 && progress < 1.0) {
        _showDownloadProgressDialog(progress);
      } else if (progress >= 1.0) {
        if (_isDownloadDialogShowing && mounted) {
          Navigator.of(context).pop(); // Close dialog
          _isDownloadDialogShowing = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MedGemma model downloaded and ready!')),
        );
      }
    });
  }

  void _handleGemmaStatusTap() async {
    final gemma = GemmaModelService.instance;
    if (gemma.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MedGemma local AI is active and ready.')),
      );
    } else if (gemma.isDownloading) {
      _showDownloadProgressDialog(gemma.currentProgress);
    } else {
      // Not ready and not downloading, try to initialize
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting MedGemma initialization...'), duration: Duration(seconds: 2)),
      );
      try {
        await gemma.ensureInitialized();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(gemma.isReady ? 'MedGemma initialized successfully!' : 'MedGemma initialization failed.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('MedGemma Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showDownloadProgressDialog(double progress) {
    if (_isDownloadDialogShowing || !mounted) return;
    
    _isDownloadDialogShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StreamBuilder<double>(
          stream: GemmaModelService.instance.downloadProgress,
          initialData: progress,
          builder: (context, snapshot) {
            final currentProgress = snapshot.data ?? 0.0;
            return AlertDialog(
              title: const Text('Downloading AI Model'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'MyWellWallet is downloading the specialized MedGemma 4B medical AI model (~2.5GB). This only happens once.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  LinearProgressIndicator(
                    value: currentProgress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${(currentProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) => _isDownloadDialogShowing = false);
  }

  Future<void> _checkGemmaStatus() async {
    final gemma = GemmaModelService.instance;
    // Periodically check if Gemma is ready
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (gemma.isReady != _gemmaReady) {
        setState(() => _gemmaReady = gemma.isReady);
      }
      if (gemma.isReady) {
        timer.cancel();
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final show = pos.maxScrollExtent - pos.pixels > 80;
    if (show != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = show);
    }
  }

  void _addWelcomeMessage() {
    _messages.add({
      'isUser': false,
      'message':
          'Hello! I\'m your MyWellWallet assistant. How can I help you with your health records today?',
      'timestamp': DateTime.now(),
    });
    _followUpPrompts = [
      'Show me my recent visits',
      'Show me my immunization record',
      'Show me my Test Results',
    ];
  }

  Future<void> _checkAuthentication() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser == null) {
      if (mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _initializeSpeech() async {
    // Permission handler and Speech to Text are mobile-centric.
    // Skip or handle defensively on Desktop (Linux/Windows).
    if (!Platform.isAndroid && !Platform.isIOS) {
      LogService.log('HomeScreen: Speech/Permissions skipped on non-mobile platform.');
      if (mounted) setState(() => _speechAvailable = false);
      return;
    }

    try {
      // Request one at a time to avoid "already requesting permissions" on iOS
      // Speech recognition (iOS: Settings > Privacy > Speech Recognition)
      var speechStatus = await Permission.speech.status;
      if (!speechStatus.isGranted) {
        speechStatus = await Permission.speech.request();
      }
      // Microphone (iOS: Settings > Privacy > Microphone)
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
      }
      // Initialize speech_to_text (triggers native Speech framework auth on iOS when needed)
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('Speech recognition error: $error');
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (mounted) setState(() => _speechAvailable = available && micStatus.isGranted);
    } catch (e) {
      LogService.log('HomeScreen: Speech initialization error: $e');
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  void _startListening() async {
    if (!_speechAvailable) {
      await _initializeSpeech();
      if (!_speechAvailable && mounted) {
        _showVoicePermissionDialog();
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isListening = true);

    // Apple-like: timeout if no speech within 6 seconds
    _noSpeechTimer?.cancel();
    _noSpeechTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_isListening && _queryController.text.trim().isEmpty) {
        _stopListening();
      }
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) {
          _noSpeechTimer?.cancel();
          _noSpeechTimer = null;
        }
        setState(() => _queryController.text = result.recognizedWords);
        if (result.finalResult) {
          _speech.stop();
          setState(() => _isListening = false);
          final text = _queryController.text.trim();
          if (text.isNotEmpty) _processQuery();
        }
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
    );
  }

  void _stopListening() {
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _showVoicePermissionDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voice input not available'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice input needs access to your microphone and speech recognition.',
                style: TextStyle(height: 1.4),
              ),
              SizedBox(height: 16),
              Text(
                'On iPhone:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '1. Tap "Open Settings" below.\n'
                '2. Tap Privacy & Security → Microphone (and Speech Recognition if listed).\n'
                '3. Find MyWellWallet and turn it ON.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'If MyWellWallet is not in the list, return to the app and tap the microphone icon once so the permission prompt appears, then check Settings again.',
                style: TextStyle(height: 1.4, fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  Future<void> _processQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    // Add user message (no auto-scroll: question stays visible; user scrolls or uses down arrow)
    setState(() {
      _messages.add({
        'isUser': true,
        'message': query,
        'timestamp': DateTime.now(),
      });
      _queryController.clear();
      _followUpPrompts = [];
    });

    // Add typing indicator
    setState(() {
      _messages.add({
        'isUser': false,
        'message': 'typing',
        'timestamp': DateTime.now(),
      });
    });

    try {
      final queryProvider = context.read<QueryProvider>();
      await queryProvider.processQuery(query);

      // Remove typing indicator
      setState(() {
        _messages.removeLast();
      });

      if (queryProvider.error != null) {
        setState(() {
          _messages.add({
            'isUser': false,
            'message': 'Sorry, I encountered an error: ${queryProvider.error}',
            'timestamp': DateTime.now(),
          });
        });
      } else if (queryProvider.lastResult != null) {
        final result = queryProvider.lastResult!;
        bool isMarkdown = result['markdown'] != null;
        
        // Check if result has markdown (already formatted)
        if (result['markdown'] != null) {
          final response = result['markdown'] as String;
          _addAssistantMessage(response, isMarkdown: true);
        } else if (result['result'] != null || result['resources'] != null) {
          // Generate response using Gemma service WITH STREAMING
          // Normalize the data format
          final Map<String, dynamic> fhirData = result['result'] != null
              ? result['result'] as Map<String, dynamic>
              : {'resources': result['resources']};
          
          // Add an empty assistant message that we will update with tokens
          setState(() {
            _messages.add({
              'isUser': false,
              'message': '',
              'timestamp': DateTime.now(),
              'isMarkdown': true,
            });
          });
          
          final int lastIndex = _messages.length - 1;
          String fullResponse = '';
          
          await for (final token in _gemmaService.generateStreamingResponse(query, fhirData)) {
            fullResponse += token;
            if (mounted && _messages.length > lastIndex) {
              setState(() {
                _messages[lastIndex]['message'] = fullResponse;
              });
            }
            // Auto-scroll as text comes in
            _scrollToBottom();
          }
        } else {
          // If result is empty but no error, still let AI provide a friendly "no data found" message
          // instead of a hardcoded string.
          setState(() {
            _messages.add({
              'isUser': false,
              'message': '',
              'timestamp': DateTime.now(),
              'isMarkdown': true,
            });
          });

          final int lastIndex = _messages.length - 1;
          String fullResponse = '';

          await for (final token in _gemmaService.generateStreamingResponse(query, {})) {
            fullResponse += token;
            if (mounted && _messages.length > lastIndex) {
              setState(() {
                _messages[lastIndex]['message'] = fullResponse;
              });
            }
            _scrollToBottom();
          }
        }
        // Generate follow-up prompts based on query
        _updateFollowUpPrompts(query);
        WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
      }
    } catch (e) {
      LogService.log('HomeScreen error: $e');
      setState(() {
        if (_messages.isNotEmpty && _messages.last['message'] == 'typing') {
          _messages.removeLast();
        }
        _messages.add({
          'isUser': false,
          'message': 'Sorry, I encountered an error processing your request: $e',
          'timestamp': DateTime.now(),
        });
      });
    }
  }

  void _addAssistantMessage(String message, {bool isMarkdown = false}) {
    setState(() {
      _messages.add({
        'isUser': false,
        'message': message,
        'timestamp': DateTime.now(),
        'isMarkdown': isMarkdown,
      });
    });
  }

  void _updateFollowUpPrompts(String query) {
    setState(() {
      if (query.toLowerCase().contains('visit') || query.toLowerCase().contains('encounter')) {
        _followUpPrompts = ['Show me my immunization record', 'Show me my Test Results'];
      } else if (query.toLowerCase().contains('immunization') || query.toLowerCase().contains('vaccine')) {
        _followUpPrompts = ['Show me my recent visits', 'Show me my Test Results'];
      } else if (query.toLowerCase().contains('test') || query.toLowerCase().contains('result') || query.toLowerCase().contains('diagnostic')) {
        _followUpPrompts = ['Show me my recent visits', 'Show me my immunization record'];
      } else {
        _followUpPrompts = [
          'Show me my recent visits',
          'Show me my immunization record',
          'Show me my Test Results',
        ];
      }
    });
  }

  void _handleFollowUpPrompt(String prompt) {
    _queryController.text = prompt;
    _processQuery();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll after layout so new messages (e.g. from suggested question) stay visible.
  void _scrollToBottomAfterResponse() {
    _scrollToBottom();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _scrollToBottom();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _scrollToBottom();
    });
  }

  void _resetChat() {
    setState(() {
      _messages.clear();
      _addWelcomeMessage();
      _queryController.clear();
      _gemmaService.clearContext();
      context.read<QueryProvider>().clearResults();
    });
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _noSpeechTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _queryController.dispose();
    _scrollController.dispose();
    _micAnimationController.dispose();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading: _messages.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF64748B)),
                onPressed: _resetChat,
                tooltip: 'Back to home',
              )
            : const AppBarLogo(showBackButton: false),
        title: const Text('MyWellWallet'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Gemma status indicator
          InkWell(
            onTap: _handleGemmaStatusTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _gemmaReady ? Icons.bolt : Icons.bolt_outlined,
                    size: 16,
                    color: _gemmaReady ? Colors.amber : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _gemmaReady ? 'MedGemma' : 'Offline',
                    style: TextStyle(
                      fontSize: 10,
                      color: _gemmaReady ? Colors.amber.shade700 : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
            onSelected: (value) async {
              if (value == 'test') {
                context.push('/test-sse');
              } else if (value == 'logs') {
                context.push('/logs');
              } else if (value == 'logout') {
                await context.read<AuthProvider>().logout();
                if (mounted) context.go('/login');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'test',
                child: ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text('Test connection'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'logs',
                child: ListTile(
                  leading: Icon(Icons.list_alt_outlined),
                  title: Text('View logs'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_outlined),
                  title: Text('Logout'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/'),
      body: SafeArea(
        child: Column(
          children: [
            // Conversation thread (always one scrollable list, LLM-style)
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      if (message['message'] == 'typing') {
                        return const TypingIndicator();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ConversationMessage(
                          isUser: message['isUser'] as bool,
                          message: message['message'] as String,
                          timestamp: message['timestamp'] as DateTime,
                          isMarkdown: message['isMarkdown'] as bool? ?? false,
                        ),
                      );
                    },
                  ),
                  // Scroll-to-bottom button (down arrow)
                  if (_showScrollToBottom)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(24),
                        color: Colors.white,
                        child: InkWell(
                          onTap: () {
                            if (_scrollController.hasClients) {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 28,
                              color: Color(0xFF7B1FA2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Suggested questions: only before first user message (LLM-style; scroll off after use)
            if (_messages.length == 1 && _followUpPrompts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                color: const Color(0xFFFAFAFA),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested questions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._followUpPrompts.take(3).toList().asMap().entries.map((entry) {
                      final i = entry.key;
                      final prompt = entry.value;
                      final cardBgColors = [
                        const Color(0xFFFFEBEE),
                        const Color(0xFFF3E5F5),
                        const Color(0xFFE8F5E9),
                      ];
                      final iconColors = [
                        const Color(0xFFD32F2F),
                        const Color(0xFF7B1FA2),
                        const Color(0xFF388E3C),
                      ];
                      final bg = cardBgColors[i % cardBgColors.length];
                      final iconColor = iconColors[i % iconColors.length];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: bg,
                          borderRadius: BorderRadius.circular(20),
                          elevation: 0,
                          child: InkWell(
                            onTap: () => _handleFollowUpPrompt(prompt),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: iconColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.medical_services_outlined, size: 22, color: iconColor),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      prompt,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // Chat input section at the bottom
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 20),
                          Expanded(
                            child: TextField(
                              controller: _queryController,
                              style: const TextStyle(fontSize: 18),
                              decoration: InputDecoration(
                                hintText: _isListening
                                    ? 'Listening...'
                                    : 'Ask me about your health...',
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade500,
                                ),
                                border: InputBorder.none,
                              ),
                              maxLines: 1,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _processQuery(),
                              enabled: !_isListening,
                            ),
                          ),
                          // Microphone button
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _isListening
                                  ? Colors.red
                                  : Colors.grey.shade400,
                              shape: BoxShape.circle,
                              boxShadow: _isListening
                                  ? [
                                      BoxShadow(
                                        color: Colors.red.withOpacity(0.5),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: IconButton(
                              icon: Icon(
                                _isListening ? Icons.mic : Icons.mic_outlined,
                                color: Colors.white,
                                size: 26,
                              ),
                              onPressed: _toggleListening,
                              tooltip: _isListening
                                  ? 'Stop'
                                  : 'Voice input',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Send Button
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: _processQuery,
                      tooltip: 'Send',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFE8E0F0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medical_services_outlined,
              color: Color(0xFF7B1FA2),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Working...',
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
