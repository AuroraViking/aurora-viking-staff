import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../models/user_model.dart';
import '../services/firebase_service.dart';

class AuthController extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'admin';
  bool get isGuide => _currentUser?.role == 'guide';

  AuthController() {
    _initializeAuth();
  }

  void _initializeAuth() {
    FirebaseService.authStateChanges.listen((firebase_auth.User? firebaseUser) async {
      if (firebaseUser != null) {
        await _loadUserData(firebaseUser.uid);
      } else {
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  Future<void> _loadUserData(String uid) async {
    try {
      _setLoading(true);
      final userData = await FirebaseService.getUserData(uid);
      if (userData != null) {
        _currentUser = userData;
      } else {
        // Create default user data if not exists
        final firebaseUser = FirebaseService.currentUser;
        _currentUser = User(
          id: uid,
          fullName: firebaseUser?.displayName ?? 'Unknown User',
          email: firebaseUser?.email ?? '',
          phoneNumber: firebaseUser?.phoneNumber ?? '',
          role: 'guide', // Default role
          profilePictureUrl: firebaseUser?.photoURL,
          createdAt: DateTime.now(),
          isActive: true,
        );
        await FirebaseService.saveUserData(_currentUser!);
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load user data: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      _setLoading(true);
      _error = null;
      
      await FirebaseService.signInWithEmailAndPassword(email, password);
      return true;
    } catch (e) {
      _error = _getAuthErrorMessage(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    try {
      _setLoading(true);
      await FirebaseService.signOut();
      _currentUser = null;
      _error = null;
    } catch (e) {
      _error = 'Failed to sign out: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateUserRole(String role) async {
    if (_currentUser != null) {
      try {
        _currentUser = _currentUser!.copyWith(role: role);
        await FirebaseService.saveUserData(_currentUser!);
        notifyListeners();
      } catch (e) {
        _error = 'Failed to update user role: $e';
        notifyListeners();
      }
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  String _getAuthErrorMessage(dynamic error) {
    if (error is firebase_auth.FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No user found with this email address.';
        case 'wrong-password':
          return 'Incorrect password.';
        case 'invalid-email':
          return 'Invalid email address.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many failed attempts. Please try again later.';
        case 'network-request-failed':
          return 'Network error. Please check your connection.';
        default:
          return 'Authentication failed: ${error.message}';
      }
    }
    return 'An unexpected error occurred.';
  }
} 