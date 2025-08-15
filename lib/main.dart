import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'modules/admin/admin_controller.dart';
import 'modules/pickup/pickup_controller.dart';
import 'modules/photos/photo_controller.dart';
import 'core/auth/auth_controller.dart';
import 'core/services/firebase_service.dart';
import 'theme/av_theme.dart';

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
  
  // Initialize Firebase once at app startup
  try {
    await FirebaseService.initialize();
    print('✅ Firebase initialized in main()');
  } catch (e) {
    print('❌ Failed to initialize Firebase in main(): $e');
    // Continue without Firebase for development
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
        ChangeNotifierProvider(create: (_) => PhotoController()),
        ChangeNotifierProvider(create: (_) => AuthController()),
      ],
      child: MaterialApp(
        title: 'Aurora Viking Staff',
        debugShowCheckedModeBanner: false,
        theme: avTheme(),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
  }
}
