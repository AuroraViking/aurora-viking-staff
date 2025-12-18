// Admin map screen for viewing all guides' locations on a map 
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
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
  
  // Bus-guide assignments and pickup data
  Map<String, Map<String, String>> _busGuideAssignments = {}; // busId -> {guideId, guideName}
  Map<String, GuidePickupList?> _guidePickupLists = {}; // guideId -> GuidePickupList

  @override
  void initState() {
    super.initState();
    _checkApiKey();
    _loadBusData();
    _loadBusLocations();
  }

  @override
  void dispose() {
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
      print('Please add GOOGLE_MAPS_API_KEY to your .env file');
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
          'icon': _getMarkerIcon(color),
          'trailColor': color.withOpacity(0.6),
          'description': bus['description'] as String? ?? '',
        };
      }
      
      setState(() {
        _busData = busData;
      });
      
      // Reload trails for new buses
      _loadAllBusTrails();
      
      // Load bus-guide assignments after buses are loaded
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

  BitmapDescriptor _getMarkerIcon(Color color) {
    if (color == Colors.blue) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    if (color == Colors.green) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    if (color == Colors.red) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    if (color == Colors.orange) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    if (color == Colors.purple) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    if (color == Colors.teal) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  }

  Future<void> _loadBusLocations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Listen to real-time bus locations
      _locationService.getAllBusLocations().listen((snapshot) {
        _updateBusLocations(snapshot);
      });

      // Load location trails for all buses
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
      final trailData = await _locationService.getBusLocationTrail(busId, hours: 48);
      final trailPoints = trailData.map((point) {
        return LatLng(point['latitude'] as double, point['longitude'] as double);
      }).toList();

      setState(() {
        _busTrails[busId] = trailPoints;
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

        // Get guide assignment and pickup info for this bus
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

        // Create marker with updated info
        markers.add(Marker(
          markerId: MarkerId(busId),
          position: LatLng(latitude, longitude),
          icon: busInfo['icon'] as BitmapDescriptor,
          infoWindow: InfoWindow(
            title: busInfo['name'] as String,
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
      
      // Refresh bus-guide assignments when bus locations update
      // This ensures we have the latest assignments
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
    final speedKmh = (speed * 3.6).toStringAsFixed(1);
    final timeAgo = _getTimeAgo(timestamp);
    
    // Build the snippet with guide/bus info if available
    if (guideName != null && busName != null && totalPassengers > 0) {
      return '$guideName - $busName - $pickedUpCount/$totalPassengers';
    } else if (guideName != null && busName != null) {
      return '$guideName - $busName';
    }
    
    // Fallback to speed/time if no guide info
    return 'Speed: ${speedKmh} km/h • $timeAgo';
  }

  String _getTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown time';
    
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
          IconButton(
            onPressed: _toggleTrails,
            icon: Icon(_showTrails ? Icons.timeline : Icons.timeline_outlined),
            tooltip: _showTrails ? 'Hide Trails' : 'Show Trails',
          ),
          IconButton(
            onPressed: _refreshTrails,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Trails',
          ),
          IconButton(
            onPressed: _centerOnReykjavik,
            icon: const Icon(Icons.center_focus_strong),
            tooltip: 'Center on Reykjavik',
          ),
          IconButton(
            onPressed: _fitMapToMarkers,
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit to Markers',
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
                        trafficEnabled: false,
                        buildingsEnabled: true,
                        indoorViewEnabled: false,
                        mapType: MapType.normal,
                        onTap: (LatLng position) {
                          // Close any open bottom sheets when tapping map
                          Navigator.of(context).popUntil((route) => route.isFirst || !route.isActive);
                        },
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map,
                                size: 64,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Google Maps Not Available',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  'Please configure GOOGLE_MAPS_API_KEY in your .env file to enable map functionality.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _checkApiKey,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
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
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
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
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_showTrails)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Trails ON',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Bus List
                  Expanded(
                    child: _activeBuses.isEmpty
                        ? const Center(
                            child: Text(
                              'No active buses',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _activeBuses.length,
                            itemBuilder: (context, index) {
                              return _buildBusCard(_activeBuses[index]);
                            },
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

  Widget _buildBusCard(Map<String, dynamic> bus) {
    final timestamp = bus['timestamp'] as Timestamp?;
    final timeAgo = _getTimeAgo(timestamp);
    final speed = bus['speed'] as double;
    final speedKmh = (speed * 3.6).toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: bus['color'] as Color,
          child: const Icon(Icons.directions_bus, color: Colors.white),
        ),
        title: Text(
          bus['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('License: ${bus['licensePlate']}'),
            Text('Speed: ${speedKmh} km/h'),
            Text('Last seen: $timeAgo'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _centerOnBus(bus),
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Center on bus',
            ),
            IconButton(
              onPressed: () => _showBusHistory(bus['busId'] as String),
              icon: const Icon(Icons.history),
              tooltip: 'View history',
            ),
          ],
        ),
      ),
    );
  }

  void _centerOnBus(Map<String, dynamic> bus) {
    final position = LatLng(bus['latitude'] as double, bus['longitude'] as double);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 15));
  }

  void _showBusHistory(String busId) {
    // TODO: Implement bus history view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('History for ${_busData[busId]?['name'] ?? 'Unknown bus'}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Load bus-guide assignments for today
  Future<void> _loadBusGuideAssignments() async {
    try {
      if (_busData.isEmpty) {
        print('⚠️ No buses available yet, skipping assignment load');
        return;
      }
      
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      print('🔍 Loading bus-guide assignments for date $dateStr (${_busData.length} buses)');
      
      // Get all buses from _busData (which contains all active buses)
      for (final busId in _busData.keys) {
        final assignment = await FirebaseService.getGuideAssignmentForBus(
          busId: busId,
          date: dateStr,
        );
        
        if (assignment != null && assignment['guideId']!.isNotEmpty) {
          print('✅ Found assignment for bus $busId: ${assignment['guideName']}');
          if (mounted) {
            setState(() {
              _busGuideAssignments[busId] = assignment;
            });
          }
          
          // Load pickup list for this guide
          await _loadGuidePickupList(assignment['guideId']!, today);
        }
      }
      
      print('✅ Loaded ${_busGuideAssignments.length} bus-guide assignments');
      
      // Refresh markers to show guide info in info windows
      _refreshMarkers();
    } catch (e) {
      print('❌ Error loading bus-guide assignments: $e');
    }
  }

  // Load pickup list for a guide
  Future<void> _loadGuidePickupList(String guideId, DateTime date) async {
    try {
      if (!mounted) return;
      
      final controller = context.read<PickupController>();
      await controller.loadBookingsForDate(date);
      
      final guideList = controller.getGuideList(guideId);
      if (guideList != null && mounted) {
        setState(() {
          _guidePickupLists[guideId] = guideList;
        });
        
        // Refresh markers to update pickup count in info windows
        _refreshMarkers();
      }
    } catch (e) {
      print('❌ Error loading guide pickup list: $e');
    }
  }

  // Refresh markers with updated guide/pickup info
  void _refreshMarkers() {
    if (_markers.isEmpty || _activeBuses.isEmpty) return;
    
    final updatedMarkers = <Marker>{};
    
    for (final marker in _markers) {
      final busId = marker.markerId.value;
      final busInfo = _busData[busId];
      if (busInfo == null) continue;
      
      // Get current bus location data
      final busData = _activeBuses.firstWhere(
        (b) => b['busId'] == busId,
        orElse: () => {},
      );
      
      if (busData.isEmpty) continue;
      
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
      
      // Create updated marker
      updatedMarkers.add(Marker(
        markerId: marker.markerId,
        position: marker.position,
        icon: marker.icon,
        infoWindow: InfoWindow(
          title: busInfo['name'] as String,
          snippet: _getLocationSnippet(
            busData['speed'] as double? ?? 0.0,
            busData['heading'] as double? ?? 0.0,
            busData['timestamp'] as Timestamp?,
            busName: busInfo['name'] as String,
            guideName: guideName,
            pickedUpCount: pickedUpCount,
            totalPassengers: totalPassengers,
          ),
        ),
        rotation: marker.rotation,
        onTap: marker.onTap,
      ));
    }
    
    if (mounted) {
      setState(() {
        _markers = updatedMarkers;
      });
    }
  }

  // Handle bus marker tap
  void _onBusMarkerTapped(String busId) async {
    final busInfo = _busData[busId];
    if (busInfo == null) return;
    
    // Load assignment if not already loaded
    if (!_busGuideAssignments.containsKey(busId)) {
      await _loadBusAssignmentForBus(busId);
    }
    
    final assignment = _busGuideAssignments[busId];
    final guideId = assignment?['guideId'];
    final guideName = assignment?['guideName'];
    
    // Load pickup list if we have a guide but don't have the list yet
    GuidePickupList? guidePickupList;
    if (guideId != null && !_guidePickupLists.containsKey(guideId)) {
      await _loadGuidePickupList(guideId, DateTime.now());
      guidePickupList = _guidePickupLists[guideId];
    } else if (guideId != null) {
      guidePickupList = _guidePickupLists[guideId];
    }
    
    // Show bottom sheet with bus info, guide info, and pickup list
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
            scrollController: scrollController,
          ),
        ),
      );
    }
  }

  // Load bus assignment for a specific bus
  Future<void> _loadBusAssignmentForBus(String busId) async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      print('🔍 Loading bus assignment for bus $busId on date $dateStr');
      
      final assignment = await FirebaseService.getGuideAssignmentForBus(
        busId: busId,
        date: dateStr,
      );
      
      print('📋 Assignment result for bus $busId: $assignment');
      
      if (assignment != null && assignment['guideId']!.isNotEmpty && mounted) {
        print('✅ Found assignment: ${assignment['guideName']} (${assignment['guideId']})');
        setState(() {
          _busGuideAssignments[busId] = assignment;
        });
        
        // Load pickup list for this guide
        await _loadGuidePickupList(assignment['guideId']!, today);
      } else {
        print('⚠️ No assignment found for bus $busId');
      }
    } catch (e) {
      print('❌ Error loading bus assignment for bus $busId: $e');
    }
  }

  // Build bus info bottom sheet
  Widget _buildBusInfoSheet({
    required String busId,
    required String busName,
    required String licensePlate,
    String? guideName,
    GuidePickupList? guidePickupList,
    required ScrollController scrollController,
  }) {
    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[600],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_bus,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      busName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'License: $licensePlate',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
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
                const Icon(
                  Icons.person,
                  color: AppColors.success,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assigned Guide',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        guideName,
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        
        if (guideName == null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.grey,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'No guide assigned to this bus',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
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
                    'Pickup List (${guidePickupList.totalPassengers} passengers)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: const Color(0xFF2A2A3E),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: booking.isArrived 
                                ? AppColors.success 
                                : Colors.grey,
                            child: Icon(
                              booking.isArrived ? Icons.check : Icons.pending,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  booking.customerFullName,
                                  style: TextStyle(
                                    color: booking.isArrived ? AppColors.success : Colors.white,
                                    fontWeight: FontWeight.w500,
                                    decoration: booking.isArrived ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              if (booking.isArrived)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Picked Up',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.pickupPlaceName,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Text(
                                '${booking.numberOfGuests} guests • ${booking.pickupTime}',
                                style: const TextStyle(color: Colors.white60),
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
                                  child: const Text(
                                    'No Show',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        else if (guideName != null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.list_alt,
                    color: Colors.grey,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No pickups assigned',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
} 