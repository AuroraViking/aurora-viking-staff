import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config_service.dart';

class CloudForecastService {
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  static Future<Map<String, dynamic>> getCloudCoverForecast(
    double lat, 
    double lon,
  ) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/forecast?lat=$lat&lon=$lon&appid=${ConfigService.weatherApiKey}&units=metric'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parseCloudData(data);
      } else {
        throw Exception('Failed to load cloud forecast: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching cloud forecast: $e');
    }
  }

  static Map<String, dynamic> _parseCloudData(Map<String, dynamic> data) {
    final List<dynamic> list = data['list'] ?? [];
    final cloudData = <String, dynamic>{};
    
    for (final item in list) {
      final dt = item['dt'] as int;
      final clouds = item['clouds']?['all'] ?? 0;
      final weather = item['weather']?[0] ?? {};
      
      cloudData[dt.toString()] = {
        'cloudCover': clouds,
        'description': weather['description'] ?? '',
        'icon': weather['icon'] ?? '',
        'timestamp': dt,
      };
    }
    
    return cloudData;
  }
} 