// Admin map screen for viewing all guides' locations on a map 
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/theme/colors.dart';
import '../../core/services/bus_management_service.dart';
import '../tracking/location_service.dart';

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

        // Create marker
        markers.add(Marker(
          markerId: MarkerId(busId),
          position: LatLng(latitude, longitude),
          icon: busInfo['icon'] as BitmapDescriptor,
          infoWindow: InfoWindow(
            title: busInfo['name'] as String,
            snippet: _getLocationSnippet(speed, heading, timestamp),
          ),
          rotation: heading,
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
    }
  }

  String _getLocationSnippet(double speed, double heading, Timestamp? timestamp) {
    final speedKmh = (speed * 3.6).toStringAsFixed(1);
    final timeAgo = _getTimeAgo(timestamp);
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
} 