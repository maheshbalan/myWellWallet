import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../providers/query_provider.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _queryController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _spokenText = '';
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final authProvider = context.read<AuthProvider>();
    
    // If user exists but not authenticated, prompt for biometrics
    if (authProvider.currentUser != null && !authProvider.isAuthenticated) {
      final authenticated = await authProvider.authenticate();
      if (!authenticated && mounted) {
        // User cancelled authentication, redirect to registration
        context.go('/register');
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

  void _startListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    setState(() {
      _spokenText = '';
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _spokenText = result.recognizedWords;
          _queryController.text = result.recognizedWords;
        });
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  Future<void> _processQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    final queryProvider = context.read<QueryProvider>();
    await queryProvider.processQuery(query);
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

    // Show registration if not authenticated
    if (!authProvider.isAuthenticated && !authProvider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/register');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MyWellWallet'),
        actions: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.users),
            onPressed: () => context.go('/patients'),
            tooltip: 'View Patients',
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.rightFromBracket),
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (mounted) {
                context.go('/register');
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
            Container(
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
                          color: colorScheme.primary.withOpacity(0.1),
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
                          // Text Input
                          TextField(
                            controller: _queryController,
                            decoration: InputDecoration(
                              hintText: 'Type your question or tap the mic...',
                              border: InputBorder.none,
                              suffixIcon: _isListening
                                  ? IconButton(
                                      icon: const Icon(
                                        FontAwesomeIcons.circleStop,
                                        color: Colors.red,
                                      ),
                                      onPressed: _stopListening,
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        FontAwesomeIcons.microphone,
                                        color: _speechAvailable
                                            ? colorScheme.primary
                                            : Colors.grey,
                                      ),
                                      onPressed: _speechAvailable ? _startListening : null,
                                    ),
                            ),
                            maxLines: 3,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _processQuery(),
                          ),
                          const SizedBox(height: 12),
                          
                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _speechAvailable && !_isListening
                                      ? _startListening
                                      : null,
                                  icon: Icon(
                                    _isListening
                                        ? FontAwesomeIcons.circleStop
                                        : FontAwesomeIcons.microphone,
                                    size: 16,
                                  ),
                                  label: Text(_isListening ? 'Listening...' : 'Voice Input'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: _processQuery,
                                  icon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 16),
                                  label: const Text('Search'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Spoken Text Display
                  if (_spokenText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            FontAwesomeIcons.microphoneLines,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _spokenText,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

                  // Empty State
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
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
                            'Try asking:\n• "Show me all patients"\n• "List my medications"\n• "What are my lab results?"',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF7F8C8D),
                              height: 1.6,
                ),
              ),
            ],
          ),
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
