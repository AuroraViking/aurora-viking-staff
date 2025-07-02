import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';

class PickupService {
  static const String _baseUrl = 'https://api.bokun.io/rest/v2';
  
  // Get Bokun API credentials from environment
  String get _accessKey => dotenv.env['BOKUN_ACCESS_KEY'] ?? '';
  String get _secretKey => dotenv.env['BOKUN_SECRET_KEY'] ?? '';
  int get _maxPassengersPerBus => int.tryParse(dotenv.env['MAX_PASSENGERS_PER_BUS'] ?? '19') ?? 19;

  // Fetch bookings from Bokun API for a specific date
  Future<List<PickupBooking>> fetchBookingsForDate(DateTime date) async {
    try {
      final startDate = DateTime(date.year, date.month, date.day);
      final endDate = startDate.add(const Duration(days: 1));

      final response = await http.get(
        Uri.parse('$_baseUrl/bookings?startDate=${startDate.toIso8601String()}&endDate=${endDate.toIso8601String()}'),
        headers: {
          'X-Bokun-AccessKey': _accessKey,
          'X-Bokun-SecretKey': _secretKey,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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
        
        return bookings;
      } else {
        throw Exception('Failed to fetch bookings: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching bookings: $e');
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