// Location service for handling GPS tracking and location data
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _locationUpdateTimer;
  Timer? _cleanupTimer;
  
  String? _currentBusId;
  String? _currentUserId;
  bool _isTracking = false;

  static const int _updateIntervalSeconds = 15; // Reduced for better tracking
  static const int _distanceFilterMeters = 5; // More precise tracking
  static const int _historyRetentionHours = 48; // 48-hour history

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
      _currentUserId = userId;
      _isTracking = true;

      // Start location stream with high accuracy and frequent updates
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, // Best accuracy for navigation
          distanceFilter: _distanceFilterMeters,
          timeLimit: Duration(seconds: 30), // Timeout for location requests
        ),
      ).listen(
        (Position position) {
          _saveLocationToFirebase(position, busId, userId);
        },
        onError: (error) {
          print('❌ Location stream error: $error');
        },
      );

      // Set up periodic location updates for history with backup positioning
      _locationUpdateTimer = Timer.periodic(
        Duration(seconds: _updateIntervalSeconds),
        (timer) async {
          if (_isTracking) {
            try {
              final position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.bestForNavigation,
                timeLimit: const Duration(seconds: 15),
              );
              _saveLocationToFirebase(position, busId, userId);
            } catch (e) {
              print('❌ Error getting periodic location: $e');
              // Try with lower accuracy as fallback
              try {
                final fallbackPosition = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high,
                  timeLimit: const Duration(seconds: 10),
                );
                _saveLocationToFirebase(fallbackPosition, busId, userId);
              } catch (fallbackError) {
                print('❌ Fallback location also failed: $fallbackError');
              }
            }
          } else {
            timer.cancel();
          }
        },
      );

      print('✅ Started tracking for bus: $busId with enhanced accuracy');
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
      _currentBusId = null;
      _currentUserId = null;
      
      print('🛑 Stopped tracking');
    } catch (e) {
      print('❌ Error stopping tracking: $e');
    }
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

      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
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
    _isTracking = false;
  }
} 