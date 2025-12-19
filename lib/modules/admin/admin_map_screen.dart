// ============================================
// ENHANCED admin_map_screen.dart
// Full replacement file with all enhancements
// ============================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../../core/theme/colors.dart';
import '../../core/services/bus_management_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/models/pickup_models.dart';
import '../tracking/location_service.dart';
import '../pickup/pickup_controller.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final BusManagementService _busService = BusManagementService();

  // Map settings
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(64.1466, -21.9426), // Reykjavik center
    zoom: 10.0,
  );

  // Dynamic bus data
  Map<String, Map<String, dynamic>> _busData = {};
  Set<Marker> _markers = {};
  Set<Polyline> _trails = {};
  List<Map<String, dynamic>> _activeBuses = [];
  bool _isLoading = true;
  bool _hasApiKey = false;
  bool _showTrails = true;
  Map<String, List<LatLng>> _busTrails = {};

  // NEW: Trail duration selector
  int _trailHours = 12;
  final List<int> _trailHourOptions = [6, 12, 24, 48];

  // NEW: Distance tracking
  Map<String, double> _busDistances = {}; // busId -> distance in km

  // Bus-guide assignments and pickup data
  Map<String, Map<String, String>> _busGuideAssignments = {};
  Map<String, GuidePickupList?> _guidePickupLists = {};

  @override
  void initState() {
    super.initState();
    _checkApiKey();
    _loadBusData();
    _loadBusLocations();
  }

  @override
  void dispose() {
    // Save daily distances before disposing
    _saveDailyDistances();
    _mapController?.dispose();
    super.dispose();
  }

  void _checkApiKey() {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    setState(() {
      _hasApiKey = apiKey != null && apiKey.isNotEmpty && apiKey != 'your_google_maps_api_key_here';
    });

    if (!_hasApiKey) {
      print('⚠️ Google Maps API key not found or not configured properly');
    }
  }

  void _loadBusData() {
    _busService.getActiveBuses().listen((buses) {
      if (!mounted) return;

      final busData = <String, Map<String, dynamic>>{};

      for (final bus in buses) {
        final busId = bus['id'] as String;
        final colorName = bus['color'] as String? ?? 'blue';
        final color = _getColorFromString(colorName);

        busData[busId] = {
          'name': bus['name'] as String,
          'licensePlate': bus['licensePlate'] as String,
          'color': color,
          'trailColor': color.withOpacity(0.6),
          'description': bus['description'] as String? ?? '',
        };
      }

      setState(() {
        _busData = busData;
      });

      _loadAllBusTrails();
      _loadBusGuideAssignments();
    });
  }

  Color _getColorFromString(String colorName) {
    switch (colorName) {
      case 'blue': return Colors.blue;
      case 'green': return Colors.green;
      case 'red': return Colors.red;
      case 'orange': return Colors.orange;
      case 'purple': return Colors.purple;
      case 'teal': return Colors.teal;
      default: return Colors.grey;
    }
  }

  // ============================================
  // NEW: Progress-based marker colors
  // ============================================

  /// Get marker color based on pickup progress
  BitmapDescriptor _getProgressMarkerIcon(int pickedUp, int total) {
    if (total == 0) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }

    final progress = pickedUp / total;

    if (progress == 0) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    } else if (progress < 0.25) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else if (progress < 0.75) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    } else if (progress < 1.0) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    } else {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }
  }

  /// Get progress color for UI elements
  Color _getProgressColor(int pickedUp, int total) {
    if (total == 0) return Colors.grey;

    final progress = pickedUp / total;

    if (progress == 0) return Colors.red;
    if (progress < 0.25) return Colors.orange;
    if (progress < 0.75) return Colors.amber;
    if (progress < 1.0) return Colors.lightGreen;
    return Colors.green;
  }

  /// Get status text based on pickup progress
  String _getPickupStatusText(int pickedUp, int total) {
    if (total == 0) return 'No pickups';

    final progress = (pickedUp / total * 100).round();

    if (progress == 0) return 'Not started';
    if (progress == 100) return 'Complete! ✓';
    return '$pickedUp/$total ($progress%)';
  }

  // ============================================
  // NEW: Distance calculation
  // ============================================

  /// Calculate total distance from trail points (in kilometers)
  double _calculateTrailDistance(List<LatLng> trail) {
    if (trail.length < 2) return 0.0;

    double totalDistance = 0.0;

    for (int i = 0; i < trail.length - 1; i++) {
      totalDistance += _calculateDistanceBetweenPoints(
        trail[i].latitude, trail[i].longitude,
        trail[i + 1].latitude, trail[i + 1].longitude,
      );
    }

    return totalDistance;
  }

  /// Haversine formula to calculate distance between two GPS points
  double _calculateDistanceBetweenPoints(
      double lat1, double lon1,
      double lat2, double lon2,
      ) {
    const double earthRadius = 6371; // km

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Save daily distances to Firebase for service tracking
  Future<void> _saveDailyDistances() async {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    for (final entry in _busDistances.entries) {
      final busId = entry.key;
      final distance = entry.value;
      final trailPoints = _busTrails[busId]?.length ?? 0;

      if (distance > 0) {
        await FirebaseService.saveBusDailyDistance(
          busId: busId,
          date: dateStr,
          distanceKm: distance,
          trailPoints: trailPoints,
        );
      }
    }

    print('✅ Saved daily distances for ${_busDistances.length} buses');
  }

  // ============================================
  // Trail loading with dynamic duration
  // ============================================

  Future<void> _loadBusLocations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _locationService.getAllBusLocations().listen((snapshot) {
        _updateBusLocations(snapshot);
      });

      await _loadAllBusTrails();
    } catch (e) {
      print('❌ Error loading bus locations: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAllBusTrails() async {
    try {
      for (final busId in _busData.keys) {
        await _loadBusTrail(busId);
      }
    } catch (e) {
      print('❌ Error loading bus trails: $e');
    }
  }

  Future<void> _loadBusTrail(String busId) async {
    try {
      // Use dynamic trail hours
      final trailData = await _locationService.getBusLocationTrail(busId, hours: _trailHours);
      final trailPoints = trailData.map((point) {
        return LatLng(point['latitude'] as double, point['longitude'] as double);
      }).toList();

      // Calculate distance
      final distance = _calculateTrailDistance(trailPoints);

      setState(() {
        _busTrails[busId] = trailPoints;
        _busDistances[busId] = distance;
      });

      _updateTrails();
    } catch (e) {
      print('❌ Error loading trail for bus $busId: $e');
    }
  }

  void _updateTrails() {
    if (!_showTrails) {
      setState(() {
        _trails = {};
      });
      return;
    }

    final trails = <Polyline>{};

    for (final entry in _busTrails.entries) {
      final busId = entry.key;
      final trailPoints = entry.value;

      if (trailPoints.length > 1) {
        final busInfo = _busData[busId];
        if (busInfo != null) {
          trails.add(Polyline(
            polylineId: PolylineId('trail_$busId'),
            points: trailPoints,
            color: busInfo['trailColor'] as Color,
            width: 3,
            geodesic: true,
          ));
        }
      }
    }

    setState(() {
      _trails = trails;
    });
  }

  void _updateBusLocations(QuerySnapshot snapshot) {
    final buses = <Map<String, dynamic>>[];
    final markers = <Marker>{};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final busId = data['busId'] as String;

      if (_busData.containsKey(busId)) {
        final busInfo = _busData[busId]!;
        final latitude = data['latitude'] as double;
        final longitude = data['longitude'] as double;
        final timestamp = data['timestamp'] as Timestamp?;
        final speed = data['speed'] as double? ?? 0.0;
        final heading = data['heading'] as double? ?? 0.0;

        // Get guide assignment and pickup info
        final assignment = _busGuideAssignments[busId];
        final guideId = assignment?['guideId'];
        final guideName = assignment?['guideName'];
        final guidePickupList = guideId != null ? _guidePickupLists[guideId] : null;

        // Calculate pickup count
        int pickedUpCount = 0;
        int totalPassengers = 0;
        if (guidePickupList != null) {
          pickedUpCount = guidePickupList.bookings
              .where((b) => b.isArrived)
              .fold<int>(0, (sum, b) => sum + b.numberOfGuests);
          totalPassengers = guidePickupList.totalPassengers;
        }

        // Create marker with PROGRESS-BASED COLOR
        markers.add(Marker(
          markerId: MarkerId(busId),
          position: LatLng(latitude, longitude),
          icon: _getProgressMarkerIcon(pickedUpCount, totalPassengers),
          infoWindow: InfoWindow(
            title: '${busInfo['name']} ${totalPassengers > 0 ? '($pickedUpCount/$totalPassengers)' : ''}',
            snippet: _getLocationSnippet(
              speed,
              heading,
              timestamp,
              busName: busInfo['name'] as String,
              guideName: guideName,
              pickedUpCount: pickedUpCount,
              totalPassengers: totalPassengers,
            ),
          ),
          rotation: heading,
          onTap: () => _onBusMarkerTapped(busId),
        ));

        buses.add({
          'busId': busId,
          'name': busInfo['name'],
          'licensePlate': busInfo['licensePlate'],
          'latitude': latitude,
          'longitude': longitude,
          'speed': speed,
          'heading': heading,
          'timestamp': timestamp,
          'color': busInfo['color'],
        });
      }
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        _activeBuses = buses;
      });

      _loadBusGuideAssignments();
    }
  }

  String _getLocationSnippet(
      double speed,
      double heading,
      Timestamp? timestamp, {
        String? busName,
        String? guideName,
        int pickedUpCount = 0,
        int totalPassengers = 0,
      }) {
    final timeAgo = _getTimeAgo(timestamp);

    final parts = <String>[];

    if (guideName != null) {
      parts.add(guideName);
    }

    if (totalPassengers > 0) {
      parts.add(_getPickupStatusText(pickedUpCount, totalPassengers));
    }

    parts.add(timeAgo);

    return parts.join(' • ');
  }

  String _getTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';

    final now = DateTime.now();
    final time = timestamp.toDate();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _fitMapToMarkers() {
    if (_markers.isEmpty) return;
    final bounds = _calculateBounds();
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  LatLngBounds _calculateBounds() {
    double? minLat, maxLat, minLng, maxLng;

    for (final marker in _markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;

      minLat = minLat == null ? lat : (minLat < lat ? minLat : lat);
      maxLat = maxLat == null ? lat : (maxLat > lat ? maxLat : lat);
      minLng = minLng == null ? lng : (minLng < lng ? minLng : lng);
      maxLng = maxLng == null ? lng : (maxLng > lng ? maxLng : lng);
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  void _centerOnReykjavik() {
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(_initialPosition));
  }

  void _toggleTrails() {
    setState(() {
      _showTrails = !_showTrails;
    });
    _updateTrails();
  }

  void _refreshTrails() async {
    await _loadAllBusTrails();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Fleet Tracking'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          // NEW: Trail duration selector
          PopupMenuButton<int>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 20),
                const SizedBox(width: 4),
                Text(
                  '${_trailHours}h',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            tooltip: 'Trail Duration',
            onSelected: (hours) {
              setState(() {
                _trailHours = hours;
              });
              _loadAllBusTrails();
            },
            itemBuilder: (context) => _trailHourOptions.map((hours) {
              return PopupMenuItem<int>(
                value: hours,
                child: Row(
                  children: [
                    if (_trailHours == hours)
                      const Icon(Icons.check, color: Colors.green, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text('${hours}h trail'),
                  ],
                ),
              );
            }).toList(),
          ),
          IconButton(
            onPressed: _toggleTrails,
            icon: Icon(_showTrails ? Icons.timeline : Icons.timeline_outlined),
            tooltip: _showTrails ? 'Hide Trails' : 'Show Trails',
          ),
          IconButton(
            onPressed: _refreshTrails,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _fitMapToMarkers,
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit All',
          ),
        ],
      ),
      body: Column(
        children: [
          // Map Section
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                _hasApiKey
                    ? GoogleMap(
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) {
                      _fitMapToMarkers();
                    }
                  },
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
                  polylines: _trails,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: true,
                  mapType: MapType.normal,
                )
                    : _buildNoApiKeyPlaceholder(),
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                // Legend overlay
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildLegend(),
                ),
              ],
            ),
          ),

          // Bus List Section
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[100],
              child: Column(
                children: [
                  _buildListHeader(),
                  Expanded(
                    child: _activeBuses.isEmpty
                        ? const Center(
                      child: Text('No active buses', style: TextStyle(color: Colors.grey)),
                    )
                        : ListView.builder(
                      itemCount: _activeBuses.length,
                      itemBuilder: (context, index) => _buildBusCard(_activeBuses[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Color legend for map
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegendItem(Colors.red, 'Not started'),
          _buildLegendItem(Colors.orange, '<25%'),
          _buildLegendItem(Colors.amber, '25-75%'),
          _buildLegendItem(Colors.lightGreen, '>75%'),
          _buildLegendItem(Colors.green, 'Complete'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_bus, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            'Active Buses (${_activeBuses.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (_showTrails)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_trailHours}h Trails',
                style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // ENHANCED: Bus card with progress indicator
  Widget _buildBusCard(Map<String, dynamic> bus) {
    final busId = bus['busId'] as String;
    final timestamp = bus['timestamp'] as Timestamp?;
    final timeAgo = _getTimeAgo(timestamp);
    final speed = bus['speed'] as double;
    final speedKmh = (speed * 3.6).toStringAsFixed(0);

    // Get guide and pickup info
    final assignment = _busGuideAssignments[busId];
    final guideId = assignment?['guideId'];
    final guideName = assignment?['guideName'];
    final guidePickupList = guideId != null ? _guidePickupLists[guideId] : null;

    // Calculate pickup progress
    int pickedUpCount = 0;
    int totalPassengers = 0;
    if (guidePickupList != null) {
      pickedUpCount = guidePickupList.bookings
          .where((b) => b.isArrived)
          .fold<int>(0, (sum, b) => sum + b.numberOfGuests);
      totalPassengers = guidePickupList.totalPassengers;
    }

    // Get distance
    final distance = _busDistances[busId] ?? 0.0;
    final progressColor = _getProgressColor(pickedUpCount, totalPassengers);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _onBusMarkerTapped(busId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Bus icon with pickup badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: progressColor.withOpacity(0.2),
                    child: Icon(Icons.directions_bus, color: progressColor, size: 24),
                  ),
                  if (totalPassengers > 0)
                    Positioned(
                      bottom: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: progressColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          '$pickedUpCount/$totalPassengers',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Bus info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            bus['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (guideName != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              guideName,
                              style: const TextStyle(color: Colors.blue, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bus['licensePlate']} • $speedKmh km/h',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(timeAgo, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                        const SizedBox(width: 10),
                        Icon(Icons.route, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text('${distance.toStringAsFixed(1)} km', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),

              // Progress circle
              if (totalPassengers > 0)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: pickedUpCount / totalPassengers,
                        backgroundColor: Colors.grey[300],
                        color: progressColor,
                        strokeWidth: 4,
                      ),
                      Text(
                        '${(pickedUpCount / totalPassengers * 100).round()}%',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: progressColor),
                      ),
                    ],
                  ),
                ),

              // Center button
              IconButton(
                onPressed: () => _centerOnBus(bus),
                icon: const Icon(Icons.gps_fixed, size: 20),
                tooltip: 'Center',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoApiKeyPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'Google Maps Not Available',
              style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text('Configure GOOGLE_MAPS_API_KEY in .env'),
          ],
        ),
      ),
    );
  }

  void _centerOnBus(Map<String, dynamic> bus) {
    final position = LatLng(bus['latitude'] as double, bus['longitude'] as double);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 15));
  }

  // ============================================
  // Bus-guide assignments and pickup data loading
  // (Keep existing methods below)
  // ============================================

  Future<void> _loadBusGuideAssignments() async {
    try {
      if (_busData.isEmpty) return;

      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      for (final busId in _busData.keys) {
        final assignment = await FirebaseService.getGuideAssignmentForBus(
          busId: busId,
          date: dateStr,
        );

        if (assignment != null && assignment['guideId']!.isNotEmpty) {
          if (mounted) {
            setState(() {
              _busGuideAssignments[busId] = assignment;
            });
          }
          await _loadGuidePickupList(assignment['guideId']!, today);
        }
      }

      _refreshMarkers();
    } catch (e) {
      print('❌ Error loading bus-guide assignments: $e');
    }
  }

  Future<void> _loadGuidePickupList(String guideId, DateTime date) async {
    try {
      if (!mounted) return;

      final controller = context.read<PickupController>();
      await controller.loadBookingsForDate(date, forceRefresh: true);

      final guideList = controller.getGuideList(guideId);
      if (guideList != null && mounted) {
        setState(() {
          _guidePickupLists[guideId] = guideList;
        });
        _refreshMarkers();
      }
    } catch (e) {
      print('❌ Error loading guide pickup list: $e');
    }
  }

  void _refreshMarkers() {
    // Trigger rebuild with updated data
    if (mounted && _activeBuses.isNotEmpty) {
      // Re-run the location update logic to refresh markers
      setState(() {});
    }
  }

  void _onBusMarkerTapped(String busId) async {
    final busInfo = _busData[busId];
    if (busInfo == null) return;

    if (!_busGuideAssignments.containsKey(busId)) {
      await _loadBusAssignmentForBus(busId);
    }

    final assignment = _busGuideAssignments[busId];
    final guideId = assignment?['guideId'];
    final guideName = assignment?['guideName'];

    GuidePickupList? guidePickupList;
    if (guideId != null) {
      if (!_guidePickupLists.containsKey(guideId)) {
        await _loadGuidePickupList(guideId, DateTime.now());
      }
      guidePickupList = _guidePickupLists[guideId];
    }

    // Get distance for this bus
    final distance = _busDistances[busId] ?? 0.0;

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1A1A2E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => _buildBusInfoSheet(
            busId: busId,
            busName: busInfo['name'] as String,
            licensePlate: busInfo['licensePlate'] as String,
            guideName: guideName,
            guidePickupList: guidePickupList,
            distance: distance,
            scrollController: scrollController,
          ),
        ),
      );
    }
  }

  Future<void> _loadBusAssignmentForBus(String busId) async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final assignment = await FirebaseService.getGuideAssignmentForBus(
        busId: busId,
        date: dateStr,
      );

      if (assignment != null && assignment['guideId']!.isNotEmpty && mounted) {
        setState(() {
          _busGuideAssignments[busId] = assignment;
        });
        await _loadGuidePickupList(assignment['guideId']!, today);
      }
    } catch (e) {
      print('❌ Error loading bus assignment: $e');
    }
  }

  // ENHANCED: Bottom sheet with distance info
  Widget _buildBusInfoSheet({
    required String busId,
    required String busName,
    required String licensePlate,
    String? guideName,
    GuidePickupList? guidePickupList,
    required double distance,
    required ScrollController scrollController,
  }) {
    // Calculate progress
    int pickedUpCount = 0;
    int totalPassengers = 0;
    if (guidePickupList != null) {
      pickedUpCount = guidePickupList.bookings
          .where((b) => b.isArrived)
          .fold<int>(0, (sum, b) => sum + b.numberOfGuests);
      totalPassengers = guidePickupList.totalPassengers;
    }
    final progressColor = _getProgressColor(pickedUpCount, totalPassengers);

    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
        ),

        // Header with bus info
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: progressColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.directions_bus, color: progressColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(busName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('$licensePlate • ${distance.toStringAsFixed(1)} km driven', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              if (totalPassengers > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: progressColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$pickedUpCount/$totalPassengers',
                        style: TextStyle(color: progressColor, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${(pickedUpCount / totalPassengers * 100).round()}%',
                        style: TextStyle(color: progressColor.withOpacity(0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Guide info
        if (guideName != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: AppColors.success, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Guide', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(guideName, style: const TextStyle(color: AppColors.success, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey, size: 20),
                SizedBox(width: 12),
                Text('No guide assigned', style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Pickup list
        if (guidePickupList != null && guidePickupList.bookings.isNotEmpty)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Pickup List (${guidePickupList.bookings.length} stops, ${guidePickupList.totalPassengers} guests)',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: guidePickupList.bookings.length,
                    itemBuilder: (context, index) {
                      final booking = guidePickupList.bookings[index];
                      final itemColor = booking.isArrived ? AppColors.success : (booking.isNoShow ? AppColors.error : Colors.white);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: const Color(0xFF2A2A3E),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: booking.isArrived
                                ? AppColors.success
                                : (booking.isNoShow ? AppColors.error : Colors.grey),
                            child: Icon(
                              booking.isArrived ? Icons.check : (booking.isNoShow ? Icons.close : Icons.pending),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            booking.customerFullName,
                            style: TextStyle(
                              color: itemColor,
                              fontWeight: FontWeight.w500,
                              decoration: booking.isArrived ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(booking.pickupPlaceName, style: const TextStyle(color: Colors.white70)),
                              Text(
                                '${booking.numberOfGuests} guests',
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: booking.isNoShow
                              ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('No Show', style: TextStyle(color: AppColors.error, fontSize: 12)),
                          )
                              : booking.isArrived
                              ? const Icon(Icons.check_circle, color: AppColors.success)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, color: Colors.grey, size: 48),
                  SizedBox(height: 16),
                  Text('No pickups assigned', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}