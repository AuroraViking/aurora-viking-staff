import 'dart:convert';
import 'package:http/http.dart' as http;

class SubstormAlertService {
  // NOAA Ovation Aurora API URL
  static const String _noaaOvationUrl = 'https://services.swpc.noaa.gov/json/ovation_aurora_latest.json';
  
  // Cache for substorm data
  Map<String, dynamic>? _cachedSubstormStatus;
  DateTime? _lastUpdate;
  static const Duration _cacheTimeout = Duration(minutes: 5);
  
  // Iceland's approximate latitude range for aurora viewing
  static const int _icelandLatMin = 60;
  static const int _icelandLatMax = 70;

  /// Get current substorm status and aurora activity
  Future<Map<String, dynamic>> getSubstormStatus() async {
    // Check if we have recent cached data
    if (_cachedSubstormStatus != null && _lastUpdate != null) {
      final timeSinceUpdate = DateTime.now().difference(_lastUpdate!);
      if (timeSinceUpdate < _cacheTimeout) {
        return _cachedSubstormStatus!;
      }
    }

    try {
      // Try to get real-time data from NOAA Ovation API
      final status = await _fetchNOAAOvationData();
      _cachedSubstormStatus = status;
      _lastUpdate = DateTime.now();
      return status;
    } catch (e) {
      print('Error fetching NOAA Ovation data: $e');
      
      // Fallback to mock data for development
      return _getMockSubstormData();
    }
  }

