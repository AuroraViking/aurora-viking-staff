// Tracking screen for guide-side location sending and admin-side map view 
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';
import '../../core/services/bus_management_service.dart';
import '../../core/services/platform_service.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  String? _selectedBus;
  bool _isTracking = false;
  Position? _currentPosition;
  String _status = 'Not tracking.';
  Timer? _positionUpdateTimer;
  
  // Permission and optimization status
  bool _hasPreciseLocation = false;
  bool _hasBackgroundLocation = false;
  bool _ignoresBatteryOptimization = false;
  bool _isOptimizedForTracking = false;
  
  final LocationService _locationService = LocationService();
  final BusManagementService _busService = BusManagementService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> _buses = [];
  bool _isLoadingBuses = true;

  @override
  void initState() {
    super.initState();
    _checkAllPermissions();
    _loadBuses();
    _checkTrackingStatus();
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }

  Future<void> _checkAllPermissions() async {
    await _checkLocationPermission();
    await _checkBatteryOptimization();
    await _checkTrackingOptimization();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = 'Location services are disabled.';
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _status = 'Location permissions are denied.';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status = 'Location permissions are permanently denied.';
      });
      return;
    }

    // Check for precise location
    _hasPreciseLocation = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    
    // Check for background location
    _hasBackgroundLocation = permission == LocationPermission.always;

    setState(() {
      _status = _hasBackgroundLocation ? 'Ready to track (background enabled).' : 'Ready to track (foreground only).';
    });
  }

  Future<void> _checkBatteryOptimization() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    _ignoresBatteryOptimization = status.isGranted;
    
    if (!_ignoresBatteryOptimization) {
      print('🔋 Battery optimization is enabled - this may affect tracking reliability');
    }
  }

  Future<void> _checkTrackingOptimization() async {
    _isOptimizedForTracking = _hasPreciseLocation && _hasBackgroundLocation && _ignoresBatteryOptimization;
  }

  Future<void> _requestBatteryOptimizationBypass() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (status.isGranted) {
        setState(() {
          _ignoresBatteryOptimization = true;
        });
        await _checkTrackingOptimization();
        _showAlert('Battery optimization bypass granted! Tracking will be more reliable.');
      } else {
        _showAlert('Battery optimization bypass denied. Tracking may be interrupted when the app is in the background.');
      }
    } catch (e) {
      print('❌ Error requesting battery optimization bypass: $e');
    }
  }

  Future<void> _requestBackgroundLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.always) {
          setState(() {
            _hasBackgroundLocation = true;
          });
          await _checkTrackingOptimization();
          _showAlert('Background location permission granted! Tracking will continue when the app is minimized.');
        } else {
          _showAlert('Background location permission denied. Tracking will stop when the app is minimized.');
        }
      }
    } catch (e) {
      print('❌ Error requesting background location: $e');
    }
  }

  void _loadBuses() {
    print('🔄 Loading buses...');
    
    // Set a timeout to prevent infinite loading
    Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoadingBuses) {
        print('⏰ Bus loading timeout, using fallback buses');
        setState(() {
          _isLoadingBuses = false;
          if (_buses.isEmpty) {
            _buses = [
              {'id': 'luxusinn_ayx70', 'name': 'Lúxusinn - AYX70', 'licensePlate': 'AYX70'},
              {'id': 'afi_stjani_maf43', 'name': 'Afi Stjáni - MAF43', 'licensePlate': 'MAF43'},
              {'id': 'meistarinn_tze50', 'name': 'Meistarinn - TZE50', 'licensePlate': 'TZE50'},
            ];
          }
        });
      }
    });
    
    _busService.getActiveBuses().listen(
      (buses) {
        print('📋 Loaded ${buses.length} buses');
        for (final bus in buses) {
          print('  - ${bus['name']} (${bus['licensePlate']})');
        }
        if (mounted) {
          setState(() {
            _buses = buses;
            _isLoadingBuses = false;
          });
        }
      },
      onError: (error) {
        print('❌ Error loading buses: $error');
        print('🔄 Using fallback bus list...');
        // Fallback to hardcoded buses if database fails
        final fallbackBuses = [
          {'id': 'luxusinn_ayx70', 'name': 'Lúxusinn - AYX70', 'licensePlate': 'AYX70'},
          {'id': 'afi_stjani_maf43', 'name': 'Afi Stjáni - MAF43', 'licensePlate': 'MAF43'},
          {'id': 'meistarinn_tze50', 'name': 'Meistarinn - TZE50', 'licensePlate': 'TZE50'},
        ];
        if (mounted) {
          setState(() {
            _buses = fallbackBuses;
            _isLoadingBuses = false;
          });
        }
      },
      onDone: () {
        print('✅ Bus loading stream completed');
        if (mounted && _isLoadingBuses) {
          setState(() {
            _isLoadingBuses = false;
          });
        }
      },
    );
  }

  Future<void> _checkTrackingStatus() async {
    if (_locationService.isTracking) {
      setState(() {
        _isTracking = true;
        _selectedBus = _locationService.currentBusId;
        _status = 'Resuming tracking: ${_getBusNameById(_locationService.currentBusId)}';
      });
      _startPositionUpdates();
    }
  }

  String _getBusNameById(String? busId) {
    if (busId == null) return 'Unknown Bus';
    try {
      final bus = _buses.firstWhere(
        (bus) => bus['id'] == busId,
      );
      return bus['name'] as String? ?? 'Unknown Bus';
    } catch (e) {
      return 'Unknown Bus';
    }
  }

  void _startPositionUpdates() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_isTracking) {
        final position = await _locationService.getCurrentLocation();
        if (position != null && mounted) {
          setState(() {
            _currentPosition = position;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _startTracking() async {
    if (_selectedBus == null) {
      _showAlert('Please select a bus first.');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _showAlert('Please log in to start tracking.');
      return;
    }

    try {
      setState(() {
        _isTracking = true;
        _status = 'Starting tracking...';
      });

      final success = await _locationService.startTracking(_selectedBus!, user.uid);
      
      if (success && mounted) {
        setState(() {
          _status = 'Tracking: ${_getBusNameById(_selectedBus)}';
        });
        
        // Get initial position
        final position = await _locationService.getCurrentLocation();
        if (position != null && mounted) {
          setState(() {
            _currentPosition = position;
          });
        }

        // Start periodic position updates
        _startPositionUpdates();

        print('✅ Tracking started successfully for bus: ${_getBusNameById(_selectedBus)}');
        print('📍 Bus ID: $_selectedBus');
        print('📍 User ID: ${user.uid}');
      } else if (mounted) {
        setState(() {
          _isTracking = false;
          _status = 'Failed to start tracking.';
        });
        _showAlert('Failed to start tracking. Please check location permissions.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error starting tracking: ${e.toString()}';
          _isTracking = false;
        });
      }
      print('❌ Error starting tracking: $e');
    }
  }

  Future<void> _stopTracking() async {
    try {
      _positionUpdateTimer?.cancel();
      await _locationService.stopTracking();
      
      if (mounted) {
        setState(() {
          _isTracking = false;
          _status = 'Tracking stopped.';
        });
      }
      print('🛑 Tracking stopped successfully');
    } catch (e) {
      print('❌ Error stopping tracking: $e');
      if (mounted) {
        setState(() {
          _status = 'Error stopping tracking: ${e.toString()}';
        });
      }
    }
  }

  void _showAlert(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alert'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF000000),
              Color(0xFF0A0A23),
              Color(0xFF1A1A40),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header - Fixed height
              Container(
                height: 80,
                padding: const EdgeInsets.all(20.0),
                child: const Center(
                  child: Text(
                    'Location Tracking',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              // Main content area - Takes remaining space
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildMainContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoadingBuses) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Loading tracking system...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        // Bus Selection
        _buildBusSelection(),
        const SizedBox(height: 20),
        
        // Tracking Optimization Status
        _buildOptimizationStatus(),
        const SizedBox(height: 20),
        
        // Control Buttons
        _buildControlButtons(),
        const SizedBox(height: 20),
        
        // Status and Location Info
        _buildStatusSection(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBusSelection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Select Bus',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          if (_buses.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'No buses available',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Please add buses in the admin section.',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedBus,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                hintText: 'Choose a bus to track',
              ),
              items: _buses.map((bus) {
                return DropdownMenuItem<String>(
                  value: bus['id'] as String,
                  child: Text('${bus['name']} (${bus['licensePlate']})'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBus = value;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOptimizationStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Tracking Optimization',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Optimized for tracking: ${_isOptimizedForTracking ? 'Yes' : 'No'}',
                  style: TextStyle(
                    color: _isOptimizedForTracking ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _requestBatteryOptimizationBypass,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Bypass Optimization'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Background location enabled: ${_hasBackgroundLocation ? 'Yes' : 'No'}',
                  style: TextStyle(
                    color: _hasBackgroundLocation ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _requestBackgroundLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Request Background'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Precise location enabled: ${_hasPreciseLocation ? 'Yes' : 'No'}',
                  style: TextStyle(
                    color: _hasPreciseLocation ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _checkAllPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Refresh Status'),
              ),
            ],
          ),
          if (!_isOptimizedForTracking) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: const Text(
                'For optimal tracking, enable all permissions and bypass battery optimization. This ensures reliable location updates even when the app is minimized.',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isTracking ? null : _startTracking,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Start Tracking',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isTracking ? _stopTracking : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Stop Tracking',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isTracking ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isTracking ? Colors.green : Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isTracking ? Icons.location_on : Icons.location_off,
                    color: _isTracking ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _isTracking ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_currentPosition != null) ...[
              const SizedBox(height: 20),
              const Text(
                'Current Location',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (_currentPosition!.speed > 0)
                      Text(
                        'Speed: ${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                        style: const TextStyle(color: Colors.white),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 