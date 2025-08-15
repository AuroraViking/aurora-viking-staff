import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

class SunriseSunsetService {
  static const String _baseUrl = 'https://api.sunrise-sunset.org/json';

  Future<Map<String, dynamic>> getSunData(Position position) async {
    final url = '$_baseUrl?lat=${position.latitude}&lng=${position.longitude}&formatted=0';
    
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        final results = data['results'];
        return {
          'sunrise': _formatTime(results['sunrise']),
          'sunset': _formatTime(results['sunset']),
          'astronomicalTwilightStart': _formatTime(results['astronomical_twilight_begin']),
          'astronomicalTwilightEnd': _formatTime(results['astronomical_twilight_end']),
          'dayLength': _formatDuration(results['day_length']),
        };
      } else {
        throw Exception('API returned error: ${data['status']}');
      }
    } else {
      throw Exception('Failed to load sun data: ${response.statusCode}');
    }
  }

  String _formatTime(String isoTime) {
    final date = DateTime.parse(isoTime);
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    return '$hours hours $minutes minutes';
  }
} 