import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'forecast_chart_widget.dart';
import 'cloud_cover_map.dart';

/// Combined widget that shows everything the AI needs to make recommendations.
/// Can be captured as a single image for Claude to analyze.
class AIContextCaptureWidget extends StatefulWidget {
  final List<double> bzValues;
  final List<String> times;
  final double kp;
  final double speed;
  final double density;
  final double bt;
  final List<double> btValues;
  final List<double> speedValues;
  final List<double> densityValues;
  final Position? position;
  final double cloudCover;
  final String weatherDescription;
  final String weatherIcon;
  final Function(Uint8List)? onImageCaptured;

  const AIContextCaptureWidget({
    super.key,
    required this.bzValues,
    required this.times,
    required this.kp,
    required this.speed,
    required this.density,
    required this.bt,
    required this.btValues,
    this.speedValues = const [],
    this.densityValues = const [],
    this.position,
    this.cloudCover = 0,
    this.weatherDescription = '',
    this.weatherIcon = '',
    this.onImageCaptured,
  });

  @override
  State<AIContextCaptureWidget> createState() => AIContextCaptureWidgetState();
}

class AIContextCaptureWidgetState extends State<AIContextCaptureWidget> {
  final GlobalKey _captureKey = GlobalKey();
  bool _isCapturing = false;

  /// Capture the entire widget as a PNG image for AI analysis
  Future<Uint8List?> captureAsImage() async {
    try {
      setState(() => _isCapturing = true);
      
      // Wait for frame to render
      await Future.delayed(const Duration(milliseconds: 100));
      
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        print('Error: Could not find render boundary');
        return null;
      }
      
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        print('Error: Could not convert image to bytes');
        return null;
      }
      
      final bytes = byteData.buffer.asUint8List();
      widget.onImageCaptured?.call(bytes);
      
      return bytes;
    } catch (e) {
      print('Error capturing widget: $e');
      return null;
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  String _getBzTrend() {
    if (widget.bzValues.length < 20) return 'stable';
    final recent = widget.bzValues.sublist(widget.bzValues.length - 10);
    final older = widget.bzValues.sublist(widget.bzValues.length - 20, widget.bzValues.length - 10);
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
    final olderAvg = older.reduce((a, b) => a + b) / older.length;
    final diff = recentAvg - olderAvg;
    if (diff < -1) return 'improving (more negative)';
    if (diff > 1) return 'worsening (becoming positive)';
    return 'stable';
  }

  double _calculateBzH() {
    if (widget.bzValues.isEmpty) return 0;
    final recentValues = widget.bzValues.length > 30
        ? widget.bzValues.sublist(widget.bzValues.length - 30)
        : widget.bzValues;
    final negatives = recentValues.where((v) => v < 0).toList();
    if (negatives.isEmpty) return 0;
    final avgNegative = negatives.reduce((a, b) => a + b) / negatives.length;
    return avgNegative.abs();
  }

  @override
  Widget build(BuildContext context) {
    final defaultPosition = Position(
      latitude: 64.1466,
      longitude: -21.9426,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    return RepaintBoundary(
      key: _captureKey,
      child: Container(
        color: const Color(0xFF0A1929), // Dark blue background
        child: Column(
          children: [
            // Header with timestamp
            _buildHeader(),
            
            // Main Bz chart with speed/density mini-charts
            Expanded(
              flex: 5,
              child: ForecastChartWidget(
                bzValues: widget.bzValues,
                times: widget.times,
                kp: widget.kp,
                speed: widget.speed,
                density: widget.density,
                bt: widget.bt,
                btValues: widget.btValues,
                speedValues: widget.speedValues,
                densityValues: widget.densityValues,
              ),
            ),
            
            // Cloud cover map
            Expanded(
              flex: 4,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.tealAccent.withOpacity(0.3),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CloudCoverMap(
                    position: widget.position ?? defaultPosition,
                    cloudCover: widget.cloudCover,
                    weatherDescription: widget.weatherDescription,
                    weatherIcon: widget.weatherIcon,
                    isNowcast: true,
                  ),
                ),
              ),
            ),
            
            // Bottom summary bar
            _buildSummaryBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: Colors.tealAccent.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.psychology,
                color: Colors.tealAccent.withOpacity(0.8),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'AI CONTEXT SNAPSHOT',
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Text(
            DateFormat('dd/MM HH:mm').format(DateTime.now()),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final bzH = _calculateBzH();
    final currentBz = widget.bzValues.isNotEmpty ? widget.bzValues.last : 0.0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        border: Border(
          top: BorderSide(
            color: Colors.tealAccent.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Bz', '${currentBz.toStringAsFixed(1)} nT', 
            currentBz < 0 ? Colors.redAccent : Colors.greenAccent),
          _summaryItem('BzH', bzH.toStringAsFixed(2), 
            bzH > 3 ? Colors.redAccent : Colors.white70),
          _summaryItem('Speed', '${widget.speed.toStringAsFixed(0)} km/s', 
            Colors.cyan),
          _summaryItem('Density', '${widget.density.toStringAsFixed(1)}', 
            Colors.purple),
          _summaryItem('Kp', widget.kp.toStringAsFixed(1), 
            Colors.orange),
          _summaryItem('Clouds', '${widget.cloudCover.toStringAsFixed(0)}%', 
            Colors.grey),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
