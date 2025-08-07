import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';

class PickupService {
  static const String _baseUrl = 'https://api.bokun.io';
  
  // Get Bokun API credentials from environment
  String get _accessKey => dotenv.env['BOKUN_ACCESS_KEY'] ?? '';
  String get _secretKey => dotenv.env['BOKUN_SECRET_KEY'] ?? '';
  int get _maxPassengersPerBus => int.tryParse(dotenv.env['MAX_PASSENGERS_PER_BUS'] ?? '19') ?? 19;

  // Check if API credentials are available
  bool get _hasApiCredentials => _accessKey.isNotEmpty && _secretKey.isNotEmpty;

  // Generate HMAC signature for Bokun API (correct format)
  String _generateSignature(String date, String accessKey, String method, String path) {
    // Concatenate: date + accessKey + method + path
    final message = date + accessKey + method + path;
    
    // Create HMAC-SHA1 signature
    final key = utf8.encode(_secretKey);
    final bytes = utf8.encode(message);
    final hmacSha1 = Hmac(sha1, key);
    final digest = hmacSha1.convert(bytes);
    
    // Base64 encode the result
    final signature = base64.encode(digest.bytes);
    
    print('🔐 Pickup HMAC Debug (Correct Format):');
    print('  Date: $date');
    print('  AccessKey: $accessKey');
    print('  Method: $method');
    print('  Path: $path');
    print('  Message: $message');
    print('  Signature: $signature');
    
    return signature;
  }

  // Get current date in Bokun format
  String _getBokunDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  // Get proper headers for Bokun API
  Map<String, String> _getHeaders(String body) {
    final date = _getBokunDate();
    final signature = _generateSignature(date, _accessKey, 'POST', '/booking.json/booking-search');
    
    return {
      'Content-Type': 'application/json',
      'X-Bokun-AccessKey': _accessKey,
      'X-Bokun-Date': date,
      'X-Bokun-Signature': signature,
    };
  }

  // Fetch bookings from Bokun API for a specific date
  Future<List<PickupBooking>> fetchBookingsForDate(DateTime date) async {
    try {
      // Check if API credentials are available
      if (!_hasApiCredentials) {
        print('❌ Pickup Service: Bokun API credentials not found in .env file. Using mock data.');
        print('Access Key: ${_accessKey.isEmpty ? "MISSING" : "FOUND"}');
        print('Secret Key: ${_secretKey.isEmpty ? "MISSING" : "FOUND"}');
        return _getMockBookings(date);
      }

      print('✅ Pickup Service: Bokun API credentials found. Making API request...');
      print('📅 Fetching bookings for date: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');

      final startDate = DateTime(date.year, date.month, date.day);
      final endDate = startDate.add(const Duration(days: 1));

      final url = '$_baseUrl/booking.json/booking-search';
      print('🌐 Pickup API URL: $url');

      final requestBody = {
        'startDateRange': {
          'from': startDate.toUtc().toIso8601String(),
          'to': endDate.toUtc().toIso8601String(),
        }
      };

      final bodyJson = json.encode(requestBody);
      print('📤 Pickup Request Body: $bodyJson');

      final response = await http.post(
        Uri.parse(url),
        headers: _getHeaders(bodyJson),
        body: bodyJson,
      );

      print('📡 Pickup API Response Status: ${response.statusCode}');
      print('📄 Pickup Response Headers: ${response.headers}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Pickup API call successful!');
        print('📊 Pickup Raw API response: ${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}...');
        
        final bookings = <PickupBooking>[];
        
        // Parse Bokun API response and convert to our model
        for (final booking in data['bookings'] ?? []) {
          try {
            final pickupBooking = _parseBokunBooking(booking);
            if (pickupBooking != null) {
              bookings.add(pickupBooking);
            }
          } catch (e) {
            print('Error parsing booking: $e');
          }
        }
        
        print('📋 Pickup Service: Parsed ${bookings.length} bookings');
        
        // If no bookings found for current date, try September 1st as a test
        if (bookings.isEmpty && date.day != 1 && date.month != 9) {
          print('🔄 No bookings found for current date, testing with September 1st, 2025...');
          return await fetchBookingsForDate(DateTime(2025, 9, 1));
        }
        
        return bookings;
      } else {
        print('❌ Pickup API Error: ${response.statusCode}');
        print('📄 Pickup Error Response: ${response.body}');
        throw Exception('Failed to fetch bookings: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Pickup Service: Error fetching bookings from Bokun API: $e');
      print('🔄 Pickup Service: Falling back to mock data for development/testing');
      // Return mock data for development/testing
      return _getMockBookings(date);
    }
  }

