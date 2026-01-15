import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:cloud_functions/cloud_functions.dart';

/// Service for AI-powered cloud map analysis
class AICloudAnalysisService {
  static final AICloudAnalysisService instance = AICloudAnalysisService._internal();
  
  AICloudAnalysisService._internal();
  
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Analyze a captured cloud map image using AI
  Future<AICloudAnalysisResult> analyzeCloudMap({
    required Uint8List mapImageBytes,
    required double latitude,
    required double longitude,
    required Map<String, dynamic> spaceWeather,
  }) async {
    try {
      final base64Image = base64Encode(mapImageBytes);
      
      final response = await _functions
          .httpsCallable('getAuroraAdvisorRecommendation')
          .call({
        'image': base64Image,
        'imageType': 'png',
        'location': {
          'latitude': latitude,
          'longitude': longitude,
        },
        'spaceWeather': spaceWeather,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final data = Map<String, dynamic>.from(response.data);
      
      if (data['success'] == true && data['result'] != null) {
        return AICloudAnalysisResult.fromJson(Map<String, dynamic>.from(data['result']));
      } else {
        return AICloudAnalysisResult.error(data['error']?.toString() ?? 'Unknown error');
      }
    } catch (e) {
      print('Error analyzing cloud map: $e');
      return AICloudAnalysisResult.error(e.toString());
    }
  }
}

/// Result from AI cloud map analysis
class AICloudAnalysisResult {
  final Map<String, String> directionAssessments; // N, NE, E, etc -> CLEAR/PARTLY_CLOUDY/CLOUDY
  final String clearestDirection;
  final String cloudiestDirection;
  final String whatAISees;
  final String recommendation;
  final String destination;
  final int distanceKm;
  final double auroraProbability;
  final double clearSkyProbability;
  final double confidence;
  final String reasoning;
  final String? error;

  AICloudAnalysisResult({
    required this.directionAssessments,
    required this.clearestDirection,
    required this.cloudiestDirection,
    required this.whatAISees,
    required this.recommendation,
    required this.destination,
    required this.distanceKm,
    required this.auroraProbability,
    required this.clearSkyProbability,
    required this.confidence,
    required this.reasoning,
    this.error,
  });

  factory AICloudAnalysisResult.fromJson(Map<String, dynamic> json) {
    return AICloudAnalysisResult(
      directionAssessments: {
        'N': json['north_assessment']?.toString() ?? 'UNKNOWN',
        'NE': json['northeast_assessment']?.toString() ?? 'UNKNOWN',
        'E': json['east_assessment']?.toString() ?? 'UNKNOWN',
        'SE': json['southeast_assessment']?.toString() ?? 'UNKNOWN',
        'S': json['south_assessment']?.toString() ?? 'UNKNOWN',
        'SW': json['southwest_assessment']?.toString() ?? 'UNKNOWN',
        'W': json['west_assessment']?.toString() ?? 'UNKNOWN',
        'NW': json['northwest_assessment']?.toString() ?? 'UNKNOWN',
      },
      clearestDirection: json['clearest_direction']?.toString() ?? 'E',
      cloudiestDirection: json['cloudiest_direction']?.toString() ?? 'W',
      whatAISees: json['what_i_see']?.toString() ?? '',
      recommendation: json['recommendation']?.toString() ?? 'Check map manually',
      destination: json['destination']?.toString() ?? '',
      distanceKm: (json['distance_km'] as num?)?.toInt() ?? 30,
      auroraProbability: (json['aurora_probability'] as num?)?.toDouble() ?? 0.5,
      clearSkyProbability: (json['clear_sky_probability'] as num?)?.toDouble() ?? 0.5,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      reasoning: json['reasoning']?.toString() ?? '',
    );
  }

  factory AICloudAnalysisResult.error(String errorMsg) {
    return AICloudAnalysisResult(
      directionAssessments: {},
      clearestDirection: 'E',
      cloudiestDirection: 'W',
      whatAISees: 'Error analyzing map',
      recommendation: 'Check map manually',
      destination: '',
      distanceKm: 0,
      auroraProbability: 0,
      clearSkyProbability: 0,
      confidence: 0,
      reasoning: '',
      error: errorMsg,
    );
  }

  bool get hasError => error != null;
  
  /// Get color for a direction assessment
  Color getColorForDirection(String direction) {
    final assessment = directionAssessments[direction] ?? 'UNKNOWN';
    switch (assessment) {
      case 'CLEAR':
        return const Color(0xFF00FF88); // Green
      case 'PARTLY_CLOUDY':
        return const Color(0xFFFFAA00); // Amber
      case 'CLOUDY':
        return const Color(0xFFFF4444); // Red
      default:
        return const Color(0xFF888888); // Grey
    }
  }
}
