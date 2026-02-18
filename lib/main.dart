import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/mcp_client.dart';
import 'services/database_service.dart';
import 'services/local_query_service.dart';
import 'services/gemma_rag_service.dart';
import 'providers/patient_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/query_provider.dart';
import 'screens/home_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/patient_list_screen.dart';
import 'screens/patient_detail_screen.dart';
import 'screens/fetch_data_screen.dart';
import 'test/mcp_sse_test_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // Show errors in the UI instead of crashing (helps debug SIGABRT)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('App error:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${details.exception}', style: const TextStyle(fontSize: 14)),
              if (details.stack != null) ...[
                const SizedBox(height: 16),
                Text('${details.stack}', style: const TextStyle(fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() {
    runApp(const MyWellWalletApp());
  }, (error, stackTrace) {
    debugPrint('Uncaught zone error: $error');
    debugPrint('$stackTrace');
  });
}

class MyWellWalletApp extends StatefulWidget {
  const MyWellWalletApp({super.key});

  @override
  State<MyWellWalletApp> createState() => _MyWellWalletAppState();
}

class _MyWellWalletAppState extends State<MyWellWalletApp> {
  late final MCPClient _mcpClient;
  late final AuthProvider _authProvider;
  late final DatabaseService _databaseService;
  late final LocalQueryService _localQueryService;
  late final GemmaRAGService _gemmaRAGService;

  @override
  void initState() {
    super.initState();

    _mcpClient = MCPClient(
      baseUrl: 'https://mcp-fhir-server.com',
      apiKey: '9mgmf20y4hRDq6-VuvHM8E5PRUQJDLVHI0gB_pFMiTY',
    );

    _authProvider = AuthProvider();
    _databaseService = DatabaseService();
    _localQueryService = LocalQueryService(databaseService: _databaseService);
    _gemmaRAGService = GemmaRAGService(
      queryService: _localQueryService,
      databaseService: _databaseService,
    );

    // Do not run async initializers inside `build()`.
    // Kick them off here and ensure errors don't take down app startup.
    unawaited(_safeInit());
  }

  Future<void> _safeInit() async {
    try {
      await _mcpClient.initialize();
    } catch (e, st) {
      debugPrint('MCPClient.initialize failed: $e');
      debugPrint('$st');
    }

    try {
      await _gemmaRAGService.initialize();
    } catch (e, st) {
      debugPrint('GemmaRAGService.initialize failed: $e');
      debugPrint('$st');
    }
  }

  /// Theme without Google Fonts to avoid iOS SIGABRT on font load.
  static ThemeData _buildSafeTheme() {
    const colorScheme = ColorScheme.light(
      primary: Color(0xFF4A90E2),
      secondary: Color(0xFF7ED321),
      tertiary: Color(0xFFF5A623),
      surface: Colors.white,
      background: Color(0xFFF8F9FA),
      error: Color(0xFFE74C3C),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFF2C3E50),
      onBackground: Color(0xFF2C3E50),
      onError: Colors.white,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: ThemeData.light().textTheme.apply(bodyColor: const Color(0xFF2C3E50)),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF2C3E50),
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)),
        iconTheme: IconThemeData(color: Color(0xFF2C3E50)),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 2),
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: _authProvider,
        ),
        ChangeNotifierProvider(
          create: (_) => PatientProvider(mcpClient: _mcpClient),
        ),
        ChangeNotifierProxyProvider<PatientProvider, QueryProvider>(
          create: (_) {
            final queryProvider = QueryProvider(mcpClient: _mcpClient);
            queryProvider.setLocalQueryService(_localQueryService);
            queryProvider.setGemmaRAGService(_gemmaRAGService);
            return queryProvider;
          },
          update: (_, patientProvider, previous) {
            previous ??= QueryProvider(mcpClient: _mcpClient);
            previous.setLocalQueryService(_localQueryService);
            previous.setGemmaRAGService(_gemmaRAGService);
            previous.setPatientProvider(patientProvider);
            return previous;
          },
        ),
      ],
      child: MaterialApp.router(
        title: 'MyWellWallet',
        debugShowCheckedModeBanner: false,
        theme: _buildSafeTheme(),
        routerConfig: _router,
      ),
    );
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Wait for user loading to complete
    while (authProvider.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    // Check if user exists in database
    final userExists = await authProvider.userExists();
    
    // If no user exists, go to registration (one-time setup)
    if (!userExists && state.uri.path != '/register') {
      return '/register';
    }
    
    // If user exists but not authenticated, go to login (normal flow after registration)
    // Never redirect to registration if user already exists
    if (userExists && 
        !authProvider.isAuthenticated && 
        state.uri.path != '/login' && 
        state.uri.path != '/register') {
      return '/login';
    }
    
    // Prevent access to registration if user already exists
    if (userExists && state.uri.path == '/register') {
      return '/login';
    }
    
    return null;
  },
  routes: [
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegistrationScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/patients',
      builder: (context, state) => const PatientListScreen(),
    ),
    GoRoute(
      path: '/patient/:id',
      builder: (context, state) {
        final patientId = state.pathParameters['id']!;
        return PatientDetailScreen(patientId: patientId);
      },
    ),
    GoRoute(
      path: '/test-sse',
      builder: (context, state) {
        return const MCPSSETestScreen();
      },
    ),
    GoRoute(
      path: '/fetch-data',
      builder: (context, state) {
        return const FetchDataScreen();
      },
    ),
  ],
);
