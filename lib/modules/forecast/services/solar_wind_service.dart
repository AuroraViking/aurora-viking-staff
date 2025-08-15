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

  BzHistory({
    required this.bzValues, 
    required this.times,
    required this.btValues,
  });
}

class SolarWindService {
  static const _plasmaUrl =
      'https://services.swpc.noaa.gov/products/solar-wind/plasma-2-hour.json';
  static const _magneticUrl =
      'https://services.swpc.noaa.gov/products/solar-wind/mag-2-hour.json';

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
      } else {
        throw Exception('Failed to load solar wind data');
      }
    } catch (e) {
      print('Error fetching solar wind data: $e');
      return SolarWindData(speed: 0, density: 0, bt: 0);
    }
  }

  static Future<BzHistory> fetchBzHistory() async {
    try {
      final response = await http.get(Uri.parse(_magneticUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final rows = data.skip(1).where((row) => 
          double.tryParse(row[1].toString()) != null && 
          double.tryParse(row[2].toString()) != null &&
          double.tryParse(row[3].toString()) != null
        );
        
        final times = rows.map((r) => r[0].toString().substring(11, 16)).toList();
        final bzValues = rows.map((r) => double.parse(r[3].toString())).toList();
        
        // Calculate Bt values using vector magnitude
        final btValues = rows.map((r) {
          final bx = double.parse(r[1].toString());
          final by = double.parse(r[2].toString());
          final bz = double.parse(r[3].toString());
          return sqrt(bx * bx + by * by + bz * bz);
        }).toList();

        return BzHistory(
          bzValues: bzValues, 
          times: times,
          btValues: btValues,
        );
      }
      throw Exception('Failed to load Bz history');
    } catch (e) {
      print('Error fetching Bz history: $e');
      return BzHistory(bzValues: [], times: [], btValues: []);
    }
  }
} 