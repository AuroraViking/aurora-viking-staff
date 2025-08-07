import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'modules/admin/admin_controller.dart';
import 'modules/pickup/pickup_controller.dart';
import 'core/auth/auth_controller.dart';
import 'core/services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables (optional - won't crash if .env doesn't exist)
  try {
    // Try to load .env file
    await dotenv.load(fileName: ".env");
    print('✅ Successfully loaded .env file');
  } catch (e) {
    print('⚠️ Warning: Could not load .env file: $e');
    print('Using default environment values');
  }
  
  runApp(const AuroraVikingStaffApp());
}

class AuroraVikingStaffApp extends StatelessWidget {
  const AuroraVikingStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminController()),
        ChangeNotifierProvider(create: (_) => PickupController()),
        ChangeNotifierProvider(create: (_) => AuthController()),
      ],
      child: MaterialApp(
        title: 'Aurora Viking Staff',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A8A), // Blue color for Viking theme
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            elevation: 2,
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeFirebase(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing Aurora Viking Staff...'),
                ],
              ),
            ),
          );
        }
        
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to initialize app',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Force rebuild to retry initialization
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        
        return Consumer<AuthController>(
          builder: (context, authController, child) {
            if (authController.isLoading) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
            
            if (authController.isAuthenticated) {
              return const HomeScreen();
            }
            
            return const LoginScreen();
          },
        );
      },
    );
  }

  Future<void> _initializeFirebase() async {
    try {
      await FirebaseService.initialize();
      print('✅ Firebase initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize Firebase: $e');
      // Don't rethrow - let the app continue without Firebase for now
      // This allows the app to work in development without Firebase setup
    }
  }
}
