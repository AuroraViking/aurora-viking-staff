// Admin data models for comprehensive admin functionality

class AdminGuide {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String profileImageUrl;
  final String status; // 'active', 'inactive', 'suspended'
  final DateTime joinDate;
  final int totalShifts;
  final double rating;
  final List<String> certifications;
  final Map<String, dynamic> preferences;
  final DateTime? lastActive;

  AdminGuide({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.profileImageUrl,
    required this.status,
    required this.joinDate,
    required this.totalShifts,
    required this.rating,
    required this.certifications,
    required this.preferences,
    this.lastActive,
  });

  factory AdminGuide.fromJson(Map<String, dynamic> json) {
    return AdminGuide(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      profileImageUrl: json['profileImageUrl'] ?? '',
      status: json['status'] ?? 'inactive',
      joinDate: DateTime.parse(json['joinDate'] ?? DateTime.now().toIso8601String()),
      totalShifts: json['totalShifts'] ?? 0,
      rating: (json['rating'] ?? 0.0).toDouble(),
      certifications: List<String>.from(json['certifications'] ?? []),
      preferences: Map<String, dynamic>.from(json['preferences'] ?? {}),
      lastActive: json['lastActive'] != null 
          ? DateTime.parse(json['lastActive']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'profileImageUrl': profileImageUrl,
      'status': status,
      'joinDate': joinDate.toIso8601String(),
      'totalShifts': totalShifts,
      'rating': rating,
      'certifications': certifications,
      'preferences': preferences,
      'lastActive': lastActive?.toIso8601String(),
    };
  }
}

class AdminShift {
  final String id;
  final String guideId;
  final String guideName;
  final String type; // 'day_tour', 'northern_lights'
  final DateTime date;
  final String status; // 'pending', 'approved', 'rejected', 'completed'
  final DateTime appliedAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? rejectionReason;
  final Map<String, dynamic>? notes;

  AdminShift({
    required this.id,
    required this.guideId,
    required this.guideName,
    required this.type,
    required this.date,
    required this.status,
    required this.appliedAt,
    this.approvedAt,
    this.approvedBy,
    this.rejectionReason,
    this.notes,
  });

  factory AdminShift.fromJson(Map<String, dynamic> json) {
    return AdminShift(
      id: json['id'] ?? '',
      guideId: json['guideId'] ?? '',
      guideName: json['guideName'] ?? '',
      type: json['type'] ?? '',
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'pending',
      appliedAt: DateTime.parse(json['appliedAt'] ?? DateTime.now().toIso8601String()),
      approvedAt: json['approvedAt'] != null 
          ? DateTime.parse(json['approvedAt']) 
          : null,
      approvedBy: json['approvedBy'],
      rejectionReason: json['rejectionReason'],
      notes: json['notes'] != null 
          ? Map<String, dynamic>.from(json['notes']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'guideId': guideId,
      'guideName': guideName,
      'type': type,
      'date': date.toIso8601String(),
      'status': status,
      'appliedAt': appliedAt.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
      'approvedBy': approvedBy,
      'rejectionReason': rejectionReason,
      'notes': notes,
    };
  }
}

class AdminStats {
  final int totalGuides;
  final int activeGuides;
  final int pendingShifts;
  final int todayTours;
  final int alerts;
  final double averageRating;
  final Map<String, int> shiftsByType;
  final Map<String, int> shiftsByStatus;
  final List<MonthlyStats> monthlyStats;

