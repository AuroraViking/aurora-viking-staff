// Location service for handling GPS tracking and location data
// With proper background tracking support via native Android foreground service
// Now with proper web compatibility - tracking disabled on web!
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Method channel for communicating with native Android service
  static const MethodChannel _channel = MethodChannel('com.auroraviking.aurora_viking_staff/location');
  static const EventChannel _locationEventChannel = EventChannel('com.auroraviking.aurora_viking_staff/location_updates');
  
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<dynamic>? _nativeLocationSubscription;
  Timer? _locationUpdateTimer;
  Timer? _cleanupTimer;
  Timer? _keepAliveTimer;
  Timer? _heartbeatTimer;
  
  String? _currentBusId;
  String? _currentUserId;
  bool _isTracking = false;
  bool _isNativeServiceRunning = false;
  DateTime? _lastLocationUpdate;
  int _consecutiveErrors = 0;

  static const int _updateIntervalSeconds = 10;
  static const int _distanceFilterMeters = 5;
  static const int _historyRetentionHours = 2160; // 90 days
  static const int _maxConsecutiveErrors = 5;
  static const int _keepAliveIntervalSeconds = 30;
  static const int _locationTimeoutSeconds = 45;
  static const int _heartbeatIntervalSeconds = 60;

  bool get isTracking => _isTracking;
  String? get currentBusId => _currentBusId;
  
  /// Check if this platform supports location tracking
  /// Web does NOT support background location tracking
  static bool get isTrackingSupported => !kIsWeb;

  Future<bool> initialize() async {
    // On web, we can still initialize but with limited functionality
    if (kIsWeb) {
      print('ℹ️ LocationService running in web mode - tracking disabled');
      _startCleanupTimer();
      return true;
    }
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions are denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        return false;
      }

      await _requestBackgroundLocationPermission();
      await _requestAdditionalPermissions();
      _setupMethodChannelHandlers();
      _startCleanupTimer();
      
      print('✅ LocationService initialized successfully');
      return true;
    } catch (e) {
      print('❌ Error initializing LocationService: $e');
      return false;
    }
  }

  Future<void> _requestBackgroundLocationPermission() async {
    if (kIsWeb) return;
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.whileInUse) {
        print('🔒 Current permission is "while in use", requesting background permission...');
        
        final backgroundStatus = await Permission.locationAlways.status;
        if (!backgroundStatus.isGranted) {
          print('🔒 Requesting ACCESS_BACKGROUND_LOCATION permission...');
          final result = await Permission.locationAlways.request();
          if (result.isGranted) {
            print('✅ Background location permission granted');
          } else {
            print('⚠️ Background location permission denied - tracking may stop when app is backgrounded');
          }
        }
      }
    } catch (e) {
      print('⚠️ Error requesting background location permission: $e');
    }
  }

  Future<void> _requestAdditionalPermissions() async {
    if (kIsWeb) return;
    
    try {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        print('🔋 Requesting battery optimization bypass...');
        final result = await Permission.ignoreBatteryOptimizations.request();
        if (result.isGranted) {
          print('✅ Battery optimization bypass granted');
        } else {
          print('⚠️ Battery optimization bypass denied - tracking may be affected');
        }
      }

      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        print('🔔 Requesting notification permission...');
        await Permission.notification.request();
      }
    } catch (e) {
      print('⚠️ Some additional permissions could not be requested: $e');
    }
  }

  void _setupMethodChannelHandlers() {
    if (kIsWeb) return; // Method channels don't work on web
    
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onLocationUpdate':
          final Map<dynamic, dynamic> locationData = call.arguments;
          await _handleNativeLocationUpdate(locationData);
          break;
        case 'onServiceStopped':
          print('⚠️ Native location service stopped unexpectedly');
          _isNativeServiceRunning = false;
          if (_isTracking && _currentBusId != null && _currentUserId != null) {
            print('🔄 Attempting to restart native service...');
            await _startNativeService(_currentBusId!, _currentUserId!);
          }
          break;
        case 'onServiceError':
          final String error = call.arguments ?? 'Unknown error';
          print('❌ Native service error: $error');
          break;
        default:
          print('⚠️ Unknown method call from native: ${call.method}');
      }
    });

    _nativeLocationSubscription = _locationEventChannel
        .receiveBroadcastStream()
        .listen(
          (dynamic event) {
            if (event is Map) {
              _handleNativeLocationUpdate(event);
            }
          },
          onError: (error) {
            print('❌ Native location stream error: $error');
          },
        );
  }

  Future<void> _handleNativeLocationUpdate(Map<dynamic, dynamic> locationData) async {
    try {
      final double latitude = (locationData['latitude'] as num).toDouble();
      final double longitude = (locationData['longitude'] as num).toDouble();
      final double accuracy = (locationData['accuracy'] as num?)?.toDouble() ?? 0.0;
      final double altitude = (locationData['altitude'] as num?)?.toDouble() ?? 0.0;
      final double speed = (locationData['speed'] as num?)?.toDouble() ?? 0.0;
      final double heading = (locationData['heading'] as num?)?.toDouble() ?? 0.0;

      _consecutiveErrors = 0;
      _lastLocationUpdate = DateTime.now();

      if (_currentBusId != null && _currentUserId != null) {
        await _saveLocationToFirebase(
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
          altitude: altitude,
          speed: speed,
          heading: heading,
          busId: _currentBusId!,
          userId: _currentUserId!,
        );
      }
    } catch (e) {
      print('❌ Error handling native location update: $e');
    }
  }

  Future<bool> startTracking(String busId, String userId) async {
    // Tracking is not supported on web
    if (kIsWeb) {
      print('❌ Location tracking is not supported on web');
      return false;
    }
    
    try {
      if (_isTracking) {
        await stopTracking();
      }

      _currentBusId = busId;
      _currentUserId = userId;
      _isTracking = true;
      _consecutiveErrors = 0;

      final nativeStarted = await _startNativeService(busId, userId);
      if (nativeStarted) {
        print('✅ Native foreground service started successfully');
      } else {
        print('⚠️ Failed to start native service, falling back to Flutter-only tracking');
      }

      await _startFlutterTracking(busId, userId);
      _startHeartbeat(busId, userId);
      _startKeepAliveMechanism(busId, userId);

      print('✅ Started tracking for bus: $busId');
      return true;
    } catch (e) {
      print('❌ Error starting tracking: $e');
      _isTracking = false;
      return false;
    }
  }

  Future<bool> _startNativeService(String busId, String userId) async {
    if (kIsWeb) return false;
    
    try {
      final result = await _channel.invokeMethod('startLocationService', {
        'busId': busId,
        'userId': userId,
        'updateIntervalMs': _updateIntervalSeconds * 1000,
        'distanceFilterMeters': _distanceFilterMeters,
      });
      
      _isNativeServiceRunning = result == true;
      return _isNativeServiceRunning;
    } catch (e) {
      print('❌ Error starting native service: $e');
      return false;
    }
  }

  Future<void> _stopNativeService() async {
    if (kIsWeb) return;
    
    try {
      await _channel.invokeMethod('stopLocationService');
      _isNativeServiceRunning = false;
    } catch (e) {
      print('❌ Error stopping native service: $e');
    }
  }

  Future<void> _startFlutterTracking(String busId, String userId) async {
    if (kIsWeb) return;
    
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _distanceFilterMeters,
        intervalDuration: Duration(seconds: _updateIntervalSeconds),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Aurora Viking Staff",
          notificationText: "Tracking bus location in background",
          enableWakeLock: true,
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        ),
      ),
    ).listen(
      (Position position) {
        _consecutiveErrors = 0;
        _lastLocationUpdate = DateTime.now();
        _saveLocationToFirebase(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speed: position.speed,
          heading: position.heading,
          busId: busId,
          userId: userId,
        );
      },
      onError: (error) {
        print('❌ Flutter location stream error: $error');
        _consecutiveErrors++;
      },
      cancelOnError: false,
    );

    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(
      Duration(seconds: _updateIntervalSeconds),
      (timer) async {
        if (!_isTracking) {
          timer.cancel();
          return;
        }
        
        if (_lastLocationUpdate == null || 
            DateTime.now().difference(_lastLocationUpdate!).inSeconds > _updateIntervalSeconds * 2) {
          await _fetchAndSaveLocation(busId, userId);
        }
      },
    );
  }

  Future<void> _fetchAndSaveLocation(String busId, String userId) async {
    if (kIsWeb) return;
    
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      
      _consecutiveErrors = 0;
      _lastLocationUpdate = DateTime.now();
      
      await _saveLocationToFirebase(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        busId: busId,
        userId: userId,
      );
    } catch (e) {
      print('❌ Error fetching location: $e');
      _consecutiveErrors++;
    }
  }

  void _startHeartbeat(String busId, String userId) {
    if (kIsWeb) return;
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _heartbeatIntervalSeconds),
      (timer) async {
        if (!_isTracking) {
          timer.cancel();
          return;
        }

        if (_isNativeServiceRunning) {
          try {
            await _channel.invokeMethod('heartbeat');
          } catch (e) {
            print('⚠️ Heartbeat failed, service may have stopped');
            _isNativeServiceRunning = false;
          }
        }

        try {
          await _firestore.collection('bus_locations').doc(busId).update({
            'isTracking': true,
            'lastHeartbeat': Timestamp.now(),
          });
        } catch (e) {
          // Document might not exist yet, that's ok
        }
      },
    );
  }

  void _startKeepAliveMechanism(String busId, String userId) {
    if (kIsWeb) return;
    
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      Duration(seconds: _keepAliveIntervalSeconds),
      (timer) async {
        if (!_isTracking) {
          timer.cancel();
          return;
        }

        if (_lastLocationUpdate != null) {
          final timeSinceLastUpdate = DateTime.now().difference(_lastLocationUpdate!);
          
          if (timeSinceLastUpdate.inSeconds > _locationTimeoutSeconds) {
            print('⚠️ No location updates for ${timeSinceLastUpdate.inSeconds}s');
            
            if (!_isNativeServiceRunning) {
              print('🔄 Restarting native service...');
              await _startNativeService(busId, userId);
            }
            
            await _fetchAndSaveLocation(busId, userId);
          }
        } else {
          print('⚠️ No location updates yet, forcing fetch...');
          await _fetchAndSaveLocation(busId, userId);
        }

        try {
          final isRunning = await _channel.invokeMethod('isServiceRunning');
          if (isRunning != true && _isTracking) {
            print('⚠️ Native service not running, restarting...');
            await _startNativeService(busId, userId);
          }
        } catch (e) {
          print('⚠️ Could not check native service status: $e');
        }
      },
    );
  }

  Future<void> stopTracking() async {
    try {
      _isTracking = false;
      
      if (!kIsWeb) {
        await _stopNativeService();
      }
      
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;

      if (_currentBusId != null) {
        try {
          await _firestore.collection('bus_locations').doc(_currentBusId).update({
            'isTracking': false,
            'stoppedAt': Timestamp.now(),
          });
        } catch (e) {
          // Ignore errors
        }
      }

      _currentBusId = null;
      _currentUserId = null;
      _lastLocationUpdate = null;
      _consecutiveErrors = 0;
      
      print('🛑 Stopped tracking');
    } catch (e) {
      print('❌ Error stopping tracking: $e');
    }
  }

  Future<void> _saveLocationToFirebase({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double altitude,
    required double speed,
    required double heading,
    required String busId,
    required String userId,
  }) async {
    try {
      final timestamp = Timestamp.now();
      
      await _firestore.collection('bus_locations').doc(busId).set({
        'busId': busId,
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'timestamp': timestamp,
        'lastUpdated': timestamp,
        'isTracking': true,
      });

      await _firestore.collection('location_history').add({
        'busId': busId,
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'timestamp': timestamp,
      });

      print('📍 Saved location for bus $busId: $latitude, $longitude (accuracy: ${accuracy.toStringAsFixed(1)}m)');
    } catch (e) {
      print('❌ Error saving location to Firebase: $e');
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _cleanupOldLocationHistory();
    });
  }

  Future<void> _cleanupOldLocationHistory() async {
    try {
      final cutoffTime = DateTime.now().subtract(Duration(hours: _historyRetentionHours));
      final cutoffTimestamp = Timestamp.fromDate(cutoffTime);

      QuerySnapshot oldEntries;
      int totalDeleted = 0;
      
      do {
        oldEntries = await _firestore
            .collection('location_history')
            .where('timestamp', isLessThan: cutoffTimestamp)
            .limit(500)
            .get();

        if (oldEntries.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in oldEntries.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          totalDeleted += oldEntries.docs.length;
        }
      } while (oldEntries.docs.length == 500);

      if (totalDeleted > 0) {
        print('🧹 Cleaned up $totalDeleted old location history entries');
      }
    } catch (e) {
      print('❌ Error cleaning up location history: $e');
    }
  }

  // === READ-ONLY METHODS (work on web too!) ===
  
  Future<Map<String, dynamic>?> getBusLocation(String busId) async {
    try {
      final doc = await _firestore.collection('bus_locations').doc(busId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ Error getting bus location: $e');
      return null;
    }
  }

  Stream<DocumentSnapshot> getBusLocationStream(String busId) {
    return _firestore.collection('bus_locations').doc(busId).snapshots();
  }

  Stream<QuerySnapshot> getAllBusLocations() {
    return _firestore
        .collection('bus_locations')
        .where('isTracking', isEqualTo: true)
        .orderBy('lastUpdated', descending: true)
        .snapshots();
  }

  /// Get all bus locations including those not currently tracking
  /// This shows the last known position for all buses
  Stream<QuerySnapshot> getAllBusLocationsWithLastKnown() {
    return _firestore
        .collection('bus_locations')
        .orderBy('lastUpdated', descending: true)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> getBusLocationHistory(
    String busId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore
          .collection('location_history')
          .where('busId', isEqualTo: busId)
          .orderBy('timestamp', descending: true);

      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      final snapshot = await query.limit(1000).get();
      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } catch (e) {
      print('❌ Error getting bus location history: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBusLocationTrail(
    String busId, {
    int hours = 48,
  }) async {
    try {
      final cutoffTime = DateTime.now().subtract(Duration(hours: hours));
      final cutoffTimestamp = Timestamp.fromDate(cutoffTime);

      final snapshot = await _firestore
          .collection('location_history')
          .where('busId', isEqualTo: busId)
          .where('timestamp', isGreaterThan: cutoffTimestamp)
          .orderBy('timestamp', descending: false)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Error getting bus location trail: $e');
      return [];
    }
  }

  Future<Position?> getCurrentLocation() async {
    if (kIsWeb) return null;
    
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  Future<Map<String, bool>> checkPermissions() async {
    final permissions = <String, bool>{};
    
    if (kIsWeb) {
      // On web, just return basic info
      permissions['locationServices'] = false;
      permissions['locationWhenInUse'] = false;
      permissions['locationAlways'] = false;
      permissions['isWeb'] = true;
      return permissions;
    }
    
    permissions['locationServices'] = await Geolocator.isLocationServiceEnabled();
    
    final locationPermission = await Geolocator.checkPermission();
    permissions['locationWhenInUse'] = locationPermission == LocationPermission.whileInUse || 
                                        locationPermission == LocationPermission.always;
    permissions['locationAlways'] = locationPermission == LocationPermission.always;
    permissions['ignoreBatteryOptimizations'] = await Permission.ignoreBatteryOptimizations.isGranted;
    permissions['notification'] = await Permission.notification.isGranted;
    
    return permissions;
  }

  void dispose() {
    _positionStreamSubscription?.cancel();
    _nativeLocationSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _cleanupTimer?.cancel();
    _keepAliveTimer?.cancel();
    _heartbeatTimer?.cancel();
    if (!kIsWeb) {
      _stopNativeService();
    }
    _isTracking = false;
  }
}
