import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Recursively converts a Map<Object?, Object?> to Map<String, dynamic>
Map<String, dynamic> _deepConvertMap(dynamic data) {
  if (data is Map) {
    return data.map((key, value) => MapEntry(
      key.toString(),
      value is Map ? _deepConvertMap(value) : (value is List ? _deepConvertList(value) : value),
    ));
  }
  return {};
}

List<dynamic> _deepConvertList(List<dynamic> list) {
  return list.map((item) => item is Map ? _deepConvertMap(item) : item).toList();
}

class AuroraRecommendation {
  final String recommendation;
  final AuroraDestination? destination;
  final double distanceKm;
  final String direction;
  final int travelTimeMinutes;
  final double auroraProbability;
  final double clearSkyProbability;
  final double combinedProbability;
  final CloudMovement? cloudMovement;
  final String spaceWeatherAnalysis;
  final double confidence;
  final String reasoning;
  final List<AlternativeOption> alternatives;
  final List<String> appliedLearnings;
  final String urgency;
  final String? specialNotes;
  final DateTime generatedAt;
  final int learningsUsed;
  final bool hasError;
  final String? errorMessage;

  AuroraRecommendation({
    required this.recommendation,
    this.destination,
    required this.distanceKm,
    required this.direction,
    required this.travelTimeMinutes,
    required this.auroraProbability,
    required this.clearSkyProbability,
    required this.combinedProbability,
    this.cloudMovement,
    required this.spaceWeatherAnalysis,
    required this.confidence,
    required this.reasoning,
    required this.alternatives,
    this.appliedLearnings = const [],
    required this.urgency,
    this.specialNotes,
    required this.generatedAt,
    this.learningsUsed = 0,
    this.hasError = false,
    this.errorMessage,
  });

  factory AuroraRecommendation.fromJson(Map<String, dynamic> json) {
    return AuroraRecommendation(
      recommendation: json['recommendation'] ?? 'No recommendation available',
      destination: json['destination'] != null ? AuroraDestination.fromJson(json['destination']) : null,
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      direction: json['direction'] ?? 'STAY',
      travelTimeMinutes: json['travel_time_minutes'] ?? 0,
      auroraProbability: (json['aurora_probability'] ?? 0).toDouble(),
      clearSkyProbability: (json['clear_sky_probability'] ?? 0).toDouble(),
      combinedProbability: (json['combined_viewing_probability'] ?? 0).toDouble(),
      cloudMovement: json['cloud_movement'] != null ? CloudMovement.fromJson(json['cloud_movement']) : null,
      spaceWeatherAnalysis: json['space_weather_analysis'] ?? '',
      confidence: (json['confidence'] ?? 0).toDouble(),
      reasoning: json['reasoning'] ?? '',
      alternatives: (json['alternative_options'] as List<dynamic>?)?.map((e) => AlternativeOption.fromJson(e)).toList() ?? [],
      appliedLearnings: (json['applied_learnings'] as List<dynamic>?)?.cast<String>() ?? [],
      urgency: json['urgency'] ?? 'medium',
      specialNotes: json['special_notes'],
      generatedAt: json['generatedAt'] != null ? DateTime.parse(json['generatedAt']) : DateTime.now(),
      learningsUsed: json['learningsUsed'] ?? 0,
      hasError: json['error'] == true,
      errorMessage: json['message'],
    );
  }

  factory AuroraRecommendation.error(String message) {
    return AuroraRecommendation(
      recommendation: 'Unable to generate recommendation',
      distanceKm: 0,
      direction: 'STAY',
      travelTimeMinutes: 0,
      auroraProbability: 0,
      clearSkyProbability: 0,
      combinedProbability: 0,
      spaceWeatherAnalysis: '',
      confidence: 0,
      reasoning: message,
      alternatives: [],
      urgency: 'low',
      generatedAt: DateTime.now(),
      hasError: true,
      errorMessage: message,
    );
  }

  String get probabilityLevel {
    if (combinedProbability >= 0.7) return 'excellent';
    if (combinedProbability >= 0.5) return 'good';
    if (combinedProbability >= 0.3) return 'moderate';
    return 'low';
  }
}

class AuroraDestination {
  final String name;
  final double lat;
  final double lng;

  AuroraDestination({required this.name, required this.lat, required this.lng});

  factory AuroraDestination.fromJson(Map<String, dynamic> json) {
    return AuroraDestination(
      name: json['name'] ?? 'Unknown',
      lat: (json['lat'] ?? 0).toDouble(),
      lng: (json['lng'] ?? 0).toDouble(),
    );
  }
}