  AdminStats({
    required this.totalGuides,
    required this.activeGuides,
    required this.pendingShifts,
    required this.todayTours,
    required this.alerts,
    required this.averageRating,
    required this.shiftsByType,
    required this.shiftsByStatus,
    required this.monthlyStats,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalGuides: json['totalGuides'] ?? 0,
      activeGuides: json['activeGuides'] ?? 0,
      pendingShifts: json['pendingShifts'] ?? 0,
      todayTours: json['todayTours'] ?? 0,
      alerts: json['alerts'] ?? 0,
      averageRating: (json['averageRating'] ?? 0.0).toDouble(),
      shiftsByType: Map<String, int>.from(json['shiftsByType'] ?? {}),
      shiftsByStatus: Map<String, int>.from(json['shiftsByStatus'] ?? {}),
      monthlyStats: (json['monthlyStats'] as List<dynamic>? ?? [])
          .map((e) => MonthlyStats.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalGuides': totalGuides,
      'activeGuides': activeGuides,
      'pendingShifts': pendingShifts,
      'todayTours': todayTours,
      'alerts': alerts,
      'averageRating': averageRating,
      'shiftsByType': shiftsByType,
      'shiftsByStatus': shiftsByStatus,
      'monthlyStats': monthlyStats.map((e) => e.toJson()).toList(),
    };
  }
}

class MonthlyStats {
  final String month;
  final int totalShifts;
  final int dayTours;
  final int northernLights;
  final double averageRating;
  final int totalGuides;

  MonthlyStats({
    required this.month,
    required this.totalShifts,
    required this.dayTours,
    required this.northernLights,
    required this.averageRating,
    required this.totalGuides,
  });

  factory MonthlyStats.fromJson(Map<String, dynamic> json) {
    return MonthlyStats(
      month: json['month'] ?? '',
      totalShifts: json['totalShifts'] ?? 0,
      dayTours: json['dayTours'] ?? 0,
      northernLights: json['northernLights'] ?? 0,
      averageRating: (json['averageRating'] ?? 0.0).toDouble(),
      totalGuides: json['totalGuides'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'month': month,
      'totalShifts': totalShifts,
      'dayTours': dayTours,
      'northernLights': northernLights,
      'averageRating': averageRating,
      'totalGuides': totalGuides,
    };
  }
}

class AdminAlert {
  final String id;
  final String type; // 'shift_conflict', 'guide_unavailable', 'weather_warning', 'system_alert'
  final String title;
  final String message;
  final String severity; // 'low', 'medium', 'high', 'critical'
  final DateTime createdAt;
  final bool isRead;
  final String? relatedId; // ID of related shift, guide, etc.
  final Map<String, dynamic>? metadata;

  AdminAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.createdAt,
    required this.isRead,
    this.relatedId,
    this.metadata,
  });

  factory AdminAlert.fromJson(Map<String, dynamic> json) {
    return AdminAlert(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      severity: json['severity'] ?? 'medium',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      isRead: json['isRead'] ?? false,
      relatedId: json['relatedId'],
      metadata: json['metadata'] != null 
          ? Map<String, dynamic>.from(json['metadata']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'severity': severity,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'relatedId': relatedId,
      'metadata': metadata,
    };
  }
}

class LiveTrackingData {
  final String guideId;
  final String guideName;
  final String busId;
  final String busName;
  final double latitude;
  final double longitude;
  final DateTime lastUpdate;
  final String status; // 'active', 'idle', 'offline'
  final String? currentShiftId;
  final String? currentShiftType;
  final double? speed;
  final double? heading;

  LiveTrackingData({
    required this.guideId,
    required this.guideName,
    required this.busId,
    required this.busName,
    required this.latitude,
    required this.longitude,
    required this.lastUpdate,
    required this.status,
    this.currentShiftId,
    this.currentShiftType,
    this.speed,
    this.heading,
  });

  factory LiveTrackingData.fromJson(Map<String, dynamic> json) {
    return LiveTrackingData(
      guideId: json['guideId'] ?? '',
      guideName: json['guideName'] ?? '',
      busId: json['busId'] ?? '',
      busName: json['busName'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      lastUpdate: DateTime.parse(json['lastUpdate'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'offline',
      currentShiftId: json['currentShiftId'],
      currentShiftType: json['currentShiftType'],
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      heading: json['heading'] != null ? (json['heading'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guideId': guideId,
      'guideName': guideName,
      'busId': busId,
      'busName': busName,
      'latitude': latitude,
      'longitude': longitude,
      'lastUpdate': lastUpdate.toIso8601String(),
      'status': status,
      'currentShiftId': currentShiftId,
      'currentShiftType': currentShiftType,
      'speed': speed,
      'heading': heading,
    };
  }
} 