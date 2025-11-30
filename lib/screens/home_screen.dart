import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../providers/query_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _queryController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
    _checkAuthentication();
    _establishPatientContext();
  }

  Future<void> _establishPatientContext() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user != null) {
      // Establish patient context from profile name
      final patientProvider = context.read<PatientProvider>();
      try {
        await patientProvider.searchPatientByName(user.name);
      } catch (e) {
        debugPrint('Could not establish patient context: $e');
      }
    }
  }

  Future<void> _checkAuthentication() async {
    final authProvider = context.read<AuthProvider>();
    
    // If user exists but not authenticated, redirect to login
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

  void _toggleListening() {
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
      });
    } else {
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
    }
  }

  Future<void> _processQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    final queryProvider = context.read<QueryProvider>();
    await queryProvider.processQuery(query);
  }

  void _handleSuggestedQuestion(String question) {
    _queryController.text = question;
    _processQuery();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authProvider = context.watch<AuthProvider>();

    // Redirect if not authenticated
    if (authProvider.currentUser == null && !authProvider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/register');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!authProvider.isAuthenticated || authProvider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MyWellWallet'),
        actions: [
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
      body: SafeArea(
        child: Column(
          children: [
            // Query Input Section
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          FontAwesomeIcons.heartPulse,
                          size: 28,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${authProvider.currentUser?.name ?? "User"}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              'Ask me anything about your health records',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF7F8C8D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Query Input Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Text Input with integrated mic
                          TextField(
                            controller: _queryController,
                            decoration: InputDecoration(
                              hintText: 'Type your question or tap the mic...',
                              border: InputBorder.none,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isListening
                                      ? FontAwesomeIcons.circleStop
                                      : FontAwesomeIcons.microphone,
                                  color: _isListening
                                      ? Colors.red
                                      : (_speechAvailable
                                          ? colorScheme.primary
                                          : Colors.grey),
                                ),
                                onPressed: _speechAvailable ? _toggleListening : null,
                              ),
                            ),
                            maxLines: 3,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _processQuery(),
                          ),
                          const SizedBox(height: 12),
                          
                          // Search Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _processQuery,
                              icon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 16),
                              label: const Text('Search'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Results Section
            Expanded(
              child: Consumer<QueryProvider>(
                builder: (context, queryProvider, child) {
                  if (queryProvider.isProcessing) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Processing your query...'),
                        ],
                      ),
                    );
                  }

                  if (queryProvider.error != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FontAwesomeIcons.triangleExclamation,
                              size: 64,
                              color: colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              queryProvider.error!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                queryProvider.clearResults();
                                _queryController.clear();
                              },
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (queryProvider.lastResult != null) {
                    final result = queryProvider.lastResult!;
                    final interpretation = result['interpretation'] as Map<String, dynamic>;
                    final intent = interpretation['intent'] as String;

                    // Handle patient list intent
                    if (intent == 'list_patients') {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        context.go('/patients');
                      });
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Display generic results
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        FontAwesomeIcons.circleCheck,
                                        color: colorScheme.secondary,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Query Processed',
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Intent: ${interpretation['intent']}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tool: ${interpretation['tool']}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              queryProvider.clearResults();
                              _queryController.clear();
                            },
                            child: const Text('New Query'),
                          ),
                        ],
                      ),
                    );
                  }

                  // Empty State with Suggested Questions
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            FontAwesomeIcons.comments,
                            size: 50,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Ask a Question',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Try one of these questions:',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF7F8C8D),
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        // Suggested Questions
                        _buildSuggestedQuestion(
                          context,
                          'Show me the most recent timeline',
                          FontAwesomeIcons.clock,
                        ),
                        const SizedBox(height: 12),
                        _buildSuggestedQuestion(
                          context,
                          'Show me my medications',
                          FontAwesomeIcons.pills,
                        ),
                        const SizedBox(height: 12),
                        _buildSuggestedQuestion(
                          context,
                          'Show me the recent tests',
                          FontAwesomeIcons.vial,
                        ),
                        const SizedBox(height: 12),
                        _buildSuggestedQuestion(
                          context,
                          'Show me the latest diagnostic reports',
                          FontAwesomeIcons.fileLines,
                        ),
                      ],
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

  Widget _buildSuggestedQuestion(
    BuildContext context,
    String question,
    IconData icon,
  ) {
    return Card(
      child: InkWell(
        onTap: () => _handleSuggestedQuestion(question),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  question,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
