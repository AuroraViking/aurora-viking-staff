// Tracking screen for guide-side location sending and admin-side map view 
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_service.dart';
import '../../core/services/bus_management_service.dart';

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
  
  final LocationService _locationService = LocationService();
  final BusManagementService _busService = BusManagementService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> _buses = [];
  bool _isLoadingBuses = true;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _loadBuses();
    _checkTrackingStatus();
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }

  void _loadBuses() {
    print('🔄 Loading buses...');
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
    );
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

    setState(() {
      _status = 'Ready to track.';
    });
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
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Header
                _buildHeader(),
                const SizedBox(height: 40),
                
                // Bus Selection
                _buildBusSelection(),
                const SizedBox(height: 30),
                
                // Control Buttons
                _buildControlButtons(),
                const SizedBox(height: 30),
                
                // Status and Location Info
                _buildStatusSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Center(
      child: Text(
        'Location Tracking',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBusSelection() {
    return Container(
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
            'Select Bus',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoadingBuses)
            Container(
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'Loading buses...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else if (_buses.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Database Connection Issue',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Using fallback bus list. Please deploy Firestore rules to see your custom buses.',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Go Back'),
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