  /// Fetch real-time data from NOAA Ovation Aurora API
  Future<Map<String, dynamic>> _fetchNOAAOvationData() async {
    try {
      final response = await http.get(
        Uri.parse(_noaaOvationUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        // Parse timestamps
        final observationTimeStr = data['Observation Time'] as String?;
        final forecastTimeStr = data['Forecast Time'] as String?;
        final coordinates = data['coordinates'] as List?;
        
        if (coordinates != null && coordinates.isNotEmpty) {
          // Calculate max aurora intensity for Iceland's latitude range
          int maxIntensity = 0;
          int avgIntensity = 0;
          int count = 0;
          
          for (final coord in coordinates) {
            final lat = coord[1] as int;
            final intensity = coord[2] as int;
            
            // Check if this coordinate is in Iceland's latitude range (Northern Hemisphere)
            if (lat >= _icelandLatMin && lat <= _icelandLatMax) {
              if (intensity > maxIntensity) {
                maxIntensity = intensity;
              }
              avgIntensity += intensity;
              count++;
            }
          }
          
          if (count > 0) {
            avgIntensity = avgIntensity ~/ count;
          }
          
          // Convert intensity (0-100) to AE-equivalent value for compatibility
          // Ovation values: 0-5 low, 5-10 moderate, 10-20 active, 20+ storm
          // Scale to AE-like values for existing UI compatibility
          final aeEquivalent = _intensityToAeEquivalent(maxIntensity);
          
          DateTime? timestamp;
          try {
            if (observationTimeStr != null) {
              timestamp = DateTime.parse(observationTimeStr);
            }
          } catch (_) {
            timestamp = DateTime.now();
          }
          
          return {
            'aeValue': aeEquivalent,
            'maxIntensity': maxIntensity,
            'avgIntensity': avgIntensity,
            'isActive': _isSubstormActive(aeEquivalent),
            'timestamp': timestamp ?? DateTime.now(),
            'forecastTime': forecastTimeStr,
            'source': 'NOAA SWPC Ovation',
          };
        }
      }

      throw Exception('Failed to fetch NOAA Ovation data: ${response.statusCode}');
    } catch (e) {
      print('NOAA Ovation API error: $e');
      rethrow;
    }
  }

  /// Convert Ovation intensity (0-100) to AE-equivalent value for UI compatibility
  int _intensityToAeEquivalent(int intensity) {
    // Ovation intensity scale:
    // 0-2: Very low aurora activity
    // 3-5: Low aurora activity  
    // 6-10: Moderate aurora activity
    // 11-20: Active aurora conditions
    // 21-50: Minor storm conditions
    // 50+: Major storm conditions
    
    // Map to AE-like values for existing description thresholds:
    // < 100: Quiet, 100-200: Unsettled, 200-300: Active, 300-500: Minor storm, 500+: Major
    if (intensity <= 2) {
      return 50 + (intensity * 15); // 50-80
    } else if (intensity <= 5) {
      return 80 + ((intensity - 2) * 20); // 80-140
    } else if (intensity <= 10) {
      return 140 + ((intensity - 5) * 20); // 140-240
    } else if (intensity <= 20) {
      return 240 + ((intensity - 10) * 15); // 240-390
    } else if (intensity <= 50) {
      return 390 + ((intensity - 20) * 5); // 390-540
    } else {
      return 540 + ((intensity - 50) * 3); // 540+
    }
  }

  /// Get mock data for development/testing
  Map<String, dynamic> _getMockSubstormData() {
    // Simulate varying aurora activity
    final now = DateTime.now();
    final hour = now.hour;
    
    // Simulate higher activity during typical aurora hours (evening/night)
    int aeValue;
    bool isActive;
    
    if (hour >= 18 || hour <= 6) {
      // Evening/night hours - higher chance of activity
      aeValue = 200 + (now.minute % 100); // Varying between 200-300
      isActive = aeValue > 250;
    } else {
      // Day hours - lower activity
      aeValue = 50 + (now.minute % 50); // Varying between 50-100
      isActive = false;
    }

    return {
      'aeValue': aeValue,
      'isActive': isActive,
      'timestamp': now,
      'source': 'Mock Data (Development)',
    };
  }

  /// Determine if substorm is active based on AE-equivalent value
  bool _isSubstormActive(int aeValue) {
    // AE Index thresholds:
    // < 100 nT: Quiet
    // 100-200 nT: Unsettled
    // 200-300 nT: Active
    // 300-500 nT: Minor storm
    // > 500 nT: Major storm
    return aeValue >= 200;
  }

  /// Get human-readable description of substorm activity
  String getSubstormDescription(int aeValue) {
    if (aeValue < 100) {
      return 'Quiet conditions - minimal auroral activity expected';
    } else if (aeValue < 200) {
      return 'Unsettled conditions - some auroral activity possible';
    } else if (aeValue < 300) {
      return 'Active conditions - good chance of aurora sightings';
    } else if (aeValue < 500) {
      return 'Minor storm - excellent aurora viewing conditions';
    } else {
      return 'Major storm - spectacular aurora displays likely!';
    }
  }

  /// Get aurora forecast for specific location and time
  Future<Map<String, dynamic>> getLocationForecast({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) async {
    try {
      // This would integrate with location-specific aurora forecast APIs
      // For now, return basic forecast based on current conditions
      final substormStatus = await getSubstormStatus();
      final aeValue = substormStatus['aeValue'] as int;
      
      // Simple forecast logic based on AE Index
      String forecast;
      double probability;
      
      if (aeValue < 100) {
        forecast = 'Low probability of aurora visibility';
        probability = 0.1;
      } else if (aeValue < 200) {
        forecast = 'Moderate chance of aurora sightings';
        probability = 0.3;
      } else if (aeValue < 300) {
        forecast = 'Good conditions for aurora viewing';
        probability = 0.6;
      } else if (aeValue < 500) {
        forecast = 'Excellent aurora viewing conditions';
        probability = 0.8;
      } else {
        forecast = 'Exceptional aurora display likely';
        probability = 0.95;
      }

      return {
        'forecast': forecast,
        'probability': probability,
        'aeIndex': aeValue,
        'date': date,
        'location': {'lat': latitude, 'lng': longitude},
      };
    } catch (e) {
      print('Error getting location forecast: $e');
      return {
        'forecast': 'Unable to load forecast data',
        'probability': 0.0,
        'aeIndex': 0,
        'date': date,
        'location': {'lat': latitude, 'lng': longitude},
      };
    }
  }

  /// Get solar wind parameters (Bz, Bt, etc.)
  Future<Map<String, dynamic>> getSolarWindData() async {
    try {
      // This would fetch real solar wind data from NOAA or other sources
      // For now, return mock data
      return {
        'bz': -2.5, // North-South component
        'bt': 5.0,  // Total magnitude
        'density': 8.0, // Particle density
        'speed': 400.0, // Solar wind speed (km/s)
        'timestamp': DateTime.now(),
      };
    } catch (e) {
      print('Error getting solar wind data: $e');
      return {};
    }
  }

  /// Get cloud cover data for aurora viewing
  Future<Map<String, dynamic>> getCloudCoverData({
    required double latitude,
    required double longitude,
  }) async {
    try {
      // This would integrate with weather APIs for cloud cover
      // For now, return mock data
      return {
        'coverage': 0.3, // 30% cloud cover
        'visibility': 'Good',
        'timestamp': DateTime.now(),
        'location': {'lat': latitude, 'lng': longitude},
      };
    } catch (e) {
      print('Error getting cloud cover data: $e');
      return {};
    }
  }
} 