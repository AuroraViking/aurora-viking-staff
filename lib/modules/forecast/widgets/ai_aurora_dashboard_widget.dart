import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'forecast_chart_widget.dart';
import 'cloud_cover_map.dart';
import '../services/hemispheric_power_service.dart';

/// Unified AI Dashboard Widget - combines Bz chart, Hemispheric Power, and Cloud Map
/// for a single screenshot that provides Claude with complete visual context.
class AIAuroraDashboardWidget extends StatefulWidget {
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

  const AIAuroraDashboardWidget({
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
  });

  @override
  State<AIAuroraDashboardWidget> createState() => AIAuroraDashboardWidgetState();
}

class AIAuroraDashboardWidgetState extends State<AIAuroraDashboardWidget> {
  final GlobalKey _captureKey = GlobalKey();
  List<HemisphericPowerReading>? _hemisphericData;
  bool _isLoadingHemispheric = true;

  @override
  void initState() {
    super.initState();
    _loadHemisphericData();
  }

  Future<void> _loadHemisphericData() async {
    try {
      final service = HemisphericPowerService();
      final data = await service.fetchHemisphericPowerData();
      if (mounted) {
        setState(() {
          _hemisphericData = data;
          _isLoadingHemispheric = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingHemispheric = false);
      }
    }
  }

  /// Capture the entire dashboard as a PNG image for AI analysis
  Future<Uint8List?> captureAsImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Error capturing dashboard: $e');
      return null;
    }
  }

  double _calculateBzH() {
    if (widget.bzValues.isEmpty) return 0;
    final recentValues = widget.bzValues.length > 30
        ? widget.bzValues.sublist(widget.bzValues.length - 30)
        : widget.bzValues;
    final negatives = recentValues.where((v) => v < 0).toList();
    if (negatives.isEmpty) return 0;
    return (negatives.reduce((a, b) => a + b) / negatives.length).abs();
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
        color: const Color(0xFF0A1929),
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Main content - three panels
            Expanded(
              child: Row(
                children: [
                  // Left panel: Bz Chart
                  Expanded(
                    flex: 5,
                    child: Container(
                      margin: const EdgeInsets.all(8),
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
                  ),
                  
                  // Right panel: Cloud Map + Hemispheric Power
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        // Cloud Cover Map
                        Expanded(
                          flex: 5,
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(0, 8, 8, 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.tealAccent.withOpacity(0.3),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
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
                        
                        // Hemispheric Power Mini Chart
                        Expanded(
                          flex: 3,
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(0, 4, 8, 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.tealAccent.withOpacity(0.3),
                              ),
                            ),
                            child: _buildHemisphericMiniChart(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Summary Bar
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
          bottom: BorderSide(color: Colors.tealAccent.withOpacity(0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, color: Colors.tealAccent.withOpacity(0.8), size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI AURORA DASHBOARD',
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
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHemisphericMiniChart() {
    if (_isLoadingHemispheric) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
        ),
      );
    }

    if (_hemisphericData == null || _hemisphericData!.isEmpty) {
      return const Center(
        child: Text('HP data unavailable', style: TextStyle(color: Colors.white54, fontSize: 10)),
      );
    }

    // Take last 30 readings
    final displayData = _hemisphericData!.length > 30 
        ? _hemisphericData!.sublist(_hemisphericData!.length - 30) 
        : _hemisphericData!;
    
    final now = DateTime.now().toUtc();
    int? earthIndex;
    int minDiff = 999999;
    for (int i = 0; i < displayData.length; i++) {
      final diff = (displayData[i].observationTime.difference(now).inMinutes).abs();
      if (diff < minDiff) {
        minDiff = diff;
        earthIndex = i;
      }
    }

    final latest = displayData.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Hemispheric Power',
              style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getBarColor(latest.northPower).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'N: ${latest.northPower} GW',
                style: TextStyle(
                  color: _getBarColor(latest.northPower),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 100,
              minY: -100,
              barTouchData: const BarTouchData(enabled: false),
              titlesData: const FlTitlesData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 50,
                getDrawingHorizontalLine: (value) {
                  if (value == 0) {
                    return const FlLine(color: Colors.white24, strokeWidth: 1);
                  }
                  return const FlLine(color: Colors.transparent);
                },
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(displayData.length, (index) {
                final reading = displayData[index];
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: reading.northPower.toDouble(),
                      color: _getBarColor(reading.northPower),
                      width: 2,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(1),
                        topRight: Radius.circular(1),
                      ),
                    ),
                    BarChartRodData(
                      toY: -reading.southPower.toDouble(),
                      color: _getBarColor(reading.southPower),
                      width: 2,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(1),
                        bottomRight: Radius.circular(1),
                      ),
                    ),
                  ],
                );
              }),
              extraLinesData: ExtraLinesData(
                verticalLines: earthIndex != null ? [
                  VerticalLine(
                    x: earthIndex.toDouble(),
                    color: Colors.amber,
                    strokeWidth: 1.5,
                    dashArray: [3, 3],
                  ),
                ] : [],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getBarColor(int power) {
    if (power >= 80) return Colors.red;
    if (power >= 50) return Colors.orange;
    if (power >= 20) return Colors.yellow;
    return Colors.green;
  }

  Widget _buildSummaryBar() {
    final bzH = _calculateBzH();
    final currentBz = widget.bzValues.isNotEmpty ? widget.bzValues.last : 0.0;
    final hpNorth = _hemisphericData?.isNotEmpty == true ? _hemisphericData!.last.northPower : 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        border: Border(top: BorderSide(color: Colors.tealAccent.withOpacity(0.3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Bz', '${currentBz.toStringAsFixed(1)}', currentBz < 0 ? Colors.redAccent : Colors.greenAccent),
          _summaryItem('BzH', bzH.toStringAsFixed(2), bzH > 3 ? Colors.redAccent : Colors.white70),
          _summaryItem('Speed', '${widget.speed.toStringAsFixed(0)}', Colors.cyan),
          _summaryItem('Density', widget.density.toStringAsFixed(1), Colors.purple),
          _summaryItem('Kp', widget.kp.toStringAsFixed(1), Colors.orange),
          _summaryItem('HP(N)', '$hpNorth GW', _getBarColor(hpNorth)),
          _summaryItem('Clouds', '${widget.cloudCover.toStringAsFixed(0)}%', Colors.grey),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
