// ============================================
// Guide Map Screen
// Simplified map showing bus locations and guide
// names only — no pickup lists or admin features.
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:ui' as ui;
import '../../core/config/env_config.dart';
import '../../core/services/bus_management_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/location_service.dart';

class GuideMapScreen extends StatefulWidget {
  const GuideMapScreen({super.key});

  @override
  State<GuideMapScreen> createState() => _GuideMapScreenState();
}

class _GuideMapScreenState extends State<GuideMapScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final BusManagementService _busService = BusManagementService();

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(64.1466, -21.9426), // Reykjavik center
    zoom: 10.0,
  );

  Map<String, Map<String, dynamic>> _busData = {};
  Set<Marker> _markers = {};
  bool _isLoading = true;
  bool _hasApiKey = false;

  // Bus-guide assignments
  Map<String, Map<String, String>> _busGuideAssignments = {};

  // Timer to periodically refresh assignments
  Timer? _assignmentRefreshTimer;

  // Cache for custom labeled marker icons
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  @override
  void initState() {
    super.initState();
    _checkApiKey();
    _loadBusData();
    _loadBusLocations();

    // Refresh assignments every 15 seconds
    _assignmentRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadBusGuideAssignments();
    });
  }

  @override
  void dispose() {
    _assignmentRefreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _checkApiKey() {
    if (kIsWeb) {
      setState(() => _hasApiKey = true);
    } else {
      final apiKey = EnvConfig.hasMapsKey
          ? EnvConfig.googleMapsApiKey
          : dotenv.env['GOOGLE_MAPS_API_KEY'];
      setState(() {
        _hasApiKey = apiKey != null &&
            apiKey.isNotEmpty &&
            apiKey != 'your_google_maps_api_key_here';
      });
    }
  }

  // ------------------------------------------------------------------
  // Data loading
  // ------------------------------------------------------------------

  void _loadBusData() {
    _busService.getActiveBuses().listen((buses) {
      if (!mounted) return;

      final busData = <String, Map<String, dynamic>>{};
      for (final bus in buses) {
        final busId = bus['id'] as String;
        busData[busId] = {
          'name': bus['name'] as String,
          'licensePlate': bus['licensePlate'] as String,
          'color': _colorFromString(bus['color'] as String? ?? 'blue'),
        };
      }

      setState(() => _busData = busData);
      _loadBusGuideAssignments();
    });
  }

  Future<void> _loadBusLocations() async {
    setState(() => _isLoading = true);

    try {
      _locationService.getAllBusLocationsWithLastKnown().listen((snapshot) {
        _updateBusLocations(snapshot);
      });
    } catch (e) {
      debugPrint('❌ GuideMap: Error loading bus locations: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBusGuideAssignments() async {
    if (_busData.isEmpty) return;

    try {
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      await Future.wait(
        _busData.keys.map((busId) async {
          final assignment = await FirebaseService.getGuideAssignmentForBus(
            busId: busId,
            date: dateStr,
          );

          if (assignment != null && assignment['guideId']!.isNotEmpty) {
            if (mounted) {
              setState(() => _busGuideAssignments[busId] = assignment);
            }
          } else {
            if (mounted && _busGuideAssignments.containsKey(busId)) {
              setState(() => _busGuideAssignments.remove(busId));
            }
          }
        }),
      );
    } catch (e) {
      debugPrint('❌ GuideMap: Error loading assignments: $e');
    }
  }

  // ------------------------------------------------------------------
  // Marker updates
  // ------------------------------------------------------------------

  void _updateBusLocations(QuerySnapshot snapshot) async {
    final markerFutures = <Future<Marker>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final busId = data['busId'] as String;

      if (!_busData.containsKey(busId)) continue;

      final busInfo = _busData[busId]!;
      final latitude = data['latitude'] as double;
      final longitude = data['longitude'] as double;
      final isTracking = data['isTracking'] as bool? ?? false;

      final busName = busInfo['name'] as String;
      final busColor = busInfo['color'] as Color;
      final guideName = _busGuideAssignments[busId]?['guideName'];

      markerFutures.add(
        _createLabeledMarkerIcon(
          busName: busName,
          guideName: guideName,
          busColor: busColor,
          isTracking: isTracking,
        ).then((icon) => Marker(
              markerId: MarkerId(busId),
              position: LatLng(latitude, longitude),
              icon: icon,
              anchor: const Offset(0.5, 1.0),
              infoWindow: InfoWindow(
                title:
                    '$busName${!isTracking ? ' (Last Known)' : ''}',
                snippet: guideName ?? '',
              ),
            )),
      );
    }

    final createdMarkers = await Future.wait(markerFutures);

    if (mounted) {
      setState(() => _markers = createdMarkers.toSet());
    }
  }

  // ------------------------------------------------------------------
  // Labeled marker icon (simplified — no progress badge)
  // ------------------------------------------------------------------

  Future<BitmapDescriptor> _createLabeledMarkerIcon({
    required String busName,
    String? guideName,
    required Color busColor,
    required bool isTracking,
  }) async {
    final cacheKey = '${busName}_${guideName ?? ''}_${busColor.value}_$isTracking';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    final label = guideName != null && guideName.isNotEmpty
        ? '$busName\n$guideName'
        : busName;
    final lines = label.split('\n');

    const double fontSize = 13;
    const double padding = 8;
    const double lineHeight = fontSize + 4;
    const double pinSize = 14;
    const double pinStemHeight = 10;

    // Measure text width
    double maxTextWidth = 0;
    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(
          text: line,
          style: const TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > maxTextWidth) maxTextWidth = tp.width;
      tp.dispose();
    }

    final double boxWidth = maxTextWidth + padding * 2;
    final double boxHeight = lines.length * lineHeight + padding * 2;
    final double totalHeight = boxHeight + pinStemHeight + pinSize;
    final double totalWidth = boxWidth < 60.0 ? 60.0 : boxWidth;

    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, totalWidth, totalHeight));

    // Rounded rectangle background
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, totalWidth, boxHeight),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color =
            isTracking ? const Color(0xEE1A1A2E) : const Color(0xCC555555),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = isTracking ? busColor : Colors.grey
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Text lines
    double yOffset = padding;
    for (int i = 0; i < lines.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: lines[i],
          style: TextStyle(
            color: i == 0 ? Colors.white : Colors.white70,
            fontSize: i == 0 ? fontSize : fontSize - 1,
            fontWeight: i == 0 ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padding, yOffset));
      tp.dispose();
      yOffset += lineHeight;
    }

    // Pin stem
    final stemX = totalWidth / 2;
    canvas.drawLine(
      Offset(stemX, boxHeight),
      Offset(stemX, boxHeight + pinStemHeight),
      Paint()
        ..color = isTracking ? busColor : Colors.grey
        ..strokeWidth = 3,
    );

    // Pin circle
    final pinColor = isTracking ? busColor : Colors.grey;
    canvas.drawCircle(
      Offset(stemX, boxHeight + pinStemHeight + pinSize / 2),
      pinSize / 2,
      Paint()..color = pinColor,
    );
    canvas.drawCircle(
      Offset(stemX, boxHeight + pinStemHeight + pinSize / 2),
      pinSize / 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(totalWidth.ceil(), totalHeight.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    if (bytes == null) return BitmapDescriptor.defaultMarker;

    final descriptor = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  Color _colorFromString(String colorName) {
    switch (colorName) {
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'teal':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  void _fitMapToMarkers() {
    if (_markers.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;
    for (final marker in _markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      minLat = minLat == null ? lat : (minLat < lat ? minLat : lat);
      maxLat = maxLat == null ? lat : (maxLat > lat ? maxLat : lat);
      minLng = minLng == null ? lng : (minLng < lng ? minLng : lng);
      maxLng = maxLng == null ? lng : (maxLng > lng ? maxLng : lng);
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat!, minLng!),
          northeast: LatLng(maxLat!, maxLng!),
        ),
        50,
      ),
    );
  }

  void _refresh() {
    _loadBusGuideAssignments();
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide Map'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _refresh,
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
      body: Stack(
        children: [
          _hasApiKey
              ? GoogleMap(
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) _fitMapToMarkers();
                  },
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
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
        ],
      ),
    );
  }

  Widget _buildNoApiKeyPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Google Maps API key not configured',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
