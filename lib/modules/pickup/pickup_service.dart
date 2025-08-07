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
  Map<String, String> _getHeaders(String body, {DateTime? requestDate}) {
    // Use the request date if provided, otherwise use current time
    final dateToUse = requestDate ?? DateTime.now();
    final date = '${dateToUse.year}-${dateToUse.month.toString().padLeft(2, '0')}-${dateToUse.day.toString().padLeft(2, '0')} ${dateToUse.hour.toString().padLeft(2, '0')}:${dateToUse.minute.toString().padLeft(2, '0')}:${dateToUse.second.toString().padLeft(2, '0')}';
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
        print('❌ Pickup Service: Bokun API credentials not found in .env file.');
        print('Access Key: ${_accessKey.isEmpty ? "MISSING" : "FOUND"}');
        print('Secret Key: ${_secretKey.isEmpty ? "MISSING" : "FOUND"}');
        return [];
      }

      // Check if date is in the past (more than 30 days ago)
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      if (date.isBefore(thirtyDaysAgo)) {
        print('ℹ️ Date ${date.toString()} is too far in the past, skipping API call');
        return [];
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
        headers: _getHeaders(bodyJson, requestDate: date),
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
        final items = data['items'] as List<dynamic>? ?? [];
        print('📊 Total hits from API: ${data['totalHits']}');
        print('📊 Items array length: ${items.length}');
        
        for (final booking in items) {
          try {
            final pickupBooking = await _parseBokunBooking(booking);
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
        
        // Don't fall back to mock data - just return empty list
        if (response.statusCode == 400 && response.body.contains('too far in the past')) {
          print('ℹ️ Date is too far in the past, returning empty list');
          return [];
        }
        
        throw Exception('Failed to fetch bookings: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Pickup Service: Error fetching bookings from Bokun API: $e');
      
      // Don't fall back to mock data - just return empty list
      if (e.toString().contains('too far in the past')) {
        print('ℹ️ Date is too far in the past, returning empty list');
        return [];
      }
      
      // For other errors, return empty list instead of mock data
      print('ℹ️ Returning empty list due to API error');
      return [];
    }
  }

  // Parse Bokun API booking data
  Future<PickupBooking?> _parseBokunBooking(Map<String, dynamic> booking) async {
    try {
      print('🔍 Parsing booking: ${booking.keys.toList()}');
      
      // Extract customer information
      final customer = booking['customer'] ?? booking['leadCustomer'] ?? {};
      final customerFullName = '${customer['firstName'] ?? ''} ${customer['lastName'] ?? ''}'.trim();
      
      // Extract contact information
      final phoneNumber = customer['phoneNumber'] ?? customer['phone'] ?? '';
      final email = customer['email'] ?? '';
      
      // Parse productBookings array for tour details
      final List<dynamic> productBookings = booking['productBookings'] ?? [];
      print('🔍 ProductBookings for $customerFullName: ${productBookings.length} products');
      
      if (productBookings.isEmpty) {
        print('⚠️ No productBookings found for $customerFullName');
        return null;
      }
      
      // Use the first product booking for pickup details
      final productBooking = productBookings.first;
      print('🔍 ProductBooking keys: ${productBooking.keys.toList()}');
      
      // Debug: Check for pickup info in nested fields
      print('🔍 Checking for pickup info in nested fields:');
      
      // Check if pickup info is in 'product' field
      if (productBooking['product'] != null) {
        print('  Product keys: ${productBooking['product'].keys.toList()}');
        final product = productBooking['product'];
        if (product['pickup'] != null) print('  Product.pickup: ${product['pickup']}');
        if (product['pickupPlace'] != null) print('  Product.pickupPlace: ${product['pickupPlace']}');
      }
      
      // Check if there are activity-specific fields
      if (productBooking['activityPickup'] != null) {
        print('  ActivityPickup: ${productBooking['activityPickup']}');
      }
      
      // Check the 'fields' object for custom data
      if (productBooking['fields'] != null) {
        print('  Fields: ${productBooking['fields']}');
      }
      
      // Check 'specialRequests' for pickup info
      if (productBooking['specialRequests'] != null) {
        print('  SpecialRequests: ${productBooking['specialRequests']}');
      }
      
      // Check for pickup in various possible locations
      if (productBooking['pickup'] != null) print('  Direct pickup: ${productBooking['pickup']}');
      if (productBooking['pickupPlace'] != null) print('  Direct pickupPlace: ${productBooking['pickupPlace']}');
      if (productBooking['pickupPlaceDescription'] != null) print('  Direct pickupPlaceDescription: ${productBooking['pickupPlaceDescription']}');
      if (productBooking['pickupLocation'] != null) print('  Direct pickupLocation: ${productBooking['pickupLocation']}');
      if (productBooking['pickupAddress'] != null) print('  Direct pickupAddress: ${productBooking['pickupAddress']}');
      
      // Print the full raw productBooking to see all available data
      print('🔍 Full ProductBooking data: $productBooking');
      
      // Extract tour time
      final startDateStr = productBooking['startDate'];
      DateTime pickupTime;
      
      // First try to use the detailed time from fields
      final fields = productBooking['fields'] ?? {};
      if (fields['startHour'] != null && fields['startMinute'] != null) {
        final startHour = fields['startHour'];
        final startMinute = fields['startMinute'];
        
        // Create time for the booking date with specific hour/minute
        final startDateMs = productBooking['startDate'];
        if (startDateMs != null) {
          try {
            final baseDate = DateTime.fromMillisecondsSinceEpoch(startDateMs);
            pickupTime = DateTime(baseDate.year, baseDate.month, baseDate.day, startHour, startMinute);
            print('✅ Parsed detailed tour time: $pickupTime');
          } catch (e) {
            print('⚠️ Error parsing detailed time: $e');
            pickupTime = DateTime.now();
          }
        } else {
          pickupTime = DateTime.now();
        }
      } else {
        // Fallback to startDateTime or startDate
        final startDateTime = productBooking['startDateTime'] ?? productBooking['startDate'];
        if (startDateTime != null) {
          try {
            // Handle both string and integer timestamps
            if (startDateTime is String) {
              pickupTime = DateTime.parse(startDateTime);
            } else if (startDateTime is int) {
              pickupTime = DateTime.fromMillisecondsSinceEpoch(startDateTime);
            } else {
              pickupTime = DateTime.now();
            }
            print('✅ Parsed fallback time: $pickupTime');
          } catch (e) {
            print('⚠️ Could not parse tour time: $startDateTime, error: $e');
            pickupTime = DateTime.now(); // Use current time as last resort
          }
        } else {
          print('⚠️ No startDate found, using current time');
          pickupTime = DateTime.now();
        }
      }
      
      // Extract number of guests
      final numberOfGuests = productBooking['totalParticipants'] ?? 
                            productBooking['totalPax'] ??
                            productBooking['pax'] ??
                            1;
      print('✅ Parsed guest count: $numberOfGuests');
      
      // Extract pickup location from fields object
      String pickupPlaceName = 'Meet on location';
      if (fields['pickup'] == true) {
        // Check for specific pickup description
        if (fields['pickupPlaceDescription'] != null && fields['pickupPlaceDescription'].toString().isNotEmpty) {
          pickupPlaceName = fields['pickupPlaceDescription'];
          print('✅ Found pickupPlaceDescription: $pickupPlaceName');
        }
        // Check for pickup in the start time label
        else if (fields['startTimeLabel'] != null) {
          final startTimeLabel = fields['startTimeLabel'];
          if (startTimeLabel.contains('Pickup')) {
            pickupPlaceName = 'Pickup at ${fields['startTimeStr'] ?? 'scheduled time'}';
            print('✅ Found pickup in startTimeLabel: $pickupPlaceName');
          }
        }
        // Fallback for general pickup
        else {
          pickupPlaceName = 'Pickup arranged';
          print('✅ General pickup arranged');
        }
      } else {
        pickupPlaceName = 'Meet on location';
        print('✅ Meet on location');
      }
      
      // Debug pickup information
      if (productBooking['pickup'] != null) {
        print('🔍 Pickup: ${productBooking['pickup']}');
      }
      if (productBooking['pickupPlace'] != null) {
        print('🔍 PickupPlace: ${productBooking['pickupPlace']}');
      }
      if (productBooking['pickupPlaceDescription'] != null) {
        print('🔍 PickupPlaceDescription: ${productBooking['pickupPlaceDescription']}');
      }

      final pickupBooking = PickupBooking(
        id: booking['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        customerFullName: customerFullName.isNotEmpty ? customerFullName : 'Unknown Customer',
        pickupPlaceName: pickupPlaceName,
        pickupTime: pickupTime,
        numberOfGuests: numberOfGuests,
        phoneNumber: phoneNumber,
        email: email,
        createdAt: DateTime.now(),
      );
      
      print('✅ Successfully parsed booking: ${pickupBooking.customerFullName} - ${pickupBooking.pickupPlaceName} - ${pickupBooking.numberOfGuests} guests - ${pickupBooking.pickupTime}');
      return pickupBooking;
    } catch (e) {
      print('❌ Error parsing Bokun booking: $e');
      print('📄 Booking data: $booking');
      return null;
    }
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