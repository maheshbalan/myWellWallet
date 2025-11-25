import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'services/mcp_client.dart';
import 'providers/patient_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/query_provider.dart';
import 'screens/home_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/patient_list_screen.dart';
import 'screens/patient_detail_screen.dart';

void main() {
  runApp(const MyWellWalletApp());
}

class MyWellWalletApp extends StatelessWidget {
  const MyWellWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize MCP Client
    final mcpClient = MCPClient(
      baseUrl: 'https://mcp-fhir-server-maheshbalan1.replit.app',
    );

    // Initialize MCP connection
    mcpClient.initialize();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => PatientProvider(mcpClient: mcpClient),
        ),
        ChangeNotifierProvider(
          create: (_) => QueryProvider(mcpClient: mcpClient),
        ),
      ],
      child: MaterialApp.router(
        title: 'MyWellWallet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          // Bauhaus-inspired calming color palette for health app
          colorScheme: ColorScheme.light(
            primary: const Color(0xFF4A90E2), // Soft calming blue
            secondary: const Color(0xFF7ED321), // Fresh mint green
            tertiary: const Color(0xFFF5A623), // Warm accent
            surface: Colors.white,
            background: const Color(0xFFF8F9FA), // Very light gray
            error: const Color(0xFFE74C3C),
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: const Color(0xFF2C3E50), // Deep blue-gray
            onBackground: const Color(0xFF2C3E50),
            onError: Colors.white,
            brightness: Brightness.light,
          ),
          // Clean, geometric typography
          textTheme: const TextTheme(
            displayLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Color(0xFF2C3E50),
            ),
            displayMedium: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: Color(0xFF2C3E50),
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: Color(0xFF2C3E50),
            ),
            titleLarge: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: Color(0xFF2C3E50),
            ),
            titleMedium: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: Color(0xFF2C3E50),
            ),
            bodyLarge: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.15,
              color: Color(0xFF34495E),
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.25,
              color: Color(0xFF34495E),
            ),
            bodySmall: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.4,
              color: Color(0xFF7F8C8D),
            ),
          ),
          // Minimalist app bar
          appBarTheme: AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF2C3E50),
            titleTextStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: Color(0xFF2C3E50),
            ),
            iconTheme: const IconThemeData(
              color: Color(0xFF2C3E50),
            ),
          ),
          // Clean geometric cards
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
            margin: EdgeInsets.zero,
          ),
          // Simple button styles
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Input decoration
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
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
          // Scaffold background
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        ),
        routerConfig: _router,
      ),
    );
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegistrationScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
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
  ],
);
