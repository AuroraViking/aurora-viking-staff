class TourDate {
  final DateTime date;
  final int totalBookings;
  final int totalPassengers;
  final List<GuideApplication> guideApplications;
  final List<BusAssignment> busAssignments;

  TourDate({
    required this.date,
    required this.totalBookings,
    required this.totalPassengers,
    required this.guideApplications,
    required this.busAssignments,
  });

  factory TourDate.fromJson(Map<String, dynamic> json) {
    return TourDate(
      date: DateTime.parse(json['date']),
      totalBookings: json['totalBookings'] ?? 0,
      totalPassengers: json['totalPassengers'] ?? 0,
      guideApplications: (json['guideApplications'] as List<dynamic>?)
          ?.map((app) => GuideApplication.fromJson(app))
          .toList() ?? [],
      busAssignments: (json['busAssignments'] as List<dynamic>?)
          ?.map((bus) => BusAssignment.fromJson(bus))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'totalBookings': totalBookings,
      'totalPassengers': totalPassengers,
      'guideApplications': guideApplications.map((app) => app.toJson()).toList(),
      'busAssignments': busAssignments.map((bus) => bus.toJson()).toList(),
    };
  }
}

class GuideApplication {
  final String guideId;
  final String guideName;
  final String tourType; // 'day_tour' or 'northern_lights'
  final DateTime appliedAt;
  final String status; // 'pending', 'approved', 'rejected'
  final String? assignedBusId;

  GuideApplication({
    required this.guideId,
    required this.guideName,
    required this.tourType,
    required this.appliedAt,
    this.status = 'pending',
    this.assignedBusId,
  });

  factory GuideApplication.fromJson(Map<String, dynamic> json) {
    return GuideApplication(
      guideId: json['guideId'] ?? '',
      guideName: json['guideName'] ?? '',
      tourType: json['tourType'] ?? '',
      appliedAt: DateTime.parse(json['appliedAt'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'pending',
      assignedBusId: json['assignedBusId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guideId': guideId,
      'guideName': guideName,
      'tourType': tourType,
      'appliedAt': appliedAt.toIso8601String(),
      'status': status,
      'assignedBusId': assignedBusId,
    };
  }

  GuideApplication copyWith({
    String? guideId,
    String? guideName,
    String? tourType,
    DateTime? appliedAt,
    String? status,
    String? assignedBusId,
  }) {
    return GuideApplication(
      guideId: guideId ?? this.guideId,
      guideName: guideName ?? this.guideName,
      tourType: tourType ?? this.tourType,
      appliedAt: appliedAt ?? this.appliedAt,
      status: status ?? this.status,
      assignedBusId: assignedBusId ?? this.assignedBusId,
    );
  }
}

class BusAssignment {
  final String busId;
  final String busName;
  final String assignedGuideId;
  final String assignedGuideName;
  final List<String> bookingIds;
  final int totalPassengers;
  final int maxPassengers;
  final String tourType;

  BusAssignment({
    required this.busId,
    required this.busName,
    required this.assignedGuideId,
    required this.assignedGuideName,
    required this.bookingIds,
    required this.totalPassengers,
    this.maxPassengers = 19,
    required this.tourType,
  });

  factory BusAssignment.fromJson(Map<String, dynamic> json) {
    return BusAssignment(
      busId: json['busId'] ?? '',
      busName: json['busName'] ?? '',
      assignedGuideId: json['assignedGuideId'] ?? '',
      assignedGuideName: json['assignedGuideName'] ?? '',
      bookingIds: List<String>.from(json['bookingIds'] ?? []),
      totalPassengers: json['totalPassengers'] ?? 0,
      maxPassengers: json['maxPassengers'] ?? 19,
      tourType: json['tourType'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'busId': busId,
      'busName': busName,
      'assignedGuideId': assignedGuideId,
      'assignedGuideName': assignedGuideName,
      'bookingIds': bookingIds,
      'totalPassengers': totalPassengers,
      'maxPassengers': maxPassengers,
      'tourType': tourType,
    };
  }

  BusAssignment copyWith({
    String? busId,
    String? busName,
    String? assignedGuideId,
    String? assignedGuideName,
    List<String>? bookingIds,
    int? totalPassengers,
    int? maxPassengers,
    String? tourType,
  }) {
    return BusAssignment(
      busId: busId ?? this.busId,
      busName: busName ?? this.busName,
      assignedGuideId: assignedGuideId ?? this.assignedGuideId,
      assignedGuideName: assignedGuideName ?? this.assignedGuideName,
      bookingIds: bookingIds ?? this.bookingIds,
      totalPassengers: totalPassengers ?? this.totalPassengers,
      maxPassengers: maxPassengers ?? this.maxPassengers,
      tourType: tourType ?? this.tourType,
    );
  }

  bool get isFull => totalPassengers >= maxPassengers;
  int get availableSeats => maxPassengers - totalPassengers;
} 