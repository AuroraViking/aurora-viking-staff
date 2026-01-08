import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

/// Top-level function to handle background messages
/// Must be top-level function, not a class method
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('🔔 Background message received: ${message.messageId}');
  print('   Title: ${message.notification?.title}');
  print('   Body: ${message.notification?.body}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static FirebaseMessaging? _messaging;
  static FlutterLocalNotificationsPlugin? _localNotifications;
  static bool _initialized = false;
  static String? _currentFcmToken;

  // Initialize notification service
  static Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      print('ℹ️ Notifications already initialized or running on web');
      return;
    }

    try {
      print('🔔 Initializing notification service...');
      
      // Initialize Firebase Cloud Messaging
      _messaging = FirebaseMessaging.instance;
      print('✅ FirebaseMessaging instance created');

      // Request notification permissions
      NotificationSettings settings = await _messaging!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('🔔 Notification permission status: ${settings.authorizationStatus}');
      print('   Alert: ${settings.alert}');
      print('   Badge: ${settings.badge}');
      print('   Sound: ${settings.sound}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Initialize local notifications for foreground messages
        _localNotifications = FlutterLocalNotificationsPlugin();

        // Android initialization
        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        // iOS initialization (if you plan to support iOS)
        const DarwinInitializationSettings initializationSettingsIOS =
            DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        const InitializationSettings initializationSettings =
            InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

        await _localNotifications!.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            print('🔔 Notification tapped: ${response.payload}');
          },
        );

        // Create Android notification channel for push notifications
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'aurora_viking_staff',
          'Aurora Viking Staff Notifications',
          description: 'Notifications for Aurora Viking Staff app',
          importance: Importance.high,
        );

        await _localNotifications!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        // Set up foreground message handler
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Set up background message handler
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

        // Set up notification tap handler
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

        // Check if app was opened from a notification
        RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
        if (initialMessage != null) {
          _handleMessageOpenedApp(initialMessage);
        }

        // Get and save FCM token
        await _saveFcmToken();

        // Listen for token refresh
        _messaging!.onTokenRefresh.listen((newToken) {
          print('🔔 FCM token refreshed: $newToken');
          _saveFcmToken();
        });

        _initialized = true;
        print('✅ Notification service initialized successfully');
      } else {
        print('❌ Notification permission denied');
      }
    } catch (e) {
      print('❌ Failed to initialize notification service: $e');
    }
  }

  // Handle foreground messages (app is open)
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('🔔 Foreground message received:');
    print('   Title: ${message.notification?.title}');
    print('   Body: ${message.notification?.body}');
    print('   Data: ${message.data}');

    // Show local notification when app is in foreground
    if (_localNotifications != null && message.notification != null) {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'aurora_viking_staff',
        'Aurora Viking Staff Notifications',
        channelDescription: 'Notifications for Aurora Viking Staff app',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _localNotifications!.show(
        message.hashCode,
        message.notification?.title ?? 'Aurora Viking Staff',
        message.notification?.body ?? '',
        platformChannelSpecifics,
        payload: message.data.toString(),
      );
    }
  }

  // Handle notification tap (when app is opened from notification)
  static void _handleMessageOpenedApp(RemoteMessage message) {
    print('🔔 Notification opened app:');
    print('   Title: ${message.notification?.title}');
    print('   Body: ${message.notification?.body}');
    print('   Data: ${message.data}');
    // TODO: Navigate to appropriate screen based on message.data
  }

  // Get FCM token and save to Firestore
  static Future<String?> _saveFcmToken() async {
    if (_messaging == null || kIsWeb) {
      print('⚠️ Cannot save FCM token: messaging is null or running on web');
      return null;
    }

    try {
      print('🔔 Requesting FCM token...');
      final token = await _messaging!.getToken();
      if (token == null) {
        print('⚠️ FCM token is null - this might indicate a Google Play Services issue');
        print('   Check:');
        print('   1. Google Play Services is installed and up to date');
        print('   2. google-services.json is in android/app/');
        print('   3. SHA-1/SHA-256 fingerprints are added to Firebase Console');
        return null;
      }

      _currentFcmToken = token;
      print('🔔 FCM Token received: ${token.substring(0, 20)}...');

      // Save token to Firestore under the user's document
      final user = FirebaseService.currentUser;
      if (user != null) {
        print('💾 Saving FCM token to Firestore for user: ${user.uid}');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print('✅ FCM token saved to Firestore successfully');
      } else {
        print('⚠️ No authenticated user, cannot save FCM token');
        print('   Token will be saved after user logs in');
      }

      return token;
    } catch (e, stackTrace) {
      print('❌ Failed to get/save FCM token: $e');
      print('   Stack trace: $stackTrace');
      if (e.toString().contains('DEVELOPER_ERROR')) {
        print('   ⚠️ DEVELOPER_ERROR detected - this usually means:');
        print('      1. SHA-1/SHA-256 fingerprints missing in Firebase Console');
        print('      2. Package name mismatch in google-services.json');
        print('      3. Google Play Services not properly configured');
      }
      return null;
    }
  }

  // Get current FCM token
  static String? get currentFcmToken => _currentFcmToken;

  // Save FCM token if needed (called after login)
  static Future<void> saveFcmTokenIfNeeded() async {
    if (_initialized && !kIsWeb) {
      print('🔔 Saving FCM token after login...');
      await _saveFcmToken();
    }
  }

  // Check if notifications are initialized
  static bool get isInitialized => _initialized;

  // Subscribe to a topic (useful for group notifications)
  static Future<void> subscribeToTopic(String topic) async {
    if (_messaging == null || kIsWeb) return;

    try {
      await _messaging!.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Failed to subscribe to topic $topic: $e');
    }
  }

  // Unsubscribe from a topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    if (_messaging == null || kIsWeb) return;

    try {
      await _messaging!.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Failed to unsubscribe from topic $topic: $e');
    }
  }

  // Delete FCM token (for logout)
  static Future<void> deleteToken() async {
    if (_messaging == null || kIsWeb) return;

    try {
      await _messaging!.deleteToken();
      _currentFcmToken = null;

      // Remove token from Firestore
      final user = FirebaseService.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'fcmToken': FieldValue.delete(),
        });
        print('✅ FCM token deleted');
      }
    } catch (e) {
      print('❌ Failed to delete FCM token: $e');
    }
  }
}

