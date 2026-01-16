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
  // V2 Core fields
  final String action; // STAY or DRIVE
  final String summary; // Normal guide language recommendation
  final String? direction;
  final AuroraDestination? destination;
  final String? navigationUrl;
  final double distanceKm;
  final int travelTimeMinutes;
  
  // Probabilities
  final double auroraProbability;
  final double clearSkyProbability;
  final double viewingProbability;
  
  // Space weather
  final String bzStatus; // STRONG, MODERATE, WEAK, QUIET
  final String bzTrend; // IMPROVING, STABLE, DECLINING
  final double bzHValue;
  final double kpIndex;
  
  // Darkness & Moon
  final Map<String, dynamic>? darkness;
  final Map<String, dynamic>? moon;
  
  // Factors summary
  final Map<String, dynamic>? factors;
  
  // Cloud truth from Stage 1
  final Map<String, dynamic>? cloudTruth;
  
  // Disclaimer
  final String disclaimer;
  
  // Error handling
  final bool hasError;
  final String? errorMessage;
  
  // Metadata
  final DateTime generatedAt;
  
  // Legacy fields (for compatibility)
  final String recommendation;
  final String reasoning;
  final double confidence;
  final String urgency;

  AuroraRecommendation({
    required this.action,
    required this.summary,
    this.direction,
    this.destination,
    this.navigationUrl,
    required this.distanceKm,
    required this.travelTimeMinutes,
    required this.auroraProbability,
    required this.clearSkyProbability,
    required this.viewingProbability,
    required this.bzStatus,
    required this.bzTrend,
    required this.bzHValue,
    required this.kpIndex,
    this.darkness,
    this.moon,
    this.factors,
    this.cloudTruth,
    required this.disclaimer,
    this.hasError = false,
    this.errorMessage,
    required this.generatedAt,
    // Legacy
    required this.recommendation,
    required this.reasoning,
    required this.confidence,
    required this.urgency,
  });


  factory AuroraRecommendation.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse a value that might be string or number
    double parseDouble(dynamic value, [double defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      if (value is String) {
        final lower = value.toLowerCase();
        if (lower == 'high' || lower == 'excellent' || lower == 'strong') return 0.8;
        if (lower == 'medium' || lower == 'moderate') return 0.5;
        if (lower == 'low' || lower == 'poor' || lower == 'weak' || lower == 'quiet') return 0.3;
        return double.tryParse(value) ?? defaultValue;
      }
      return defaultValue;
    }

    final action = json['action']?.toString() ?? 'STAY';
    final summary = json['summary']?.toString() ?? json['recommendation']?.toString() ?? 'Check conditions';
    
    return AuroraRecommendation(
      // V2 fields
      action: action,
      summary: summary,
      direction: json['direction']?.toString(),
      destination: json['destination'] != null ? AuroraDestination.fromJson(json['destination']) : null,
      navigationUrl: json['navigation_url']?.toString(),
      distanceKm: parseDouble(json['distance_km'], 35),
      travelTimeMinutes: (json['travel_time_min'] as num?)?.toInt() ?? (json['travel_time_minutes'] as num?)?.toInt() ?? 30,
      
      // Probabilities
      auroraProbability: parseDouble(json['aurora_probability']),
      clearSkyProbability: parseDouble(json['clear_sky_probability']),
      viewingProbability: parseDouble(json['viewing_probability'], parseDouble(json['combined_viewing_probability'])),
      
      // Space weather
      bzStatus: json['bz_status']?.toString() ?? 'MODERATE',
      bzTrend: json['bz_trend']?.toString() ?? 'STABLE',
      bzHValue: parseDouble(json['bzH_value']),
      kpIndex: parseDouble(json['kp_index'], 2),
      
      // Darkness & Moon
      darkness: json['darkness'] is Map ? Map<String, dynamic>.from(json['darkness']) : null,
      moon: json['moon'] is Map ? Map<String, dynamic>.from(json['moon']) : null,
      
      // Factors
      factors: json['factors'] is Map ? Map<String, dynamic>.from(json['factors']) : null,
      
      // Cloud truth
      cloudTruth: json['cloud_truth'] is Map ? Map<String, dynamic>.from(json['cloud_truth']) : null,
      
      // Disclaimer
      disclaimer: json['disclaimer']?.toString() ?? 'Satellite images can lag. Trust your eyes if conditions look different.',
      
      // Error
      hasError: json['error'] == true,
      errorMessage: json['message']?.toString(),
      
      // Meta
      generatedAt: json['generatedAt'] != null ? DateTime.tryParse(json['generatedAt'].toString()) ?? DateTime.now() : DateTime.now(),
      
      // Legacy compatibility
      recommendation: action == 'STAY' ? summary : 'Drive ${json['direction']} toward ${json['destination']?['name'] ?? 'destination'}',
      reasoning: summary,
      confidence: parseDouble(json['confidence'], 0.7),
      urgency: action == 'DRIVE' ? 'high' : 'medium',
    );
  }



  factory AuroraRecommendation.error(String message) {
    return AuroraRecommendation(
      action: 'STAY',
      summary: message,
      distanceKm: 0,
      travelTimeMinutes: 0,
      auroraProbability: 0,
      clearSkyProbability: 0,
      viewingProbability: 0,
      bzStatus: 'QUIET',
      bzTrend: 'STABLE',
      bzHValue: 0,
      kpIndex: 0,
      disclaimer: 'Unable to analyze conditions.',
      generatedAt: DateTime.now(),
      hasError: true,
      errorMessage: message,
      // Legacy
      recommendation: 'Unable to generate recommendation',
      reasoning: message,
      confidence: 0,
      urgency: 'low',
    );
  }

  String get probabilityLevel {
    if (viewingProbability >= 0.7) return 'excellent';
    if (viewingProbability >= 0.5) return 'good';
    if (viewingProbability >= 0.3) return 'moderate';
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
        debugPrint('   📷 Encoded ${base64Images.length} images');
        debugPrint('   📏 First image size: ${base64Images[0].length} chars');
      } else {
        debugPrint('   ⚠️ No satellite images provided!');
      }

      debugPrint('   🌐 Calling Cloud Function...');
      final callable = _functions.httpsCallable('getAuroraAdvisorRecommendation');
      
      try {
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
        
        debugPrint('   ✅ Cloud Function returned successfully');

        // Recursively convert the response to Map<String, dynamic>
        final Map<String, dynamic> data = _deepConvertMap(result.data);
        debugPrint('   📦 Response data: ${data.keys.toList()}');
        return AuroraRecommendation.fromJson(data);
      } catch (callError) {
        debugPrint('   ❌ Cloud Function call error: $callError');
        debugPrint('   ❌ Error type: ${callError.runtimeType}');
        rethrow;
      }
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

  // ============================================
  // PHOTOGRAPHY DIRECTION TIPS
  // ============================================

  static PhotographyTip getPhotographyDirection(double kp, double bzH) {
    if (kp >= 5 || bzH > 5) {
      return PhotographyTip(
        direction: 'EVERYWHERE',
        icon: '🌌',
        message: 'Point your camera EVERYWHERE tonight! With these conditions, aurora can appear overhead and across the entire sky.',
        cameraSettings: 'ISO 1600, 15-20 sec, f/2.8',
        intensity: 'EXCEPTIONAL',
      );
    } else if (kp >= 4 || bzH > 4) {
      return PhotographyTip(
        direction: 'NORTH + OVERHEAD',
        icon: '📸',
        message: 'Look NORTH and check OVERHEAD - strong aurora expected! The lights may dance right above you.',
        cameraSettings: 'ISO 2000, 20 sec, f/2.8',
        intensity: 'STRONG',
      );
    } else if (kp >= 3 || bzH > 3) {
      return PhotographyTip(
        direction: 'NORTH',
        icon: '📸',
        message: 'Face NORTH for the best view. Aurora will form along the northern horizon.',
        cameraSettings: 'ISO 2500, 25 sec, f/2.8',
        intensity: 'MODERATE',
      );
    } else if (kp >= 2 || bzH > 2) {
      return PhotographyTip(
        direction: 'LOW NORTH',
        icon: '📸',
        message: 'Watch LOW on the northern horizon. Faint aurora may appear - your camera will see more than your eyes!',
        cameraSettings: 'ISO 3200, 30 sec, f/2.8',
        intensity: 'FAINT',
      );
    }
    
    return PhotographyTip(
      direction: 'NORTH',
      icon: '📷',
      message: 'Keep watching NORTH - conditions may improve. Set up your camera and be patient.',
      cameraSettings: 'ISO 3200, 30 sec, f/2.8',
      intensity: 'QUIET',
    );
  }

  // ============================================
  // AURORA HUNTING TIPS
  // ============================================

  static List<String> getAuroraHuntingTips({
    required double cloudCover,
    required double auroraActivity, // 1-5 scale based on Kp/BzH
  }) {
    final tips = <String>[];

    // Cloudy / waiting tips
    if (cloudCover > 60) {
      tips.add("☁️ Cloudy skies - but clouds move! Check satellite imagery for gaps and be ready to chase clear skies");
      tips.add("⏰ Patience pays off - some of the best aurora moments come after waiting through clouds");
    }

    // Activity-based tips
    if (auroraActivity >= 4) {
      tips.add("🎉 Conditions are GREAT tonight! Get out there and enjoy the show!");
      tips.add("📸 Take test shots - your camera sees aurora before your eyes do");
      tips.add("👀 Look UP! Strong aurora can appear directly overhead");
    } else if (auroraActivity >= 3) {
      tips.add("📸 Good conditions! Set your camera to take test shots - it'll see faint aurora before you do");
      tips.add("🌌 Face north and give your eyes 15-20 minutes to adjust to the dark");
    } else if (auroraActivity >= 2) {
      tips.add("⏳ Moderate chance tonight - worth going out! Be patient and let your eyes adjust");
      tips.add("📱 Keep checking conditions - they can change quickly");
    } else {
      tips.add("🔮 Quiet conditions, but aurora can surprise us! If skies are clear, it's always worth a look");
    }

    // General tips
    tips.add("📵 Turn off your phone screen brightness or use red mode - protect your night vision!");
    tips.add("🔦 Use a red flashlight if you need light - white light ruins everyone's night vision");

    return tips;
  }

  /// Calculate aurora activity level (1-5) from Kp and BzH
  static double calculateAuroraActivity(double kp, double bzH) {
    if (bzH > 6 || kp >= 6) return 5;
    if (bzH > 4.5 || kp >= 4) return 4;
    if (bzH > 3 || kp >= 3) return 3;
    if (bzH > 1.5 || kp >= 2) return 2;
    return 1;
  }

  /// Get aurora chance text from activity level
  static String getAuroraChanceText(double activity) {
    if (activity >= 5) return "EXCEPTIONAL - Don't miss this!";
    if (activity >= 4) return "HIGH - Great night for aurora!";
    if (activity >= 3) return "GOOD - Worth going out";
    if (activity >= 2) return "MODERATE - Possible sightings";
    return "LOW - But always worth checking";
  }
}

