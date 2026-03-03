// Upload session model for tracking upload progress and enabling resume
import 'dart:convert';

enum UploadSessionStatus {
  active,
  paused,
  completed,
}

class UploadSession {
  final String sessionId;
  final String guideName;
  final String date; // YYYY-MM-DD
  final DateTime timestamp;
  final int totalFiles;
  int completedFiles;
  final Set<String> completedUris; // URIs already uploaded
  final String? folderId; // Drive folder ID (so we don't re-create)
  UploadSessionStatus status;

  UploadSession({
    required this.sessionId,
    required this.guideName,
    required this.date,
    required this.timestamp,
    required this.totalFiles,
    this.completedFiles = 0,
    Set<String>? completedUris,
    this.folderId,
    this.status = UploadSessionStatus.active,
  }) : completedUris = completedUris ?? <String>{};

  int get remainingFiles => totalFiles - completedFiles;

  double get progressPercent =>
      totalFiles > 0 ? completedFiles / totalFiles : 0.0;

  bool get isComplete => completedFiles >= totalFiles;

  void markFileCompleted(String uri) {
    if (!completedUris.contains(uri)) {
      completedUris.add(uri);
      completedFiles = completedUris.length;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'guideName': guideName,
      'date': date,
      'timestamp': timestamp.toIso8601String(),
      'totalFiles': totalFiles,
      'completedFiles': completedFiles,
      'completedUris': completedUris.toList(),
      'folderId': folderId,
      'status': status.name,
    };
  }

  factory UploadSession.fromJson(Map<String, dynamic> json) {
    return UploadSession(
      sessionId: json['sessionId'] ?? '',
      guideName: json['guideName'] ?? '',
      date: json['date'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      totalFiles: json['totalFiles'] ?? 0,
      completedFiles: json['completedFiles'] ?? 0,
      completedUris: json['completedUris'] != null
          ? Set<String>.from(json['completedUris'])
          : <String>{},
      folderId: json['folderId'],
      status: UploadSessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => UploadSessionStatus.active,
      ),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory UploadSession.fromJsonString(String jsonString) {
    return UploadSession.fromJson(jsonDecode(jsonString));
  }

  @override
  String toString() {
    return 'UploadSession(guide: $guideName, date: $date, '
        '$completedFiles/$totalFiles files, status: ${status.name})';
  }
}
