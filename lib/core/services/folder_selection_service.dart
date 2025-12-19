import 'package:flutter/services.dart';

class FolderSelectionService {
  static const MethodChannel _channel = MethodChannel('com.auroraviking.aurora_viking_staff/folder_selection');

  /// Request folder selection via SAF Intent
  /// Returns the folder URI as a string
  static Future<String?> requestFolderSelection() async {
    try {
      final String? uri = await _channel.invokeMethod('requestFolderSelection');
      return uri;
    } on PlatformException catch (e) {
      print('❌ Failed to request folder selection: ${e.message}');
      if (e.code == 'CANCELLED') {
        return null; // User cancelled
      }
      rethrow;
    }
  }
}

