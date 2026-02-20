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

  /// Theme: purple accent, light background, rounded cards (design-reference style). No Google Fonts (iOS safe).
  static ThemeData _buildSafeTheme() {
    const primaryPurple = Color(0xFF7C3AED);
    const primaryPurpleLight = Color(0xFFA78BFA);
    const surfaceDark = Color(0xFF1E293B);
    const surfaceMuted = Color(0xFF64748B);
    const colorScheme = ColorScheme.light(
      primary: primaryPurple,
      secondary: primaryPurpleLight,
      tertiary: Color(0xFFF59E0B),
      surface: Colors.white,
      background: Color(0xFFFAFAFA),
      error: Color(0xFFDC2626),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: surfaceDark,
      onBackground: surfaceDark,
      onError: Colors.white,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: surfaceDark,
        displayColor: surfaceDark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: surfaceDark,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: surfaceDark),
        iconTheme: IconThemeData(color: surfaceMuted),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black26,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryPurple,
          side: const BorderSide(color: primaryPurpleLight),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: surfaceMuted,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryPurple, width: 2),
        ),
        labelStyle: const TextStyle(color: surfaceMuted),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      dividerColor: const Color(0xFFE2E8F0),
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
