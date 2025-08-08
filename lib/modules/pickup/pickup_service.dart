import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crypto/crypto.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
import '../../core/services/firebase_service.dart';

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

  // Fetch booking questions from Bokun API
  Future<Map<String, dynamic>?> _fetchBookingQuestions(String bookingId) async {
    try {
      if (!_hasApiCredentials) {
        print('❌ Booking Questions: Bokun API credentials not found');
        return null;
      }

      final url = '$_baseUrl/booking.json/$bookingId/questions';
      print('🌐 Booking Questions API URL: $url');

      final headers = _getHeaders('');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      print('📡 Booking Questions API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Booking Questions API call successful!');
        print('📊 Booking Questions Raw response: ${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}...');
        return data;
      } else {
        print('❌ Booking Questions API Error: ${response.statusCode}');
        print('📄 Booking Questions Error Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Booking Questions Service: Error fetching questions for booking $bookingId: $e');
      return null;
    }
  }

  // Parse pickup information from booking questions
  String? _parsePickupFromQuestions(Map<String, dynamic> questionsData) {
    print('🔍 === PARSING PICKUP FROM QUESTIONS ===');
    
    try {
      // Check for pickup questions in activity bookings
      if (questionsData['activityBookings'] != null) {
        for (var activityBooking in questionsData['activityBookings']) {
          print('🔍 Activity booking: ${activityBooking['bookingId']}');
          
          // Check pickup questions
          if (activityBooking['pickupQuestions'] != null) {
            for (var question in activityBooking['pickupQuestions']) {
              print('🔍 Pickup question: ${question}');
              
              // Look for pickup location in answers
              if (question['answer'] != null && question['answer'] is String) {
                final answer = question['answer'] as String;
                if (answer.isNotEmpty) {
                  print('✅ Found pickup location in pickup questions: $answer');
                  return answer;
                }
              }
              
              // Also check if the answer is in a different format
              if (question['answers'] != null) {
                for (var answer in question['answers']) {
                  if (answer is String && answer.isNotEmpty) {
                    print('✅ Found pickup location in pickup questions array: $answer');
                    return answer;
                  }
                }
              }
            }
          }
          
          // Check general pickup answers
          if (activityBooking['pickupAnswers'] != null) {
            for (var answer in activityBooking['pickupAnswers']) {
              print('🔍 Pickup answer: ${answer}');
              if (answer['answer'] != null && answer['answer'] is String) {
                final answerText = answer['answer'] as String;
                if (answerText.isNotEmpty) {
                  print('✅ Found pickup location in pickup answers: $answerText');
                  return answerText;
                }
              }
            }
          }
          
          // Check all answers for pickup-related content
          if (activityBooking['answers'] != null) {
            for (var answer in activityBooking['answers']) {
              print('🔍 General answer: ${answer}');
              
              // Check if this is a pickup-related question
              if (answer['question'] != null && 
                  answer['question']['questionCode'] != null &&
                  answer['question']['questionCode'].toString().toLowerCase().contains('pickup')) {
                
                if (answer['answer'] != null && answer['answer'] is String) {
                  final answerText = answer['answer'] as String;
                  print('✅ Found pickup location in general answers: $answerText');
                  return answerText;
                }
              }
            }
          }
        }
      }
      
      // Also check for pickup questions in the main questions structure
      if (questionsData['pickupQuestions'] != null) {
        for (var question in questionsData['pickupQuestions']) {
          print('🔍 Main pickup question: ${question}');
          
          if (question['answer'] != null && question['answer'] is String) {
            final answer = question['answer'] as String;
            if (answer.isNotEmpty) {
              print('✅ Found pickup location in main pickup questions: $answer');
              return answer;
            }
          }
        }
      }
      
      print('🔍 No pickup location found in questions');
      return null;
    } catch (e) {
      print('❌ Error parsing pickup from questions: $e');
      return null;
    }
  }

  // Fetch individual booking details from Bokun API
  Future<Map<String, dynamic>?> _fetchIndividualBooking(String bookingId) async {
    try {
      if (!_hasApiCredentials) {
        print('❌ Individual Booking: Bokun API credentials not found');
        return null;
      }

      final url = '$_baseUrl/booking.json/booking/$bookingId';
      print('🌐 Individual Booking API URL: $url');

      final headers = _getHeaders('');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      print('📡 Individual Booking API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Individual Booking API call successful!');
        print('📊 Individual Booking Raw response: ${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}...');
        return data;
      } else {
        print('❌ Individual Booking API Error: ${response.statusCode}');
        print('📄 Individual Booking Error Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Individual Booking Service: Error fetching booking $bookingId: $e');
      return null;
    }
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
      final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

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
      print('📅 Date Range: ${startDate.toUtc().toIso8601String()} to ${endDate.toUtc().toIso8601String()}');
      print('📅 Local Date Range: ${startDate.toLocal()} to ${endDate.toLocal()}');

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
        
        // Second pass: For bookings with pickup: true but no pickup details, try questions API
        print('🔄 Starting second pass: Checking questions API for missing pickup details...');
        for (int i = 0; i < bookings.length; i++) {
          final booking = bookings[i];
          if (booking.pickupPlaceName == 'Pickup arranged' || booking.pickupPlaceName == 'Meet on location') {
            print('🔍 Booking ${booking.customerFullName} has generic pickup info, trying questions API...');
            
            // Use bookingId if available, otherwise use the booking id
            final bookingIdForQuestions = booking.bookingId ?? booking.id;
            
            // Try to get pickup details from questions API
            final questionsData = await _fetchBookingQuestions(bookingIdForQuestions);
            if (questionsData != null) {
              final pickupFromQuestions = _parsePickupFromQuestions(questionsData);
              if (pickupFromQuestions != null && pickupFromQuestions.isNotEmpty) {
                print('✅ Found pickup details for ${booking.customerFullName}: $pickupFromQuestions');
                // Update the booking with the correct pickup location
                bookings[i] = booking.copyWith(pickupPlaceName: pickupFromQuestions);
              }
            }
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

  // Parse individual Bokun API booking data (for detailed booking calls)
  Future<PickupBooking?> _parseIndividualBokunBooking(Map<String, dynamic> booking) async {
    try {
      print('🔍 Parsing individual booking: ${booking.keys.toList()}');
      
      // Extract customer information
      final customer = booking['customer'] ?? booking['leadCustomer'] ?? {};
      final customerFullName = '${customer['firstName'] ?? ''} ${customer['lastName'] ?? ''}'.trim();
      
      if (customerFullName.isEmpty) {
        print('⚠️ Individual Booking: No customer name found');
        return null;
      }
      
      // Get the first product booking (assuming one product per booking)
      final productBookings = booking['productBookings'] as List<dynamic>? ?? [];
      if (productBookings.isEmpty) {
        print('⚠️ Individual Booking: No product bookings found');
        return null;
      }
      
      final productBooking = productBookings.first;
      
      // Extract pickup information with enhanced debugging
      final fields = productBooking['fields'] ?? {};
      String pickupPlaceName = 'Meet on location';
      
      print('🔍 === INDIVIDUAL BOOKING PICKUP DEBUG ===');
      print('🔍 Individual booking fields: $fields');
      
      // Check for pickup info in all possible locations
      if (fields['pickup'] == true) {
        // Check all possible pickup fields
        if (fields['pickupPlaceDescription'] != null && fields['pickupPlaceDescription'].toString().trim().isNotEmpty) {
          pickupPlaceName = fields['pickupPlaceDescription'];
          print('✅ Individual: Found pickupPlaceDescription: $pickupPlaceName');
        } else if (fields['pickupDescription'] != null && fields['pickupDescription'].toString().trim().isNotEmpty) {
          pickupPlaceName = fields['pickupDescription'];
          print('✅ Individual: Found pickupDescription: $pickupPlaceName');
        } else if (fields['pickupPlaceId'] != null) {
          print('🔍 Individual: Found pickupPlaceId: ${fields['pickupPlaceId']}');
          // TODO: We might need to fetch pickup place details using this ID
        }
        
        // Check for pickup info in answers
        if (productBooking['answers'] != null && productBooking['answers'] is List) {
          final answers = productBooking['answers'] as List;
          for (final answer in answers) {
            if (answer is Map) {
              final question = answer['question'] ?? '';
              final answerText = answer['answer'] ?? '';
              if (question.toString().toLowerCase().contains('pickup') && 
                  answerText.toString().trim().isNotEmpty) {
                pickupPlaceName = answerText.toString().trim();
                print('✅ Individual: Found pickup info in answers: $pickupPlaceName');
                break;
              }
            }
          }
        }
        
        // Check for pickup info in priceCategoryBookings answers
        if (fields['priceCategoryBookings'] != null && fields['priceCategoryBookings'] is List) {
          final priceCategoryBookings = fields['priceCategoryBookings'] as List;
          for (final priceBooking in priceCategoryBookings) {
            if (priceBooking['answers'] != null && priceBooking['answers'] is List) {
              final answers = priceBooking['answers'] as List;
              for (final answer in answers) {
                if (answer is Map) {
                  final question = answer['question'] ?? '';
                  final answerText = answer['answer'] ?? '';
                  if (question.toString().toLowerCase().contains('pickup') && 
                      answerText.toString().trim().isNotEmpty) {
                    pickupPlaceName = answerText.toString().trim();
                    print('✅ Individual: Found pickup info in priceCategoryBookings answers: $pickupPlaceName');
                    break;
                  }
                }
              }
            }
          }
        }
        
        if (pickupPlaceName == 'Meet on location') {
          pickupPlaceName = 'Pickup arranged';
        }
      }
      
      // Extract other booking details (similar to regular parsing)
      final startDateStr = productBooking['startDate'];
      DateTime pickupTime;
      
      if (fields['startHour'] != null && fields['startMinute'] != null) {
        final startHour = fields['startHour'];
        final startMinute = fields['startMinute'];
        
        if (startDateStr != null) {
          try {
            final baseDate = DateTime.fromMillisecondsSinceEpoch(startDateStr);
            pickupTime = DateTime(baseDate.year, baseDate.month, baseDate.day, startHour, startMinute);
          } catch (e) {
            pickupTime = DateTime.now();
          }
        } else {
          pickupTime = DateTime.now();
        }
      } else {
        final startDateTime = productBooking['startDateTime'] ?? productBooking['startDate'];
        if (startDateTime != null) {
          try {
            if (startDateTime is String) {
              pickupTime = DateTime.parse(startDateTime);
            } else if (startDateTime is int) {
              pickupTime = DateTime.fromMillisecondsSinceEpoch(startDateTime);
            } else {
              pickupTime = DateTime.now();
            }
          } catch (e) {
            pickupTime = DateTime.now();
          }
        } else {
          pickupTime = DateTime.now();
        }
      }
      
      final numberOfGuests = productBooking['totalParticipants'] ?? 1;
      
      // Extract booking ID for questions API calls
      final bookingId = productBooking['parentBookingId']?.toString() ?? 
                       productBooking['id']?.toString() ?? 
                       booking['id']?.toString();
      
      return PickupBooking(
        id: booking['id']?.toString() ?? '',
        customerFullName: customerFullName,
        pickupPlaceName: pickupPlaceName,
        pickupTime: pickupTime,
        numberOfGuests: numberOfGuests,
        phoneNumber: customer['phoneNumber']?.toString() ?? '',
        email: customer['email']?.toString() ?? '',
        isArrived: false,
        isNoShow: false,
        assignedGuideId: '',
        assignedGuideName: '',
        createdAt: DateTime.now(),
        bookingId: bookingId,
      );
    } catch (e) {
      print('❌ Error parsing individual booking: $e');
      return null;
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
      
      // Check for pickup info in the main booking object
      print('🔍 Checking main booking object for pickup info:');
      if (booking['pickup'] != null) print('  Main booking pickup: ${booking['pickup']}');
      if (booking['pickupPlace'] != null) print('  Main booking pickupPlace: ${booking['pickupPlace']}');
      if (booking['pickupPlaceDescription'] != null) print('  Main booking pickupPlaceDescription: ${booking['pickupPlaceDescription']}');
      if (booking['pickupLocation'] != null) print('  Main booking pickupLocation: ${booking['pickupLocation']}');
      if (booking['pickupAddress'] != null) print('  Main booking pickupAddress: ${booking['pickupAddress']}');
      
      // Check for pickup info in notes
      if (booking['notes'] != null) {
        print('  Main booking notes: ${booking['notes']}');
      }
      if (productBooking['notes'] != null) {
        print('  Product booking notes: ${productBooking['notes']}');
      }
      
      // Check for pickup info in labels
      if (booking['labels'] != null) {
        print('  Main booking labels: ${booking['labels']}');
      }
      if (productBooking['labels'] != null) {
        print('  Product booking labels: ${productBooking['labels']}');
      }
      
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
      
      // Extract pickup information from the 'fields' object
      String pickupPlaceName = 'Meet on location';

      if (fields['pickup'] == true) {
        // 1. Check for pickupPlaceId first (reference to predefined pickup place)
        if (fields['pickupPlaceId'] != null) {
          print('🔍 Found pickupPlaceId: ${fields['pickupPlaceId']}');
          // TODO: We might need to fetch pickup place details using this ID
        }
        
        // 2. Check for pickupDescription (free text description)
        if (fields['pickupDescription'] != null && 
            fields['pickupDescription'].toString().trim().isNotEmpty) {
          pickupPlaceName = fields['pickupDescription'];
          print('✅ Found pickupDescription: $pickupPlaceName');
        }
        // 3. Check for specific pickup description
        else if (fields['pickupPlaceDescription'] != null && 
            fields['pickupPlaceDescription'].toString().trim().isNotEmpty) {
          pickupPlaceName = fields['pickupPlaceDescription'];
          print('✅ Found pickupPlaceDescription: $pickupPlaceName');
        }
        // 4. Check for pickup info in priceCategoryBookings answers
        else if (fields['priceCategoryBookings'] != null && fields['priceCategoryBookings'] is List) {
          final priceCategoryBookings = fields['priceCategoryBookings'] as List;
          for (final priceBooking in priceCategoryBookings) {
            if (priceBooking['answers'] != null && priceBooking['answers'] is List) {
              final answers = priceBooking['answers'] as List;
              for (final answer in answers) {
                if (answer is Map) {
                  final question = answer['question'] ?? '';
                  final answerText = answer['answer'] ?? '';
                  if (question.toString().toLowerCase().contains('pickup') && 
                      answerText.toString().trim().isNotEmpty) {
                    pickupPlaceName = answerText.toString().trim();
                    print('✅ Found pickup info in priceCategoryBookings answers: $pickupPlaceName');
                    break;
                  }
                }
              }
            }
          }
        }
        // 5. Check for pickup info in main booking answers
        else if (booking['answers'] != null && booking['answers'] is List) {
          final answers = booking['answers'] as List;
          for (final answer in answers) {
            if (answer is Map) {
              final question = answer['question'] ?? '';
              final answerText = answer['answer'] ?? '';
              if (question.toString().toLowerCase().contains('pickup') && 
                  answerText.toString().trim().isNotEmpty) {
                pickupPlaceName = answerText.toString().trim();
                print('✅ Found pickup info in main booking answers: $pickupPlaceName');
                break;
              }
            }
          }
        }
        // 6. Check for pickup info in productBooking answers
        else if (productBooking['answers'] != null && productBooking['answers'] is List) {
          final answers = productBooking['answers'] as List;
          for (final answer in answers) {
            if (answer is Map) {
              final question = answer['question'] ?? '';
              final answerText = answer['answer'] ?? '';
              if (question.toString().toLowerCase().contains('pickup') && 
                  answerText.toString().trim().isNotEmpty) {
                pickupPlaceName = answerText.toString().trim();
                print('✅ Found pickup info in productBooking answers: $pickupPlaceName');
                break;
              }
            }
          }
        }
        // 7. Check for room number info
        else if (fields['pickupPlaceRoomNumber'] != null && 
                 fields['pickupPlaceRoomNumber'].toString().trim().isNotEmpty) {
          pickupPlaceName = 'Room ${fields['pickupPlaceRoomNumber']}';
          print('✅ Found pickupPlaceRoomNumber: ${fields['pickupPlaceRoomNumber']}');
        }
        // 8. Check if startTimeLabel has actual place info (not just time)
        else if (fields['startTimeLabel'] != null) {
          final startTimeLabel = fields['startTimeLabel'].toString();
          
          // Only use startTimeLabel if it contains actual location info
          // Skip if it's just time + "Pickup"
          if (!RegExp(r'^\d{1,2}:\d{2}\s*Pickup$').hasMatch(startTimeLabel)) {
            pickupPlaceName = startTimeLabel;
            print('✅ Using startTimeLabel with location info: $pickupPlaceName');
          } else {
            // It's just "HH:MM Pickup" - use generic message
            pickupPlaceName = 'Pickup arranged';
            print('✅ Using generic pickup message (time only in startTimeLabel)');
          }
        }
        // 9. Fallback for pickup without location details
        else {
          pickupPlaceName = 'Pickup arranged';
          print('✅ General pickup arranged');
        }
      } else {
        pickupPlaceName = 'Meet on location';
        print('✅ Meet on location');
      }
      
      // Debug pickup information
      print('🔍 === PICKUP DEBUG INFO ===');
      print('🔍 Fields object: $fields');
      
      // Enhanced debugging for all potential pickup locations
      print('🔍 === ENHANCED PICKUP DEBUG ===');
      
      // Check for pickupPlaceId and pickupDescription in fields
      print('🔍 Checking pickupPlaceId: ${fields['pickupPlaceId']}');
      print('🔍 Checking pickupDescription: ${fields['pickupDescription']}');
      
      // Check for pickup info in priceCategoryBookings answers
      if (fields['priceCategoryBookings'] != null && fields['priceCategoryBookings'] is List) {
        print('🔍 Checking priceCategoryBookings for pickup answers:');
        final priceCategoryBookings = fields['priceCategoryBookings'] as List;
        for (int i = 0; i < priceCategoryBookings.length; i++) {
          final priceBooking = priceCategoryBookings[i];
          print('  PriceCategoryBooking $i answers: ${priceBooking['answers']}');
          print('  PriceCategoryBooking $i bookingAnswers: ${priceBooking['bookingAnswers']}');
          
          // Check for pickup-related questions in answers
          if (priceBooking['answers'] != null && priceBooking['answers'] is List) {
            final answers = priceBooking['answers'] as List;
            for (final answer in answers) {
              if (answer is Map) {
                final question = answer['question'] ?? '';
                final answerText = answer['answer'] ?? '';
                if (question.toString().toLowerCase().contains('pickup') || 
                    answerText.toString().toLowerCase().contains('pickup')) {
                  print('    🔍 PICKUP ANSWER FOUND: Question: $question, Answer: $answerText');
                }
              }
            }
          }
        }
      }
      
      // Check for pickupAnswers in the main booking object
      print('🔍 Checking main booking pickupAnswers: ${booking['pickupAnswers']}');
      
      // Check for pickup info in booking answers
      if (booking['answers'] != null && booking['answers'] is List) {
        print('🔍 Checking main booking answers for pickup info:');
        final answers = booking['answers'] as List;
        for (final answer in answers) {
          if (answer is Map) {
            final question = answer['question'] ?? '';
            final answerText = answer['answer'] ?? '';
            if (question.toString().toLowerCase().contains('pickup') || 
                answerText.toString().toLowerCase().contains('pickup')) {
              print('    🔍 PICKUP ANSWER FOUND: Question: $question, Answer: $answerText');
            }
          }
        }
      }
      
      // Check for pickup info in productBooking answers
      if (productBooking['answers'] != null && productBooking['answers'] is List) {
        print('🔍 Checking productBooking answers for pickup info:');
        final answers = productBooking['answers'] as List;
        for (final answer in answers) {
          if (answer is Map) {
            final question = answer['question'] ?? '';
            final answerText = answer['answer'] ?? '';
            if (question.toString().toLowerCase().contains('pickup') || 
                answerText.toString().toLowerCase().contains('pickup')) {
              print('    🔍 PICKUP ANSWER FOUND: Question: $question, Answer: $answerText');
            }
          }
        }
      }
      
      // Check for pickup info in specialRequests
      if (productBooking['specialRequests'] != null) {
        print('🔍 Checking specialRequests for pickup info: ${productBooking['specialRequests']}');
      }
      
      // Check for pickup info in notes
      if (productBooking['notes'] != null) {
        print('🔍 Checking productBooking notes for pickup info: ${productBooking['notes']}');
      }
      
      // Check for pickup info in labels
      if (productBooking['labels'] != null) {
        print('🔍 Checking productBooking labels for pickup info: ${productBooking['labels']}');
      }
      
      // Check for pickup location in priceCategoryBookings
      if (fields['priceCategoryBookings'] != null && fields['priceCategoryBookings'] is List) {
        print('🔍 Checking priceCategoryBookings for pickup info:');
        final priceCategoryBookings = fields['priceCategoryBookings'] as List;
        for (int i = 0; i < priceCategoryBookings.length; i++) {
          final priceBooking = priceCategoryBookings[i];
          print('  PriceCategoryBooking $i: $priceBooking');
          if (priceBooking['answers'] != null && priceBooking['answers'] is List) {
            final answers = priceBooking['answers'] as List;
            for (final answer in answers) {
              print('    Answer: $answer');
            }
          }
        }
      }
      
      // Check for pickup location in bookedExtras
      if (fields['bookedExtras'] != null && fields['bookedExtras'] is List) {
        print('🔍 Checking bookedExtras for pickup info:');
        final bookedExtras = fields['bookedExtras'] as List;
        for (final extra in bookedExtras) {
          print('  BookedExtra: $extra');
        }
      }
      
      // Check for pickup location in partnerBookings
      if (fields['partnerBookings'] != null && fields['partnerBookings'] is List) {
        print('🔍 Checking partnerBookings for pickup info:');
        final partnerBookings = fields['partnerBookings'] as List;
        for (final partnerBooking in partnerBookings) {
          print('  PartnerBooking: $partnerBooking');
        }
      }
      print('🔍 ProductBooking pickup fields:');
      if (productBooking['pickup'] != null) {
        print('  Pickup: ${productBooking['pickup']}');
      }
      if (productBooking['pickupPlace'] != null) {
        print('  PickupPlace: ${productBooking['pickupPlace']}');
      }
      if (productBooking['pickupPlaceDescription'] != null) {
        print('  PickupPlaceDescription: ${productBooking['pickupPlaceDescription']}');
      }
      if (productBooking['pickupAddress'] != null) {
        print('  PickupAddress: ${productBooking['pickupAddress']}');
      }
      if (productBooking['pickupLocation'] != null) {
        print('  PickupLocation: ${productBooking['pickupLocation']}');
      }
      if (productBooking['activityPickup'] != null) {
        print('  ActivityPickup: ${productBooking['activityPickup']}');
      }
      if (productBooking['specialRequests'] != null) {
        print('  SpecialRequests: ${productBooking['specialRequests']}');
      }
      if (productBooking['notes'] != null) {
        print('  Notes: ${productBooking['notes']}');
      }
      
      // Check product object if it exists
      if (productBooking['product'] != null) {
        print('🔍 Product object pickup fields:');
        final product = productBooking['product'];
        if (product['pickup'] != null) {
          print('  Product.pickup: ${product['pickup']}');
        }
        if (product['pickupPlace'] != null) {
          print('  Product.pickupPlace: ${product['pickupPlace']}');
        }
        if (product['pickupPlaceDescription'] != null) {
          print('  Product.pickupPlaceDescription: ${product['pickupPlaceDescription']}');
        }
      }
      
      // Check main booking object
      print('🔍 Main booking pickup fields:');
      if (booking['pickup'] != null) {
        print('  Main pickup: ${booking['pickup']}');
      }
      if (booking['pickupPlace'] != null) {
        print('  Main pickupPlace: ${booking['pickupPlace']}');
      }
      if (booking['pickupPlaceDescription'] != null) {
        print('  Main pickupPlaceDescription: ${booking['pickupPlaceDescription']}');
      }
      if (booking['pickupLocation'] != null) {
        print('  Main pickupLocation: ${booking['pickupLocation']}');
      }
      if (booking['pickupAddress'] != null) {
        print('  Main pickupAddress: ${booking['pickupAddress']}');
      }
      if (booking['notes'] != null) {
        print('  Main notes: ${booking['notes']}');
      }
      if (booking['labels'] != null) {
        print('  Main labels: ${booking['labels']}');
      }
      
      print('🔍 Final pickup place name: $pickupPlaceName');
      print('🔍 === END PICKUP DEBUG ===');

      // Extract booking ID for questions API calls
      final bookingId = productBooking['parentBookingId']?.toString() ?? 
                       productBooking['id']?.toString() ?? 
                       booking['id']?.toString();
      
      final pickupBooking = PickupBooking(
        id: booking['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        customerFullName: customerFullName.isNotEmpty ? customerFullName : 'Unknown Customer',
        pickupPlaceName: pickupPlaceName,
        pickupTime: pickupTime,
        numberOfGuests: numberOfGuests,
        phoneNumber: phoneNumber,
        email: email,
        createdAt: DateTime.now(),
        bookingId: bookingId,
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
  Future<bool> assignBookingToGuide(String bookingId, String guideId, String guideName, {DateTime? date}) async {
    try {
      final assignmentDate = date ?? DateTime.now();
      print('🔄 Assigning booking $bookingId to guide $guideName ($guideId) for date $assignmentDate');
      
      if (guideId.isEmpty) {
        // Unassigning - remove from Firebase
        print('❌ Unassigning booking $bookingId');
        await FirebaseService.removePickupAssignment(bookingId);
        return true;
      }
      
      // Save assignment to Firebase
      print('💾 Saving assignment to Firebase...');
      await FirebaseService.savePickupAssignment(
        bookingId: bookingId,
        guideId: guideId,
        guideName: guideName,
        date: assignmentDate,
      );
      
      print('✅ Assignment saved successfully');
      return true;
    } catch (e) {
      print('❌ Error assigning booking: $e');
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