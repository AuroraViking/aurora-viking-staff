// Tracking screen for guide-side location sending and admin-side map view 
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/location_service.dart';
import '../../core/services/bus_management_service.dart';
import '../../core/services/platform_service.dart';
import '../../widgets/common/logo_widget.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep widget alive when navigating away
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

  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    // Only initialize once - don't reinitialize if widget is recreated
    if (!_hasInitialized) {
      _hasInitialized = true;
      _checkAllPermissions();
      _loadBuses();
    }
    // Always check tracking status when widget becomes visible
    _checkTrackingStatus();
    // Check service status periodically to sync UI with native service
    _startServiceStatusChecker();
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _serviceStatusTimer?.cancel();
    // Don't call _locationService.dispose() here - it would stop tracking
    // The service should continue running even when navigating away
    // Only stop tracking when explicitly requested via _stopTracking()
    super.dispose();
  }

  Timer? _serviceStatusTimer;

  void _startServiceStatusChecker() {
    _serviceStatusTimer?.cancel();
    _serviceStatusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      await _syncServiceStatus();
    });
  }

  Future<void> _syncServiceStatus() async {
    try {
      // Check if native service is running
      final isNativeServiceRunning = await PlatformService.isLocationServiceRunning();
      
      // If native service is running but UI thinks it's not, sync the UI
      if (isNativeServiceRunning && !_isTracking) {
        print('🔄 Native service is running but UI is not synced, updating UI...');
        await _checkTrackingStatus();
      }
      // If native service is not running but UI thinks it is, sync the UI
      else if (!isNativeServiceRunning && _isTracking) {
        print('⚠️ Native service stopped but UI thinks it\'s running, updating UI...');
        setState(() {
          _isTracking = false;
          _status = 'Tracking stopped (service not running).';
        });
      }
    } catch (e) {
      print('⚠️ Error checking service status: $e');
    }
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
    try {
      // Check both Flutter service state and native service state
      final isFlutterTracking = _locationService.isTracking;
      final isNativeServiceRunning = await PlatformService.isLocationServiceRunning();
      
      print('🔍 Checking tracking status: Flutter=$isFlutterTracking, Native=$isNativeServiceRunning');
      
      // If native service is running, we should show tracking as active
      if (isNativeServiceRunning) {
        print('✅ Native service is running');
        
        // Get bus ID from Firebase or LocationService
        String? busId = _locationService.currentBusId;
        
        // If we don't have busId from LocationService, try to get it from Firebase
        if (busId == null) {
          // Try to get the active tracking bus from Firebase
          try {
            final firestore = FirebaseFirestore.instance;
            final snapshot = await firestore
                .collection('bus_locations')
                .where('isTracking', isEqualTo: true)
                .limit(1)
                .get();
            
            if (snapshot.docs.isNotEmpty) {
              busId = snapshot.docs.first.id;
              print('📋 Found active tracking bus from Firebase: $busId');
            }
          } catch (e) {
            print('⚠️ Could not get bus ID from Firebase: $e');
          }
        }
        
        if (busId != null) {
          if (mounted) {
            setState(() {
              _isTracking = true;
              _selectedBus = busId;
              _status = 'Tracking: ${_getBusNameById(busId)}';
            });
            _startPositionUpdates();
          }
        } else {
          print('⚠️ Native service running but no bus ID found');
          if (mounted) {
            setState(() {
              _isTracking = true;
              _status = 'Tracking active (bus ID unknown)';
            });
            _startPositionUpdates();
          }
        }
      } else if (isFlutterTracking) {
        // Flutter side thinks it's tracking but native service is not running
        print('⚠️ Flutter thinks tracking but native service not running');
        // Don't change UI state - let the periodic checker handle it
      } else {
        // Neither is tracking
        print('ℹ️ Not tracking');
        if (mounted && _isTracking) {
          setState(() {
            _isTracking = false;
            _status = 'Not tracking.';
          });
        }
      }
    } catch (e) {
      print('❌ Error checking tracking status: $e');
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
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
              // Header - Fixed height with logo
              Container(
                height: 80,
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const LogoSmall(),
                    const SizedBox(width: 12),
                    const Text(
                      'Location Tracking',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.directions_bus,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Select Bus',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                hintText: 'Choose a bus to track',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              dropdownColor: Colors.white,
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade700),
              items: _buses.map((bus) {
                return DropdownMenuItem<String>(
                  value: bus['id'] as String,
                  child: Text(
                    '${bus['name']} (${bus['licensePlate']})',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                    ),
                  ),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isOptimizedForTracking 
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isOptimizedForTracking ? Icons.check_circle : Icons.warning,
                  color: _isOptimizedForTracking ? Colors.green : Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Tracking Optimization',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildOptimizationRow(
            label: 'Optimized for tracking',
            value: _isOptimizedForTracking,
            icon: Icons.tune,
            onAction: _requestBatteryOptimizationBypass,
            actionLabel: 'Bypass',
            actionColor: Colors.blue,
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          _buildOptimizationRow(
            label: 'Background location',
            value: _hasBackgroundLocation,
            icon: Icons.location_searching,
            onAction: _requestBackgroundLocation,
            actionLabel: 'Request',
            actionColor: Colors.purple,
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          _buildOptimizationRow(
            label: 'Precise location',
            value: _hasPreciseLocation,
            icon: Icons.gps_fixed,
            onAction: _checkAllPermissions,
            actionLabel: 'Refresh',
            actionColor: Colors.orange,
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

  Widget _buildOptimizationRow({
    required String label,
    required bool value,
    required IconData icon,
    required VoidCallback onAction,
    required String actionLabel,
    required Color actionColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: value ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ? 'Enabled' : 'Disabled',
                  style: TextStyle(
                    color: value ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isTracking ? null : _startTracking,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Start Tracking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isTracking ? _stopTracking : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stop, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Stop Tracking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isTracking 
                      ? Colors.green.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isTracking ? Icons.location_on : Icons.location_off,
                  color: _isTracking ? Colors.green : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Status',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isTracking
                    ? [
                        Colors.green.withOpacity(0.3),
                        Colors.green.withOpacity(0.15),
                      ]
                    : [
                        Colors.grey.withOpacity(0.3),
                        Colors.grey.withOpacity(0.15),
                      ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isTracking ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isTracking ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isTracking ? Icons.check_circle : Icons.cancel,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: _isTracking ? Colors.green.shade100 : Colors.grey.shade300,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_currentPosition != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Current Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLocationInfoRow(
                    Icons.navigation,
                    'Latitude',
                    '${_currentPosition!.latitude.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 12),
                  _buildLocationInfoRow(
                    Icons.navigation,
                    'Longitude',
                    '${_currentPosition!.longitude.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 12),
                  _buildLocationInfoRow(
                    Icons.gps_fixed,
                    'Accuracy',
                    '${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                  ),
                  if (_currentPosition!.speed > 0) ...[
                    const SizedBox(height: 12),
                    _buildLocationInfoRow(
                      Icons.speed,
                      'Speed',
                      '${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue.shade300, size: 18),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
} 