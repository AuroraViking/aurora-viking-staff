// Photo controller for managing photo upload state and business logic 
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_controller.dart';
import 'photo_service.dart';

class PhotoController extends ChangeNotifier {
  final PhotoService _photoService = PhotoService();
  
  List<File> _selectedPhotos = [];
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadError;
  bool _isInitialized = false;
  bool _isSignedIn = false;

  // Getters
  List<File> get selectedPhotos => _selectedPhotos;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get uploadError => _uploadError;
  bool get isInitialized => _isInitialized;
  bool get isSignedIn => _isSignedIn;
  String? get currentUserEmail => _photoService.currentUserEmail;

  // Initialize the photo service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      _isSignedIn = _photoService.isSignedIn;
      if (_isSignedIn) {
        final success = await _photoService.initialize();
        if (success) {
          _isInitialized = true;
          notifyListeners();
        }
        return success;
      }
      return false;
    } catch (e) {
      print('❌ Failed to initialize photo service: $e');
      return false;
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      final success = await _photoService.signInWithGoogle();
      if (success) {
        _isSignedIn = true;
        final initialized = await initialize();
        notifyListeners();
        return initialized;
      }
      return false;
    } catch (e) {
      print('❌ Google sign-in failed: $e');
      return false;
    }
  }

  // Sign out from Google
  Future<void> signOut() async {
    await _photoService.signOut();
    _isSignedIn = false;
    _isInitialized = false;
    notifyListeners();
  }

  // Add photos to selection
  void addPhotos(List<File> photos) {
    _selectedPhotos.addAll(photos);
    notifyListeners();
  }

  // Remove photo from selection
  void removePhoto(int index) {
    if (index >= 0 && index < _selectedPhotos.length) {
      _selectedPhotos.removeAt(index);
      notifyListeners();
    }
  }

  // Clear all selected photos
  void clearPhotos() {
    _selectedPhotos.clear();
    notifyListeners();
  }

  // Upload photos to Google Drive
  Future<bool> uploadPhotos({
    required String guideName,
    required String busName,
    required DateTime date,
    required BuildContext context,
  }) async {
    if (_selectedPhotos.isEmpty) {
      _uploadError = 'No photos selected';
      notifyListeners();
      return false;
    }

    if (!_isSignedIn) {
      _uploadError = 'Please sign in with Google first';
      notifyListeners();
      return false;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadError = null;
    });

    try {
      final success = await _photoService.uploadPhotos(
        photos: _selectedPhotos,
        guideName: guideName,
        busName: busName,
        date: date,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );

      if (success) {
        _selectedPhotos.clear();
        _uploadProgress = 1.0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Photos uploaded successfully to Google Drive!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        _uploadError = 'Upload failed. Please try again.';
      }

      setState(() {
        _isUploading = false;
      });
      return success;
    } catch (e) {
      _uploadError = 'Upload error: $e';
      setState(() {
        _isUploading = false;
      });
      return false;
    }
  }

  // Get current user's name from AuthController
  String getCurrentGuideName(BuildContext context) {
    final authController = context.read<AuthController>();
    return authController.currentUser?.fullName ?? 'Unknown Guide';
  }

  // Clear upload error
  void clearError() {
    _uploadError = null;
    notifyListeners();
  }

  // Update state
  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  @override
  void dispose() {
    _photoService.dispose();
    super.dispose();
  }
} 