class CloudMovement {
  final String direction;
  final double? speedKmh;
  final String analysis;

  CloudMovement({required this.direction, this.speedKmh, required this.analysis});

  factory CloudMovement.fromJson(Map<String, dynamic> json) {
    return CloudMovement(
      direction: json['direction'] ?? 'Unknown',
      speedKmh: json['speed_kmh']?.toDouble(),
      analysis: json['analysis'] ?? '',
    );
  }
}

class AlternativeOption {
  final String destination;
  final double probability;
  final double distanceKm;
  final String? note;

  AlternativeOption({required this.destination, required this.probability, required this.distanceKm, this.note});

  factory AlternativeOption.fromJson(Map<String, dynamic> json) {
    return AlternativeOption(
      destination: json['destination'] ?? 'Unknown',
      probability: (json['probability'] ?? 0).toDouble(),
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      note: json['note'],
    );
  }
}

class SpaceWeatherInput {
  final double bz;
  final double bt;
  final double speed;
  final double density;
  final double kp;
  final double? hemPower;
  final int? aeIndex;
  final double? bzH;

  SpaceWeatherInput({
    required this.bz,
    required this.bt,
    required this.speed,
    required this.density,
    required this.kp,
    this.hemPower,
    this.aeIndex,
    this.bzH,
  });

  Map<String, dynamic> toJson() => {
    'bz': bz, 'bt': bt, 'speed': speed, 'density': density,
    'kp': kp, 'hemPower': hemPower, 'aeIndex': aeIndex, 'bzH': bzH,
  };
}

class AuroraAdvisorService {
  final FirebaseFunctions _functions;

  AuroraAdvisorService._({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  static final AuroraAdvisorService _instance = AuroraAdvisorService._();
  static AuroraAdvisorService get instance => _instance;

  Future<AuroraRecommendation> getRecommendation({
    required double latitude,
    required double longitude,
    required SpaceWeatherInput spaceWeather,
    required double cloudCover,
    List<Uint8List>? satelliteImages,
    String? nauticalDarknessStart,
    String? nauticalDarknessEnd,
  }) async {
    try {
      debugPrint('🤖 Requesting Aurora Advisor recommendation...');
      debugPrint('   Cloud cover: $cloudCover%');
      debugPrint('   Darkness: $nauticalDarknessStart - $nauticalDarknessEnd');

      List<String>? base64Images;
      if (satelliteImages != null && satelliteImages.isNotEmpty) {
        base64Images = satelliteImages.map((img) => base64Encode(img)).toList();
      }

      final callable = _functions.httpsCallable('getAuroraAdvisorRecommendation');
      final result = await callable.call({
        'location': {'lat': latitude, 'lng': longitude},
        'spaceWeather': spaceWeather.toJson(),
        'cloudCover': cloudCover,
        'satelliteImages': base64Images,
        'currentTime': DateTime.now().toIso8601String(),
        'darknessWindow': {
          'nauticalStart': nauticalDarknessStart,
          'nauticalEnd': nauticalDarknessEnd,
        },
      });

      // Recursively convert the response to Map<String, dynamic>
      final Map<String, dynamic> data = _deepConvertMap(result.data);
      return AuroraRecommendation.fromJson(data);
    } catch (e) {
      debugPrint('❌ Aurora Advisor error: $e');
      return AuroraRecommendation.error(e.toString());
    }
  }

  static double calculateLocalAuroraProbability({
    required double bz,
    required double speed,
    required double kp,
    required double density,
  }) {
    double score = 0;
    if (bz < -10) score += 40;
    else if (bz < -5) score += 25;
    else if (bz < 0) score += 10;
    
    if (speed > 500) score += 20;
    else if (speed > 400) score += 15;
    else if (speed > 300) score += 5;
    
    if (kp >= 5) score += 25;
    else if (kp >= 4) score += 20;
    else if (kp >= 3) score += 10;
    
    if (density > 10) score += 15;
    else if (density > 5) score += 10;

    return (score / 100).clamp(0.0, 1.0);
  }

  static String getAssessmentText(double probability) {
    if (probability >= 0.7) return 'Excellent aurora conditions!';
    if (probability >= 0.5) return 'Good aurora potential';
    if (probability >= 0.3) return 'Moderate conditions';
    return 'Quiet conditions';
  }
}
