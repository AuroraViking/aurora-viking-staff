// Upload session persistence service using SharedPreferences
import 'package:shared_preferences/shared_preferences.dart';
import '../models/upload_session.dart';

class UploadSessionService {
  static const String _sessionKey = 'active_upload_session';

  /// Save the current upload session
  static Future<void> saveSession(UploadSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, session.toJsonString());
  }

  /// Load a saved upload session (returns null if none exists)
  static Future<UploadSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_sessionKey);
    if (jsonString == null || jsonString.isEmpty) return null;

    try {
      final session = UploadSession.fromJsonString(jsonString);
      // Don't return completed sessions
      if (session.status == UploadSessionStatus.completed) {
        await clearSession();
        return null;
      }
      return session;
    } catch (e) {
      print('⚠️ Failed to load upload session: $e');
      await clearSession();
      return null;
    }
  }

  /// Clear any saved upload session
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// Check if there's an incomplete session to resume
  static Future<bool> hasIncompleteSession() async {
    final session = await loadSession();
    return session != null &&
        session.status != UploadSessionStatus.completed &&
        session.remainingFiles > 0;
  }
}
