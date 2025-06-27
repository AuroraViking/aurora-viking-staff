// Tracking screen for guide-side location sending and admin-side map view 
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:async';

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
  StreamSubscription<Position>? _positionStreamSubscription;

  // Bus options
  final List<String> _buses = [
    'Lúxusinn - AYX70',
    'Afi Stjáni - MAF43',
    'Meistarinn - TZE50',
  ];

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
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
  }

  Future<void> _startTracking() async {
    if (_selectedBus == null || _selectedBus!.isEmpty) {
      _showAlert('Please select your bus.');
      return;
    }

    try {
      setState(() {
        _isTracking = true;
        _status = 'Starting tracking...';
      });

      // Get initial position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _status = 'Tracking: $_selectedBus';
      });

      // Start continuous tracking
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen(
        (Position position) {
          setState(() {
            _currentPosition = position;
          });
          
          // Send location to Firebase (placeholder for now)
          _sendLocationToFirebase(position);
        },
        onError: (error) {
          setState(() {
            _status = 'Error: ${error.toString()}';
            _isTracking = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _status = 'Error starting tracking: ${e.toString()}';
        _isTracking = false;
      });
    }
  }

  void _stopTracking() {
    _positionStreamSubscription?.cancel();
    setState(() {
      _isTracking = false;
      _status = 'Tracking stopped.';
    });
  }

  void _sendLocationToFirebase(Position position) {
    // TODO: Implement Firebase integration
    // For now, just log the location
    print('Location update for $_selectedBus:');
    print('Latitude: ${position.latitude}');
    print('Longitude: ${position.longitude}');
    print('Timestamp: ${DateTime.now().millisecondsSinceEpoch}');
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
                
                // Status Display
                _buildStatusDisplay(),
                const SizedBox(height: 30),
                
                // Location Info
                if (_currentPosition != null) _buildLocationInfo(),
                
                const Spacer(),
                
                // Logo
                _buildLogo(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'Fleet Tracker - Tablet',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF00BFFF),
            shadows: [
              Shadow(
                color: const Color(0xFF00BFFF).withOpacity(0.8),
                blurRadius: 10,
              ),
              Shadow(
                color: const Color(0xFF00BFFF).withOpacity(0.6),
                blurRadius: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusSelection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border.all(color: const Color(0xFF00BFFF), width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BFFF).withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBus,
          hint: const Text(
            'Select Bus',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          dropdownColor: const Color(0xFF111111),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00BFFF)),
          items: _buses.map((String bus) {
            return DropdownMenuItem<String>(
              value: bus,
              child: Text(bus),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedBus = newValue;
            });
          },
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Start Button
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            child: ElevatedButton(
              onPressed: _isTracking ? null : _startTracking,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 8,
                shadowColor: const Color(0xFF00BFFF).withOpacity(0.5),
              ),
              child: const Text(
                'Start Tracking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        
        // Stop Button
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 10),
            child: ElevatedButton(
              onPressed: _isTracking ? _stopTracking : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4C4C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 8,
                shadowColor: const Color(0xFFFF4C4C).withOpacity(0.5),
              ),
              child: const Text(
                'Stop Tracking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusDisplay() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00BFFF).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        _status,
        style: TextStyle(
          fontSize: 20,
          color: const Color(0xFF00BFFF),
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: const Color(0xFF00BFFF).withOpacity(0.8),
              blurRadius: 10,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00BFFF).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Location:',
            style: TextStyle(
              color: Color(0xFF00BFFF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Updated: ${DateFormat('HH:mm:ss').format(_currentPosition!.timestamp!)}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF00BFFF).withOpacity(0.1),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BFFF).withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(
        Icons.location_on,
        size: 50,
        color: Color(0xFF00BFFF),
      ),
    );
  }
} 