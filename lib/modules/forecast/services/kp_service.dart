import 'dart:convert';
import 'package:http/http.dart' as http;

class KpService {
  static const _kpUrl =
      'https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json';

  static Future<double> fetchCurrentKp() async {
    try {
      final response = await http.get(Uri.parse(_kpUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final latest = data.last;
        
        // Convert to double and handle any potential integer values
        final kpValue = latest[1];
        if (kpValue is int) {
          return kpValue.toDouble();
        }
        return double.tryParse(kpValue.toString()) ?? 0.0;
      } else {
        throw Exception('Failed to load Kp index');
      }
    } catch (e) {
      print('Error fetching Kp index: $e');
      return 0.0;
    }
  }
} 