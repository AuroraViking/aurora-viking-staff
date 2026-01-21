import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_controller.dart';

class AdminController extends ChangeNotifier {
  bool _isAdminMode = false;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasCheckedAutoLogin = false;
  
  bool get isAdminMode => _isAdminMode;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  
  /// Check if user is a Firebase admin and auto-enable admin mode
  /// Call this when the app starts or when the admin dashboard is accessed
  Future<void> checkAutoAdminLogin(BuildContext context) async {
    if (_hasCheckedAutoLogin && _isAdminMode) return;
    
    try {
      final authController = context.read<AuthController>();
      final user = authController.currentUser;
      
      if (user != null && user.isAdmin) {
        print('🔓 Auto-enabling admin mode for ${user.fullName} (isAdmin: true)');
        _isAdminMode = true;
        _hasCheckedAutoLogin = true;
        notifyListeners();
      }
    } catch (e) {
      print('⚠️ Error checking auto admin login: $e');
    }
  }
  
  // Login to admin mode (with password for non-admin users)
  Future<bool> loginToAdminMode(String password, {BuildContext? context}) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    
    try {
      // Check if user is already a Firebase admin
      if (context != null) {
        final authController = context.read<AuthController>();
        final user = authController.currentUser;
        
        if (user != null && user.isAdmin) {
          // Auto-login for Firebase admins - password is optional
          print('🔓 Firebase admin detected (${user.fullName}), granting access');
          _isAdminMode = true;
          _errorMessage = '';
          _hasCheckedAutoLogin = true;
          notifyListeners();
          return true;
        }
      }
      
      // For non-admin users, require password
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Use hardcoded password for non-admins (temporary solution)
      const adminPassword = 'aurora2024!';
      
      if (password == adminPassword) {
        _isAdminMode = true;
        _errorMessage = '';
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Invalid password. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'An error occurred. Please try again.';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Logout from admin mode
  void logoutFromAdminMode() {
    _isAdminMode = false;
    _errorMessage = '';
    _hasCheckedAutoLogin = false;
    notifyListeners();
  }
  
  // Check if admin session exists (for app restart)
  // Now checks Firebase user's isAdmin field
  Future<void> checkAdminSession(BuildContext context) async {
    await checkAutoAdminLogin(context);
  }
  
  // Clear error message
  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }
}