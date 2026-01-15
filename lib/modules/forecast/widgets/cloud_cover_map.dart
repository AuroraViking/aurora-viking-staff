import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../services/cloud_tile_provider.dart';
import '../services/cloud_forecast_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import '../services/config_service.dart';

class CloudCoverMap extends StatefulWidget {
  final Position position;
  final double cloudCover;
  final String weatherDescription;
  final String weatherIcon;
  final bool isNowcast;

  const CloudCoverMap({
    super.key,
    required this.position,
    required this.cloudCover,
    required this.weatherDescription,
    required this.weatherIcon,
    this.isNowcast = false,
  });

  // Static key for capturing screenshot
  static final GlobalKey mapKey = GlobalKey();

  /// Capture the cloud cover map as an image for AI analysis
  static Future<Uint8List?> captureMapImage() async {
    try {
      final RenderRepaintBoundary? boundary = mapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('⚠️ Could not find map boundary for capture');
        return null;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      debugPrint('✅ Captured cloud cover map image');
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('❌ Failed to capture map: $e');
      return null;
    }
  }

  @override
  State<CloudCoverMap> createState() => _CloudCoverMapState();
}

class _CloudCoverMapState extends State<CloudCoverMap> {
  GoogleMapController? _mapController;
  bool _isMapLoading = true;
  Set<TileOverlay> _tileOverlays = {};
  double _timeOffset = 0;
  bool _isDragging = false;
  bool _isLoadingForecast = false;
  LatLng _currentCenter = const LatLng(0, 0);

  @override
  void initState() {
    super.initState();
    _currentCenter = LatLng(widget.position.latitude, widget.position.longitude);
    _createTileOverlays();
  }

  void _createTileOverlays() {
    final TileOverlay cloudOverlay = TileOverlay(
      tileOverlayId: const TileOverlayId('cloud_overlay'),
      tileProvider: CloudTileProvider(
        urlTemplate: 'https://tile.openweathermap.org/map/clouds_new/{z}/{x}/{y}.png?appid=${ConfigService.weatherApiKey}',
        timeOffset: _timeOffset,
      ),
      transparency: 0.0,
    );

    setState(() {
      _tileOverlays = {cloudOverlay};
    });
  }

  Future<void> _updateTimeOffset(double value) async {
    setState(() {
      _timeOffset = value;
      _isLoadingForecast = true;
    });

    // Force reload of tiles by recreating the overlay
    _createTileOverlays();

    // Add a small delay to ensure the loading indicator is visible
    await Future.delayed(const Duration(milliseconds: 100));
    
    setState(() {
      _isLoadingForecast = false;
    });
  }

  String _getTimeLabel() {
    final now = DateTime.now();
    final time = now.add(Duration(hours: _timeOffset.toInt()));
    return DateFormat('EEEE, MMM d, HH:mm').format(time);
  }

  Widget _buildTimeLabels() {
    final now = DateTime.now();
    final labels = <Widget>[];
    
    for (int i = 0; i <= 96; i += 24) {
      final time = now.add(Duration(hours: i));
      labels.add(
        SizedBox(
          width: 40,
          child: Text(
            DateFormat('EEE\nMMM d').format(time),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isNowcast)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Satellite image of cloud cover in your area',
              style: TextStyle(
                color: Colors.tealAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.tealAccent.withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        Container(
          height: MediaQuery.of(context).size.height * 0.7, // Match Bz chart height
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border.all(
              color: Colors.tealAccent.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Stack(
            children: [
              RepaintBoundary(
                key: CloudCoverMap.mapKey,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentCenter,
                    zoom: 8,
                  ),
                  onMapCreated: (controller) {
                    setState(() {
                      _mapController = controller;
                      _isMapLoading = false;
                    });
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: false,
                  mapType: MapType.hybrid,
                  tileOverlays: _tileOverlays,
                  onCameraMove: (position) {
                    setState(() {
                      _currentCenter = position.target;
                      _isDragging = true;
                    });
                  },
                  onCameraIdle: () {
                    setState(() => _isDragging = false);
                  },
                  gestureRecognizers: {
                    Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
                    Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
                    Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
                  },
                ),
              ),
              ), // Close RepaintBoundary
              if (_isMapLoading || _isLoadingForecast)
                Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.tealAccent,
                    ),
                  ),
                ),
              if (!widget.isNowcast)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.tealAccent.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getTimeLabel(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildTimeLabels(),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.tealAccent,
                            inactiveTrackColor: Colors.tealAccent.withOpacity(0.3),
                            thumbColor: Colors.tealAccent,
                            overlayColor: Colors.tealAccent.withOpacity(0.2),
                            valueIndicatorColor: Colors.tealAccent,
                            valueIndicatorTextStyle: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                            ),
                            trackHeight: 4,
                            activeTickMarkColor: Colors.tealAccent,
                            inactiveTickMarkColor: Colors.tealAccent.withOpacity(0.3),
                            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
                          ),
                          child: Slider(
                            value: _timeOffset,
                            min: 0,
                            max: 96,
                            divisions: 96,
                            label: _getTimeLabel(),
                            onChanged: _updateTimeOffset,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
} 