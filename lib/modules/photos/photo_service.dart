// Photo service for handling photo operations, camera integration, and Drive uploads 
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PhotoService {
  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  PhotoService._internal();

  drive.DriveApi? _driveApi;
  bool _isInitialized = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  // Initialize Google Drive API with Google Sign-In
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Check if user is already signed in
      final GoogleSignInAccount? currentUser = _googleSignIn.currentUser;
      if (currentUser == null) {
        print('🔐 No Google account signed in');
        return false;
      }

      // Get authentication headers
      final GoogleSignInAuthentication auth = await currentUser.authentication;
      final accessToken = auth.accessToken;
      
      if (accessToken == null) {
        print('❌ No access token available');
        return false;
      }

      // Create authenticated HTTP client
      final httpClient = http.Client();
      final authenticatedClient = AuthenticatedClient(httpClient, accessToken);

      // Initialize Drive API
      _driveApi = drive.DriveApi(authenticatedClient);
      
      print('✅ Google Drive API initialized successfully');
      print('👤 Signed in as: ${currentUser.email}');
      _isInitialized = true;
      return true;
    } catch (e) {
      print('❌ Failed to initialize Google Drive API: $e');
      return false;
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null) {
        print('✅ Signed in with Google: ${account.email}');
        return true;
      } else {
        print('❌ Google sign-in cancelled');
        return false;
      }
    } catch (e) {
      print('❌ Google sign-in failed: $e');
      return false;
    }
  }

  // Sign out from Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _driveApi = null;
    _isInitialized = false;
    print('👋 Signed out from Google');
  }

  // Check if user is signed in
  bool get isSignedIn => _googleSignIn.currentUser != null;

  // Get current user email
  String? get currentUserEmail => _googleSignIn.currentUser?.email;

  // Upload photos to Google Drive
  Future<bool> uploadPhotos({
    required List<io.File> photos,
    required String guideName,
    String? busName, // Made optional since it's not used
    required DateTime date,
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        print('❌ Photo service not initialized');
        return false;
      }
    }

    try {
      final year = date.year.toString();
      final month = _getMonthName(date.month);
      final day = date.day.toString();
      final dateFolder = '$day $month';
      
      // Create the full folder path: Norðurljósamyndir/2025/December/21 December/Kolbeinn
      final folderPath = 'Norðurljósamyndir/$year/$month/$dateFolder/$guideName';
      
      print('📁 Creating folder structure: $folderPath');
      print('📸 Uploading ${photos.length} photos');

      // Create folder structure
      final folderId = await _createFolderStructure(folderPath);
      if (folderId == null) {
        print('❌ Failed to create folder structure');
        return false;
      }

      // Upload photos
      for (int i = 0; i < photos.length; i++) {
        final photo = photos[i];
        final fileName = '${(i + 1).toString().padLeft(3, '0')}_${photo.path.split('/').last}';
        
        final success = await _uploadSinglePhoto(photo, fileName, folderId);
        if (!success) {
          print('❌ Failed to upload photo: $fileName');
          return false;
        }
        
        // Update progress
        final progress = (i + 1) / photos.length;
        onProgress?.call(progress);
        
        print('📤 Uploaded: ${i + 1}/${photos.length} - $fileName');
      }

      print('✅ Successfully uploaded ${photos.length} photos');
      print('🎯 Target folder: $folderPath');
      return true;
    } catch (e) {
      print('❌ Upload failed: $e');
      return false;
    }
  }

  // Create folder structure in Drive
  Future<String?> _createFolderStructure(String folderPath) async {
    try {
      final folders = folderPath.split('/');
      String? parentId = 'root'; // Start from root

      for (final folderName in folders) {
        if (folderName.isEmpty) continue;
        
        // Check if folder already exists
        String? folderId = await _findFolder(folderName, parentId);
        
        if (folderId == null) {
          // Create new folder
          final folder = drive.File()
            ..name = folderName
            ..mimeType = 'application/vnd.google-apps.folder'
            ..parents = parentId != null ? [parentId!] : null;

          final createdFolder = await _driveApi!.files.create(folder);
          folderId = createdFolder.id;
          print('📁 Created folder: $folderName');
        }

        parentId = folderId;
      }

      return parentId;
    } catch (e) {
      print('❌ Failed to create folder structure: $e');
      return null;
    }
  }

  // Find existing folder
  Future<String?> _findFolder(String folderName, String? parentId) async {
    try {
      String query = "name='$folderName' and mimeType='application/vnd.google-apps.folder'";
      if (parentId != null && parentId != 'root') {
        query += " and '$parentId' in parents";
      }

      final result = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }
      return null;
    } catch (e) {
      print('❌ Error finding folder: $e');
      return null;
    }
  }

  // Upload single photo
  Future<bool> _uploadSinglePhoto(io.File photo, String fileName, String folderId) async {
    try {
      final bytes = await photo.readAsBytes();
      
      final file = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
      );

      await _driveApi!.files.create(file, uploadMedia: media);
      return true;
    } catch (e) {
      print('❌ Failed to upload photo $fileName: $e');
      return false;
    }
  }

  // Helper method to get month name
  String _getMonthName(int month) {
    switch (month) {
      case 1: return 'January';
      case 2: return 'February';
      case 3: return 'March';
      case 4: return 'April';
      case 5: return 'May';
      case 6: return 'June';
      case 7: return 'July';
      case 8: return 'August';
      case 9: return 'September';
      case 10: return 'October';
      case 11: return 'November';
      case 12: return 'December';
      default: return 'Unknown';
    }
  }

  // Dispose resources
  void dispose() {
    _driveApi = null;
    _isInitialized = false;
  }
}

// Custom authenticated HTTP client
class AuthenticatedClient extends http.BaseClient {
  final http.Client _client;
  final String _accessToken;

  AuthenticatedClient(this._client, this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }
} 