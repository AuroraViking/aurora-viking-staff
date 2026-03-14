import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../core/models/pickup_models.dart';
import '../../core/models/tour_group.dart';
import '../../core/models/user_model.dart';
import '../../core/services/firebase_service.dart';

class PickupService {
  static const String _baseUrl = 'https://api.bokun.io';
  
  // Valid booking statuses that should show up in pickup lists
  // When customers reschedule, original productBooking gets CANCELLED
  // and a new one is created. We need to find the valid one.
  static const Set<String> _validBookingStatuses = {
    'CONFIRMED',
    'INVOICED',
    'PAID_IN_FULL',
  };
  
  // Get Bokun API credentials from environment
  String get _accessKey => dotenv.env['BOKUN_ACCESS_KEY'] ?? '';
  String get _secretKey => dotenv.env['BOKUN_SECRET_KEY'] ?? '';
  int get _maxPassengersPerBus => int.tryParse(dotenv.env['MAX_PASSENGERS_PER_BUS'] ?? '18') ?? 18;

  // Check if API credentials are available
  bool get _hasApiCredentials => _accessKey.isNotEmpty && _secretKey.isNotEmpty;

  /// Retry a future-returning function on transient network errors.
  /// Uses exponential backoff: 2s, 4s, 8s between attempts.
  /// Catches DNS failures, socket errors, timeouts, and HTTP 5xx.
  Future<T> _retryOnTransientError<T>(Future<T> Function() fn, {int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isTransient = errorStr.contains('socketexception') ||
            errorStr.contains('socket') ||
            errorStr.contains('host lookup') ||
            errorStr.contains('connection refused') ||
            errorStr.contains('connection reset') ||
            errorStr.contains('connection closed') ||
            errorStr.contains('network is unreachable') ||
            errorStr.contains('no address associated') ||
            errorStr.contains('timed out') ||
            errorStr.contains('timeout') ||
            e is TimeoutException;

        if (!isTransient || attempt == maxAttempts) {
          print('❌ Retry: giving up after $attempt attempt(s): $e');
          rethrow;
        }

        final delay = Duration(seconds: 1 << attempt); // 2s, 4s, 8s
        print('⚠️ Retry: transient error on attempt $attempt/$maxAttempts, retrying in ${delay.inSeconds}s: $e');
        await Future.delayed(delay);
      }
    }
    throw StateError('Unreachable'); // satisfy type system
  }

  /// Check if a booking status is valid for showing in pickup lists
  bool _isValidBookingStatus(String status) {
    return _validBookingStatuses.contains(status.toUpperCase());
  }

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

  /// Extract pickup location from the pickupPlace object (predefined pickup locations)
  /// According to Bokun API, PickupDropoffPlace has: title (string), address (Address object)
  String? _extractPickupFromPickupPlaceObject(dynamic pickupPlace) {
    if (pickupPlace == null) return null;
    
    print('🔍 Extracting from pickupPlace object: $pickupPlace');
    print('🔍 pickupPlace type: ${pickupPlace.runtimeType}');
    
    if (pickupPlace is Map) {
      // Try 'title' first (per Bokun API spec: PickupDropoffPlace has title and address)
      if (pickupPlace['title'] != null && pickupPlace['title'].toString().trim().isNotEmpty) {
        final title = pickupPlace['title'].toString().trim();
        print('✅ Found pickupPlace.title: $title');
        
        // If there's also an address, append it for more context
        String fullLocation = title;
        if (pickupPlace['address'] != null) {
          final address = pickupPlace['address'];
          if (address is Map) {
            final addressParts = <String>[];
            if (address['addressLine1'] != null && address['addressLine1'].toString().trim().isNotEmpty) {
              addressParts.add(address['addressLine1'].toString().trim());
            }
            if (address['addressLine2'] != null && address['addressLine2'].toString().trim().isNotEmpty) {
              addressParts.add(address['addressLine2'].toString().trim());
            }
            if (address['city'] != null && address['city'].toString().trim().isNotEmpty) {
              addressParts.add(address['city'].toString().trim());
            }
            if (address['postCode'] != null && address['postCode'].toString().trim().isNotEmpty) {
              addressParts.add(address['postCode'].toString().trim());
            }
            if (addressParts.isNotEmpty) {
              fullLocation = '$title, ${addressParts.join(', ')}';
            }
          } else if (address is String && address.trim().isNotEmpty) {
            fullLocation = '$title, ${address.trim()}';
          }
        }
        return fullLocation;
      }
      
      // Fallback to 'name' if title not present
      if (pickupPlace['name'] != null && pickupPlace['name'].toString().trim().isNotEmpty) {
        final name = pickupPlace['name'].toString().trim();
        print('✅ Found pickupPlace.name: $name');
        return name;
      }
      
      // Fallback to 'description' 
      if (pickupPlace['description'] != null && pickupPlace['description'].toString().trim().isNotEmpty) {
        final description = pickupPlace['description'].toString().trim();
        print('✅ Found pickupPlace.description: $description');
        return description;
      }
      
      // Try to construct from address only if no title/name
      if (pickupPlace['address'] != null) {
        final address = pickupPlace['address'];
        if (address is Map) {
          final addressParts = <String>[];
          if (address['addressLine1'] != null && address['addressLine1'].toString().trim().isNotEmpty) {
            addressParts.add(address['addressLine1'].toString().trim());
          }
          if (address['city'] != null && address['city'].toString().trim().isNotEmpty) {
            addressParts.add(address['city'].toString().trim());
          }
          if (addressParts.isNotEmpty) {
            final fullAddress = addressParts.join(', ');
            print('✅ Constructed address from pickupPlace.address: $fullAddress');
            return fullAddress;
          }
        } else if (address is String && address.trim().isNotEmpty) {
          print('✅ Found pickupPlace.address (string): ${address.trim()}');
          return address.trim();
        }
      }
    } else if (pickupPlace is String && pickupPlace.trim().isNotEmpty) {
      // Sometimes it might just be a string
      print('✅ pickupPlace is a string: ${pickupPlace.trim()}');
      return pickupPlace.trim();
    }
    
    print('⚠️ Could not extract location from pickupPlace object');
    return null;
  }

  // Extract pickup information from supplier notes
  String? _extractPickupFromNotes(List<dynamic>? notes) {
    if (notes == null) return null;
    
    print('🔍 === PARSING PICKUP FROM NOTES ===');
    
    for (var note in notes) {
      if (note['body'] != null) {
        final noteBody = note['body'].toString();
        print('🔍 Note body: $noteBody');
        
        // Look for supplier note section with pickup changes
        if (noteBody.contains('--- Supplier note: ---') || 
            noteBody.contains('Pickup point changed')) {
          
          // Extract pickup location from "Pickup point changed from X to Y" pattern
          final lines = noteBody.split('\n');
          for (var line in lines) {
            line = line.trim();
            
            // Look for the "Pickup point changed from X to Y" line
            if (line.startsWith('Pickup point changed from') && line.contains(' to ')) {
              final toIndex = line.lastIndexOf(' to ');
              if (toIndex != -1) {
                var pickupLocation = line.substring(toIndex + 4).trim();
                
                // Remove trailing period if present
                if (pickupLocation.endsWith('.')) {
                  pickupLocation = pickupLocation.substring(0, pickupLocation.length - 1);
                }
                
                // Only return if it's not the default "select later" message
                if (pickupLocation.isNotEmpty && 
                    !pickupLocation.toLowerCase().contains('i will select my pickup location later') &&
                    !pickupLocation.toLowerCase().contains('i will contact the supplier later')) {
                  print('✅ Found pickup location in supplier notes: $pickupLocation');
                  return pickupLocation;
                }
              }
            }
          }
        }
      }
    }
    
    print('🔍 No pickup location found in notes');
    return null;
  }

  /// Check if a pickup value is a placeholder that means "no pickup selected yet"
  bool _isPlaceholderPickup(String? value) {
    if (value == null || value.trim().isEmpty) return true;
    
    final lowerValue = value.toLowerCase().trim();
    return lowerValue.contains('i will select my pickup location later') ||
           lowerValue.contains('i will contact the supplier later') ||
           lowerValue.contains('select later') ||
           lowerValue.contains('contact supplier') ||
           lowerValue == 'meet on location' ||
           lowerValue == 'pickup arranged';
  }

  /// Detect if this is a private tour based on product title and booking data
  bool _isPrivateTour(String? productTitle, Map<String, dynamic> productBooking, Map<String, dynamic> booking) {
    // Use the helper from TourGroup
    if (PrivateTourDetector.isPrivateTour(productTitle)) {
      return true;
    }
    
    // Check labels/tags in booking
    final labels = booking['labels'] as List<dynamic>?;
    if (labels != null) {
      for (final label in labels) {
        if (PrivateTourDetector.isPrivateTour(label.toString())) {
          return true;
        }
      }
    }
    
    // Check product labels
    final product = productBooking['product'] as Map<String, dynamic>?;
    final productLabels = product?['labels'] as List<dynamic>?;
    if (productLabels != null) {
      for (final label in productLabels) {
        if (PrivateTourDetector.isPrivateTour(label.toString())) {
          return true;
        }
      }
    }
    
    // Check booking type
    final bookingType = booking['bookingType']?.toString();
    if (PrivateTourDetector.isPrivateTour(bookingType)) {
      return true;
    }
    
    // Check product type
    final productType = product?['type']?.toString();
    if (PrivateTourDetector.isPrivateTour(productType)) {
      return true;
    }
    
    return false;
  }

  /// Main method to extract pickup location from all possible sources
  /// Priority order:
  /// 1. pickupPlace object (predefined pickup locations with checkmark in Bokun UI)
  /// 2. pickupPlaceDescription (free text/custom locations)
  /// 3. Supplier notes (pickup point changed messages)
  /// 4. Various answer fields
  /// 5. Fallback defaults
  String _extractPickupLocation({
    required Map<String, dynamic> fields,
    required Map<String, dynamic> productBooking,
    required Map<String, dynamic> booking,
  }) {
    print('🔍 === EXTRACTING PICKUP LOCATION ===');
    
    // Debug: Print all potential pickup fields
    print('🔍 fields[pickupPlace]: ${fields['pickupPlace']}');
    print('🔍 fields[pickupPlaceDescription]: ${fields['pickupPlaceDescription']}');
    print('🔍 fields[pickupPlaceId]: ${fields['pickupPlaceId']}');
    print('🔍 fields[pickupDescription]: ${fields['pickupDescription']}');
    print('🔍 fields[pickup]: ${fields['pickup']}');
    
    // If pickup is not enabled, return meet on location
    if (fields['pickup'] != true) {
      print('ℹ️ Pickup not enabled, returning "Meet on location"');
      return 'Meet on location';
    }
    
    // PRIORITY 1: Check pickupPlace OBJECT (predefined pickup locations - shown with checkmark in Bokun UI)
    // According to Bokun API, PickupDropoffPlace has: title (required), address (required)
    final pickupPlaceResult = _extractPickupFromPickupPlaceObject(fields['pickupPlace']);
    if (pickupPlaceResult != null && !_isPlaceholderPickup(pickupPlaceResult)) {
      print('✅ FINAL: Using pickupPlace object: $pickupPlaceResult');
      return pickupPlaceResult;
    }
    
    // Also check at productBooking level
    final productPickupPlaceResult = _extractPickupFromPickupPlaceObject(productBooking['pickupPlace']);
    if (productPickupPlaceResult != null && !_isPlaceholderPickup(productPickupPlaceResult)) {
      print('✅ FINAL: Using productBooking.pickupPlace object: $productPickupPlaceResult');
      return productPickupPlaceResult;
    }
    
    // PRIORITY 2: Check pickupPlaceDescription (free text/custom locations)
    if (fields['pickupPlaceDescription'] != null) {
      final description = fields['pickupPlaceDescription'].toString().trim();
      if (description.isNotEmpty && !_isPlaceholderPickup(description)) {
        print('✅ FINAL: Using pickupPlaceDescription: $description');
        return description;
      }
    }
    
    // Also check pickupDescription
    if (fields['pickupDescription'] != null) {
      final description = fields['pickupDescription'].toString().trim();
      if (description.isNotEmpty && !_isPlaceholderPickup(description)) {
        print('✅ FINAL: Using pickupDescription: $description');
        return description;
      }
    }
    
    // PRIORITY 3: Check supplier notes for pickup changes
    final notesPickup = _extractPickupFromNotes(productBooking['notes']);
    if (notesPickup != null && !_isPlaceholderPickup(notesPickup)) {
      print('✅ FINAL: Using notes pickup: $notesPickup');
      return notesPickup;
    }
    
    // PRIORITY 4: Check priceCategoryBookings for pickup answers
    if (fields['priceCategoryBookings'] != null && fields['priceCategoryBookings'] is List) {
      final priceCategoryBookings = fields['priceCategoryBookings'] as List;
      for (final priceBooking in priceCategoryBookings) {
        // Check answers array
        if (priceBooking['answers'] != null && priceBooking['answers'] is List) {
          final answers = priceBooking['answers'] as List;
          for (final answer in answers) {
            if (answer is Map) {
              final question = answer['question']?.toString().toLowerCase() ?? '';
              final answerText = answer['answer']?.toString().trim() ?? '';
              if ((question.contains('pickup') || question.contains('pick-up') || question.contains('pick up')) && 
                  answerText.isNotEmpty && !_isPlaceholderPickup(answerText)) {
                print('✅ FINAL: Using priceCategoryBookings answer: $answerText');
                return answerText;
              }
            }
          }
        }
        
        // Check bookingAnswers array
        if (priceBooking['bookingAnswers'] != null && priceBooking['bookingAnswers'] is List) {
          final answers = priceBooking['bookingAnswers'] as List;
          for (final answer in answers) {
            if (answer is Map) {
              final question = answer['question']?.toString().toLowerCase() ?? '';
              final answerText = answer['answer']?.toString().trim() ?? '';
              if ((question.contains('pickup') || question.contains('pick-up') || question.contains('pick up')) && 
                  answerText.isNotEmpty && !_isPlaceholderPickup(answerText)) {
                print('✅ FINAL: Using priceCategoryBookings bookingAnswer: $answerText');
                return answerText;
              }
            }
          }
        }
      }
    }
    
    // PRIORITY 5: Check main booking answers
    if (booking['answers'] != null && booking['answers'] is List) {
      final answers = booking['answers'] as List;
      for (final answer in answers) {
        if (answer is Map) {
          final question = answer['question']?.toString().toLowerCase() ?? '';
          final answerText = answer['answer']?.toString().trim() ?? '';
          if ((question.contains('pickup') || question.contains('pick-up') || question.contains('pick up')) && 
              answerText.isNotEmpty && !_isPlaceholderPickup(answerText)) {
            print('✅ FINAL: Using main booking answer: $answerText');
            return answerText;
          }
        }
      }
    }
    
    // PRIORITY 6: Check productBooking answers
    if (productBooking['answers'] != null && productBooking['answers'] is List) {
      final answers = productBooking['answers'] as List;
      for (final answer in answers) {
        if (answer is Map) {
          final question = answer['question']?.toString().toLowerCase() ?? '';
          final answerText = answer['answer']?.toString().trim() ?? '';
          if ((question.contains('pickup') || question.contains('pick-up') || question.contains('pick up')) && 
              answerText.isNotEmpty && !_isPlaceholderPickup(answerText)) {
            print('✅ FINAL: Using productBooking answer: $answerText');
            return answerText;
          }
        }
      }
    }
    
    // PRIORITY 7: Check pickupAnswers at various levels
    for (final source in [booking, productBooking, fields]) {
      if (source['pickupAnswers'] != null && source['pickupAnswers'] is List) {
        final pickupAnswers = source['pickupAnswers'] as List;
        for (final answer in pickupAnswers) {
          if (answer is Map && answer['answer'] != null) {
            final answerText = answer['answer'].toString().trim();
            if (answerText.isNotEmpty && !_isPlaceholderPickup(answerText)) {
              print('✅ FINAL: Using pickupAnswers: $answerText');
              return answerText;
            }
          } else if (answer is String && answer.trim().isNotEmpty && !_isPlaceholderPickup(answer)) {
            print('✅ FINAL: Using pickupAnswers (string): ${answer.trim()}');
            return answer.trim();
          }
        }
      }
    }
    
    // PRIORITY 8: Check specialRequests
    if (productBooking['specialRequests'] != null) {
      final specialRequests = productBooking['specialRequests'].toString().trim();
      if (specialRequests.isNotEmpty && 
          (specialRequests.toLowerCase().contains('pickup') || 
           specialRequests.toLowerCase().contains('pick up') ||
           specialRequests.toLowerCase().contains('bus stop') ||
           specialRequests.toLowerCase().contains('hotel'))) {
        print('✅ FINAL: Using specialRequests: $specialRequests');
        return specialRequests;
      }
    }
    
    // PRIORITY 9: Check room number as last resort
    if (fields['pickupPlaceRoomNumber'] != null && 
        fields['pickupPlaceRoomNumber'].toString().trim().isNotEmpty) {
      final roomNumber = fields['pickupPlaceRoomNumber'].toString().trim();
      print('✅ FINAL: Using room number: Room $roomNumber');
      return 'Room $roomNumber';
    }
    
    // FALLBACK: Return placeholder values if they exist, otherwise "Pickup pending"
    if (fields['pickupPlaceDescription'] != null) {
      final description = fields['pickupPlaceDescription'].toString().trim();
      if (description.isNotEmpty) {
        print('ℹ️ FINAL: Returning placeholder pickup: $description');
        return description;
      }
    }
    
    print('ℹ️ FINAL: No pickup found, returning "Pickup pending"');
    return 'Pickup pending';
  }

  /// Helper to get normalized date key (YYYY-MM-DD format)
  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Fetch bookings for a PAST date using alternative strategies
  /// Strategy 1: Wide date range that includes today (most likely to work!)
  /// Strategy 2: Query by creationDateRange instead of startDateRange
  /// Strategy 3: Fall back to Firebase cached data
  Future<List<PickupBooking>> _fetchPastBookings(DateTime date) async {
    final dateKey = _getDateKey(date);
    print('📅 Attempting to fetch PAST bookings for: $dateKey');
    
    // Strategy 1: Try with a wide date range that ENDS today
    // Bokun likely only checks if the START is too far in the past
    try {
      print('🔄 Strategy 1: Trying wide date range ending today...');
      
      final now = DateTime.now();
      final startDate = DateTime(date.year, date.month, date.day);
      // End at today 23:59:59 (not in the past!)
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      
      Map<String, dynamic> data;
      
      // On web, use Cloud Function
      if (kIsWeb) {
        print('🌐 Using Cloud Function for past bookings (web)');
        data = await _fetchBookingsViaCloudFunction(
          startDate.toUtc().toIso8601String(),
          endDate.toUtc().toIso8601String(),
        );
      } else {
        // On mobile, use direct API call
        final requestBody = {
          'startDateRange': {
            'from': startDate.toUtc().toIso8601String(),
            'to': endDate.toUtc().toIso8601String(),
          }
        };
        
        final bodyJson = json.encode(requestBody);
        print('📤 Request Body (wide range): $bodyJson');
        print('📅 Date range: ${_getDateKey(startDate)} to ${_getDateKey(endDate)}');
        
        // Use current time for the signature (not the past date!)
        final response = await http.post(
          Uri.parse('$_baseUrl/booking.json/booking-search'),
          headers: _getHeaders(bodyJson, requestDate: now),
          body: bodyJson,
        );
        
        print('📡 Wide range response status: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          data = json.decode(response.body);
        } else {
          throw Exception('Bokun API Error (${response.statusCode}): ${response.body}');
        }
      }
      
      final items = data['items'] as List<dynamic>? ?? [];
      print('✅ Wide range query succeeded! Got ${items.length} total bookings');
        
        // Filter to only the specific date we want
        final bookings = <PickupBooking>[];
        for (final booking in items) {
          try {
            // Filter to only valid productBookings (handles rescheduled bookings)
            final productBookings = booking['productBookings'] as List<dynamic>? ?? [];
            if (productBookings.isEmpty) continue;
            
            final validProductBookings = productBookings.where((pb) {
              final status = pb['status']?.toString().toUpperCase() ?? '';
              return _isValidBookingStatus(status);
            }).toList();
            
            if (validProductBookings.isEmpty) continue;
            
            // _parseBokunBooking will use the first valid productBooking
            final parsed = _parseBokunBooking(booking);
            if (parsed != null) {
              final bookingDate = parsed.pickupTime;
              // Check if this booking is for our target date
              if (bookingDate.year == date.year &&
                  bookingDate.month == date.month &&
                  bookingDate.day == date.day) {
                bookings.add(parsed);
                print('✅ Found booking for $dateKey: ${parsed.customerFullName}');
              }
            }
          } catch (e) {
            print('⚠️ Error parsing booking in wide range: $e');
          }
        }
        
        print('📋 Filtered to ${bookings.length} bookings for $dateKey');
        
        if (bookings.isNotEmpty) {
          // Cache these for next time!
          await FirebaseService.cacheBookings(date: dateKey, bookings: bookings);
          return bookings;
        }
    } catch (e) {
      print('❌ Strategy 1 failed: $e');
    }
    
    // Strategy 2: Try creationDateRange (when booking was made, not tour date)
    // Note: This strategy might not work well with Cloud Function as it uses a different query type
    // For now, skip this on web and only try on mobile where we have full API access
    if (!kIsWeb) {
      try {
        print('🔄 Strategy 2: Trying creationDateRange...');
        
        final now = DateTime.now();
        // Query bookings created in the last 60 days
        final sixtyDaysAgo = now.subtract(const Duration(days: 60));
        
        final requestBody = {
          'creationDateRange': {
            'from': sixtyDaysAgo.toUtc().toIso8601String(),
            'to': now.toUtc().toIso8601String(),
          }
        };
        
        final bodyJson = json.encode(requestBody);
        print('📤 Request Body (creationDateRange): $bodyJson');
        
        final response = await http.post(
          Uri.parse('$_baseUrl/booking.json/booking-search'),
          headers: _getHeaders(bodyJson, requestDate: now),
          body: bodyJson,
        );
        
        print('📡 creationDateRange response status: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final items = data['items'] as List<dynamic>? ?? [];
          print('✅ creationDateRange query succeeded! Got ${items.length} total bookings');
        
        // Filter to only bookings with tour date matching our target
        final bookings = <PickupBooking>[];
        for (final booking in items) {
          try {
            // Filter to only valid productBookings (handles rescheduled bookings)
            final productBookings = booking['productBookings'] as List<dynamic>? ?? [];
            if (productBookings.isEmpty) continue;
            
            final validProductBookings = productBookings.where((pb) {
              final status = pb['status']?.toString().toUpperCase() ?? '';
              return _isValidBookingStatus(status);
            }).toList();
            
            if (validProductBookings.isEmpty) continue;
            
            // _parseBokunBooking will use the first valid productBooking
            final parsed = _parseBokunBooking(booking);
            if (parsed != null) {
              final bookingDate = parsed.pickupTime;
              if (bookingDate.year == date.year &&
                  bookingDate.month == date.month &&
                  bookingDate.day == date.day) {
                bookings.add(parsed);
                print('✅ Found booking for $dateKey: ${parsed.customerFullName}');
              }
            }
          } catch (e) {
            print('⚠️ Error parsing booking in creationDateRange: $e');
          }
        }
        
        print('📋 Filtered to ${bookings.length} bookings with tour date $dateKey');
        
        if (bookings.isNotEmpty) {
          await FirebaseService.cacheBookings(date: dateKey, bookings: bookings);
          return bookings;
        }
        } else {
          print('❌ creationDateRange query failed: ${response.statusCode}');
          print('📄 Error response: ${response.body}');
        }
      } catch (e) {
        print('❌ Strategy 2 failed: $e');
      }
    } else {
      print('⚠️ Strategy 2 (creationDateRange) skipped on web - Cloud Function uses startDateRange only');
    }
    
    // Strategy 3: Fall back to Firebase cached data
    print('🔄 Strategy 3: Checking Firebase cache for past bookings...');
    try {
      final cachedBookings = await FirebaseService.getCachedBookings(dateKey);
      if (cachedBookings.isNotEmpty) {
        print('✅ Found ${cachedBookings.length} cached bookings in Firebase for $dateKey');
        return cachedBookings;
      } else {
        print('⚠️ No cached bookings found for $dateKey');
      }
    } catch (e) {
      print('❌ Firebase cache lookup failed: $e');
    }
    
    print('⚠️ All strategies exhausted for past date $dateKey - returning empty list');
    return [];
  }

  // Fetch bookings via Cloud Function using HTTP (for web - avoids Int64 issues with cloud_functions package)
  Future<Map<String, dynamic>> _fetchBookingsViaCloudFunction(
    String startDate,
    String endDate,
  ) async {
    try {
      print('☁️ Calling Cloud Function getBookings via HTTP');
      print('📅 Date range: $startDate to $endDate');
      
      // Get Firebase auth token for authentication
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      final token = await user.getIdToken();
      
      // Call Cloud Function via HTTP (2nd Gen callable function endpoint)
      final response = await http.post(
        Uri.parse('https://us-central1-aurora-viking-staff.cloudfunctions.net/getBookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'data': {
            'startDate': startDate,
            'endDate': endDate,
          }
        }),
      );
      
      print('📡 Cloud Function HTTP response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // 2nd Gen callable functions return result in 'result' key
        final data = responseData['result'] as Map<String, dynamic>;
        print('✅ Cloud Function returned ${data['items']?.length ?? 0} bookings');
        return data;
      } else {
        print('❌ Cloud Function error response: ${response.body}');
        throw Exception('Cloud Function error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Cloud Function HTTP error: $e');
      rethrow;
    }
  }

  // Fetch bookings from Bokun API for a specific date
  Future<List<PickupBooking>> fetchBookingsForDate(DateTime date) async {
    print('🔍 DEBUG: fetchBookingsForDate called with date: $date');
    print('🔍 DEBUG: Date components - Year: ${date.year}, Month: ${date.month}, Day: ${date.day}');
    print('🔍 DEBUG: Date timezone: ${date.timeZoneName}');
    try {
      // Check if API credentials are available (only needed for mobile, not web)
      if (!kIsWeb && !_hasApiCredentials) {
        print('❌ Pickup Service: Bokun API credentials not found in .env file.');
        print('Access Key: ${_accessKey.isEmpty ? "MISSING" : "FOUND"}');
        print('Secret Key: ${_secretKey.isEmpty ? "MISSING" : "FOUND"}');
        return [];
      }

      // Determine if this is a past date
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final requestedDate = DateTime(date.year, date.month, date.day);
      final isPastDate = requestedDate.isBefore(today);
      
      // Also check if more than 30 days ago (Bokun's hard limit)
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final isTooOld = requestedDate.isBefore(thirtyDaysAgo);
      
      if (isTooOld) {
        print('📅 Date is more than 30 days ago - checking Firebase cache only');
        final cachedBookings = await FirebaseService.getCachedBookings(_getDateKey(date));
        if (cachedBookings.isNotEmpty) {
          print('✅ Found ${cachedBookings.length} cached bookings for old date');
          return cachedBookings;
        }
        print('⚠️ No cached data available for date more than 30 days ago');
        return [];
      }
      
      if (isPastDate) {
        print('📅 Requested date is in the PAST (but within 30 days) - using alternative fetch strategy');
        return await _fetchPastBookings(date);
      }

      if (kIsWeb) {
        print('✅ Pickup Service: Using Cloud Function (web - API keys secured server-side)');
      } else {
        print('✅ Pickup Service: Bokun API credentials found. Making direct API request (mobile)...');
      }
      print('📅 Fetching bookings for date: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');

      final startDate = DateTime(date.year, date.month, date.day);
      final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

      // On web, use Cloud Function to keep API keys secure
      // On mobile, use direct API call (keys are in .env which isn't deployed)
      Map<String, dynamic> data;
      
      if (kIsWeb) {
        print('🌐 Using Cloud Function (web)');
        data = await _retryOnTransientError(() => _fetchBookingsViaCloudFunction(
          startDate.toUtc().toIso8601String(),
          endDate.toUtc().toIso8601String(),
        ));
      } else {
        print('📱 Using direct API call (mobile)');
        final url = '$_baseUrl/booking.json/booking-search';
        print('🌐 Pickup API URL: $url');

        final requestBody = {
          'startDateRange': {
            'from': startDate.toUtc().toIso8601String(),
            'to': endDate.toUtc().toIso8601String(),
          }
        };

        // Debug: Print exact date range being sent
        print('🔍 DEBUG: Requesting bookings for single day only');
        print('🔍 DEBUG: startDate (local): $startDate');
        print('🔍 DEBUG: endDate (local): $endDate');
        print('🔍 DEBUG: startDate (UTC): ${startDate.toUtc()}');
        print('🔍 DEBUG: endDate (UTC): ${endDate.toUtc()}');
        print('🔍 DEBUG: Date range spans: ${endDate.difference(startDate).inHours} hours');
        print('🔍 DEBUG: Request body date range: ${startDate.toUtc().toIso8601String()} to ${endDate.toUtc().toIso8601String()}');

        final bodyJson = json.encode(requestBody);
        print('📤 Pickup Request Body: $bodyJson');
        print('📅 Date Range: ${startDate.toUtc().toIso8601String()} to ${endDate.toUtc().toIso8601String()}');
        print('📅 Local Date Range: ${startDate.toLocal()} to ${endDate.toLocal()}');

        final response = await _retryOnTransientError(() => http.post(
          Uri.parse(url),
          headers: _getHeaders(bodyJson, requestDate: date),
          body: bodyJson,
        ));

        print('📡 Pickup API Response Status: ${response.statusCode}');
        print('📄 Pickup Response Headers: ${response.headers}');

        if (response.statusCode == 200) {
          data = json.decode(response.body);
        } else {
          // Parse error response to get more details
          try {
            final errorData = json.decode(response.body);
            final errorMessage = errorData['message'] ?? 'Unknown API error';
            print('❌ API Error Message: $errorMessage');
            throw Exception('Bokun API Error (${response.statusCode}): $errorMessage');
          } catch (e) {
            // If error parsing fails, throw generic exception
            if (e is Exception && e.toString().contains('Bokun API Error')) {
              rethrow;
            }
            throw Exception('Bokun API Error (${response.statusCode}): ${response.body}');
          }
        }
      }

      // Process the data (works for both web and mobile)
      print('✅ Pickup API call successful!');
      print('📊 Pickup Raw API response: ${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}...');
      
      final bookings = <PickupBooking>[];
      final filteredBookings = <PickupBooking>[];
      
      // Parse Bokun API response and convert to our model
      final items = data['items'] as List<dynamic>? ?? [];
      print('📊 Total hits from API: ${data['totalHits']}');
      print('📊 Items array length: ${items.length}');
      print('🔍 DEBUG: Processing ${items.length} bookings from API response');
      
      // Track dates for debugging
      final dateCounts = <String, int>{};
      
      for (final booking in items) {
        try {
          // CRITICAL FIX: Filter to only valid (non-cancelled) productBookings
          // When customers reschedule via Bokun portal, the old booking gets CANCELLED
          // and a new one is created under the same parent booking. We need to find
          // the valid one, not just take .first which might be the cancelled one.
          final productBookings = booking['productBookings'] as List<dynamic>? ?? [];
          
          if (productBookings.isEmpty) {
            print('⚠️ No productBookings found, skipping');
            continue;
          }
          
          // Filter to only valid productBookings
          final validProductBookings = productBookings.where((pb) {
            final status = pb['status']?.toString().toUpperCase() ?? '';
            return _isValidBookingStatus(status);
          }).toList();
          
          if (validProductBookings.isEmpty) {
            final customer = booking['customer'] ?? booking['leadCustomer'] ?? {};
            final customerName = '${customer['firstName'] ?? ''} ${customer['lastName'] ?? ''}'.trim();
            print('❌ No valid productBookings for $customerName - all are cancelled/invalid');
            continue;
          }
          
          // Use the first VALID productBooking (not just the first one in array)
          final productBooking = validProductBookings.first;
          
          // Debug: Show what we found
          final bookingStatus = productBooking['status']?.toString() ?? 'NO_STATUS';
          print('✅ Found valid productBooking with status: $bookingStatus');
          
          // Debug: Print the actual date of each booking being processed
          final startDate = productBooking['startDate'];
          final startDateTime = productBooking['startDateTime'];
          
          DateTime? bookingDate;
          if (startDate != null) {
            bookingDate = DateTime.fromMillisecondsSinceEpoch(startDate);
          } else if (startDateTime != null) {
            bookingDate = DateTime.parse(startDateTime);
          }
          
          if (bookingDate != null) {
            final dateKey = '${bookingDate.day}/${bookingDate.month}/${bookingDate.year}';
            dateCounts[dateKey] = (dateCounts[dateKey] ?? 0) + 1;
            print('🔍 DEBUG: Booking date: ${bookingDate.toLocal()} (${dateKey})');
          }
          
          final pickupBooking = _parseBokunBooking(booking);
          if (pickupBooking != null) {
            bookings.add(pickupBooking);
            
            // Filter bookings to only include the requested date
            final bookingDate = pickupBooking.pickupTime;
            final requestedDate = DateTime(date.year, date.month, date.day);
            
            if (bookingDate.year == requestedDate.year &&
                bookingDate.month == requestedDate.month &&
                bookingDate.day == requestedDate.day) {
              filteredBookings.add(pickupBooking);
              print('✅ Added booking for requested date: ${pickupBooking.customerFullName}');
            } else {
              print('❌ Filtered out booking for different date: ${pickupBooking.customerFullName} - ${bookingDate.day}/${bookingDate.month}/${bookingDate.year}');
            }
          }
        } catch (e) {
          print('Error parsing booking: $e');
        }
      }
      
      // Print date distribution summary
      print('📊 DEBUG: Date distribution from API:');
      dateCounts.forEach((dateKey, count) {
        print('  $dateKey: $count bookings');
      });
      
      print('📊 DEBUG: Total bookings before filtering: ${bookings.length}');
      print('📊 DEBUG: Total bookings after filtering: ${filteredBookings.length}');
      
      return filteredBookings;
    } catch (e) {
      // Re-throw API errors so controller can handle them (check cache, etc.)
      if (e is Exception && e.toString().contains('Bokun API Error')) {
        print('❌ Pickup Service: Re-throwing API error: $e');
        rethrow;
      }
      // For other unexpected errors, still throw but with context
      print('❌ Pickup Service: Unexpected error fetching bookings for date $date: $e');
      throw Exception('Failed to fetch bookings: $e');
    }
  }

  // Parse Bokun API booking data
  PickupBooking? _parseBokunBooking(Map<String, dynamic> booking) {
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
      
      // Filter to only valid productBookings (handles rescheduled bookings)
      final validProductBookings = productBookings.where((pb) {
        final status = pb['status']?.toString().toUpperCase() ?? '';
        return _isValidBookingStatus(status);
      }).toList();
      
      if (validProductBookings.isEmpty) {
        print('⚠️ No valid productBookings found for $customerFullName - all are cancelled/invalid');
        return null;
      }
      
      // Use the first valid product booking for pickup details
      final productBooking = validProductBookings.first;
      print('🔍 ProductBooking keys: ${productBooking.keys.toList()}');
      
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
            pickupTime = DateTime.now();
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
                            fields['totalParticipants'] ??
                            1;
      print('✅ Parsed guest count: $numberOfGuests');
      
      // Extract pickup location using the unified extraction method
      final pickupPlaceName = _extractPickupLocation(
        fields: fields,
        productBooking: productBooking,
        booking: booking,
      );
      
      // ===== TOUR GROUPING: Extract product/tour info =====
      final product = productBooking['product'] as Map<String, dynamic>?;
      final productId = product?['id']?.toString();
      final productTitle = product?['title']?.toString() ?? 
                          product?['name']?.toString() ??
                          'Northern Lights Tour';
      
      // Extract departure time (startTime in HH:mm format)
      String? departureTime;
      final startTimeValue = productBooking['startTime'];
      if (startTimeValue != null) {
        if (startTimeValue is String) {
          // Already in HH:mm format
          departureTime = startTimeValue;
        } else if (startTimeValue is int) {
          // Convert minutes since midnight to HH:mm
          final hours = startTimeValue ~/ 60;
          final minutes = startTimeValue % 60;
          departureTime = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
        }
      }
      // Fallback: Extract from fields if not in productBooking
      if (departureTime == null && fields['startHour'] != null && fields['startMinute'] != null) {
        final startHour = fields['startHour'];
        final startMinute = fields['startMinute'];
        if (startHour is int && startMinute is int) {
          departureTime = '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
        }
      }
      
      // Get startTimeId for unique departure identification
      final startTimeId = productBooking['startTimeId']?.toString() ??
                         productBooking['activityId']?.toString();
      
      // Detect if this is a private tour
      final isPrivateTour = _isPrivateTour(productTitle, productBooking, booking);
      
      print('🔍 === TOUR INFO ===');
      print('🔍 Product ID: $productId');
      print('🔍 Product Title: $productTitle');
      print('🔍 Departure Time: $departureTime');
      print('🔍 Is Private Tour: $isPrivateTour');
      print('🔍 ==================');
      
      print('🔍 === FINAL PICKUP RESULT ===');
      print('🔍 Customer: $customerFullName');
      print('🔍 Pickup Location: $pickupPlaceName');
      print('🔍 ===========================');

      // Extract booking ID for questions API calls
      final bookingId = productBooking['parentBookingId']?.toString() ?? 
                       productBooking['id']?.toString() ?? 
                       booking['id']?.toString();
      
      // Extract confirmation code for booking details API calls
      final confirmationCode = booking['confirmationCode']?.toString() ?? 
                              booking['externalBookingReference']?.toString() ??
                              productBooking['productConfirmationCode']?.toString();
      
      // Extract payment information
      bool isUnpaid = false;
      double? amountToPayOnArrival;
      
      // DEBUG: Print all booking keys to see what payment fields are available
      print('🔍 === PAYMENT DEBUG FOR ${customerFullName} ===');
      print('🔍 Booking keys: ${booking.keys.toList()}');
      print('🔍 ProductBooking keys: ${productBooking.keys.toList()}');
      
      // Check payment status from booking - try multiple possible field names
      String paymentStatus = '';
      if (booking['paymentStatus'] != null) {
        paymentStatus = booking['paymentStatus'].toString().toUpperCase();
        print('🔍 Found paymentStatus: $paymentStatus');
      } else if (booking['payment'] != null) {
        final payment = booking['payment'];
        if (payment is Map) {
          paymentStatus = payment['status']?.toString().toUpperCase() ?? '';
          print('🔍 Found payment.status: $paymentStatus');
          print('🔍 Payment object keys: ${payment.keys.toList()}');
        }
      } else if (booking['paymentStatusId'] != null) {
        paymentStatus = booking['paymentStatusId'].toString().toUpperCase();
        print('🔍 Found paymentStatusId: $paymentStatus');
      } else if (productBooking['paymentStatus'] != null) {
        paymentStatus = productBooking['paymentStatus'].toString().toUpperCase();
        print('🔍 Found productBooking.paymentStatus: $paymentStatus');
      }
      
      // Also check if there's a payment method that indicates pay on arrival
      final paymentMethod = booking['paymentMethod']?.toString().toUpperCase() ?? 
                          booking['payment']?['method']?.toString().toUpperCase() ?? '';
      if (paymentMethod.isNotEmpty) {
        print('🔍 Found paymentMethod: $paymentMethod');
      }
      
      // Check if unpaid (common statuses: UNPAID, NOT_PAID, PARTIALLY_PAID, PAY_ON_ARRIVAL, etc.)
      // CRITICAL FIX: Check for unpaid statuses FIRST with exact matches or NOT_ prefix check
      // This prevents "NOT_PAID" from being incorrectly matched as "PAID"
      bool isExplicitlyUnpaid = false;
      if (paymentStatus == 'NOT_PAID' || 
          paymentStatus == 'UNPAID' ||
          paymentStatus.startsWith('NOT_') ||
          paymentStatus.startsWith('UNPAID')) {
        isExplicitlyUnpaid = true;
      }
      
      // Check for common paid statuses (only if NOT explicitly unpaid)
      bool isExplicitlyPaid = false;
      if (!isExplicitlyUnpaid) {
        if (paymentStatus == 'PAID_IN_FULL' || 
            paymentStatus == 'FULLY_PAID' || 
            paymentStatus == 'COMPLETE' ||
            paymentStatus == 'PAID') {
          isExplicitlyPaid = true;
        }
      }
      
      if (isExplicitlyUnpaid) {
        isUnpaid = true;
        print('✅ Marked as UNPAID - explicit unpaid status: $paymentStatus');
      } else if (isExplicitlyPaid) {
        print('✅ Marked as PAID - explicit paid status: $paymentStatus');
      } else if (!isExplicitlyPaid && (paymentStatus.contains('PARTIALLY') || 
          paymentStatus.contains('PAY_ON_ARRIVAL') ||
          paymentStatus.contains('DUE') ||
          paymentMethod.contains('ARRIVAL') ||
          paymentMethod.contains('ON_SITE') ||
          paymentStatus.isEmpty)) {
        isUnpaid = true;
        print('✅ Marked as UNPAID based on status: $paymentStatus or method: $paymentMethod');
      }
      
      // Extract amount to pay on arrival
      // For unpaid bookings, we need the BALANCE DUE, not the total price
      // Try balance/due fields first, then calculate from total - paid
      
      // First, try to find balance due directly
      dynamic balanceDue;
      if (booking['balanceDue'] != null) {
        balanceDue = booking['balanceDue'];
        print('🔍 Found booking.balanceDue: $balanceDue');
      } else if (booking['amountDue'] != null) {
        balanceDue = booking['amountDue'];
        print('🔍 Found booking.amountDue: $balanceDue');
      } else if (booking['unpaidAmount'] != null) {
        balanceDue = booking['unpaidAmount'];
        print('🔍 Found booking.unpaidAmount: $balanceDue');
      } else if (booking['amountToPay'] != null) {
        balanceDue = booking['amountToPay'];
        print('🔍 Found booking.amountToPay: $balanceDue');
      } else if (productBooking['balanceDue'] != null) {
        balanceDue = productBooking['balanceDue'];
        print('🔍 Found productBooking.balanceDue: $balanceDue');
      } else if (productBooking['amountDue'] != null) {
        balanceDue = productBooking['amountDue'];
        print('🔍 Found productBooking.amountDue: $balanceDue');
      }
      
      // If we found balance due directly, use it
      if (balanceDue != null) {
        try {
          if (balanceDue is num) {
            amountToPayOnArrival = balanceDue.toDouble();
            print('✅ Using balance due (direct): $amountToPayOnArrival');
          } else if (balanceDue is String) {
            amountToPayOnArrival = double.tryParse(balanceDue);
            print('✅ Using balance due (parsed from string): $amountToPayOnArrival');
          }
        } catch (e) {
          print('⚠️ Error parsing balance due: $e');
        }
      }
      
      // If no balance due found, calculate it: totalPrice - paidAmount
      if (isUnpaid && (amountToPayOnArrival == null || amountToPayOnArrival == 0)) {
        print('🔍 Calculating balance due from total - paid...');
        
        // Get total price - try totalPriceAmount first (it's the actual amount, not just a flag)
        dynamic totalPrice;
        if (productBooking['totalPriceAmount'] != null) {
          totalPrice = productBooking['totalPriceAmount'];
          print('🔍 Found productBooking.totalPriceAmount: $totalPrice');
        } else if (booking['totalPriceAmount'] != null) {
          totalPrice = booking['totalPriceAmount'];
          print('🔍 Found booking.totalPriceAmount: $totalPrice');
        } else if (productBooking['totalPrice'] != null) {
          totalPrice = productBooking['totalPrice'];
          print('🔍 Found productBooking.totalPrice: $totalPrice');
        } else if (booking['totalPrice'] != null) {
          totalPrice = booking['totalPrice'];
          print('🔍 Found booking.totalPrice: $totalPrice');
        }
        
        // Also check invoice objects for total amount
        // Invoice objects often have the actual price information
        if ((totalPrice == null || (totalPrice is num && totalPrice == 0)) && productBooking['customerInvoice'] != null) {
          final invoice = productBooking['customerInvoice'];
          if (invoice is Map) {
            print('🔍 Checking productBooking.customerInvoice for amount...');
            print('🔍 customerInvoice keys: ${invoice.keys.toList()}');
            print('🔍 customerInvoice full object: $invoice');
            
            // Try multiple possible fields in invoice
            final invoiceTotal = invoice['total'] ?? 
                               invoice['totalAmount'] ?? 
                               invoice['amount'] ?? 
                               invoice['price'] ??
                               invoice['subtotal'] ??
                               invoice['totalPrice'] ??
                               invoice['grandTotal'];
            
            // Also check if it's nested in a money object
            if (invoiceTotal == null) {
              final totalMoney = invoice['totalMoney'] ?? invoice['totalAsMoney'];
              if (totalMoney is Map && totalMoney['amount'] != null) {
                totalPrice = totalMoney['amount'];
                print('🔍 Found customerInvoice.totalMoney.amount: $totalPrice');
              } else if (totalMoney is num) {
                totalPrice = totalMoney;
                print('🔍 Found customerInvoice.totalMoney (direct): $totalPrice');
              }
            } else {
              totalPrice = invoiceTotal;
              print('🔍 Found customerInvoice total: $totalPrice');
            }
          }
        }
        
        // Check booking-level invoice
        if ((totalPrice == null || (totalPrice is num && totalPrice == 0)) && booking['customerInvoice'] != null) {
          final invoice = booking['customerInvoice'];
          if (invoice is Map) {
            print('🔍 Checking booking.customerInvoice for amount...');
            print('🔍 booking.customerInvoice keys: ${invoice.keys.toList()}');
            print('🔍 booking.customerInvoice full object: $invoice');
            
            final invoiceTotal = invoice['total'] ?? 
                               invoice['totalAmount'] ?? 
                               invoice['amount'] ?? 
                               invoice['price'] ??
                               invoice['subtotal'] ??
                               invoice['totalPrice'] ??
                               invoice['grandTotal'];
            
            // Also check if it's nested in a money object
            if (invoiceTotal == null) {
              final totalMoney = invoice['totalMoney'] ?? invoice['totalAsMoney'];
              if (totalMoney is Map && totalMoney['amount'] != null) {
                totalPrice = totalMoney['amount'];
                print('🔍 Found booking.customerInvoice.totalMoney.amount: $totalPrice');
              } else if (totalMoney is num) {
                totalPrice = totalMoney;
                print('🔍 Found booking.customerInvoice.totalMoney (direct): $totalPrice');
              }
            } else {
              totalPrice = invoiceTotal;
              print('🔍 Found booking.customerInvoice total: $totalPrice');
            }
          }
        }
        
        // Get paid amount
        dynamic paidAmount;
        if (booking['paidAmount'] != null) {
          paidAmount = booking['paidAmount'];
          print('🔍 Found booking.paidAmount: $paidAmount');
        } else if (booking['paidAmountAsMoney'] != null) {
          // paidAmountAsMoney might be an object with amount field
          final paidMoney = booking['paidAmountAsMoney'];
          if (paidMoney is Map && paidMoney['amount'] != null) {
            paidAmount = paidMoney['amount'];
            print('🔍 Found booking.paidAmountAsMoney.amount: $paidAmount');
          } else if (paidMoney is num) {
            paidAmount = paidMoney;
            print('🔍 Found booking.paidAmountAsMoney (direct): $paidAmount');
          }
        } else if (productBooking['paidAmount'] != null) {
          paidAmount = productBooking['paidAmount'];
          print('🔍 Found productBooking.paidAmount: $paidAmount');
        }
        
        // Calculate balance: total - paid
        if (totalPrice != null) {
          double? totalPriceNum;
          double? paidAmountNum;
          
          try {
            if (totalPrice is num) {
              totalPriceNum = totalPrice.toDouble();
            } else if (totalPrice is String) {
              totalPriceNum = double.tryParse(totalPrice);
            }
            
            if (paidAmount != null) {
              if (paidAmount is num) {
                paidAmountNum = paidAmount.toDouble();
              } else if (paidAmount is String) {
                paidAmountNum = double.tryParse(paidAmount);
              }
            } else {
              paidAmountNum = 0.0; // If no paid amount, assume 0
            }
            
            if (totalPriceNum != null && totalPriceNum > 0 && paidAmountNum != null) {
              amountToPayOnArrival = totalPriceNum - paidAmountNum;
              print('✅ Calculated balance due: $totalPriceNum - $paidAmountNum = $amountToPayOnArrival');
              
              // Only use if the result is positive (there's actually something to pay)
              if (amountToPayOnArrival <= 0) {
                print('⚠️ Calculated balance is 0 or negative, setting to null');
                amountToPayOnArrival = null;
              }
            } else {
              print('⚠️ Cannot calculate balance - totalPrice: $totalPriceNum, paidAmount: $paidAmountNum');
            }
          } catch (e) {
            print('⚠️ Error calculating balance due: $e');
          }
        }
      }
      
      // If still no amount and unpaid, try payment object
      if (isUnpaid && (amountToPayOnArrival == null || amountToPayOnArrival == 0)) {
        final payment = booking['payment'];
        if (payment != null && payment is Map) {
          print('🔍 Checking payment object for amount...');
          print('🔍 Payment object keys: ${payment.keys.toList()}');
          final paymentAmount = payment['balance'] ?? 
                               payment['amountDue'] ?? 
                               payment['balanceDue'] ??
                               payment['unpaidAmount'] ??
                               payment['amount'];
          if (paymentAmount != null) {
            print('🔍 Found payment amount: $paymentAmount');
            try {
              if (paymentAmount is num) {
                amountToPayOnArrival = paymentAmount.toDouble();
              } else if (paymentAmount is String) {
                amountToPayOnArrival = double.tryParse(paymentAmount);
              }
              print('✅ Parsed payment amount: $amountToPayOnArrival');
            } catch (e) {
              print('⚠️ Error parsing payment amount from payment object: $e');
            }
          }
        }
      }
      
      print('💰 FINAL Payment info - Unpaid: $isUnpaid, Amount: $amountToPayOnArrival, Status: $paymentStatus, Method: $paymentMethod');
      print('🔍 === END PAYMENT DEBUG ===');
      
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
        confirmationCode: confirmationCode,
        isUnpaid: isUnpaid,
        amountToPayOnArrival: amountToPayOnArrival,
        productId: productId,
        productTitle: productTitle,
        departureTime: departureTime,
        startTimeId: startTimeId,
        isPrivateTour: isPrivateTour,
      );
      
      print('✅ Successfully parsed booking: ${pickupBooking.customerFullName} - ${pickupBooking.pickupPlaceName} - ${pickupBooking.numberOfGuests} guests - ${pickupBooking.pickupTime} (Tour: $productTitle @ $departureTime)');
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

  // Mark or unmark booking as no-show
  Future<bool> markBookingAsNoShow(String bookingId, {bool isNoShow = true}) async {
    try {
      // In a real implementation, this would update the backend
      // For now, we'll just return success
      // The actual state is managed in Firebase via the controller
      await Future.delayed(const Duration(milliseconds: 500));
      print('${isNoShow ? "Marked" : "Unmarked"} booking $bookingId as ${isNoShow ? "no-show" : "not no-show"}');
      return true;
    } catch (e) {
      print('Error ${isNoShow ? "marking" : "unmarking"} booking as no-show: $e');
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

    if (guideLists.isEmpty || bookings.isEmpty) return guideLists;

    // ======================================================
    // Step 1: Group bookings by normalised pickup place name.
    //         Fuzzy-match handles OTA naming differences
    //         (e.g. "Harpa" vs "Harpa Concert Hall").
    // ======================================================
    final groups = _groupByPickupPlace(bookings);
    print('📍 Grouped ${bookings.length} bookings into ${groups.length} pickup-place groups');

    // ======================================================
    // Step 2: Sort groups by size DESCENDING (largest first).
    //         Placing big groups first gives much better
    //         balanced bin-packing across guides.
    // ======================================================
    groups.sort((a, b) {
      final aPax = a.fold<int>(0, (s, bk) => s + bk.numberOfGuests);
      final bPax = b.fold<int>(0, (s, bk) => s + bk.numberOfGuests);
      return bPax.compareTo(aPax);
    });

    // ======================================================
    // Step 3: Assign each group (NEVER split) to the guide
    //         with the fewest passengers that can fit it.
    //         Classic largest-first bin-packing.
    // ======================================================
    for (final group in groups) {
      final groupPax = group.fold<int>(0, (s, b) => s + b.numberOfGuests);

      // Find guide with fewest passengers that can fit this group
      int bestIdx = -1;
      int bestPax = 999999;
      for (int i = 0; i < guideLists.length; i++) {
        final gl = guideLists[i];
        if (gl.totalPassengers + groupPax <= _maxPassengersPerBus &&
            gl.totalPassengers < bestPax) {
          bestPax = gl.totalPassengers;
          bestIdx = i;
        }
      }

      // If no guide can fit within limit, assign to emptiest guide
      // (group stays whole — NEVER split)
      if (bestIdx == -1) {
        int fewestPax = 999999;
        for (int i = 0; i < guideLists.length; i++) {
          if (guideLists[i].totalPassengers < fewestPax) {
            fewestPax = guideLists[i].totalPassengers;
            bestIdx = i;
          }
        }
      }

      if (bestIdx == -1) bestIdx = 0;
      _assignGroupToGuide(guideLists, bestIdx, group);
      print('🚌 ${group.first.pickupPlaceName} (${groupPax}pax) → ${guideLists[bestIdx].guideName} (${guideLists[bestIdx].totalPassengers}pax)');
    }

    // ======================================================
    // Step 4: Rebalance — if any guide has 0 bookings, take
    //         trailing alphabetical groups from the heaviest.
    // ======================================================
    for (int i = 0; i < guideLists.length; i++) {
      if (guideLists[i].bookings.isNotEmpty) continue;

      // Find heaviest guide
      int heaviestIdx = 0;
      for (int j = 1; j < guideLists.length; j++) {
        if (guideLists[j].totalPassengers > guideLists[heaviestIdx].totalPassengers) {
          heaviestIdx = j;
        }
      }

      if (guideLists[heaviestIdx].bookings.length <= 1) continue;

      // Move trailing groups (by pickup place) from heaviest to empty guide
      final heavyBookings = List<PickupBooking>.from(guideLists[heaviestIdx].bookings);
      // Group by place within this guide's bookings
      final placeGroups = <String, List<PickupBooking>>{};
      for (final b in heavyBookings) {
        placeGroups.putIfAbsent(b.pickupPlaceName, () => []).add(b);
      }
      final placeKeys = placeGroups.keys.toList();

      // Move trailing groups until reasonably balanced
      final emptyTarget = guideLists[i];
      final movedBookings = <PickupBooking>[];
      int movedPax = 0;
      final halfLoad = guideLists[heaviestIdx].totalPassengers ~/ 2;

      while (placeKeys.isNotEmpty && movedPax < halfLoad) {
        final lastPlace = placeKeys.removeLast();
        final placePax = placeGroups[lastPlace]!.fold<int>(0, (s, b) => s + b.numberOfGuests);
        if (movedPax + placePax > _maxPassengersPerBus) break;
        movedBookings.addAll(placeGroups[lastPlace]!);
        movedPax += placePax;
      }

      if (movedBookings.isNotEmpty) {
        // Remove from heavy guide
        final remainingHeavy = heavyBookings.where((b) => !movedBookings.contains(b)).toList();
        final remainingPax = remainingHeavy.fold<int>(0, (s, b) => s + b.numberOfGuests);
        guideLists[heaviestIdx] = guideLists[heaviestIdx].copyWith(
          bookings: remainingHeavy,
          totalPassengers: remainingPax,
        );

        // Add to empty guide
        final updatedMoved = movedBookings.map((b) => b.copyWith(
          assignedGuideId: emptyTarget.guideId,
          assignedGuideName: emptyTarget.guideName,
        )).toList();
        guideLists[i] = emptyTarget.copyWith(
          bookings: updatedMoved,
          totalPassengers: movedPax,
        );

        print('⚖️ Rebalanced: moved ${movedBookings.length} bookings ($movedPax pax) from ${guideLists[heaviestIdx].guideName} → ${emptyTarget.guideName}');
      }
    }

    // ======================================================
    // Step 5: Sort each guide's bookings alphabetically by
    //         pickup place (the learning module will re-sort
    //         after this if route history exists).
    // ======================================================
    for (int i = 0; i < guideLists.length; i++) {
      final gl = guideLists[i];
      if (gl.bookings.length <= 1) continue;
      final sorted = List<PickupBooking>.from(gl.bookings)
        ..sort((a, b) {
          final placeCompare = a.pickupPlaceName.compareTo(b.pickupPlaceName);
          if (placeCompare != 0) return placeCompare;
          return a.customerFullName.compareTo(b.customerFullName);
        });
      guideLists[i] = gl.copyWith(bookings: sorted);
    }

    final totalAssigned = guideLists.fold<int>(0, (s, gl) => s + gl.totalPassengers);
    final totalInput = bookings.fold<int>(0, (s, b) => s + b.numberOfGuests);
    print('✅ Distribution complete: $totalAssigned / $totalInput guests assigned to ${guideLists.length} guides');
    for (final gl in guideLists) {
      final places = gl.bookings.map((b) => b.pickupPlaceName).toSet();
      print('  📋 ${gl.guideName}: ${gl.totalPassengers} pax, ${places.length} stops: ${places.join(", ")}');
    }

    return guideLists;
  }

  /// Assign an entire group of bookings to the guide at [guideIdx].
  void _assignGroupToGuide(
    List<GuidePickupList> guideLists,
    int guideIdx,
    List<PickupBooking> group,
  ) {
    final target = guideLists[guideIdx];
    final updatedBookings = List<PickupBooking>.from(target.bookings);
    int addedPax = 0;
    for (final booking in group) {
      updatedBookings.add(booking.copyWith(
        assignedGuideId: target.guideId,
        assignedGuideName: target.guideName,
      ));
      addedPax += booking.numberOfGuests;
    }
    guideLists[guideIdx] = target.copyWith(
      bookings: updatedBookings,
      totalPassengers: target.totalPassengers + addedPax,
    );
  }

  /// Group bookings by normalised pickup place name.
  /// Uses fuzzy matching so "Bus Stop X" and "Bus Stop x - City" merge.
  List<List<PickupBooking>> _groupByPickupPlace(List<PickupBooking> bookings) {
    // Canonical key → list of bookings
    final map = <String, List<PickupBooking>>{};
    // Canonical key → original display name (first occurrence)
    final canonicalNames = <String, String>{};

    for (final b in bookings) {
      final key = _normalisePickupName(b.pickupPlaceName);

      // Try fuzzy merge: check if this key is a prefix/suffix of an existing key
      String? matchedKey;
      for (final existing in map.keys) {
        if (_fuzzyMatch(key, existing)) {
          matchedKey = existing;
          break;
        }
      }

      final finalKey = matchedKey ?? key;
      map.putIfAbsent(finalKey, () => []);
      map[finalKey]!.add(b);
      canonicalNames.putIfAbsent(finalKey, () => b.pickupPlaceName);
    }

    return map.values.toList();
  }

  /// Normalise a pickup place name for grouping.
  String _normalisePickupName(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // strip punctuation
        .replaceAll(RegExp(r'\s+'), ' ');        // collapse whitespace
  }

  /// Fuzzy match: true only if the names are very similar.
  /// Strict matching to avoid merging different bus stops.
  bool _fuzzyMatch(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;

    // Only do contains-match when the contained string is very long
    // (prevents "bus stop 1" matching "bus stop 10")
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length > b.length ? a : b;

    // If shorter string is long enough AND the longer string equals
    // shorter + some suffix that starts with a non-alphanumeric char
    // (e.g. "Harpa" matches "Harpa, Austurbakki 2" but not "Harpa Concert")
    if (shorter.length >= 6 && longer.startsWith(shorter)) {
      // Check that the character right after the match is non-alphanumeric
      // (comma, space-dash, etc.) — not a continuation of a word/number
      if (longer.length > shorter.length) {
        final nextChar = longer[shorter.length];
        if (nextChar == ',' || nextChar == '-' || nextChar == '(' || nextChar == '/') {
          return true;
        }
      }
    }

    // Long common prefix: ≥85% of the shorter string AND at least 10 chars
    int common = 0;
    for (int i = 0; i < shorter.length; i++) {
      if (shorter[i] == longer[i]) {
        common++;
      } else {
        break;
      }
    }
    return common >= 10 && common >= (shorter.length * 0.85);
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