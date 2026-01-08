class PickupBooking {
  final String id;
  final String customerFullName;
  final String pickupPlaceName;
  final DateTime pickupTime;
  final int numberOfGuests;
  final String phoneNumber;
  final String email;
  final String? assignedGuideId;
  final String? assignedGuideName;
  final bool isNoShow;
  final bool isArrived;
  final DateTime createdAt;
  final String? bookingId; // Added for questions API calls
  final String? confirmationCode; // Added for booking details API calls
  final bool isUnpaid; // Whether booking is unpaid
  final double? amountToPayOnArrival; // Amount to pay on arrival (if applicable)
  final bool paidOnArrival; // Whether guest has paid on arrival (marked by guide)

  PickupBooking({
    required this.id,
    required this.customerFullName,
    required this.pickupPlaceName,
    required this.pickupTime,
    required this.numberOfGuests,
    required this.phoneNumber,
    required this.email,
    this.assignedGuideId,
    this.assignedGuideName,
    this.isNoShow = false,
    this.isArrived = false,
    required this.createdAt,
    this.bookingId,
    this.confirmationCode,
    this.isUnpaid = false,
    this.amountToPayOnArrival,
    this.paidOnArrival = false,
  });

  factory PickupBooking.fromJson(Map<String, dynamic> json) {
    return PickupBooking(
      id: json['id'] ?? '',
      customerFullName: json['customerFullName'] ?? '',
      pickupPlaceName: json['pickupPlaceName'] ?? '',
      pickupTime: DateTime.parse(json['pickupTime'] ?? DateTime.now().toIso8601String()),
      numberOfGuests: json['numberOfGuests'] ?? 0,
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'] ?? '',
      assignedGuideId: json['assignedGuideId'],
      assignedGuideName: json['assignedGuideName'],
      isNoShow: json['isNoShow'] ?? false,
      isArrived: json['isArrived'] ?? false,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      bookingId: json['bookingId'],
      confirmationCode: json['confirmationCode'],
      isUnpaid: json['isUnpaid'] ?? false,
      amountToPayOnArrival: json['amountToPayOnArrival'] != null 
          ? (json['amountToPayOnArrival'] is num 
              ? (json['amountToPayOnArrival'] as num).toDouble() 
              : double.tryParse(json['amountToPayOnArrival'].toString()))
          : null,
      paidOnArrival: json['paidOnArrival'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerFullName': customerFullName,
      'pickupPlaceName': pickupPlaceName,
      'pickupTime': pickupTime.toIso8601String(),
      'numberOfGuests': numberOfGuests,
      'phoneNumber': phoneNumber,
      'email': email,
      'assignedGuideId': assignedGuideId,
      'assignedGuideName': assignedGuideName,
      'isNoShow': isNoShow,
      'isArrived': isArrived,
      'createdAt': createdAt.toIso8601String(),
      'bookingId': bookingId,
      'confirmationCode': confirmationCode,
      'isUnpaid': isUnpaid,
      'amountToPayOnArrival': amountToPayOnArrival,
      'paidOnArrival': paidOnArrival,
    };
  }

  PickupBooking copyWith({
    String? id,
    String? customerFullName,
    String? pickupPlaceName,
    DateTime? pickupTime,
    int? numberOfGuests,
    String? phoneNumber,
    String? email,
    String? assignedGuideId,
    String? assignedGuideName,
    bool? isNoShow,
    bool? isArrived,
    DateTime? createdAt,
    String? bookingId,
    String? confirmationCode,
    bool? isUnpaid,
    double? amountToPayOnArrival,
    bool? paidOnArrival,
  }) {
    return PickupBooking(
      id: id ?? this.id,
      customerFullName: customerFullName ?? this.customerFullName,
      pickupPlaceName: pickupPlaceName ?? this.pickupPlaceName,
      pickupTime: pickupTime ?? this.pickupTime,
      numberOfGuests: numberOfGuests ?? this.numberOfGuests,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      assignedGuideId: assignedGuideId ?? this.assignedGuideId,
      assignedGuideName: assignedGuideName ?? this.assignedGuideName,
      isNoShow: isNoShow ?? this.isNoShow,
      isArrived: isArrived ?? this.isArrived,
      createdAt: createdAt ?? this.createdAt,
      bookingId: bookingId ?? this.bookingId,
      confirmationCode: confirmationCode ?? this.confirmationCode,
      isUnpaid: isUnpaid ?? this.isUnpaid,
      amountToPayOnArrival: amountToPayOnArrival ?? this.amountToPayOnArrival,
      paidOnArrival: paidOnArrival ?? this.paidOnArrival,
    );
  }
}

class GuidePickupList {
  final String guideId;
  final String guideName;
  final List<PickupBooking> bookings;
  final int totalPassengers;
  final DateTime date;

  GuidePickupList({
    required this.guideId,
    required this.guideName,
    required this.bookings,
    required this.totalPassengers,
    required this.date,
  });

  factory GuidePickupList.fromJson(Map<String, dynamic> json) {
    return GuidePickupList(
      guideId: json['guideId'] ?? '',
      guideName: json['guideName'] ?? '',
      bookings: (json['bookings'] as List<dynamic>?)
          ?.map((booking) => PickupBooking.fromJson(booking))
          .toList() ?? [],
      totalPassengers: json['totalPassengers'] ?? 0,
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guideId': guideId,
      'guideName': guideName,
      'bookings': bookings.map((booking) => booking.toJson()).toList(),
      'totalPassengers': totalPassengers,
      'date': date.toIso8601String(),
    };
  }

  GuidePickupList copyWith({
    String? guideId,
    String? guideName,
    List<PickupBooking>? bookings,
    int? totalPassengers,
    DateTime? date,
  }) {
    return GuidePickupList(
      guideId: guideId ?? this.guideId,
      guideName: guideName ?? this.guideName,
      bookings: bookings ?? this.bookings,
      totalPassengers: totalPassengers ?? this.totalPassengers,
      date: date ?? this.date,
    );
  }
}

class PickupListStats {
  final int totalBookings;
  final int totalPassengers;
  final int assignedBookings;
  final int unassignedBookings;
  final int noShows;
  final List<GuidePickupList> guideLists;

  PickupListStats({
    required this.totalBookings,
    required this.totalPassengers,
    required this.assignedBookings,
    required this.unassignedBookings,
    required this.noShows,
    required this.guideLists,
  });

  factory PickupListStats.fromBookings(List<PickupBooking> bookings, List<GuidePickupList> guideLists) {
    final totalBookings = bookings.length;
    final totalPassengers = bookings.fold(0, (sum, booking) => sum + booking.numberOfGuests);
    final assignedBookings = bookings.where((booking) => booking.assignedGuideId != null).length;
    final unassignedBookings = totalBookings - assignedBookings;
    final noShows = bookings.where((booking) => booking.isNoShow).length;

    return PickupListStats(
      totalBookings: totalBookings,
      totalPassengers: totalPassengers,
      assignedBookings: assignedBookings,
      unassignedBookings: unassignedBookings,
      noShows: noShows,
      guideLists: guideLists,
    );
  }
} 