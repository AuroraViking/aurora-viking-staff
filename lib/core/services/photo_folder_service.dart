import 'package:flutter/services.dart';

class PhotoFolderService {
  static const MethodChannel _channel = MethodChannel('com.auroraviking.aurora_viking_staff/photo_folder');

  /// List files in a SAF folder URI, filtered by time
  /// Returns a list of maps with: uri, path (nullable), name, lastModified, size
  static Future<List<Map<String, dynamic>>> listFilesInFolder(
    String folderUri,
    int hoursAgo,
  ) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'listFilesInFolder',
        {
          'folderUri': folderUri,
          'hoursAgo': hoursAgo,
        },
      );
      
      return result.cast<Map<dynamic, dynamic>>().map((item) {
        return {
          'uri': item['uri'] as String?,
          'path': item['path'] as String?,
          'name': item['name'] as String?,
          'lastModified': item['lastModified'] as int?,
          'size': item['size'] as int?,
        };
      }).toList();
    } on PlatformException catch (e) {
      print('❌ Failed to list files in folder: ${e.message}');
      rethrow;
    }
  }
}


