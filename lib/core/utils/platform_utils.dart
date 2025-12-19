// Platform utilities for web-safe platform detection
// Use these helpers instead of dart:io Platform checks!

import 'package:flutter/foundation.dart' show kIsWeb;

/// Check if running on web platform
bool get isWeb => kIsWeb;

/// Check if running on mobile (Android or iOS)
/// Safe to use on web - will return false
bool get isMobile => !kIsWeb;

/// Check if the current platform supports location tracking
/// Web does NOT support background GPS tracking
bool get supportsLocationTracking => !kIsWeb;

/// Check if the current platform supports USB file access
/// Web does NOT support USB/SAF file access
bool get supportsUsbFileAccess => !kIsWeb;

/// Check if the current platform supports native foreground services
bool get supportsForegroundService => !kIsWeb;

/// Features available on current platform
class PlatformFeatures {
  /// Photo upload to Drive - requires native file system access
  static bool get uploadTab => !kIsWeb;
  
  /// GPS tracking - requires native location services
  static bool get trackingTab => !kIsWeb;
  
  /// Pickup list - works on all platforms (Firestore only)
  static bool get pickupListTab => true;
  
  /// Shift signup - works on all platforms (Firestore only)
  static bool get shiftSignupTab => true;
  
  /// Schedule/Forecast - works on all platforms
  static bool get forecastTab => true;
  
  /// Admin features that work on web
  static bool get adminDashboard => true;
  
  /// Admin map - needs Maps JavaScript API on web
  static bool get adminMap => true; // Google Maps supports web!
  
  /// Get list of tab IDs that should be shown on current platform
  static List<String> get availableTabs {
    final tabs = <String>['forecast', 'shifts', 'pickup'];
    if (uploadTab) tabs.insert(2, 'photos'); // After shifts
    if (trackingTab) tabs.insert(3, 'tracking'); // After photos or shifts
    return tabs;
  }
  
  /// Check if a specific tab should be shown
  static bool shouldShowTab(String tabId) {
    switch (tabId) {
      case 'photos':
      case 'upload':
        return uploadTab;
      case 'tracking':
        return trackingTab;
      case 'pickup':
      case 'pickup_list':
        return pickupListTab;
      case 'shifts':
      case 'shift_signup':
        return shiftSignupTab;
      case 'forecast':
      case 'schedule':
        return forecastTab;
      default:
        return true;
    }
  }
  
  /// Get a user-friendly message about why a feature isn't available
  static String getUnavailableMessage(String feature) {
    if (kIsWeb) {
      switch (feature) {
        case 'photos':
        case 'upload':
          return 'Photo upload requires the mobile app. Please use the tablet to upload photos from cameras.';
        case 'tracking':
          return 'GPS tracking requires the mobile app. Please use the tablet for live location sharing.';
        default:
          return 'This feature is not available on web.';
      }
    }
    return 'This feature is not available on this platform.';
  }
}

