// Tour Group Model
// Groups pickup bookings by tour type and departure time
// Prevents mixing up private tours with group tours!

import 'pickup_models.dart';

/// Represents a group of bookings for the same tour/departure
class TourGroup {
  final String groupKey;
  final String productId;
  final String productTitle;
  final String? departureTime;
  final String? startTimeId;
  final bool isPrivateTour;
  final List<PickupBooking> bookings;

  TourGroup({
    required this.groupKey,
    this.productId = '',
    required this.productTitle,
    this.departureTime,
    this.startTimeId,
    this.isPrivateTour = false,
    required this.bookings,
  });

  /// Total passengers in this group
  int get totalPassengers => bookings.fold(0, (sum, b) => sum + b.numberOfGuests);

  /// Number of bookings in this group
  int get bookingCount => bookings.length;

  /// Display label for the group header
  String get displayLabel {
    final time = departureTime ?? 'TBD';
    if (isPrivateTour) {
      return '⭐ Private: $productTitle - $time';
    }
    return '🚌 $productTitle - $time Departure';
  }

  /// Short label for compact displays
  String get shortLabel {
    final time = departureTime ?? 'TBD';
    if (isPrivateTour) {
      return '⭐ Private - $time';
    }
    return '$time Departure';
  }

  /// Icon for the group
  String get icon => isPrivateTour ? '⭐' : '🚌';

  /// Get bookings sorted by pickup time
  List<PickupBooking> get sortedBookings {
    final sorted = List<PickupBooking>.from(bookings);
    sorted.sort((a, b) => a.pickupTime.compareTo(b.pickupTime));
    return sorted;
  }

  /// Get earliest pickup time in this group
  DateTime? get earliestPickup {
    if (bookings.isEmpty) return null;
    return sortedBookings.first.pickupTime;
  }

  /// Get latest pickup time in this group
  DateTime? get latestPickup {
    if (bookings.isEmpty) return null;
    return sortedBookings.last.pickupTime;
  }

  /// Check if all pickups in this group are complete
  bool get allPickupsComplete {
    return bookings.every((b) => b.isArrived || b.isNoShow);
  }

  /// Count of completed pickups (arrived)
  int get completedCount => bookings.where((b) => b.isArrived).length;

  /// Count of no-shows
  int get noShowCount => bookings.where((b) => b.isNoShow).length;

  /// Count of pending pickups
  int get pendingCount => bookings.where((b) => !b.isArrived && !b.isNoShow).length;

  /// Group a list of bookings by tour/departure time
  /// Returns sorted list: private tours first, then by departure time
  static List<TourGroup> groupBookings(List<PickupBooking> bookings) {
    if (bookings.isEmpty) return [];

    final groups = <String, List<PickupBooking>>{};

    for (final booking in bookings) {
      final key = _getGroupKey(booking);
      groups.putIfAbsent(key, () => []).add(booking);
    }

    // Convert to TourGroup objects
    final tourGroups = groups.entries.map((entry) {
      final groupBookings = entry.value;
      final first = groupBookings.first;

      return TourGroup(
        groupKey: entry.key,
        productId: first.productId ?? '',
        productTitle: first.productTitle ?? 'Northern Lights Tour',
        departureTime: first.departureTime,
        startTimeId: first.startTimeId,
        isPrivateTour: first.isPrivateTour,
        bookings: groupBookings,
      );
    }).toList();

    // Sort groups
    tourGroups.sort(_compareTourGroups);

    return tourGroups;
  }

  /// Generate a grouping key for a booking
  static String _getGroupKey(PickupBooking booking) {
    final productId = booking.productId ?? 'unknown';
    final departureTime = booking.departureTime ?? 'unknown';
    final isPrivate = booking.isPrivateTour ? 'private' : 'group';
    return '${productId}_${departureTime}_$isPrivate';
  }

  /// Compare function for sorting tour groups
  static int _compareTourGroups(TourGroup a, TourGroup b) {
    // 1. Private tours come first (they need special attention!)
    if (a.isPrivateTour && !b.isPrivateTour) return -1;
    if (!a.isPrivateTour && b.isPrivateTour) return 1;

    // 2. Then sort by departure time
    final aTime = a.departureTime ?? '99:99';
    final bTime = b.departureTime ?? '99:99';
    final timeCompare = aTime.compareTo(bTime);
    if (timeCompare != 0) return timeCompare;

    // 3. Finally by product title
    return a.productTitle.compareTo(b.productTitle);
  }

  @override
  String toString() {
    return 'TourGroup($displayLabel, $bookingCount bookings, $totalPassengers pax)';
  }
}

/// Helper class for detecting private tours
class PrivateTourDetector {
  /// Keywords that indicate a private tour
  static const List<String> privateKeywords = [
    'private',
    'exclusive',
    'vip',
    'custom',
    'charter',
  ];

  /// Check if a product title indicates a private tour
  static bool isPrivateTour(String? productTitle) {
    if (productTitle == null) return false;
    final lower = productTitle.toLowerCase();
    return privateKeywords.any((keyword) => lower.contains(keyword));
  }

  /// Check booking data for private tour indicators
  static bool checkBookingData(Map<String, dynamic> bookingData) {
    // Check product title
    final product = bookingData['product'] as Map<String, dynamic>?;
    final title = product?['title'] as String?;
    if (isPrivateTour(title)) return true;

    // Check labels/tags
    final labels = bookingData['labels'] as List<dynamic>?;
    if (labels != null) {
      for (final label in labels) {
        if (isPrivateTour(label.toString())) return true;
      }
    }

    // Check booking type field if available
    final bookingType = bookingData['bookingType'] as String?;
    if (isPrivateTour(bookingType)) return true;

    return false;
  }
}

