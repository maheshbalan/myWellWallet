import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../providers/query_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';
import '../services/gemma_service.dart';
import '../widgets/conversation_message.dart';

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

    _initializeSpeech();
    _checkAuthentication();
    _establishPatientContext();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    _messages.add({
      'isUser': false,
      'message':
          'Hello! I\'m your MyWellWallet assistant. How can I help you with your health records today?',
      'timestamp': DateTime.now(),
    });
    _followUpPrompts = [
      'Show me the most recent timeline',
      'Show me my medications',
      'Show me the recent tests',
      'Show me the latest diagnostic reports',
    ];
  }

  Future<void> _establishPatientContext() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user != null && user.dateOfBirth != null) {
      final patientProvider = context.read<PatientProvider>();
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
    } else if (user != null) {
      final patientProvider = context.read<PatientProvider>();
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

  Future<void> _checkAuthentication() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null && !authProvider.isAuthenticated) {
      if (mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _initializeSpeech() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _isListening = status == 'listening';
              if (!_isListening) {
                _micAnimationController.stop();
                _micAnimationController.reset();
              } else {
                _micAnimationController.repeat(reverse: true);
              }
            });
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Speech error: ${error.errorMsg}')),
            );
          }
        },
      );
      if (mounted) {
        setState(() {
          _speechAvailable = available;
        });
      }
    }
  }

  void _startListening() {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    _speech.listen(
      onResult: (result) {
        setState(() {
          _queryController.text = result.recognizedWords;
        });
      },
    );
    setState(() {
      _isListening = true;
    });
    _micAnimationController.repeat(reverse: true);
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
    _micAnimationController.stop();
    _micAnimationController.reset();
  }

  Future<void> _processQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    // Add user message
    setState(() {
      _messages.add({
        'isUser': true,
        'message': query,
        'timestamp': DateTime.now(),
      });
      _queryController.clear();
    });

    _gemmaService.addToHistory('user', query);
    _scrollToBottom();

    // Add typing indicator
    setState(() {
      _messages.add({
        'isUser': false,
        'message': 'typing',
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();

    try {
      final queryProvider = context.read<QueryProvider>();
      await queryProvider.processQuery(query);

      // Remove typing indicator
      setState(() {
        _messages.removeLast();
      });

      if (queryProvider.error != null) {
        // Add error message
        setState(() {
          _messages.add({
            'isUser': false,
            'message':
                'I\'m sorry, I encountered an error: ${queryProvider.error}',
            'timestamp': DateTime.now(),
          });
        });
      } else if (queryProvider.lastResult != null) {
        // Generate conversational response
        final response = await _gemmaService.generateResponse(
          query,
          queryProvider.lastResult!,
        );

        setState(() {
          _messages.add({
            'isUser': false,
            'message': response,
            'timestamp': DateTime.now(),
          });

          // Generate follow-up prompts
          _followUpPrompts = _gemmaService.generateFollowUpPrompts(
            query,
            queryProvider.lastResult,
          );
        });

        _gemmaService.addToHistory('assistant', response);
      }
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add({
          'isUser': false,
          'message':
              'I encountered an error processing your request. Please try again.',
          'timestamp': DateTime.now(),
        });
      });
    }

    _scrollToBottom();
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

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _micAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.currentUser == null && !authProvider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/register');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!authProvider.isAuthenticated || authProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MyWellWallet'),
        actions: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.flask),
            onPressed: () => context.go('/test-sse'),
            tooltip: 'Test SSE Connection',
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.user),
            onPressed: () => context.go('/profile'),
            tooltip: 'Profile',
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.rightFromBracket),
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (mounted) {
                context.go('/login');
              }
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome Message (only shown when no conversation)
          if (_messages.length <= 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: ConversationMessage(
                isUser: false,
                message: _messages.isNotEmpty
                    ? _messages[0]['message'] as String
                    : 'Hello! I\'m your MyWellWallet assistant. How can I help you with your health records today?',
                timestamp: DateTime.now(),
              ),
            ),

          // Conversation Area (scrollable, like ChatGPT/Claude)
          Expanded(
            child: _messages.length <= 1
                ? const SizedBox.shrink()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      if (message['message'] == 'typing') {
                        return const TypingIndicator();
                      }
                      return ConversationMessage(
                        isUser: message['isUser'] as bool,
                        message: message['message'] as String,
                        timestamp: message['timestamp'] as DateTime,
                      );
                    },
                  ),
          ),

          // Bottom Section: Prompts + Search Bar (always visible)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Follow-up Prompts (stacked vertically, max 3)
              if (_followUpPrompts.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _followUpPrompts.length > 3
                        ? 3
                        : _followUpPrompts.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: InkWell(
                            onTap: () =>
                                _handleFollowUpPrompt(_followUpPrompts[index]),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Icon(
                                    FontAwesomeIcons.lightbulb,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _followUpPrompts[index],
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Search Bar (always accessible at bottom)
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Recording Indicator
                    if (_isListening)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red, width: 2),
                        ),
                        child: Row(
                          children: [
                            AnimatedBuilder(
                              animation: _micAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _micAnimation.value,
                                  child: Icon(
                                    FontAwesomeIcons.microphone,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Recording... Tap to stop',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                FontAwesomeIcons.circleStop,
                                color: Colors.red,
                              ),
                              onPressed: _stopListening,
                              tooltip: 'Stop Recording',
                            ),
                          ],
                        ),
                      ),

                    // Input Field
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            decoration: InputDecoration(
                              hintText: _isListening
                                  ? 'Listening...'
                                  : 'Type your question or tap the mic...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              suffixIcon: _isListening
                                  ? IconButton(
                                      icon: const Icon(
                                        FontAwesomeIcons.circleStop,
                                        color: Colors.red,
                                      ),
                                      onPressed: _stopListening,
                                      tooltip: 'Stop Recording',
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        FontAwesomeIcons.microphone,
                                        color: _speechAvailable
                                            ? colorScheme.primary
                                            : Colors.grey,
                                      ),
                                      onPressed: _speechAvailable
                                          ? _startListening
                                          : null,
                                      tooltip: 'Start Voice Input',
                                    ),
                            ),
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _processQuery(),
                            enabled: !_isListening,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Send Button
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              FontAwesomeIcons.paperPlane,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: _processQuery,
                            tooltip: 'Send',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
