import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'dart:async';
import '../models/user_model.dart';
import '../services/firebase_service.dart';

class AuthController extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _firebaseInitialized = false;
  bool _disposed = false;
  StreamSubscription<firebase_auth.User?>? _authStateSubscription;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'admin';
  bool get isGuide => _currentUser?.role == 'guide';
  bool get firebaseInitialized => _firebaseInitialized;
  bool get isDisposed => _disposed;

  AuthController() {
    print('🔐 AuthController created');
    _initializeAuth();
  }

  @override
  void dispose() {
    print('🗑️ AuthController disposed');
    _disposed = true;
    _authStateSubscription?.cancel();
    super.dispose();
  }

  // Safe state update method
  void _safeNotifyListeners() {
    if (!_disposed) {
      try {
        notifyListeners();
      } catch (e) {
        print('❌ Failed to notify listeners: $e');
      }
    }
  }

  void _initializeAuth() async {
    print('🔐 Initializing auth...');
    try {
      // Check if Firebase is available
      _firebaseInitialized = FirebaseService.currentUser != null || 
                            await _testFirebaseConnection();
      
      if (_firebaseInitialized) {
        print('✅ Firebase initialized, setting up auth listener');
        _authStateSubscription = FirebaseService.authStateChanges.listen((firebase_auth.User? firebaseUser) async {
          if (_disposed) {
            print('❌ AuthController disposed during auth state change');
            return;
          }
          
          print('🔄 Auth state changed: ${firebaseUser?.email ?? 'null'}');
          if (firebaseUser != null) {
            await _loadUserData(firebaseUser.uid);
          } else {
            _currentUser = null;
            _safeNotifyListeners();
          }
        });
      } else {
        print('⚠️ Firebase not initialized - running in offline mode');
        // Create a default user for development/testing
        _currentUser = User(
          id: 'dev-user',
          fullName: 'Development User',
          email: 'dev@auroraviking.com',
          phoneNumber: '',
          role: 'guide',
          profilePictureUrl: null,
          createdAt: DateTime.now(),
          isActive: true,
        );
        _safeNotifyListeners();
      }
    } catch (e) {
      print('❌ Auth initialization error: $e');
      _firebaseInitialized = false;
      // Create default user for development
      _currentUser = User(
        id: 'dev-user',
        fullName: 'Development User',
        email: 'dev@auroraviking.com',
        phoneNumber: '',
        role: 'guide',
        profilePictureUrl: null,
        createdAt: DateTime.now(),
        isActive: true,
      );
      _safeNotifyListeners();
    }
  }

  Future<bool> _testFirebaseConnection() async {
    try {
      // Try to access Firebase Auth to see if it's initialized
      final auth = firebase_auth.FirebaseAuth.instance;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadUserData(String uid) async {
    if (_disposed) {
      print('❌ AuthController disposed during user data load');
      return;
    }
    
    try {
      _setLoading(true);
      print('📥 Loading user data for: $uid');
      final userData = await FirebaseService.getUserData(uid);
      if (userData != null) {
        print('✅ User data loaded: ${userData.fullName} (${userData.role})');
        _currentUser = userData;
      } else {
        print('❌ Failed to load or create user data for: $uid');
        _error = 'Failed to load user data';
      }
      _error = null;
    } catch (e) {
      print('❌ Failed to load user data: $e');
      _error = 'Failed to load user data: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signIn(String email, String password) async {
    if (_disposed) {
      print('❌ AuthController disposed during sign in');
      return false;
    }
    
    print('🔐 Starting sign in for: $email');
    
    if (!_firebaseInitialized) {
      // In development mode, allow any login
      _currentUser = User(
        id: 'dev-user',
        fullName: 'Development User',
        email: email,
        phoneNumber: '',
        role: email.contains('admin') ? 'admin' : 'guide',
        profilePictureUrl: null,
        createdAt: DateTime.now(),
        isActive: true,
      );
      _safeNotifyListeners();
      print('✅ Development mode sign in successful');
      return true;
    }

    try {
      _setLoading(true);
      _error = null;
      
      await FirebaseService.signInWithEmailAndPassword(email, password);
      print('✅ Firebase sign in successful');
      return true;
    } catch (e) {
      print('❌ Sign in failed: $e');
      _error = _getAuthErrorMessage(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signUp(String email, String password, String fullName) async {
    if (_disposed) {
      print('❌ AuthController disposed during sign up');
      return false;
    }
    
    print('📝 Starting sign up for: $email ($fullName)');
    
    if (!_firebaseInitialized) {
      // In development mode, create a local user
      _currentUser = User(
        id: 'dev-user-${DateTime.now().millisecondsSinceEpoch}',
        fullName: fullName,
        email: email,
        phoneNumber: '',
        role: email.contains('admin') ? 'admin' : 'guide',
        profilePictureUrl: null,
        createdAt: DateTime.now(),
        isActive: true,
      );
      _safeNotifyListeners();
      print('✅ Development mode sign up successful');
      return true;
    }

    try {
      _setLoading(true);
      _error = null;
      
      final credential = await FirebaseService.createUserWithEmailAndPassword(email, password);
      
      if (credential.user != null) {
        print('✅ Firebase user created, saving user data');
        // Create user profile
        final user = User(
          id: credential.user!.uid,
          fullName: fullName,
          email: email,
          phoneNumber: '',
          role: 'guide', // Default role
          profilePictureUrl: null,
          createdAt: DateTime.now(),
          isActive: true,
        );
        
        await FirebaseService.saveUserData(user);
        _currentUser = user;
        _safeNotifyListeners();
        
        print('✅ Sign up successful: ${user.fullName}');
        return true;
      } else {
        print('❌ Failed to create user account');
        _error = 'Failed to create user account';
        return false;
      }
    } catch (e) {
      print('❌ Sign up failed: $e');
      _error = _getAuthErrorMessage(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> forgotPassword(String email) async {
    if (_disposed) {
      print('❌ AuthController disposed during password reset');
      return false;
    }
    
    print('🔑 Starting password reset for: $email');
    
    if (!_firebaseInitialized) {
      // In development mode, simulate success
      print('✅ Development mode password reset successful');
      return true;
    }

    try {
      _setLoading(true);
      _error = null;
      
      await FirebaseService.sendPasswordResetEmail(email);
      print('✅ Password reset email sent');
      return true;
    } catch (e) {
      print('❌ Password reset failed: $e');
      _error = _getAuthErrorMessage(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    if (_disposed) {
      print('❌ AuthController disposed during sign out');
      return;
    }
    
    print('🚪 Starting sign out');
    
    if (!_firebaseInitialized) {
      // In development mode, just clear the user
      _currentUser = null;
      _safeNotifyListeners();
      print('✅ Development mode sign out successful');
      return;
    }

    try {
      _setLoading(true);
      await FirebaseService.signOut();
      _currentUser = null;
      _error = null;
      print('✅ Firebase sign out successful');
    } catch (e) {
      print('❌ Sign out failed: $e');
      _error = 'Failed to sign out: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateUserRole(String role) async {
    if (_disposed) {
      print('❌ AuthController disposed during role update');
      return;
    }
    
    if (_currentUser != null) {
      try {
        _currentUser = _currentUser!.copyWith(role: role);
        if (_firebaseInitialized) {
          await FirebaseService.saveUserData(_currentUser!);
        }
        _safeNotifyListeners();
        print('✅ User role updated to: $role');
      } catch (e) {
        print('❌ Failed to update user role: $e');
        _error = 'Failed to update user role: $e';
        _safeNotifyListeners();
      }
    }
  }

  void clearError() {
    if (!_disposed) {
      _error = null;
      _safeNotifyListeners();
    }
  }

  void _setLoading(bool loading) {
    if (!_disposed) {
      _isLoading = loading;
      _safeNotifyListeners();
    }
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