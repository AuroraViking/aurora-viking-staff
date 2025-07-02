import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'screens/home_screen.dart';
import 'modules/admin/admin_controller.dart';
import 'modules/pickup/pickup_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables (optional - won't crash if .env doesn't exist)
  try {
    // Try to load .env file
    await dotenv.load(fileName: ".env");
    print('Successfully loaded .env file');
  } catch (e) {
    print('Warning: Could not load .env file: $e');
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
        home: const HomeScreen(),
      ),
    );
  }
}
