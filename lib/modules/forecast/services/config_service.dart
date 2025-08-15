import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigService {
  /// Get OpenWeatherMap API key from environment variables
  static String get weatherApiKey => dotenv.env['OPENWEATHER_API_KEY'] ?? '';
  
  /// Get other API keys as needed
  static String get noaaApiKey => dotenv.env['NOAA_API_KEY'] ?? '';
  
  /// Check if required API keys are configured
  static bool get isWeatherConfigured => weatherApiKey.isNotEmpty;
  static bool get isNoaaConfigured => noaaApiKey.isNotEmpty;
} 