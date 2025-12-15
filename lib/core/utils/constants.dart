// Constants file for app-wide constants and configuration values 

// App constants and configuration

class AppConstants {
  // API Configuration
  static const String apiBaseUrl = 'https://api.auroraviking.com'; // TODO: Update with actual API URL
  
  // App Configuration
  static const String appName = 'Aurora Viking Staff';
  static const String appVersion = '1.0.0';
  
  // Admin Configuration
  static const String adminPassword = 'a'; // TODO: Move to secure storage
  
  // Default Values
  static const int defaultPageSize = 20;
  static const Duration defaultTimeout = Duration(seconds: 30);
  
  // File Upload
  static const int maxImageSize = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'heic'];
  
  // Location
  static const double defaultLatitude = 64.9631; // Reykjavik
  static const double defaultLongitude = -19.0208;
  static const double locationUpdateInterval = 30.0; // seconds
  
  // UI Constants
  static const double borderRadius = 8.0;
  static const double cardElevation = 2.0;
  static const Duration animationDuration = Duration(milliseconds: 300);
} 