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
      'Show me my recent visits',
      'Show me my immunization record',
      'Show me my Test Results',
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
    if (authProvider.currentUser == null) {
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
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          debugPrint('Speech recognition error: $error');
          setState(() {
            _isListening = false;
          });
        },
      );
      setState(() {
        _speechAvailable = available;
      });
    }
  }

  void _startListening() async {
    if (!_speechAvailable) return;

    setState(() {
      _isListening = true;
    });

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() {
            _queryController.text = result.recognizedWords;
            _isListening = false;
          });
          _processQuery();
        } else {
          setState(() {
            _queryController.text = result.recognizedWords;
          });
        }
      },
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

    // Add user message
    setState(() {
      _messages.add({
        'isUser': true,
        'message': query,
        'timestamp': DateTime.now(),
      });
      _queryController.clear();
      _followUpPrompts = [];
    });

    _scrollToBottom();

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
    _micAnimationController.dispose();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MyWellWallet',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Profile Button - Clean Health UI Kit style
          IconButton(
            icon: const Icon(
              Icons.person_outline,
              size: 24,
            ),
            onPressed: () => context.go('/profile'),
            tooltip: 'Profile',
          ),
          // Test Connection Button - Clean Health UI Kit style
          IconButton(
            icon: const Icon(
              Icons.science_outlined,
              size: 24,
            ),
            onPressed: () => context.go('/test-sse'),
            tooltip: 'Test Connection',
          ),
          // Fetch Data Button - Clean Health UI Kit style
          IconButton(
            icon: const Icon(
              Icons.cloud_download_outlined,
              size: 24,
            ),
            onPressed: () => context.go('/fetch-data'),
            tooltip: 'Fetch Data',
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_outlined,
              size: 24,
            ),
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
      body: SafeArea(
        child: Column(
          children: [
            // Prominent Search Bar Section (at top, large and friendly)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome text (larger, friendly)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'How can I help you today?',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  
                  // Large Search Bar
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: _isListening 
                                  ? Colors.red 
                                  : colorScheme.primary.withOpacity(0.3),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
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
                                  onPressed: _speechAvailable
                                      ? _toggleListening
                                      : null,
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

            // Suggested Questions (prominent, larger, friendly)
            if (_followUpPrompts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested Questions:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._followUpPrompts.take(3).map((prompt) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _handleFollowUpPrompt(prompt),
                            icon: const Icon(
                              Icons.lightbulb_outline,
                              size: 18,
                            ),
                            label: Text(
                              prompt,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.left,
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              alignment: Alignment.centerLeft,
                              backgroundColor: Colors.white,
                              foregroundColor: colorScheme.primary,
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: colorScheme.primary.withOpacity(0.3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // Conversation Area (scrollable)
            Expanded(
              child: _messages.length <= 1
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConversationMessage(
                          isUser: false,
                          message: _messages.isNotEmpty
                              ? _messages[0]['message'] as String
                              : 'Hello! I\'m your MyWellWallet assistant. How can I help you with your health records today?',
                          timestamp: DateTime.now(),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_outline,
              color: Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Working...',
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
