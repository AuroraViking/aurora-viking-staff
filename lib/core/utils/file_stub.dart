// Stub file for web compatibility
// This file is only used when dart:io is not available (web platform)

// On web, File operations are not supported
// This stub provides a placeholder to prevent compilation errors

class File {
  final String path;
  
  File(this.path);
  
  Future<String> readAsString() {
    throw UnsupportedError('File operations not supported on web');
  }
  
  Future<void> writeAsString(String contents) {
    throw UnsupportedError('File operations not supported on web');
  }
  
  bool existsSync() => false;
  
  Future<bool> exists() async => false;
}