  // Parse Bokun API booking data
  PickupBooking? _parseBokunBooking(Map<String, dynamic> booking) {
    try {
      // Extract customer information
      final customer = booking['customer'] ?? {};
      final customerFullName = '${customer['firstName'] ?? ''} ${customer['lastName'] ?? ''}'.trim();
      
      // Extract pickup information
      final pickupInfo = booking['pickupInfo'] ?? {};
      final pickupPlaceName = pickupInfo['pickupPlaceName'] ?? 'Unknown Location';
      final pickupTime = DateTime.parse(pickupInfo['pickupTime'] ?? DateTime.now().toIso8601String());
      
      // Extract guest count
      final numberOfGuests = booking['numberOfGuests'] ?? 1;
      
      // Extract contact information
      final phoneNumber = customer['phoneNumber'] ?? '';
      final email = customer['email'] ?? '';

      return PickupBooking(
        id: booking['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        customerFullName: customerFullName,
        pickupPlaceName: pickupPlaceName,
        pickupTime: pickupTime,
        numberOfGuests: numberOfGuests,
        phoneNumber: phoneNumber,
        email: email,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print('Error parsing Bokun booking: $e');
      return null;
    }
  }

  // Mock data for development/testing
  List<PickupBooking> _getMockBookings(DateTime date) {
    return [
      PickupBooking(
        id: '1',
        customerFullName: 'John Smith',
        pickupPlaceName: 'Hotel Keflavik',
        pickupTime: DateTime(date.year, date.month, date.day, 8, 30),
        numberOfGuests: 2,
        phoneNumber: '+354 123 4567',
        email: 'john.smith@email.com',
        createdAt: DateTime.now(),
      ),
      PickupBooking(
        id: '2',
        customerFullName: 'Maria Garcia',
        pickupPlaceName: 'Reykjavik Downtown Hostel',
        pickupTime: DateTime(date.year, date.month, date.day, 9, 0),
        numberOfGuests: 4,
        phoneNumber: '+354 234 5678',
        email: 'maria.garcia@email.com',
        createdAt: DateTime.now(),
      ),
      PickupBooking(
        id: '3',
        customerFullName: 'David Johnson',
        pickupPlaceName: 'Blue Lagoon Hotel',
        pickupTime: DateTime(date.year, date.month, date.day, 8, 45),
        numberOfGuests: 3,
        phoneNumber: '+354 345 6789',
        email: 'david.johnson@email.com',
        createdAt: DateTime.now(),
      ),
      PickupBooking(
        id: '4',
        customerFullName: 'Sarah Wilson',
        pickupPlaceName: 'Icelandair Hotel Reykjavik Marina',
        pickupTime: DateTime(date.year, date.month, date.day, 9, 15),
        numberOfGuests: 2,
        phoneNumber: '+354 456 7890',
        email: 'sarah.wilson@email.com',
        createdAt: DateTime.now(),
      ),
      PickupBooking(
        id: '5',
        customerFullName: 'Michael Brown',
        pickupPlaceName: 'CenterHotel Arnarhvoll',
        pickupTime: DateTime(date.year, date.month, date.day, 8, 0),
        numberOfGuests: 6,
        phoneNumber: '+354 567 8901',
        email: 'michael.brown@email.com',
        createdAt: DateTime.now(),
      ),
    ];
  }

  // Assign booking to a guide
  Future<bool> assignBookingToGuide(String bookingId, String guideId, String guideName) async {
    try {
      // In a real implementation, this would update the backend
      // For now, we'll just return success
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      print('Error assigning booking: $e');
      return false;
    }
  }

  // Mark booking as no-show
  Future<bool> markBookingAsNoShow(String bookingId) async {
    try {
      // In a real implementation, this would update the backend
      // For now, we'll just return success
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      print('Error marking booking as no-show: $e');
      return false;
    }
  }

  // Get pickup list for a specific guide
  Future<GuidePickupList?> getGuidePickupList(String guideId, DateTime date) async {
    try {
      final bookings = await fetchBookingsForDate(date);
      final guideBookings = bookings.where((booking) => booking.assignedGuideId == guideId).toList();
      final totalPassengers = guideBookings.fold(0, (sum, booking) => sum + booking.numberOfGuests);

      // Mock guide name - in real app, get from user service
      final guideName = 'Guide $guideId';

      return GuidePickupList(
        guideId: guideId,
        guideName: guideName,
        bookings: guideBookings,
        totalPassengers: totalPassengers,
        date: date,
      );
    } catch (e) {
      print('Error getting guide pickup list: $e');
      return null;
    }
  }

  // Distribute bookings among guides
  Future<List<GuidePickupList>> distributeBookings(
    List<PickupBooking> bookings,
    List<User> guides,
    DateTime date,
  ) async {
    final guideLists = <GuidePickupList>[];
    final unassignedBookings = List<PickupBooking>.from(bookings);
    
    // Create empty lists for each guide
    for (final guide in guides) {
      guideLists.add(GuidePickupList(
        guideId: guide.id,
        guideName: guide.fullName,
        bookings: [],
        totalPassengers: 0,
        date: date,
      ));
    }

    // Simple distribution algorithm
    int guideIndex = 0;
    for (final booking in unassignedBookings) {
      if (guideLists.isEmpty) break;
      
      final currentGuideList = guideLists[guideIndex % guideLists.length];
      final newTotalPassengers = currentGuideList.totalPassengers + booking.numberOfGuests;
      
      // Check if adding this booking would exceed passenger limit
      if (newTotalPassengers <= _maxPassengersPerBus) {
        // Add booking to this guide
        final updatedBookings = List<PickupBooking>.from(currentGuideList.bookings)
          ..add(booking.copyWith(
            assignedGuideId: currentGuideList.guideId,
            assignedGuideName: currentGuideList.guideName,
          ));
        
        guideLists[guideIndex % guideLists.length] = currentGuideList.copyWith(
          bookings: updatedBookings,
          totalPassengers: newTotalPassengers,
        );
      }
      
      guideIndex++;
    }

    return guideLists;
  }

  // Get pickup list statistics
  Future<PickupListStats> getPickupListStats(DateTime date) async {
    try {
      final bookings = await fetchBookingsForDate(date);
      final guideLists = <GuidePickupList>[];
      
      // Group bookings by assigned guide
      final guideGroups = <String, List<PickupBooking>>{};
      for (final booking in bookings) {
        if (booking.assignedGuideId != null) {
          guideGroups.putIfAbsent(booking.assignedGuideId!, () => []);
          guideGroups[booking.assignedGuideId]!.add(booking);
        }
      }

      // Create guide lists
      for (final entry in guideGroups.entries) {
        final totalPassengers = entry.value.fold(0, (sum, booking) => sum + booking.numberOfGuests);
        guideLists.add(GuidePickupList(
          guideId: entry.key,
          guideName: entry.value.first.assignedGuideName ?? 'Unknown Guide',
          bookings: entry.value,
          totalPassengers: totalPassengers,
          date: date,
        ));
      }

      return PickupListStats.fromBookings(bookings, guideLists);
    } catch (e) {
      print('Error getting pickup list stats: $e');
      return PickupListStats(
        totalBookings: 0,
        totalPassengers: 0,
        assignedBookings: 0,
        unassignedBookings: 0,
        noShows: 0,
        guideLists: [],
      );
    }
  }

  // Validate passenger count for a guide
  bool validatePassengerCount(int currentCount, int additionalPassengers) {
    return (currentCount + additionalPassengers) <= _maxPassengersPerBus;
  }

  // Get maximum passengers per bus
  int get maxPassengersPerBus => _maxPassengersPerBus;
} 