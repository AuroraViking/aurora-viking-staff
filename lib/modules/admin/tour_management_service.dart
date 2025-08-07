import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/models/tour_models.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';

class TourManagementService {
  static const String _baseUrl = 'https://api.bokun.io';
  
  // Get Bokun API credentials from environment
  String get _accessKey => dotenv.env['BOKUN_ACCESS_KEY'] ?? '';
  String get _secretKey => dotenv.env['BOKUN_SECRET_KEY'] ?? '';
  String get _octoToken => dotenv.env['BOKUN_OCTO_TOKEN'] ?? '';
  int get _maxPassengersPerBus => int.tryParse(dotenv.env['MAX_PASSENGERS_PER_BUS'] ?? '19') ?? 19;

  // Check if API credentials are available
  bool get _hasApiCredentials => _accessKey.isNotEmpty && _secretKey.isNotEmpty;
  bool get _hasOctoToken => _octoToken.isNotEmpty;

  // Generate HMAC signature for Bokun API
  String _generateSignature(String date, String body) {
    final key = utf8.encode(_secretKey);
    final message = utf8.encode('$date$body');
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(message);
    return digest.toString();
  }

  // Get current date in Bokun format
  String _getBokunDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  // Get proper headers for Bokun API
  Map<String, String> _getHeaders(String body) {
    final date = _getBokunDate();
    final signature = _generateSignature(date, body);
    
    return {
      'Content-Type': 'application/json',
      'access-key': _accessKey,
      'secret-key': _secretKey,
      'X-Bokun-Date': date,
      'X-Bokun-Signature': signature,
    };
  }

  // Fetch tour data for a specific month
  Future<Map<DateTime, TourDate>> fetchTourDataForMonth(DateTime month) async {
    try {
      if (!_hasApiCredentials) {
        print('❌ Bokun API credentials not found. Using mock data.');
        print('Access Key: ${_accessKey.isEmpty ? "MISSING" : "FOUND"}');
        print('Secret Key: ${_secretKey.isEmpty ? "MISSING" : "FOUND"}');
        return _getMockTourDataForMonth(month);
      }

      print('✅ Bokun API credentials found. Making API request...');
      print('📅 Fetching data for month: ${month.year}-${month.month.toString().padLeft(2, '0')}');

      final startDate = DateTime(month.year, month.month, 1);
      final endDate = DateTime(month.year, month.month + 1, 0);

      final url = '$_baseUrl/booking.json/booking-search';
      print('🌐 API URL: $url');

      final requestBody = {
        'startDateRange': {
          'from': startDate.toUtc().toIso8601String(),
          'to': endDate.toUtc().toIso8601String(),
        }
      };

      final bodyJson = json.encode(requestBody);
      print('📤 Request Body: $bodyJson');

      final response = await http.post(
        Uri.parse(url),
        headers: _getHeaders(bodyJson),
        body: bodyJson,
      );

      print('📡 API Response Status: ${response.statusCode}');
      print('📄 Response Headers: ${response.headers}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ API call successful!');
        print('📊 Raw API response: ${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}...');
        
        final tourData = _parseTourDataFromBookings(data['bookings'] ?? [], month);
        print('🗓️ Parsed ${tourData.length} tour dates');
        return tourData;
      } else {
        print('❌ API Error: ${response.statusCode}');
        print('📄 Error Response: ${response.body}');
        throw Exception('Failed to fetch tour data: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error fetching tour data from Bokun API: $e');
      print('🔄 Falling back to mock data');
      return _getMockTourDataForMonth(month);
    }
  }

  // Parse bookings into tour data grouped by date
  Map<DateTime, TourDate> _parseTourDataFromBookings(List<dynamic> bookings, DateTime month) {
    final tourData = <DateTime, TourDate>{};
    
    // Group bookings by date
    final bookingsByDate = <DateTime, List<Map<String, dynamic>>>{};
    
    for (final booking in bookings) {
      try {
        final pickupInfo = booking['pickupInfo'] ?? {};
        final pickupTime = DateTime.parse(pickupInfo['pickupTime'] ?? DateTime.now().toIso8601String());
        final date = DateTime(pickupTime.year, pickupTime.month, pickupTime.day);
        
        bookingsByDate.putIfAbsent(date, () => []);
        bookingsByDate[date]!.add(booking);
      } catch (e) {
        print('Error parsing booking date: $e');
      }
    }

    // Create TourDate objects for each date
    for (final entry in bookingsByDate.entries) {
      final date = entry.key;
      final dateBookings = entry.value;
      
      final totalBookings = dateBookings.length;
      final totalPassengers = dateBookings.fold<int>(0, (sum, booking) => 
        sum + (booking['numberOfGuests'] as int? ?? 1));

      tourData[date] = TourDate(
        date: date,
        totalBookings: totalBookings,
        totalPassengers: totalPassengers,
        guideApplications: _getMockGuideApplications(date),
        busAssignments: [],
      );
    }

    return tourData;
  }