// ============================================
// PHOTOGRAPHY TIP MODEL
// ============================================

class PhotographyTip {
  final String direction;
  final String icon;
  final String message;
  final String cameraSettings;
  final String intensity;

  PhotographyTip({
    required this.direction,
    required this.icon,
    required this.message,
    required this.cameraSettings,
    required this.intensity,
  });
}

// ============================================
// SAFETY WARNING MODELS
// ============================================

enum WarningLevel { caution, warning, danger }

class SafetyWarning {
  final WarningLevel level;
  final String icon;
  final String title;
  final String message;
  final int colorValue; // Store color as int for simplicity

  SafetyWarning({
    required this.level,
    required this.icon,
    required this.title,
    required this.message,
    required this.colorValue,
  });

  /// Generate safety warnings based on weather conditions
  /// windSpeed in m/s, temperature in °C
  static List<SafetyWarning> generateWarnings({
    required double windSpeed,
    required double temperature,
  }) {
    final warnings = <SafetyWarning>[];

    // Wind warnings (thresholds in m/s for Iceland)
    if (windSpeed >= 30) {
      warnings.add(SafetyWarning(
        level: WarningLevel.danger,
        icon: '🚨',
        title: 'EXTREME WIND',
        message: 'Wind speeds of ${windSpeed.toStringAsFixed(0)} m/s are dangerous. Stay indoors tonight - the aurora will be back!',
        colorValue: 0xFFF44336, // Red
      ));
    } else if (windSpeed >= 25) {
      warnings.add(SafetyWarning(
        level: WarningLevel.danger,
        icon: '⚠️',
        title: 'DANGEROUS WIND',
        message: '${windSpeed.toStringAsFixed(0)} m/s winds can blow you off your feet. Consider staying in tonight.',
        colorValue: 0xFFF44336, // Red
      ));
    } else if (windSpeed >= 20) {
      warnings.add(SafetyWarning(
        level: WarningLevel.warning,
        icon: '💨',
        title: 'STRONG WIND',
        message: '${windSpeed.toStringAsFixed(0)} m/s gusts expected. Hold onto your tripod and hat! Drive carefully.',
        colorValue: 0xFFFF9800, // Orange
      ));
    } else if (windSpeed >= 15) {
      warnings.add(SafetyWarning(
        level: WarningLevel.caution,
        icon: '🌬️',
        title: 'Breezy Conditions',
        message: 'Wind at ${windSpeed.toStringAsFixed(0)} m/s. Secure your tripod and bring an extra layer.',
        colorValue: 0xFFFFC107, // Amber
      ));
    }

    // Temperature / Ice warnings (thresholds in °C)
    if (temperature <= -10) {
      warnings.add(SafetyWarning(
        level: WarningLevel.danger,
        icon: '🥶',
        title: 'EXTREME COLD',
        message: '${temperature.toStringAsFixed(0)}°C is dangerously cold. Limit time outside to 20-30 minutes and warm up in your car.',
        colorValue: 0xFFF44336, // Red
      ));
    } else if (temperature <= -5) {
      warnings.add(SafetyWarning(
        level: WarningLevel.warning,
        icon: '❄️',
        title: 'VERY COLD',
        message: '${temperature.toStringAsFixed(0)}°C - Bundle up! Bring hand warmers and take breaks to warm up.',
        colorValue: 0xFF2196F3, // Blue
      ));
    } else if (temperature <= 0) {
      warnings.add(SafetyWarning(
        level: WarningLevel.warning,
        icon: '🧊',
        title: 'ICY ROADS',
        message: '${temperature.toStringAsFixed(0)}°C means icy roads. Drive slowly and brake early.',
        colorValue: 0xFFFF9800, // Orange
      ));
    } else if (temperature <= 5) {
      warnings.add(SafetyWarning(
        level: WarningLevel.caution,
        icon: '🌡️',
        title: 'Chilly Night',
        message: '${temperature.toStringAsFixed(0)}°C - Dress warmer than you think! Standing still gets cold fast.',
        colorValue: 0xFF64B5F6, // Light blue
      ));
    }

    return warnings;
  }
}

