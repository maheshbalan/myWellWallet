import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'services/mcp_client.dart';
import 'services/database_service.dart';
import 'services/local_query_service.dart';
import 'services/gemma_rag_service.dart';
import 'services/log_service.dart';
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
import 'screens/health_dashboard_screen.dart';
import 'screens/health_glucose_screen.dart';
import 'screens/health_heart_rate_screen.dart';
import 'screens/health_steps_screen.dart';
import 'screens/health_blood_pressure_screen.dart';
import 'screens/health_lab_results_screen.dart';
import 'screens/log_viewer_screen.dart';
import 'test/mcp_sse_test_screen.dart';
import 'config/app_config.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Logging
    await LogService.init();
    LogService.log('Application starting...');

    await _initBackgroundFileDownloader();

    // Initialize sqflite for desktop (Linux, Windows, macOS)
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

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

    runApp(const MyWellWalletApp());
  }, (error, stackTrace) {
    debugPrint('Uncaught zone error: $error');
    debugPrint('$stackTrace');
  });
}

Future<void> _initBackgroundFileDownloader() async {
  try {
    await FileDownloader().ready;
    await FileDownloader().configure(
      globalConfig: [
        (Config.requestTimeout, const Duration(minutes: 45)),
      ],
      androidConfig: [
        (Config.useCacheDir, Config.never),
      ],
    );
    // Note: FileDownloader().updates is a single-subscription stream.
    // We do NOT subscribe here — GemmaModelService owns the subscription so
    // it can drive resume/enqueue/completer logic during a download.
    // doRescheduleKilledTasks is disabled: it re-enqueues killed tasks from
    // scratch via enqueue() (not resume()), which consumes any stored
    // ResumeData without sending a Range header. GemmaModelService calls
    // FileDownloader().resume(task) itself to use the stored Range data.
    await FileDownloader().start(
      doTrackTasks: true,
      markDownloadedComplete: true,
      doRescheduleKilledTasks: false,
    );
    LogService.log('FileDownloader: ready (background downloads enabled).');
  } catch (e, st) {
    LogService.log('FileDownloader init failed: $e');
    debugPrint('$st');
  }
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
  late final PatientProvider _patientProvider;
  bool _isCoreReady = false;

  @override
  void initState() {
    super.initState();

    _mcpClient = MCPClient(
      baseUrl: AppConfig.mcpBaseUrl,
      apiKey: AppConfig.mcpApiKey,
    );

    _authProvider = AuthProvider();
    _databaseService = DatabaseService();
    _localQueryService = LocalQueryService(databaseService: _databaseService);
    _gemmaRAGService = GemmaRAGService(
      queryService: _localQueryService,
      databaseService: _databaseService,
    );
    _patientProvider = PatientProvider(mcpClient: _mcpClient);

    // Kick off initialization
    unawaited(_safeInit());
  }

  Future<void> _safeInit() async {
    try {
      // 1. Initialize MCP
      await _mcpClient.initialize();

      // 2. Initialize RAG
      await _gemmaRAGService.initialize();

      // Model download/verify is kicked off at login (see login_screen /
      // registration_screen) so unauthenticated users don't trigger a 2.5GB
      // download.

      // 4. Wait for AuthProvider to load
      int retries = 0;
      while (_authProvider.isLoading && retries < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }

      // 5. Establish patient context if user exists
      final userExists = await _authProvider.userExists();
      if (userExists) {
        final users = await _databaseService.getAllUsers();
        if (users.isNotEmpty) {
          final user = users.first;
          LogService.log('Main: Establishing patient context for ${user.name}');
          try {
            if (user.dateOfBirth != null) {
              await _patientProvider.searchPatientByNameAndDOB(user.name, user.dateOfBirth!);
            } else {
              await _patientProvider.searchPatientByName(user.name);
            }
          } catch (e) {
            LogService.log('Main: Could not establish patient context: $e');
          }
        }
      }
    } catch (e, st) {
      LogService.log('MCP/RAG Init Error: $e');
      debugPrint('$st');
    } finally {
      if (mounted) {
        setState(() {
          _isCoreReady = true;
        });
      }
    }
  }

  /// Theme: purple accent, light background, rounded cards.
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
    if (!_isCoreReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _buildSafeTheme(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icons/MyWellWallet.png',
                  width: 100,
                  height: 100,
                  errorBuilder: (_, __, ___) => const Icon(Icons.medical_services, size: 60, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Initializing MyWellWallet...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: _authProvider,
        ),
        ChangeNotifierProvider.value(
          value: _patientProvider,
        ),
        ChangeNotifierProxyProvider2<PatientProvider, AuthProvider, QueryProvider>(
          create: (_) {
            final queryProvider = QueryProvider(mcpClient: _mcpClient);
            queryProvider.setLocalQueryService(_localQueryService);
            queryProvider.setGemmaRAGService(_gemmaRAGService);
            return queryProvider;
          },
          update: (_, patientProvider, authProvider, previous) {
            previous ??= QueryProvider(mcpClient: _mcpClient);
            previous.setLocalQueryService(_localQueryService);
            previous.setGemmaRAGService(_gemmaRAGService);
            previous.setPatientProvider(patientProvider);
            previous.setAuthProvider(authProvider);
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
    
    while (authProvider.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    final userExists = await authProvider.userExists();
    
    if (!userExists && state.uri.path != '/register') {
      return '/register';
    }
    
    if (userExists && 
        !authProvider.isAuthenticated && 
        state.uri.path != '/login' && 
        state.uri.path != '/register') {
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
    GoRoute(
      path: '/logs',
      builder: (context, state) => const LogViewerScreen(),
    ),
    GoRoute(
      path: '/health',
      builder: (context, state) => const HealthDashboardScreen(),
    ),
    GoRoute(
      path: '/health/glucose',
      builder: (context, state) => const HealthGlucoseScreen(),
    ),
    GoRoute(
      path: '/health/heart-rate',
      builder: (context, state) => const HealthHeartRateScreen(),
    ),
    GoRoute(
      path: '/health/steps',
      builder: (context, state) => const HealthStepsScreen(),
    ),
    GoRoute(
      path: '/health/blood-pressure',
      builder: (context, state) => const HealthBloodPressureScreen(),
    ),
    GoRoute(
      path: '/health/lab-results',
      builder: (context, state) => const HealthLabResultsScreen(),
    ),
  ],
);
