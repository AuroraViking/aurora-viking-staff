import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';

class SolarWindData {
  final double speed;
  final double density;
  final double bt;

  SolarWindData({
    required this.speed, 
    required this.density,
    required this.bt,
  });
}

class BzHistory {
  final List<double> bzValues;
  final List<String> times;
  final List<double> btValues;
  final List<double> speedValues;
  final List<double> densityValues;

  BzHistory({
    required this.bzValues, 
    required this.times,
    required this.btValues,
    required this.speedValues,
    required this.densityValues,
  });
}

class SolarWindService {
  static const _plasmaUrl =
      'https://services.swpc.noaa.gov/products/solar-wind/plasma-2-hour.json';
  static const _magneticUrl =
      'https://services.swpc.noaa.gov/products/solar-wind/mag-2-hour.json';

  /// Cache of the last successful BzHistory so transient API failures
  /// don't wipe out the chart data.
  static BzHistory? _cachedHistory;

  static Future<SolarWindData> fetchData() async {
    try {
      final plasmaRes = await http.get(Uri.parse(_plasmaUrl));
      final magneticRes = await http.get(Uri.parse(_magneticUrl));

      if (plasmaRes.statusCode == 200 && magneticRes.statusCode == 200) {
        final plasma = jsonDecode(plasmaRes.body) as List<dynamic>;
        final magnetic = jsonDecode(magneticRes.body) as List<dynamic>;
        
        final latestPlasma = plasma.last;
        final latestMagnetic = magnetic.last;

        final speed = double.tryParse(latestPlasma[2].toString()) ?? 0;
        final density = double.tryParse(latestPlasma[1].toString()) ?? 0;
        
        // Calculate Bt using vector magnitude
        final bx = double.tryParse(latestMagnetic[1].toString()) ?? 0;
        final by = double.tryParse(latestMagnetic[2].toString()) ?? 0;
        final bz = double.tryParse(latestMagnetic[3].toString()) ?? 0;
        final bt = sqrt(bx * bx + by * by + bz * bz);

        return SolarWindData(speed: speed, density: density, bt: bt);
      }
      throw Exception('Failed to load solar wind data');
    } catch (e) {
      print('Error fetching solar wind data: $e');
      return SolarWindData(speed: 0, density: 0, bt: 0);
    }
  }

  /// Fetch complete 2-hour history including speed and density trends.
  /// Returns cached data on failure so the chart never disappears.
  static Future<BzHistory> fetchBzHistory() async {
    // Try up to 2 attempts (initial + 1 retry)
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(const Duration(seconds: 2));
          print('🔄 Retrying Bz history fetch (attempt ${attempt + 1})...');
        }

        final plasmaRes = await http.get(Uri.parse(_plasmaUrl))
            .timeout(const Duration(seconds: 10));
        final magneticRes = await http.get(Uri.parse(_magneticUrl))
            .timeout(const Duration(seconds: 10));

        if (plasmaRes.statusCode != 200 || magneticRes.statusCode != 200) {
          throw Exception('Failed to load data (status: ${plasmaRes.statusCode}/${magneticRes.statusCode})');
        }

        final plasma = jsonDecode(plasmaRes.body) as List<dynamic>;
        final magnetic = jsonDecode(magneticRes.body) as List<dynamic>;

        // Skip header row
        final plasmaData = plasma.skip(1).toList();
        final magneticData = magnetic.skip(1).toList();

        // Create maps keyed by timestamp for alignment
        final plasmaMap = <String, Map<String, double>>{};
        for (final row in plasmaData) {
          final timestamp = row[0].toString();
          final density = double.tryParse(row[1].toString());
          final speed = double.tryParse(row[2].toString());
          if (density != null && speed != null) {
            plasmaMap[timestamp] = {
              'density': density,
              'speed': speed,
            };
          }
        }

        final List<double> bzValues = [];
        final List<double> btValues = [];
        final List<double> speedValues = [];
        final List<double> densityValues = [];
        final List<String> times = [];

        for (final row in magneticData) {
          final timestamp = row[0].toString();
          final bx = double.tryParse(row[1].toString());
          final by = double.tryParse(row[2].toString());
          final bz = double.tryParse(row[3].toString());
          
          // Skip rows with invalid magnetic data
          if (bx == null || by == null || bz == null) continue;
          
          final bt = sqrt(bx * bx + by * by + bz * bz);

          bzValues.add(bz);
          btValues.add(bt);
          times.add(timestamp);

          // Get matching plasma data or use last known value
          if (plasmaMap.containsKey(timestamp)) {
            speedValues.add(plasmaMap[timestamp]!['speed']!);
            densityValues.add(plasmaMap[timestamp]!['density']!);
          } else {
            // Use last known value for interpolation
            speedValues.add(speedValues.isNotEmpty ? speedValues.last : 400);
            densityValues.add(densityValues.isNotEmpty ? densityValues.last : 5);
          }
        }

        final result = BzHistory(
          bzValues: bzValues,
          times: times,
          btValues: btValues,
          speedValues: speedValues,
          densityValues: densityValues,
        );

        // Only cache if we got real data
        if (bzValues.isNotEmpty) {
          _cachedHistory = result;
        }

        return result;
      } catch (e) {
        print('⚠️ Bz history fetch failed (attempt ${attempt + 1}): $e');
        // Continue to retry on first attempt
      }
    }

    // All attempts failed — return cached data if available
    if (_cachedHistory != null) {
      print('📦 Using cached Bz history (${_cachedHistory!.bzValues.length} points)');
      return _cachedHistory!;
    }

    // No cache available either — return empty as last resort
    print('❌ No cached Bz history available, returning empty');
    return BzHistory(
      bzValues: [],
      times: [],
      btValues: [],
      speedValues: [],
      densityValues: [],
    );
  }
}