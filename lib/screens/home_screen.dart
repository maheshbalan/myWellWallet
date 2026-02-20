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
import '../widgets/conversation_message.dart';
import '../widgets/app_bottom_nav.dart';

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
    _initializeSpeech();
    _checkAuthentication();
    _establishPatientContext();
    _addWelcomeMessage();
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

  Future<void> _establishPatientContext() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user == null) return;

    final patientProvider = context.read<PatientProvider>();
    final existing = patientProvider.foundPatient;

    // If we already have a patient that matches the current user, reuse it so we don't clear
    // foundPatient (search* clears it at start) and avoid "Patient ID not available" on query.
    if (existing != null && _foundPatientMatchesUser(existing, user.name, user.dateOfBirth)) {
      _gemmaService.setContext(
        'Patient: ${existing.displayName}, ID: ${existing.id}',
      );
      return;
    }

    if (user.dateOfBirth != null) {
      try {
        await patientProvider.searchPatientByNameAndDOB(
          user.name,
          user.dateOfBirth!,
        );
        final patient = patientProvider.foundPatient;
        if (patient != null) {
          _gemmaService.setContext(
            'Patient: ${patient.displayName}, ID: ${patient.id}',
          );
        }
      } catch (e) {
        debugPrint('Could not establish patient context: $e');
        try {
          await patientProvider.searchPatientByName(user.name);
          final patient = patientProvider.foundPatient;
          if (patient != null) {
            _gemmaService.setContext(
              'Patient: ${patient.displayName}, ID: ${patient.id}',
            );
          }
        } catch (e2) {
          debugPrint('Could not establish patient context with name only: $e2');
        }
      }
    } else {
      try {
        await patientProvider.searchPatientByName(user.name);
        final patient = patientProvider.foundPatient;
        if (patient != null) {
          _gemmaService.setContext(
            'Patient: ${patient.displayName}, ID: ${patient.id}',
          );
        }
      } catch (e) {
        debugPrint('Could not establish patient context: $e');
      }
    }
  }

  static bool _foundPatientMatchesUser(
    Patient patient,
    String userName,
    DateTime? userDob,
  ) {
    final nameMatch = patient.displayName
            .toLowerCase()
            .contains(userName.toLowerCase()) ||
        userName.toLowerCase().contains(patient.displayName.toLowerCase());
    if (!nameMatch) return false;
    if (userDob == null) return true;
    final birthDate = patient.birthDate;
    if (birthDate == null) return true;
    final patientDob = birthDate.split('T').first;
    final expected = userDob.toIso8601String().split('T').first;
    return patientDob == expected;
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
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (status.isGranted) {
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
      if (mounted) setState(() => _speechAvailable = available);
    }
  }

  void _startListening() async {
    if (!_speechAvailable) {
      await _initializeSpeech();
      if (!_speechAvailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input is not available. Check microphone and speech recognition permissions.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _queryController.text = result.recognizedWords);
        if (result.finalResult) {
          _speech.stop();
          setState(() => _isListening = false);
          final text = _queryController.text.trim();
          if (text.isNotEmpty) _processQuery();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
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
        String response;
        
        // Check if result has markdown (from local query)
        if (result['result'] != null && result['result']['markdown'] != null) {
          response = result['result']['markdown'] as String;
        } else {
          // Generate response using Gemma service for MCP results
          response = await _gemmaService.generateResponse(
            query,
            result['result'] ?? result,
          );
        }

        setState(() {
          _messages.add({
            'isUser': false,
            'message': response,
            'timestamp': DateTime.now(),
            'isMarkdown': result['result'] != null && result['result']['markdown'] != null,
          });
          // Generate follow-up prompts based on query
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
        WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
      }
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add({
          'isUser': false,
          'message': 'Sorry, I encountered an error processing your request: $e',
          'timestamp': DateTime.now(),
        });
      });
    }
    // No auto-scroll: user keeps question in view and scrolls down or uses arrow to see answer
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

  @override
  void dispose() {
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
        title: const Text('MyWellWallet'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
            onSelected: (value) async {
              if (value == 'test') {
                context.go('/test-sse');
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
            // Purple header section with search (design-reference style)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'How can I help you today?',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // White rounded search bar inside purple area
                  Row(
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
                                        : 'Ask me anything about your health...',
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
                              // Microphone button - Clean Health UI Kit style
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _isListening
                                      ? Colors.red
                                      : colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    _isListening
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_outlined,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: _toggleListening,
                                  tooltip: _isListening
                                      ? 'Stop Recording'
                                      : 'Start Voice Input',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Send Button (large, prominent)
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
                  
                  // Recording indicator (if listening)
                  if (_isListening)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red, width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _micAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _micAnimation.value,
                                  child: const Icon(
                                    Icons.mic_outlined,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Recording... Tap microphone to stop',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
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

            // Conversation thread (always one scrollable list, LLM-style)
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
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
                      bottom: 24,
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
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 28,
                              color: const Color(0xFF7B1FA2),
                            ),
                          ),
                        ),
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
