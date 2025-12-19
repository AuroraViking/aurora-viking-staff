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

  // Fetch bookings from Bokun API for a specific date
  Future<List<PickupBooking>> fetchBookingsForDate(DateTime date) async {
    print('🔍 DEBUG: fetchBookingsForDate called with date: $date');
    print('🔍 DEBUG: Date components - Year: ${date.year}, Month: ${date.month}, Day: ${date.day}');
    print('🔍 DEBUG: Date timezone: ${date.timeZoneName}');
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
            // Debug: Print the actual date of each booking being processed
            final productBookings = booking['productBookings'] as List<dynamic>? ?? [];
            if (productBookings.isNotEmpty) {
              final productBooking = productBookings.first;
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
            }
            
            // Check booking status - only process CONFIRMED bookings
            bool isConfirmed = false;
            String bookingStatus = 'UNKNOWN';
            
            if (productBookings.isNotEmpty) {
              final productBooking = productBookings.first;
              bookingStatus = productBooking['status']?.toString() ?? 'NO_STATUS';
              isConfirmed = bookingStatus == 'CONFIRMED';
              
              // Also check main booking status
              final mainBookingStatus = booking['status']?.toString() ?? 'NO_MAIN_STATUS';
              if (mainBookingStatus == 'CONFIRMED') {
                isConfirmed = true;
              }
              
              print('🔍 DEBUG: Booking status - Product: $bookingStatus, Main: $mainBookingStatus, IsConfirmed: $isConfirmed');
            }
            
            // Only process confirmed bookings
            if (!isConfirmed) {
              final customer = booking['customer'] ?? booking['leadCustomer'] ?? {};
              final customerFullName = '${customer['firstName'] ?? ''} ${customer['lastName'] ?? ''}'.trim();
              print('❌ Skipping non-confirmed booking: $customerFullName (Status: $bookingStatus)');
              continue;
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
      } else {
        print('❌ Pickup API Error: ${response.statusCode}');
        print('📄 Pickup Error Response: ${response.body}');
        
        // Parse error response to get more details
        try {
          final errorData = json.decode(response.body);
          final errorMessage = errorData['message'] ?? 'Unknown API error';
          print('❌ API Error Message: $errorMessage');
          
          // Throw exception with error details so controller can handle it
          throw Exception('Bokun API Error (${response.statusCode}): $errorMessage');
        } catch (e) {
          // If error parsing fails, throw generic exception
          if (e is Exception && e.toString().contains('Bokun API Error')) {
            rethrow;
          }
          throw Exception('Bokun API Error (${response.statusCode}): ${response.body}');
        }
      }
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
      
      // Use the first product booking for pickup details
      final productBooking = productBookings.first;
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