  // Get guide applications for a specific date (mock data for now)
  List<GuideApplication> _getMockGuideApplications(DateTime date) {
    return [
      GuideApplication(
        guideId: '1',
        guideName: 'John Guide',
        tourType: 'day_tour',
        appliedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      GuideApplication(
        guideId: '2',
        guideName: 'Sarah Guide',
        tourType: 'northern_lights',
        appliedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      GuideApplication(
        guideId: '3',
        guideName: 'Mike Guide',
        tourType: 'day_tour',
        appliedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
    ];
  }

  // Mock tour data for development/testing
  Map<DateTime, TourDate> _getMockTourDataForMonth(DateTime month) {
    final tourData = <DateTime, TourDate>{};
    
    // Generate mock data for the first 15 days of the month
    for (int day = 1; day <= 15; day++) {
      final date = DateTime(month.year, month.month, day);
      final totalBookings = 5 + (day % 10); // Varying number of bookings
      final totalPassengers = totalBookings * 2 + (day % 5); // Varying passenger count
      
      tourData[date] = TourDate(
        date: date,
        totalBookings: totalBookings,
        totalPassengers: totalPassengers,
        guideApplications: _getMockGuideApplications(date),
        busAssignments: _getMockBusAssignments(date),
      );
    }
    
    return tourData;
  }

  // Mock bus assignments for development/testing
  List<BusAssignment> _getMockBusAssignments(DateTime date) {
    return [
      BusAssignment(
        busId: 'bus_1',
        busName: 'Bus 1',
        assignedGuideId: '1',
        assignedGuideName: 'John Guide',
        bookingIds: ['1', '2', '3'],
        totalPassengers: 8,
        tourType: 'day_tour',
      ),
      BusAssignment(
        busId: 'bus_2',
        busName: 'Bus 2',
        assignedGuideId: '2',
        assignedGuideName: 'Sarah Guide',
        bookingIds: ['4', '5'],
        totalPassengers: 6,
        tourType: 'northern_lights',
      ),
    ];
  }

  // Assign guide to bus
  Future<bool> assignGuideToBus(String guideId, String busId, DateTime date) async {
    try {
      // In a real implementation, this would update the backend
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      print('Error assigning guide to bus: $e');
      return false;
    }
  }

  // Create new bus assignment
  Future<bool> createBusAssignment(BusAssignment assignment) async {
    try {
      // In a real implementation, this would update the backend
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      print('Error creating bus assignment: $e');
      return false;
    }
  }

  // Get available buses
  List<String> getAvailableBuses() {
    return [
      'Bus 1',
      'Bus 2',
      'Bus 3',
      'Bus 4',
      'Bus 5',
    ];
  }

  // Get maximum passengers per bus
  int get maxPassengersPerBus => _maxPassengersPerBus;

  // Test API connection
  Future<Map<String, dynamic>> testApiConnection() async {
    try {
      if (!_hasApiCredentials) {
        return {
          'success': false,
          'error': 'API credentials not found',
          'accessKey': _accessKey.isEmpty ? 'MISSING' : 'FOUND',
          'secretKey': _secretKey.isEmpty ? 'MISSING' : 'FOUND',
          'octoToken': _octoToken.isEmpty ? 'MISSING' : 'FOUND',
        };
      }

      print('🧪 Testing Bokun API connection...');
      
      final testDate = DateTime.now();
      final startDate = DateTime(testDate.year, testDate.month, testDate.day);
      final endDate = startDate.add(const Duration(days: 1));

      final url = '$_baseUrl/booking.json/booking-search';
      print('🌐 Test API URL: $url');

      final requestBody = {
        'startDateRange': {
          'from': startDate.toUtc().toIso8601String(),
          'to': endDate.toUtc().toIso8601String(),
        }
      };

      final bodyJson = json.encode(requestBody);
      print('📤 Test Request Body: $bodyJson');

      final response = await http.post(
        Uri.parse(url),
        headers: _getHeaders(bodyJson),
        body: bodyJson,
      );

      print('📡 Test API Response Status: ${response.statusCode}');
      print('📄 Test Response Headers: ${response.headers}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          print('✅ API call successful!');
          return {
            'success': true,
            'statusCode': response.statusCode,
            'workingEndpoint': url,
            'authMethod': 'HMAC Signature',
            'bookingsCount': (data['bookings'] as List<dynamic>?)?.length ?? 0,
            'responsePreview': data.toString().substring(0, data.toString().length > 200 ? 200 : data.toString().length),
          };
        } catch (e) {
          return {
            'success': false,
            'statusCode': response.statusCode,
            'error': 'Failed to parse JSON response: $e',
            'responseBody': response.body,
          };
        }
      } else {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'error': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
} 