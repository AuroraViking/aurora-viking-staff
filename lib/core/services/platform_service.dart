import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformService {
  static const MethodChannel _channel = MethodChannel('aurora_viking_location');
  
  /// Start the Android location tracking service
  static Future<bool> startLocationService() async {
    if (kIsWeb) {
      // Web doesn't support native location services
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('startLocationService');
      return result;
    } on PlatformException catch (e) {
      print('❌ Failed to start location service: ${e.message}');
      return false;
    }
  }
  
  /// Stop the Android location tracking service
  static Future<bool> stopLocationService() async {
    if (kIsWeb) {
      // Web doesn't support native location services
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('stopLocationService');
      return result;
    } on PlatformException catch (e) {
      print('❌ Failed to stop location service: ${e.message}');
      return false;
    }
  }
  
  /// Check if the location service is running
  static Future<bool> isLocationServiceRunning() async {
    if (kIsWeb) {
      // Web doesn't support native location services
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('isLocationServiceRunning');
      return result;
    } on PlatformException catch (e) {
      print('❌ Failed to check location service status: ${e.message}');
      return false;
    }
  }
  
  /// Request battery optimization bypass
  static Future<bool> requestBatteryOptimizationBypass() async {
    if (kIsWeb) {
      // Web doesn't support battery optimization
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('requestBatteryOptimizationBypass');
      return result;
    } on PlatformException catch (e) {
      print('❌ Failed to request battery optimization bypass: ${e.message}');
      return false;
    }
  }
  
  /// Request precise location permission
  static Future<bool> requestPreciseLocationPermission() async {
    if (kIsWeb) {
      // Web uses browser geolocation API (handled by geolocator package)
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('requestPreciseLocationPermission');
      return result;
    } on PlatformException catch (e) {
      print('❌ Failed to request precise location permission: ${e.message}');
      return false;
    }
  }
} 