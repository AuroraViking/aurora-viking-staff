// Location service for handling GPS tracking and location data
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _locationUpdateTimer;
  Timer? _cleanupTimer;
  Timer? _keepAliveTimer;
  Timer? _restartTimer;
  
  String? _currentBusId;
  bool _isTracking = false;
  DateTime? _lastLocationUpdate;
  int _consecutiveErrors = 0;

  static const int _updateIntervalSeconds = 15; // Reduced for better tracking
  static const int _distanceFilterMeters = 5; // More precise tracking
  static const int _historyRetentionHours = 48; // 48-hour history
  static const int _maxConsecutiveErrors = 5; // Max errors before restart
  static const int _keepAliveIntervalSeconds = 30; // Keep-alive check interval
  static const int _locationTimeoutSeconds = 60; // Timeout before considering tracking dead

  bool get isTracking => _isTracking;
  String? get currentBusId => _currentBusId;

  Future<bool> initialize() async {
    try {
      // Check location permissions with enhanced permission handling
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return false;
      }

      // Request precise location permission
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

      // Request background location permission
      if (permission == LocationPermission.whileInUse) {
        print('🔒 Requesting background location permission...');
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.always) {
          print('⚠️ Background location permission not granted, tracking may be limited');
        }
      }

      // Request additional permissions for better tracking
      await _requestAdditionalPermissions();

      // Start cleanup timer to remove old location history
      _startCleanupTimer();
      
      print('✅ LocationService initialized successfully');
      return true;
    } catch (e) {
      print('❌ Error initializing LocationService: $e');
      return false;
    }
  }

  Future<void> _requestAdditionalPermissions() async {
    try {
      // Request ignore battery optimization permission
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        print('🔋 Requesting battery optimization bypass...');
        await Permission.ignoreBatteryOptimizations.request();
      }

      // Request system alert window for better foreground service
      if (await Permission.systemAlertWindow.isDenied) {
        print('🪟 Requesting system alert window permission...');
        await Permission.systemAlertWindow.request();
      }
    } catch (e) {
      print('⚠️ Some additional permissions could not be requested: $e');
    }
  }

  Future<bool> startTracking(String busId, String userId) async {
    try {
      if (_isTracking) {
        await stopTracking();
      }

      _currentBusId = busId;
      _isTracking = true;

      // Start location stream with high accuracy and frequent updates
      // Removed timeLimit to prevent stream from stopping
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, // Best accuracy for navigation
          distanceFilter: _distanceFilterMeters,
          // Removed timeLimit to allow continuous tracking
        ),
      ).listen(
        (Position position) {
          _consecutiveErrors = 0; // Reset error count on successful update
          _lastLocationUpdate = DateTime.now();
          _saveLocationToFirebase(position, busId, userId);
        },
        onError: (error) {
          print('❌ Location stream error: $error');
          _consecutiveErrors++;
          // Don't stop tracking on errors, just log them
          // If too many errors, restart the stream
          if (_consecutiveErrors >= _maxConsecutiveErrors) {
            print('⚠️ Too many consecutive errors, restarting location stream...');
            _restartLocationStream(busId, userId);
          }
        },
        cancelOnError: false, // Don't cancel stream on errors
      );

      // Set up periodic location updates for history with backup positioning
      _locationUpdateTimer = Timer.periodic(
        Duration(seconds: _updateIntervalSeconds),
        (timer) async {
          if (_isTracking) {
            try {
              final position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.bestForNavigation,
                // Removed timeLimit to prevent timeout
              );
              _consecutiveErrors = 0;
              _lastLocationUpdate = DateTime.now();
              _saveLocationToFirebase(position, busId, userId);
            } catch (e) {
              print('❌ Error getting periodic location: $e');
              _consecutiveErrors++;
              // Try with lower accuracy as fallback
              try {
                final fallbackPosition = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high,
                  // Removed timeLimit
                );
                _consecutiveErrors = 0;
                _lastLocationUpdate = DateTime.now();
                _saveLocationToFirebase(fallbackPosition, busId, userId);
              } catch (fallbackError) {
                print('❌ Fallback location also failed: $fallbackError');
                // Don't stop tracking, just continue trying
              }
            }
          } else {
            timer.cancel();
          }
        },
      );

      // Start keep-alive mechanism to ensure tracking continues
      _startKeepAliveMechanism(busId, userId);

      print('✅ Started tracking for bus: $busId with enhanced accuracy and keep-alive');
      return true;
    } catch (e) {
      print('❌ Error starting tracking: $e');
      _isTracking = false;
      return false;
    }
  }

  Future<void> stopTracking() async {
    try {
      _isTracking = false;
      _positionStreamSubscription?.cancel();
      _locationUpdateTimer?.cancel();
      _keepAliveTimer?.cancel();
      _restartTimer?.cancel();
      _currentBusId = null;
      _lastLocationUpdate = null;
      _consecutiveErrors = 0;
      
      print('🛑 Stopped tracking');
    } catch (e) {
      print('❌ Error stopping tracking: $e');
    }
  }

  // Keep-alive mechanism to ensure tracking continues
  void _startKeepAliveMechanism(String busId, String userId) {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      Duration(seconds: _keepAliveIntervalSeconds),
      (timer) {
        if (!_isTracking) {
          timer.cancel();
          return;
        }

        // Check if we haven't received location updates in a while
        if (_lastLocationUpdate != null) {
          final timeSinceLastUpdate = DateTime.now().difference(_lastLocationUpdate!);
          if (timeSinceLastUpdate.inSeconds > _locationTimeoutSeconds) {
            print('⚠️ No location updates for ${timeSinceLastUpdate.inSeconds}s, restarting stream...');
            _restartLocationStream(busId, userId);
          }
        } else {
          // If we never got a location update, try to get one now
          print('⚠️ No location updates yet, forcing location check...');
          _forceLocationUpdate(busId, userId);
        }
      },
    );
  }

  // Restart location stream if it stops
  void _restartLocationStream(String busId, String userId) {
    print('🔄 Restarting location stream...');
    _positionStreamSubscription?.cancel();
    _consecutiveErrors = 0;
    
    // Restart the stream
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _distanceFilterMeters,
      ),
    ).listen(
      (Position position) {
        _consecutiveErrors = 0;
        _lastLocationUpdate = DateTime.now();
        _saveLocationToFirebase(position, busId, userId);
      },
      onError: (error) {
        print('❌ Location stream error after restart: $error');
        _consecutiveErrors++;
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          // Schedule another restart attempt
          _scheduleRestart(busId, userId);
        }
      },
      cancelOnError: false,
    );
  }

  // Force a location update
  Future<void> _forceLocationUpdate(String busId, String userId) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _consecutiveErrors = 0;
      _lastLocationUpdate = DateTime.now();
      _saveLocationToFirebase(position, busId, userId);
    } catch (e) {
      print('❌ Error forcing location update: $e');
    }
  }

  // Schedule a restart attempt
  void _scheduleRestart(String busId, String userId) {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 30), () {
      if (_isTracking) {
        _restartLocationStream(busId, userId);
      }
    });
  }

  Future<void> _saveLocationToFirebase(Position position, String busId, String userId) async {
    try {
      final timestamp = Timestamp.now();
      
      // Save current location
      await _firestore.collection('bus_locations').doc(busId).set({
        'busId': busId,
        'userId': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': timestamp,
        'lastUpdated': timestamp,
      });

      // Save to location history
      await _firestore.collection('location_history').add({
        'busId': busId,
        'userId': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': timestamp,
      });

      print('📍 Saved location for bus $busId: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('❌ Error saving location to Firebase: $e');
    }
  }

  void _startCleanupTimer() {
    // Run cleanup every hour
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _cleanupOldLocationHistory();
    });
  }

  Future<void> _cleanupOldLocationHistory() async {
    try {
      final cutoffTime = DateTime.now().subtract(Duration(hours: _historyRetentionHours));
      final cutoffTimestamp = Timestamp.fromDate(cutoffTime);

      // Delete old location history entries
      final oldEntries = await _firestore
          .collection('location_history')
          .where('timestamp', isLessThan: cutoffTimestamp)
          .get();

      if (oldEntries.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in oldEntries.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('🧹 Cleaned up ${oldEntries.docs.length} old location history entries');
      }
    } catch (e) {
      print('❌ Error cleaning up location history: $e');
    }
  }

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

  Stream<QuerySnapshot> getAllBusLocations() {
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

      // Apply date filters if provided
      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      final snapshot = await query.get();
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
          .orderBy('timestamp', descending: false) // Oldest first for trail
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Error getting bus location trail: $e');
      return [];
    }
  }

  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  void dispose() {
    _positionStreamSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _cleanupTimer?.cancel();
    _keepAliveTimer?.cancel();
    _restartTimer?.cancel();
    _isTracking = false;
  }
} 