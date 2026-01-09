class EndOfShiftReport {
  final String id;
  final String date;           // YYYY-MM-DD
  final String guideId;
  final String guideName;
  final String? busId;
  final String? busName;
  final String auroraRating;   // "not_seen", "camera_only", "a_little", "good", "great", "exceptional"
  final bool shouldRequestReviews;
  final String? notes;         // Optional incident/notes text
  final DateTime createdAt;

  EndOfShiftReport({
    required this.id,
    required this.date,
    required this.guideId,
    required this.guideName,
    this.busId,
    this.busName,
    required this.auroraRating,
    required this.shouldRequestReviews,
    this.notes,
    required this.createdAt,
  });

  factory EndOfShiftReport.fromJson(Map<String, dynamic> json) {
    return EndOfShiftReport(
      id: json['id'] ?? '',
      date: json['date'] ?? '',
      guideId: json['guideId'] ?? '',
      guideName: json['guideName'] ?? '',
      busId: json['busId'],
      busName: json['busName'],
      auroraRating: json['auroraRating'] ?? 'not_seen',
      shouldRequestReviews: json['shouldRequestReviews'] ?? false,
      notes: json['notes'],
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'guideId': guideId,
      'guideName': guideName,
      'busId': busId,
      'busName': busName,
      'auroraRating': auroraRating,
      'shouldRequestReviews': shouldRequestReviews,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Human-readable aurora rating
  String get auroraRatingDisplay {
    switch (auroraRating) {
      case 'not_seen':
        return 'Not seen';
      case 'camera_only':
        return 'Only through camera';
      case 'a_little':
        return 'A little bit';
      case 'good':
        return 'Good';
      case 'great':
        return 'Great';
      case 'exceptional':
        return 'Exceptional';
      default:
        return auroraRating;
    }
  }

  // Emoji for aurora rating
  String get auroraRatingEmoji {
    switch (auroraRating) {
      case 'not_seen':
        return '😔';
      case 'camera_only':
        return '📷';
      case 'a_little':
        return '✨';
      case 'good':
        return '🌟';
      case 'great':
        return '⭐';
      case 'exceptional':
        return '🤩';
      default:
        return '';
    }
  }
}

// Aurora rating options for the UI
class AuroraRating {
  final String value;
  final String label;
  final String emoji;

  const AuroraRating(this.value, this.label, this.emoji);

  static const List<AuroraRating> options = [
    AuroraRating('not_seen', 'Not seen', '😔'),
    AuroraRating('camera_only', 'Only through camera', '📷'),
    AuroraRating('a_little', 'A little bit', '✨'),
    AuroraRating('good', 'Good', '🌟'),
    AuroraRating('great', 'Great', '⭐'),
    AuroraRating('exceptional', 'Exceptional', '🤩'),
  ];
}

