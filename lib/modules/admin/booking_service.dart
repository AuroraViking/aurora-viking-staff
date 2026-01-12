// Booking Service for Bokun API integration
// Handles fetching, rescheduling, and cancelling bookings

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class BookingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Cloud Function base URL - update for your project
  static const String _functionsBaseUrl = 
      'https://us-central1-aurora-viking-staff.cloudfunctions.net';

  /// Get bookings for a date range from the existing getBookings cloud function
  Future<List<Booking>> getBookingsForDateRange(DateTime start, DateTime end) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      
      final token = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/getBookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'startDate': _formatDate(start),
          'endDate': _formatDate(end),
        }),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch bookings: ${response.body}');
      }
      
      final data = jsonDecode(response.body);
      final result = data['result'];
      
      if (result == null || result['items'] == null) {
        return [];
      }
      
      final items = result['items'] as List;
      return items.map((item) => Booking.fromBokunJson(item)).toList();
    } catch (e) {
      print('❌ Error fetching bookings: $e');
      rethrow;
    }
  }

  /// Get booking details by ID
  Future<Booking?> getBookingDetails(String bookingId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      
      final token = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/getBookingDetails'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bookingId': bookingId,
        }),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch booking details: ${response.body}');
      }
      
      final data = jsonDecode(response.body);
      return Booking.fromBokunJson(data['result']);
    } catch (e) {
      print('❌ Error fetching booking details: $e');
      rethrow;
    }
  }

  /// Reschedule a booking to a new date
  Future<bool> rescheduleBooking({
    required String bookingId,
    required String confirmationCode,
    required DateTime newDate,
    required String reason,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      
      final token = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/rescheduleBooking'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bookingId': bookingId,
          'confirmationCode': confirmationCode,
          'newDate': _formatDate(newDate),
          'reason': reason,
        }),
      );
      
      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to reschedule booking');
      }
      
      // Log the action to Firestore
      await _logBookingAction(
        bookingId: bookingId,
        confirmationCode: confirmationCode,
        action: 'reschedule',
        reason: reason,
        newData: {'date': _formatDate(newDate)},
        success: true,
      );
      
      return true;
    } catch (e) {
      print('❌ Error rescheduling booking: $e');
      
      // Log failed action
      await _logBookingAction(
        bookingId: bookingId,
        confirmationCode: confirmationCode,
        action: 'reschedule',
        reason: reason,
        newData: {'date': _formatDate(newDate)},
        success: false,
        errorMessage: e.toString(),
      );
      
      rethrow;
    }
  }

  /// Cancel a booking
  Future<bool> cancelBooking({
    required String bookingId,
    required String confirmationCode,
    required String reason,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      
      final token = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/cancelBooking'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bookingId': bookingId,
          'confirmationCode': confirmationCode,
          'reason': reason,
        }),
      );
      
      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to cancel booking');
      }
      
      // Log the action
      await _logBookingAction(
        bookingId: bookingId,
        confirmationCode: confirmationCode,
        action: 'cancel',
        reason: reason,
        success: true,
      );
      
      return true;
    } catch (e) {
      print('❌ Error cancelling booking: $e');
      
      // Log failed action
      await _logBookingAction(
        bookingId: bookingId,
        confirmationCode: confirmationCode,
        action: 'cancel',
        reason: reason,
        success: false,
        errorMessage: e.toString(),
      );
      
      rethrow;
    }
  }

  /// Log booking action for AI training
  Future<void> _logBookingAction({
    required String bookingId,
    required String confirmationCode,
    required String action,
    required String reason,
    Map<String, dynamic>? originalData,
    Map<String, dynamic>? newData,
    required bool success,
    String? errorMessage,
  }) async {
    try {
      final user = _auth.currentUser;
      
      await _firestore.collection('booking_actions').add({
        'bookingId': bookingId,
        'confirmationCode': confirmationCode,
        'action': action,
        'performedBy': user?.uid ?? 'unknown',
        'performedByEmail': user?.email ?? 'unknown',
        'performedAt': FieldValue.serverTimestamp(),
        'reason': reason,
        'originalData': originalData,
        'newData': newData,
        'success': success,
        'errorMessage': errorMessage,
      });
    } catch (e) {
      print('❌ Failed to log booking action: $e');
    }
  }

  /// Group bookings by date for calendar display (excludes cancelled)
  Map<DateTime, List<Booking>> groupBookingsByDate(List<Booking> bookings) {
    final grouped = <DateTime, List<Booking>>{};
    
    for (final booking in bookings) {
      // Skip cancelled bookings
      if (booking.isCancelled) continue;
      
      final dateKey = DateTime(
        booking.startDate.year,
        booking.startDate.month,
        booking.startDate.day,
      );
      
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(booking);
    }
    
    return grouped;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Booking model representing a Bokun booking
class Booking {
  final String id;
  final String confirmationCode;
  final String status;
  final DateTime startDate;
  final DateTime? endDate;
  final String productTitle;
  final String? productId;
  final int totalParticipants;
  final double totalPrice;
  final String currency;
  final Customer customer;
  final PickupInfo? pickup;
  final List<Participant> participants;
  final String? notes;
  final DateTime createdAt;
  
  Booking({
    required this.id,
    required this.confirmationCode,
    required this.status,
    required this.startDate,
    this.endDate,
    required this.productTitle,
    this.productId,
    required this.totalParticipants,
    required this.totalPrice,
    required this.currency,
    required this.customer,
    this.pickup,
    required this.participants,
    this.notes,
    required this.createdAt,
  });

  factory Booking.fromBokunJson(Map<String, dynamic> json) {
    // Parse customer
    final customerData = json['customer'] ?? {};
    final customer = Customer(
      firstName: customerData['firstName'] ?? '',
      lastName: customerData['lastName'] ?? '',
      email: customerData['email'] ?? '',
      phone: customerData['phoneNumber'] ?? customerData['phone'] ?? '',
    );
    
    // Parse pickup
    PickupInfo? pickup;
    final pickupData = json['pickup'] ?? json['pickupPlace'];
    if (pickupData != null) {
      pickup = PickupInfo(
        location: pickupData['title'] ?? pickupData['name'] ?? 'Unknown',
        time: pickupData['pickupTime'] ?? pickupData['time'] ?? '',
        address: pickupData['address'] ?? '',
      );
    }
    
    // Parse participants
    final participantsList = <Participant>[];
    final participantsData = json['participants'] ?? json['passengers'] ?? [];
    for (final p in participantsData) {
      participantsList.add(Participant(
        firstName: p['firstName'] ?? '',
        lastName: p['lastName'] ?? '',
        category: p['category'] ?? p['pricingCategory']?['title'] ?? 'Adult',
      ));
    }
    
    // Parse dates - Tour date is in productBookings[0].startDate or startDateTime
    DateTime startDate;
    try {
      dynamic startDateStr;
      
      // Get from productBookings (confirmed from API logs)
      final pBookings = json['productBookings'] as List?;
      if (pBookings != null && pBookings.isNotEmpty) {
        final firstProduct = pBookings[0] as Map<String, dynamic>?;
        if (firstProduct != null) {
          // Try startDateTime first (full ISO string), then startDate
          startDateStr = firstProduct['startDateTime'] ?? firstProduct['startDate'];
          print('📅 Found date in productBookings: $startDateStr (type: ${startDateStr.runtimeType})');
        }
      }
      
      // Fall back to top-level fields
      startDateStr ??= json['startDate'] ?? json['date'];
      
      if (startDateStr is String) {
        startDate = DateTime.parse(startDateStr);
      } else if (startDateStr is Map) {
        // Handle {year, month, day} format
        startDate = DateTime(
          (startDateStr['year'] as int?) ?? 2026,
          (startDateStr['month'] as int?) ?? 1,
          (startDateStr['day'] as int?) ?? 1,
        );
      } else if (startDateStr is int) {
        // Handle epoch timestamp
        startDate = DateTime.fromMillisecondsSinceEpoch(startDateStr);
      } else {
        print('⚠️ Could not parse startDate from booking: ${json['id']}, value: $startDateStr');
        startDate = DateTime.now();
      }
    } catch (e) {
      print('❌ Error parsing date for booking ${json['id']}: $e');
      startDate = DateTime.now();
    }
    
    DateTime createdAt;
    try {
      final createdStr = json['createdDate'] ?? json['createdAt'];
      if (createdStr is String) {
        createdAt = DateTime.parse(createdStr);
      } else {
        createdAt = DateTime.now();
      }
    } catch (e) {
      createdAt = DateTime.now();
    }
    
    // Get totalParticipants from productBookings[0] (that's where Bokun stores it)
    int totalParticipants = 0;
    final pBookingsForParticipants = json['productBookings'] as List?;
    if (pBookingsForParticipants != null && pBookingsForParticipants.isNotEmpty) {
      final firstPB = pBookingsForParticipants[0] as Map<String, dynamic>?;
      if (firstPB != null) {
        totalParticipants = (firstPB['totalParticipants'] as int?) ?? 0;
      }
    }
    // Fallback to top-level or participant list length
    if (totalParticipants == 0) {
      totalParticipants = (json['totalParticipants'] as int?) ?? participantsList.length;
    }
    
    // Get status from productBookings[0] (that's where Bokun stores it)
    String status = 'CONFIRMED';
    if (pBookingsForParticipants != null && pBookingsForParticipants.isNotEmpty) {
      final firstPB = pBookingsForParticipants[0] as Map<String, dynamic>?;
      if (firstPB != null) {
        status = (firstPB['status'] as String?) ?? 'CONFIRMED';
      }
    }
    
    return Booking(
      id: json['id']?.toString() ?? '',
      confirmationCode: json['confirmationCode'] ?? json['externalBookingReference'] ?? '',
      status: status,
      startDate: startDate,
      endDate: null,
      productTitle: json['productTitle'] ?? json['product']?['title'] ?? 'Northern Lights Tour',
      productId: json['productId']?.toString() ?? json['product']?['id']?.toString(),
      totalParticipants: totalParticipants,
      totalPrice: (json['totalPrice'] ?? json['totalAmount'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'ISK',
      customer: customer,
      pickup: pickup,
      participants: participantsList,
      notes: json['internalNote'] ?? json['notes'],
      createdAt: createdAt,
    );
  }
  
  String get customerName => '${customer.firstName} ${customer.lastName}'.trim();
  
  String get statusDisplay {
    switch (status.toUpperCase()) {
      case 'CONFIRMED':
        return 'Confirmed';
      case 'CANCELLED':
        return 'Cancelled';
      case 'PENDING':
        return 'Pending';
      case 'NO_SHOW':
        return 'No Show';
      default:
        return status;
    }
  }
  
  bool get isConfirmed => status.toUpperCase() == 'CONFIRMED';
  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
}

class Customer {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  
  Customer({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
  });
  
  String get fullName => '$firstName $lastName'.trim();
}

class PickupInfo {
  final String location;
  final String time;
  final String address;
  
  PickupInfo({
    required this.location,
    required this.time,
    required this.address,
  });
}

class Participant {
  final String firstName;
  final String lastName;
  final String category;
  
  Participant({
    required this.firstName,
    required this.lastName,
    required this.category,
  });
  
  String get fullName => '$firstName $lastName'.trim();
}
