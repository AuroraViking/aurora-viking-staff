// Environment configuration for web-safe API key access
// Keys are injected at build time via --dart-define, NOT bundled in assets
//
// Usage:
//   flutter run -d chrome --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
//   
// Or use the run_web.sh script which reads from .env automatically!

class EnvConfig {
  // These are compile-time constants injected via --dart-define
  // They are NOT read from the .env file on web (that would expose them)
  
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
  
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY', 
    defaultValue: '',
  );
  
  /// Check if Maps API key is configured
  static bool get hasMapsKey => googleMapsApiKey.isNotEmpty;
  
  /// Check if Firebase API key is configured  
  static bool get hasFirebaseKey => firebaseApiKey.isNotEmpty;
  
  /// Debug: Print config status (don't print actual keys!)
  static void printStatus() {
    print('🔑 EnvConfig Status:');
    print('   GOOGLE_MAPS_API_KEY: ${hasMapsKey ? "✅ Set" : "❌ Not set"}');
    print('   FIREBASE_WEB_API_KEY: ${hasFirebaseKey ? "✅ Set" : "❌ Not set (using firebase_options.dart)"}');
  }
}


