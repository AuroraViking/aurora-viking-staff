import 'dart:convert';
import 'package:http/http.dart' as http;

class SubstormAlertService {
  // Base URLs for aurora forecast APIs
  static const String _noaaApiUrl = 'https://services.swpc.noaa.gov/json/';
  static const String _spaceWeatherUrl = 'https://api.spaceweather.com/';
  
  // Cache for substorm data
  Map<String, dynamic>? _cachedSubstormStatus;
  DateTime? _lastUpdate;
  static const Duration _cacheTimeout = Duration(minutes: 5);

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
      // Try to get real-time data from NOAA
      final status = await _fetchNOAAData();
      _cachedSubstormStatus = status;
      _lastUpdate = DateTime.now();
      return status;
    } catch (e) {
      print('Error fetching NOAA data: $e');
      
      // Fallback to mock data for development
      return _getMockSubstormData();
    }
  }

  /// Fetch real-time data from NOAA Space Weather Prediction Center
  Future<Map<String, dynamic>> _fetchNOAAData() async {
    try {
      // Get AE Index (Auroral Electrojet Index)
      final aeResponse = await http.get(
        Uri.parse('${_noaaApiUrl}ae_pro_1h.json'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (aeResponse.statusCode == 200) {
        final aeData = json.decode(aeResponse.body) as List;
        if (aeData.isNotEmpty) {
          final latestAE = aeData.last['ae_index'] as int? ?? 0;
          final timestamp = DateTime.parse(aeData.last['time_tag'] as String);
          
          return {
            'aeValue': latestAE,
            'isActive': _isSubstormActive(latestAE),
            'timestamp': timestamp,
            'source': 'NOAA SWPC',
          };
        }
      }

      // If NOAA fails, try alternative sources
      return await _fetchAlternativeData();
    } catch (e) {
      print('NOAA API error: $e');
      rethrow;
    }
  }

  /// Fetch data from alternative sources
  Future<Map<String, dynamic>> _fetchAlternativeData() async {
    try {
      // This could be expanded with other aurora forecast APIs
      // For now, return mock data
      return _getMockSubstormData();
    } catch (e) {
      print('Alternative API error: $e');
      return _getMockSubstormData();
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

  /// Determine if substorm is active based on AE Index
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