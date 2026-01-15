import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';

/// Service to capture AI context widget and send to Cloud Function for analysis
class AICaptureService {
  static final AICaptureService instance = AICaptureService._internal();
  
  AICaptureService._internal();
  
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Send captured image to AI for aurora recommendation
  /// This uses the existing getAuroraAdvisorRecommendation Cloud Function
  /// which already supports satelliteImages parameter
  Future<Map<String, dynamic>> getAIRecommendationWithImage({
    required Uint8List imageBytes,
    required double latitude,
    required double longitude,
    required Map<String, dynamic> spaceWeather,
    String? nauticalDarknessStart,
    String? nauticalDarknessEnd,
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);
      
      final result = await _functions
          .httpsCallable('getAuroraAdvisorRecommendation')
          .call({
        'location': {
          'lat': latitude,
          'lng': longitude,
        },
        'spaceWeather': spaceWeather,
        'cloudCover': spaceWeather['cloudCover'] ?? 0,
        'satelliteImages': [base64Image], // Enhanced chart + cloud map image
        'currentTime': DateTime.now().toIso8601String(),
        'darknessWindow': nauticalDarknessStart != null ? {
          'nauticalStart': nauticalDarknessStart,
          'nauticalEnd': nauticalDarknessEnd,
        } : null,
      });

      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      print('Error getting AI recommendation with image: $e');
      return {
        'error': e.toString(),
        'recommendation': 'Unable to get AI recommendation at this time.',
        'aurora_probability': 0.0,
        'clear_sky_probability': 0.0,
        'combined_viewing_probability': 0.0,
        'confidence': 0.0,
      };
    }
  }
}
