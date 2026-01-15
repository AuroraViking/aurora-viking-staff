import 'package:http/http.dart' as http;

/// Data model for a single hemispheric power reading
class HemisphericPowerReading {
  final DateTime observationTime;
  final DateTime forecastTime;
  final int northPower; // Gigawatts
  final int southPower; // Gigawatts

  HemisphericPowerReading({
    required this.observationTime,
    required this.forecastTime,
    required this.northPower,
    required this.southPower,
  });

  /// Get the activity level based on power value
  static String getActivityLevel(int power) {
    if (power < 20) return 'Quiet';
    if (power < 50) return 'Moderate';
    if (power < 100) return 'Active';
    return 'Storm';
  }
}

/// Service to fetch hemispheric power data from NOAA SWPC
class HemisphericPowerService {
  static const String _noaaHemiPowerUrl = 
      'https://services.swpc.noaa.gov/text/aurora-nowcast-hemi-power.txt';

  // Cache management
  List<HemisphericPowerReading>? _cachedData;
  DateTime? _lastFetch;
  static const Duration _cacheTimeout = Duration(minutes: 2);

  /// Fetch hemispheric power data from NOAA
  /// Returns a list of readings sorted by observation time (oldest first)
  Future<List<HemisphericPowerReading>> fetchHemisphericPowerData() async {
    // Return cached data if still valid
    if (_cachedData != null && _lastFetch != null) {
      final timeSinceUpdate = DateTime.now().difference(_lastFetch!);
      if (timeSinceUpdate < _cacheTimeout) {
        return _cachedData!;
      }
    }

    try {
      final response = await http.get(
        Uri.parse(_noaaHemiPowerUrl),
        headers: {'Accept': 'text/plain'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _parseHemiPowerData(response.body);
        _cachedData = data;
        _lastFetch = DateTime.now();
        return data;
      }

      throw Exception('Failed to fetch data: ${response.statusCode}');
    } catch (e) {
      print('⚠️ HemisphericPowerService error: $e');
      // Return cached data if available, even if stale
      if (_cachedData != null) {
        return _cachedData!;
      }
      rethrow;
    }
  }

  /// Parse the NOAA text format into structured data
  /// Format: observation_time  forecast_time  north_power  south_power
  /// Example: 2026-01-15_14:00    2026-01-15_14:40      15      14
  List<HemisphericPowerReading> _parseHemiPowerData(String rawData) {
    final readings = <HemisphericPowerReading>[];
    final lines = rawData.split('\n');

    for (final line in lines) {
      // Skip header lines and empty lines
      if (line.trim().isEmpty || 
          line.startsWith('#') || 
          line.startsWith('-') ||
          line.contains('Observation') ||
          line.contains('Forecast')) {
        continue;
      }

      try {
        // Split by whitespace and filter empty strings
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final observationTime = _parseDateTime(parts[0]);
          final forecastTime = _parseDateTime(parts[1]);
          final northPower = int.parse(parts[2]);
          final southPower = int.parse(parts[3]);

          if (observationTime != null && forecastTime != null) {
            readings.add(HemisphericPowerReading(
              observationTime: observationTime,
              forecastTime: forecastTime,
              northPower: northPower,
              southPower: southPower,
            ));
          }
        }
      } catch (e) {
        // Skip malformed lines
        continue;
      }
    }

    // Sort by observation time (oldest first for chart display)
    readings.sort((a, b) => a.observationTime.compareTo(b.observationTime));
    
    return readings;
  }

  /// Parse NOAA datetime format: 2026-01-15_14:00
  DateTime? _parseDateTime(String dateStr) {
    try {
      // Replace underscore with space and parse
      final normalized = dateStr.replaceAll('_', 'T');
      return DateTime.parse(normalized);
    } catch (e) {
      return null;
    }
  }

  /// Get the latest reading
  Future<HemisphericPowerReading?> getLatestReading() async {
    final data = await fetchHemisphericPowerData();
    return data.isNotEmpty ? data.last : null;
  }

  /// Clear the cache
  void clearCache() {
    _cachedData = null;
    _lastFetch = null;
  }
}
