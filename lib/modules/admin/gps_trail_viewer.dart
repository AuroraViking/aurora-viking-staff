import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/colors.dart';

class GpsTrailViewer extends StatefulWidget {
  final String date; // YYYY-MM-DD format
  final String? busId;
  final String? busName;
  final String? guideName;
  final List<Map<String, dynamic>>? pickupLocations; // Optional: show pickup points

  const GpsTrailViewer({
    super.key,
    required this.date,
    this.busId,
    this.busName,
    this.guideName,
    this.pickupLocations,
  });

  @override
  State<GpsTrailViewer> createState() => _GpsTrailViewerState();
}

class _GpsTrailViewerState extends State<GpsTrailViewer> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  List<LatLng> _trailPoints = [];
  List<Map<String, dynamic>> _rawTrailData = [];
  
  bool _isLoading = true;
  String? _error;
  
  // Stats
  double _totalDistanceKm = 0;
  double _maxSpeedKmh = 0;
  DateTime? _startTime;
  DateTime? _endTime;
  int _pointCount = 0;

  // Iceland center (default)
  static const LatLng _reykjavikCenter = LatLng(64.1466, -21.9426);

  @override
  void initState() {
    super.initState();
    _loadTrailData();
  }

  Future<void> _loadTrailData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Parse the date and create time range for that night's tour
      // Tours typically run 8pm to 3am, so we need to span two calendar days
      final dateParts = widget.date.split('-');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      // Tour date evening (8pm) to next morning (5am)
      final startTime = DateTime(year, month, day, 18, 0); // 6pm to catch early prep
      final endTime = DateTime(year, month, day + 1, 5, 0); // 5am next day

      print('🗺️ Loading GPS trail for ${widget.date}');
      print('   Time range: $startTime to $endTime');
      print('   Bus ID: ${widget.busId ?? "ALL"}');

      // Query location_history
      Query query = FirebaseFirestore.instance
          .collection('location_history')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startTime))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endTime));

      // Filter by bus if specified
      if (widget.busId != null) {
        query = query.where('busId', isEqualTo: widget.busId);
      }

      // OrderBy must come after all where clauses
      query = query.orderBy('timestamp', descending: false);

      final snapshot = await query.limit(5000).get(); // Limit to prevent memory issues

      print('📍 Found ${snapshot.docs.length} location points');

      if (snapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'No GPS data found for this date.\n\nThis could mean:\n• GPS tracking wasn\'t active\n• Data has been cleaned up (older than retention period)\n• Wrong bus selected';
        });
        return;
      }

      // Process points
      final points = <LatLng>[];
      final rawData = <Map<String, dynamic>>[];
      DateTime? firstTime;
      DateTime? lastTime;
      double maxSpeed = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        final timestamp = data['timestamp'] as Timestamp?;
        final speed = data['speed'] as double? ?? 0.0;

        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
          rawData.add(data);
          
          final speedKmh = speed * 3.6;
          if (speedKmh > maxSpeed) maxSpeed = speedKmh;
          
          if (timestamp != null) {
            final time = timestamp.toDate();
            firstTime ??= time;
            lastTime = time;
          }
        }
      }

      // Calculate total distance
      double totalDistance = 0;
      for (int i = 0; i < points.length - 1; i++) {
        totalDistance += _calculateDistance(
          points[i].latitude, points[i].longitude,
          points[i + 1].latitude, points[i + 1].longitude,
        );
      }

      setState(() {
        _trailPoints = points;
        _rawTrailData = rawData;
        _totalDistanceKm = totalDistance;
        _maxSpeedKmh = maxSpeed;
        _startTime = firstTime;
        _endTime = lastTime;
        _pointCount = points.length;
        _isLoading = false;
      });

      _buildTrailVisualization();

    } catch (e) {
      print('❌ Error loading trail: $e');
      setState(() {
        _isLoading = false;
        _error = 'Error loading GPS data: $e';
      });
    }
  }

  void _buildTrailVisualization() {
    if (_trailPoints.isEmpty) return;

    final polylines = <Polyline>{};
    final markers = <Marker>{};

    // Main trail polyline
    polylines.add(Polyline(
      polylineId: const PolylineId('main_trail'),
      points: _trailPoints,
      color: AppColors.primary,
      width: 4,
    ));

    // Start marker
    markers.add(Marker(
      markerId: const MarkerId('start'),
      position: _trailPoints.first,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title: '🚀 Tour Start',
        snippet: _startTime != null 
            ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
            : 'Start',
      ),
    ));

    // End marker
    markers.add(Marker(
      markerId: const MarkerId('end'),
      position: _trailPoints.last,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: '🏁 Tour End',
        snippet: _endTime != null
            ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
            : 'End',
      ),
    ));

    // Add pickup location markers if provided
    if (widget.pickupLocations != null) {
      for (int i = 0; i < widget.pickupLocations!.length; i++) {
        final pickup = widget.pickupLocations![i];
        final lat = pickup['latitude'] as double?;
        final lng = pickup['longitude'] as double?;
        final name = pickup['name'] as String? ?? 'Pickup ${i + 1}';

        if (lat != null && lng != null) {
          markers.add(Marker(
            markerId: MarkerId('pickup_$i'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: '📍 $name',
              snippet: 'Scheduled pickup location',
            ),
          ));
        }
      }
    }

    setState(() {
      _polylines.clear();
      _polylines.addAll(polylines);
      _markers.clear();
      _markers.addAll(markers);
    });

    // Fit map to trail
    _fitMapToTrail();
  }

  void _fitMapToTrail() {
    if (_trailPoints.isEmpty || _mapController == null) return;

    double minLat = _trailPoints.first.latitude;
    double maxLat = _trailPoints.first.latitude;
    double minLng = _trailPoints.first.longitude;
    double maxLng = _trailPoints.first.longitude;

    for (final point in _trailPoints) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;

  String _formatDuration() {
    if (_startTime == null || _endTime == null) return 'Unknown';
    final duration = _endTime!.difference(_startTime!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// When the map is tapped, find nearest trail point and show info
  void _onMapTapped(LatLng position) {
    if (_rawTrailData.isEmpty) return;

    double minDist = double.infinity;
    Map<String, dynamic>? nearest;

    for (final point in _rawTrailData) {
      final lat = point['latitude'] as double;
      final lng = point['longitude'] as double;
      final dLat = position.latitude - lat;
      final dLon = (position.longitude - lng) * 0.55;
      final dist = dLat * dLat + dLon * dLon;
      if (dist < minDist) {
        minDist = dist;
        nearest = point;
      }
    }

    // Threshold: ~200m at Iceland's latitude
    if (nearest != null && minDist < 0.000004) {
      final speed = nearest['speed'] as double? ?? 0.0;
      final speedKmh = speed * 3.6;
      _showTrailPointInfo(
        speedKmh: speedKmh,
        timestamp: nearest['timestamp'] as Timestamp?,
        lat: nearest['latitude'] as double,
        lng: nearest['longitude'] as double,
      );
    }
  }

  /// Rainbow color gradient based on speed in km/h
  Color _getSpeedColor(double speedKmh) {
    if (speedKmh < 5) return Colors.blue;
    if (speedKmh < 30) return Colors.cyan;
    if (speedKmh < 50) return Colors.green;
    if (speedKmh < 70) return Colors.lime;
    if (speedKmh < 90) return Colors.yellow.shade700;
    if (speedKmh < 110) return Colors.orange;
    return Colors.red;
  }

  /// Show time & speed info when a trail circle marker is tapped
  void _showTrailPointInfo({
    required double speedKmh,
    required Timestamp? timestamp,
    required double lat,
    required double lng,
  }) {
    final timeStr = timestamp != null
        ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}:${timestamp.toDate().second.toString().padLeft(2, '0')}'
        : 'Unknown';
    final dateStr = timestamp != null
        ? '${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}'
        : '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E3A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.busName ?? 'Trail Point',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: '${speedKmh.toStringAsFixed(1)} km/h',
                    color: _getSpeedColor(speedKmh),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: timeStr,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: dateStr,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.location_on,
                    label: 'Position',
                    value: '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GPS Trail - ${widget.date}'),
            if (widget.busName != null || widget.guideName != null)
              Text(
                [widget.busName, widget.guideName].where((e) => e != null).join(' • '),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrailData,
            tooltip: 'Reload',
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            onPressed: _fitMapToTrail,
            tooltip: 'Fit to trail',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading GPS data...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadTrailData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    // Map
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: _reykjavikCenter,
                        zoom: 10,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _fitMapToTrail();
                      },
                      onTap: _onMapTapped,
                      polylines: _polylines,
                      markers: _markers,
                      mapType: MapType.normal,
                      myLocationEnabled: false,
                      zoomControlsEnabled: false,
                    ),
                    
                    // Stats overlay
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E).withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              '📏 Distance',
                              '${_totalDistanceKm.toStringAsFixed(1)} km',
                            ),
                            _buildStatItem(
                              '⏱️ Duration',
                              _formatDuration(),
                            ),
                            _buildStatItem(
                              '🏎️ Max Speed',
                              '${_maxSpeedKmh.toStringAsFixed(0)} km/h',
                            ),
                            _buildStatItem(
                              '📍 Points',
                              '$_pointCount',
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Time range
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E).withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.play_circle, color: Colors.green, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _startTime != null
                                      ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
                                      : '--:--',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Text(
                              '→',
                              style: TextStyle(color: Colors.grey, fontSize: 20),
                            ),
                            Row(
                              children: [
                                Text(
                                  _endTime != null
                                      ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
                                      : '--:--',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.stop_circle, color: Colors.red, size: 20),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Legend
                    Positioned(
                      bottom: 80,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E).withOpacity(0.95),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Tap trail for speed/time', style: TextStyle(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic)),
                            SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, color: Colors.green, size: 14),
                                SizedBox(width: 4),
                                Text('Start', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                            SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, color: Colors.red, size: 14),
                                SizedBox(width: 4),
                                Text('End', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                            SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, color: Colors.blue, size: 14),
                                SizedBox(width: 4),
                                Text('Pickup', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedLegendRow(Color color, String range) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text('$range km/h', style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

