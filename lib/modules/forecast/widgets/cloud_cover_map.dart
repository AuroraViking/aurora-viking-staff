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
import 'compass_rose_overlay.dart';

class CloudCoverMap extends StatefulWidget {
  final Position position;
  final double cloudCover;
  final String weatherDescription;
  final String weatherIcon;
  final bool isNowcast;
  final bool isAICaptureMode; // For AI analysis - zooms out and adds overlays
  final Function(Uint8List)? onImageCaptured;

  const CloudCoverMap({
    super.key,
    required this.position,
    required this.cloudCover,
    required this.weatherDescription,
    required this.weatherIcon,
    this.isNowcast = false,
    this.isAICaptureMode = false,
    this.onImageCaptured,
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

      // Wait a moment to ensure tiles are loaded
      await Future.delayed(const Duration(milliseconds: 500));

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      debugPrint('📐 Captured image: ${image.width}x${image.height}');
      
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('⚠️ Could not convert image to bytes');
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      debugPrint('✅ Captured cloud cover map: ${bytes.length} bytes (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
      
      // If image is too small, it's probably blank
      if (bytes.length < 10000) {
        debugPrint('⚠️ Image seems too small - may be blank');
      }
      
      return bytes;
    } catch (e) {
      debugPrint('❌ Failed to capture map: $e');
      return null;
    }
  }

  @override
  State<CloudCoverMap> createState() => CloudCoverMapState();
}

class CloudCoverMapState extends State<CloudCoverMap> {
  GoogleMapController? _mapController;
  bool _isMapLoading = true;
  Set<TileOverlay> _tileOverlays = {};
  double _timeOffset = 0;
  bool _isDragging = false;
  bool _isLoadingForecast = false;
  LatLng _currentCenter = const LatLng(0, 0);
  final GlobalKey _aiCaptureKey = GlobalKey();
  
  // Zoom 7 for regional overview (~150km radius)
  static const double _aiCaptureZoom = 7.0;
  static const double _normalZoom = 7.0;

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

  /// Capture the map for AI analysis - zooms out first
  Future<Uint8List?> captureForAI() async {
    try {
      // Zoom out for better regional overview
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(widget.position.latitude, widget.position.longitude),
          _aiCaptureZoom,
        ),
      );
      
      // Wait for tiles to load
      await Future.delayed(const Duration(milliseconds: 1500));
      
      final boundary = _aiCaptureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      
      final bytes = byteData.buffer.asUint8List();
      widget.onImageCaptured?.call(bytes);
      
      // Zoom back if not in permanent AI mode
      if (!widget.isAICaptureMode) {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(widget.position.latitude, widget.position.longitude),
            _normalZoom,
          ),
        );
      }
      
      return bytes;
    } catch (e) {
      debugPrint('❌ Error capturing map for AI: $e');
      return null;
    }
  }

  Future<void> _updateTimeOffset(double value) async {
    setState(() {
      _timeOffset = value;
      _isLoadingForecast = true;
    });

    _createTileOverlays();
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
            style: const TextStyle(color: Colors.white70, fontSize: 10),
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
    final zoom = widget.isAICaptureMode ? _aiCaptureZoom : _normalZoom;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isNowcast && !widget.isAICaptureMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Satellite image of cloud cover in your area',
              style: TextStyle(
                color: Colors.tealAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.tealAccent.withOpacity(0.5), blurRadius: 8),
                ],
              ),
            ),
          ),
        Container(
          height: widget.isAICaptureMode 
              ? MediaQuery.of(context).size.height * 0.5 
              : MediaQuery.of(context).size.height * 0.7,
          margin: widget.isAICaptureMode ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: widget.isAICaptureMode 
                ? BorderRadius.zero 
                : const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
            border: Border.all(
              color: Colors.tealAccent.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: RepaintBoundary(
            key: _aiCaptureKey,
            child: Stack(
              children: [
                // The map
                RepaintBoundary(
                  key: CloudCoverMap.mapKey,
                  child: ClipRRect(
                    borderRadius: widget.isAICaptureMode 
                        ? BorderRadius.zero
                        : const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentCenter,
                        zoom: zoom,
                      ),
                      onMapCreated: (controller) {
                        setState(() {
                          _mapController = controller;
                          _isMapLoading = false;
                        });
                      },
                      myLocationEnabled: !widget.isAICaptureMode,
                      myLocationButtonEnabled: !widget.isAICaptureMode,
                      zoomControlsEnabled: !widget.isAICaptureMode,
                      mapToolbarEnabled: false,
                      mapType: MapType.hybrid,
                      tileOverlays: _tileOverlays,
                      onCameraMove: (position) {
                        setState(() {
                          _currentCenter = position.target;
                          _isDragging = true;
                        });
                      },
                      onCameraIdle: () => setState(() => _isDragging = false),
                      gestureRecognizers: widget.isAICaptureMode ? {} : {
                        Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
                        Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
                        Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
                      },
                    ),
                  ),
                ),
                
                // Loading indicator
                if (_isMapLoading || _isLoadingForecast)
                  Container(
                    color: Colors.black.withOpacity(0.5),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.tealAccent),
                    ),
                  ),
                
                // AI Capture Mode Overlays (also show on nowcast for visibility)
                if (widget.isAICaptureMode || widget.isNowcast) ...[
                  // Full compass rose with 16 directions
                  Positioned.fill(
                    child: Center(
                      child: CompassRoseOverlay(
                        size: MediaQuery.of(context).size.width * 0.85,
                        show16Directions: true,
                        lineColor: Colors.white.withOpacity(0.6),
                        labelColor: Colors.tealAccent,
                        labelFontSize: 11,
                      ),
                    ),
                  ),
                ],
                
                // Time slider (not in AI capture mode)
                if (!widget.isNowcast && !widget.isAICaptureMode)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
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
                              trackHeight: 4,
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
        ),
      ],
    );
  }

  Widget _buildDirectionLabel(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

/// Draws compass crosshairs on the map for AI orientation
class _CompassOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.tealAccent.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    final center = Offset(size.width / 2, size.height / 2);
    
    // N-S line
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    // E-W line
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    
    // Diagonal lines (lighter)
    final diagonalPaint = Paint()
      ..color = Colors.tealAccent.withOpacity(0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height), diagonalPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), diagonalPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}