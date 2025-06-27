// Shift model for representing shift data

enum ShiftType {
  dayTour,
  northernLights,
}

enum ShiftStatus {
  available,
  applied,
  accepted,
  completed,
  cancelled,
}

class Shift {
  final String id;
  final ShiftType type;
  final DateTime date;
  final String startTime;
  final String endTime;
  ShiftStatus status;
  final String? guideId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Shift({
    required this.id,
    required this.type,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.guideId,
    this.createdAt,
    this.updatedAt,
  });

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'date': date.toIso8601String(),
      'startTime': startTime,
      'endTime': endTime,
      'status': status.name,
      'guideId': guideId,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // Create from JSON
  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'],
      type: ShiftType.values.firstWhere((e) => e.name == json['type']),
      date: DateTime.parse(json['date']),
      startTime: json['startTime'],
      endTime: json['endTime'],
      status: ShiftStatus.values.firstWhere((e) => e.name == json['status']),
      guideId: json['guideId'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  // Copy with method for creating modified copies
  Shift copyWith({
    String? id,
    ShiftType? type,
    DateTime? date,
    String? startTime,
    String? endTime,
    ShiftStatus? status,
    String? guideId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Shift(
      id: id ?? this.id,
      type: type ?? this.type,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      guideId: guideId ?? this.guideId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Shift && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Shift(id: $id, type: $type, date: $date, status: $status)';
  }
} 