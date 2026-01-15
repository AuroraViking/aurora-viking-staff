import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'pulsing_aurora_icon.dart';

class ForecastChartWidget extends StatefulWidget {
  // Static key for AI capture
  static final GlobalKey chartKey = GlobalKey();

  /// Capture the Bz chart as an image for AI analysis
  static Future<Uint8List?> captureChartImage() async {
    try {
      final RenderRepaintBoundary? boundary = chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('⚠️ Could not find chart boundary for capture');
        return null;
      }

      await Future.delayed(const Duration(milliseconds: 300));

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      debugPrint('📐 Captured Bz chart: ${image.width}x${image.height}');
      
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final bytes = byteData.buffer.asUint8List();
      debugPrint('✅ Captured Bz chart: ${(bytes.length / 1024).toStringAsFixed(1)} KB');
      return bytes;
    } catch (e) {
      debugPrint('❌ Failed to capture Bz chart: $e');
      return null;
    }
  }

  final List<double> bzValues;
  final List<String> times;
  final double kp;
  final double speed;
  final double density;
  final double bt;
  final List<double> btValues;
  final List<double> speedValues;
  final List<double> densityValues;
  final GlobalKey? captureKey;

  const ForecastChartWidget({
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
    this.captureKey,
  });

  @override
  State<ForecastChartWidget> createState() => _ForecastChartWidgetState();
}

class _ForecastChartWidgetState extends State<ForecastChartWidget> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Color constants
  static const Color _negativeColor = Color(0xFFFF4444); // Red for negative (GOOD for aurora)
  static const Color _positiveColor = Color(0xFF00FF88); // Green for positive
  static const Color _neutralColor = Color(0xFFFFAA00);  // Amber/yellow for near zero
  static const Color _btColor = Color(0xFFFFAA00);       // Amber for Bt envelope
  static const Color _speedColor = Color(0xFF00BFFF);    // Deep sky blue for speed
  static const Color _densityColor = Color(0xFF9370DB);  // Medium purple for density

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bzH = _calculateBzH(widget.bzValues);
    final isAuroraLikely = bzH > 3;
    final yLimit = _getYLimit(widget.bzValues);

    // Limit to 2 hours of data (120 minutes assuming 1-minute resolution)
    const int twoHoursOfData = 120;

    // Fallback test data if real data is empty, otherwise take last 2 hours
    final bzValues = widget.bzValues.isEmpty
        ? List.generate(twoHoursOfData, (i) => 2 * sin(i * 0.1) + 0.5 * sin(i * 0.3))
        : widget.bzValues.length > twoHoursOfData
        ? widget.bzValues.sublist(widget.bzValues.length - twoHoursOfData)
        : widget.bzValues;

    final btValues = widget.btValues.isEmpty
        ? List.generate(twoHoursOfData, (i) => 5 + 2 * sin(i * 0.05))
        : widget.btValues.length > twoHoursOfData
        ? widget.btValues.sublist(widget.btValues.length - twoHoursOfData)
        : widget.btValues;

    final times = widget.times.isEmpty
        ? List.generate(twoHoursOfData, (i) => '')
        : widget.times.length > twoHoursOfData
        ? widget.times.sublist(widget.times.length - twoHoursOfData)
        : widget.times;

    // Speed and density data for mini-charts
    final speedValues = widget.speedValues.isEmpty
        ? List.generate(twoHoursOfData, (i) => 400 + 50 * sin(i * 0.05))
        : widget.speedValues.length > twoHoursOfData
        ? widget.speedValues.sublist(widget.speedValues.length - twoHoursOfData)
        : widget.speedValues;

    final densityValues = widget.densityValues.isEmpty
        ? List.generate(twoHoursOfData, (i) => 5 + 3 * sin(i * 0.08))
        : widget.densityValues.length > twoHoursOfData
        ? widget.densityValues.sublist(widget.densityValues.length - twoHoursOfData)
        : widget.densityValues;

    // Calculate Earth impact index relative to the DISPLAYED data
    // The most recent data point is at the END of the array (index = length - 1)
    // Earth impact shows where in the past the solar wind currently hitting Earth was measured
    final earthImpactIndex = _calculateEarthImpactIndexForDisplayedData(bzValues.length);

    // Calculate time label interval - show ~8 labels across the chart
    final int timeLabelInterval = max(1, (bzValues.length / 8).floor());

    // Adjust pulse speed based on BzH value
    if (bzH > 1) {
      final speed = 1500 / (bzH * 0.5);
      _pulseController.duration = Duration(milliseconds: speed.toInt());
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.tealAccent.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              if (isAuroraLikely)
                BoxShadow(
                  color: _negativeColor.withOpacity(0.2 + _pulseAnimation.value * 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Background gradient showing positive/negative zones
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ZoneBackgroundPainter(yLimit: yLimit),
                  ),
                ),

                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LineChart(
                      LineChartData(
                        lineBarsData: [
                          // Bt envelope lines (amber, dashed)
                          if (btValues.isNotEmpty) ...[
                            // Positive Bt envelope
                            LineChartBarData(
                              spots: List.generate(
                                btValues.length,
                                    (i) => FlSpot(i.toDouble(), btValues[i]),
                              ),
                              isCurved: true,
                              color: _btColor.withOpacity(0.5),
                              barWidth: 1.5,
                              dotData: const FlDotData(show: false),
                              dashArray: [4, 4],
                            ),
                            // Negative Bt envelope
                            LineChartBarData(
                              spots: List.generate(
                                btValues.length,
                                    (i) => FlSpot(i.toDouble(), -btValues[i]),
                              ),
                              isCurved: true,
                              color: _btColor.withOpacity(0.5),
                              barWidth: 1.5,
                              dotData: const FlDotData(show: false),
                              dashArray: [4, 4],
                            ),
                          ],
                          // Bz line with precise zero-crossing color changes
                          ..._buildPreciseColorSegments(bzValues, yLimit, bzH),
                        ],
                        minY: -yLimit,
                        maxY: yLimit,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: yLimit / 4,
                          getDrawingHorizontalLine: (value) {
                            if (value == 0) {
                              return FlLine(
                                color: Colors.white.withOpacity(0.5),
                                strokeWidth: 1.5,
                              );
                            }
                            return FlLine(
                              color: Colors.white.withOpacity(0.08),
                              strokeWidth: 1,
                            );
                          },
                          getDrawingVerticalLine: (value) {
                            return FlLine(
                              color: Colors.white.withOpacity(0.05),
                              strokeWidth: 1,
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: yLimit / 2,
                              getTitlesWidget: (value, meta) {
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  child: Text(
                                    value.toInt().toString(),
                                    style: TextStyle(
                                      color: _getColorForValue(value, yLimit),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                // Show labels at calculated intervals
                                if (idx % timeLabelInterval == 0 && idx < times.length && times[idx].isNotEmpty) {
                                  final isEarthImpact = earthImpactIndex != null &&
                                      (idx - earthImpactIndex!).abs() < timeLabelInterval / 2;
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    child: Text(
                                      times[idx],
                                      style: TextStyle(
                                        color: isEarthImpact
                                            ? Colors.amber
                                            : Colors.white70,
                                        fontSize: 10,
                                        fontWeight: isEarthImpact
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 0,
                              color: Colors.white.withOpacity(0.4),
                              strokeWidth: 2,
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.only(right: 8, bottom: 4),
                                labelResolver: (_) => 'Bz = 0',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          verticalLines: (earthImpactIndex != null && earthImpactIndex! >= 0 && earthImpactIndex < bzValues.length) ? [
                            VerticalLine(
                              x: earthImpactIndex.toDouble(),
                              color: Colors.amber,
                              strokeWidth: 2.5,
                              dashArray: const [6, 4],
                              label: VerticalLineLabel(
                                show: true,
                                alignment: Alignment.topLeft,
                                padding: const EdgeInsets.only(right: 8, top: 4),
                                labelResolver: (_) => '🌍 At Earth',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.amber, blurRadius: 8),
                                  ],
                                ),
                              ),
                            ),
                          ] : [],
                        ),
                        backgroundColor: Colors.transparent,
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipBorder: BorderSide(
                              color: Colors.tealAccent.withOpacity(0.3),
                              width: 1,
                            ),
                            tooltipRoundedRadius: 8,
                            tooltipPadding: const EdgeInsets.all(10),
                            tooltipMargin: 8,
                            getTooltipItems: (touchedSpots) => _buildTooltipItems(touchedSpots, bzValues, btValues, times, yLimit),
                          ),
                          handleBuiltInTouches: true,
                        ),
                      ),
                    ),
                  ),
                ),

                // Aurora icon when conditions are good
                if (isAuroraLikely)
                  const Positioned(
                    top: 16,
                    left: 16,
                    child: PulsingAuroraIcon(),
                  ),

                // Legend
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildLegend(),
                ),

                // BzH Index display
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: _buildBzHDisplay(bzH),
                ),

                // Chart info
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _buildChartInfo(earthImpactIndex),
                ),

                // Speed mini-chart (top left)
                if (speedValues.isNotEmpty)
                  Positioned(
                    top: 60,
                    left: 16,
                    child: _buildMiniChart(
                      values: speedValues,
                      label: 'Speed',
                      value: '${widget.speed.toStringAsFixed(0)} km/s',
                      color: _speedColor,
                      trend: _getTrendIndicator(speedValues),
                    ),
                  ),

                // Density mini-chart (top right)
                if (densityValues.isNotEmpty)
                  Positioned(
                    top: 60,
                    right: 16,
                    child: _buildMiniChart(
                      values: densityValues,
                      label: 'Density',
                      value: '${widget.density.toStringAsFixed(1)} cm⁻³',
                      color: _densityColor,
                      trend: _getTrendIndicator(densityValues),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Get color based on Bz value
  Color _getColorForValue(double value, double yLimit) {
    if (value < 0) {
      return _negativeColor; // Red for negative
    } else if (value > 0) {
      return _positiveColor; // Green for positive
    } else {
      return _neutralColor; // Yellow for zero
    }
  }

  /// Builds Bz line segments with PRECISE zero-crossing points
  /// This calculates exactly where the line crosses zero and splits segments there
  List<LineChartBarData> _buildPreciseColorSegments(List<double> bzValues, double yLimit, double bzH) {
    if (bzValues.isEmpty) return [];

    final segments = <LineChartBarData>[];
    var currentSegmentSpots = <FlSpot>[];
    bool? currentIsNegative;

    for (int i = 0; i < bzValues.length; i++) {
      final currentValue = bzValues[i];
      final isNegative = currentValue < 0;

      if (i == 0) {
        // First point - start a new segment
        currentSegmentSpots.add(FlSpot(i.toDouble(), currentValue));
        currentIsNegative = isNegative;
        continue;
      }

      final prevValue = bzValues[i - 1];
      final prevIsNegative = prevValue < 0;

      // Check if we crossed zero between previous point and current point
      final crossedZero = (prevValue > 0 && currentValue < 0) || (prevValue < 0 && currentValue > 0);

      if (crossedZero) {
        // Calculate the exact X position where zero is crossed
        // Using linear interpolation:
        // If prev = 5 and curr = -5, zero crossing is at 50% (5 / (5+5) = 0.5)
        // If prev = 3 and curr = -1, zero crossing is at 75% (3 / (3+1) = 0.75)
        final prevAbs = prevValue.abs();
        final currAbs = currentValue.abs();
        final crossingRatio = prevAbs / (prevAbs + currAbs);
        final crossingX = (i - 1) + crossingRatio;

        // Add the zero-crossing point to the current segment
        currentSegmentSpots.add(FlSpot(crossingX, 0));

        // Finish the current segment
        if (currentSegmentSpots.length >= 2) {
          segments.add(_createSegment(currentSegmentSpots, currentIsNegative ?? false, bzH));
        }

        // Start a new segment from the zero-crossing point
        currentSegmentSpots = [FlSpot(crossingX, 0)];
        currentIsNegative = isNegative;
      }

      // Add current point to segment
      currentSegmentSpots.add(FlSpot(i.toDouble(), currentValue));

      // Handle the case where value is exactly zero
      if (currentValue == 0 && i < bzValues.length - 1) {
        // If we're at exactly zero, check the next value to determine color
        // For now, just continue the segment
      }
    }

    // Don't forget the last segment
    if (currentSegmentSpots.length >= 2) {
      segments.add(_createSegment(currentSegmentSpots, currentIsNegative ?? false, bzH));
    }

    return segments;
  }

  /// Creates a colored line segment
  LineChartBarData _createSegment(List<FlSpot> spots, bool isNegative, double bzH) {
    final color = isNegative ? _negativeColor : _positiveColor;

    // Calculate glow intensity - stronger for negative (good for aurora)
    final glowIntensity = isNegative
        ? 0.5 + (_pulseAnimation.value * 0.4 * min(bzH / 2, 1.0))
        : 0.3;
    final glowRadius = isNegative
        ? 10.0 + (_pulseAnimation.value * 12 * min(bzH / 2, 1.0))
        : 5.0;

    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2, // Reduced smoothness to keep lines closer to actual data
      preventCurveOverShooting: true, // Prevent curve from overshooting zero line
      preventCurveOvershootingThreshold: 0.1,
      color: color,
      barWidth: isNegative ? 3.5 : 3.0,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      shadow: Shadow(
        color: color.withOpacity(glowIntensity),
        blurRadius: glowRadius,
        offset: const Offset(0, 0),
      ),
      belowBarData: BarAreaData(
        show: isNegative,
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.3),
            color.withOpacity(0.1),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      aboveBarData: BarAreaData(
        show: !isNegative,
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            color.withOpacity(0.1),
            color.withOpacity(0.2),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem(
            color: _negativeColor,
            label: 'Bz Negative',
            subtitle: 'Good for Aurora ✓',
            hasGlow: true,
          ),
          const SizedBox(height: 6),
          _legendItem(
            color: _positiveColor,
            label: 'Bz Positive',
            subtitle: 'Not favorable',
            hasGlow: false,
          ),
          const SizedBox(height: 6),
          _legendItem(
            color: _btColor,
            label: 'Bt Envelope',
            subtitle: 'Total field',
            hasGlow: false,
            isDashed: true,
          ),
        ],
      ),
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required String subtitle,
    required bool hasGlow,
    bool isDashed = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 4,
          decoration: BoxDecoration(
            color: isDashed ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(2),
            border: isDashed ? Border.all(color: color, width: 1) : null,
            boxShadow: hasGlow ? [
              BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ] : null,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 8,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBzHDisplay(double bzH) {
    final Color accentColor;
    final String emoji;
    if (bzH >= 3) {
      accentColor = const Color(0xFFFF4444); // Red - storm (lots of negative Bz)
      emoji = '🌌';
    } else if (bzH >= 2) {
      accentColor = const Color(0xFFFF6666); // Lighter red - active
      emoji = '✨';
    } else if (bzH >= 1) {
      accentColor = const Color(0xFFFFAA00); // Amber - moderate
      emoji = '⚡';
    } else {
      accentColor = const Color(0xFF888888); // Gray - quiet
      emoji = '☀️';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.25),
            accentColor.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withOpacity(0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.3 + _pulseAnimation.value * 0.2),
            blurRadius: 15 + _pulseAnimation.value * 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BzH Index',
                style: TextStyle(
                  color: accentColor.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(emoji, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            bzH.toStringAsFixed(2),
            style: TextStyle(
              color: accentColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: accentColor.withOpacity(0.8),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          Text(
            _getBzHDescription(bzH),
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartInfo(int? earthImpactIndex) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.tealAccent.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'IMF Bz Component',
            style: TextStyle(
              color: Colors.tealAccent.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (earthImpactIndex != null && widget.speed > 0)
            Text(
              '~${_getEarthImpactDelay().toStringAsFixed(0)} min to Earth',
              style: TextStyle(
                color: Colors.amber.withOpacity(0.9),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  List<LineTooltipItem?> _buildTooltipItems(
      List<LineBarSpot> touchedSpots,
      List<double> bzValues,
      List<double> btValues,
      List<String> times,
      double yLimit,
      ) {
    if (touchedSpots.isEmpty) return [];

    final spot = touchedSpots.first;
    final index = spot.x.toInt();
    if (index >= times.length) return [null];

    // Check if this is a Bz value
    final isBzValue = index < bzValues.length &&
        (spot.y - bzValues[index]).abs() < 0.5;

    // Check if this is a Bt value
    final isBtPositive = index < btValues.length &&
        (spot.y - btValues[index]).abs() < 0.5;
    final isBtNegative = index < btValues.length &&
        (spot.y - (-btValues[index])).abs() < 0.5;

    if (isBzValue) {
      final bzValue = bzValues[index];
      final color = _getColorForValue(bzValue, yLimit);
      final isNegative = bzValue < 0;
      return [
        LineTooltipItem(
          '${times[index]}\nBz: ${bzValue.toStringAsFixed(1)} nT\n${isNegative ? "✓ Good for Aurora" : "✗ Not favorable"}',
          TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ];
    } else if (isBtPositive || isBtNegative) {
      final btValue = btValues[index];
      return [
        LineTooltipItem(
          '${times[index]}\nBt: ${btValue.toStringAsFixed(1)} nT',
          const TextStyle(
            color: _btColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ];
    }

    return [null];
  }

  /// Get trend indicator arrow based on recent values
  String _getTrendIndicator(List<double> values) {
    if (values.length < 20) return '→';
    final recent = values.sublist(values.length - 10);
    final older = values.sublist(values.length - 20, values.length - 10);
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
    final olderAvg = older.reduce((a, b) => a + b) / older.length;
    final diff = recentAvg - olderAvg;
    // Use percentage change for better sensitivity
    final percentChange = (diff / olderAvg) * 100;
    if (percentChange > 5) return '↑';
    if (percentChange < -5) return '↓';
    return '→';
  }

  /// Build a mini-chart for speed or density trends
  Widget _buildMiniChart({
    required List<double> values,
    required String label,
    required String value,
    required Color color,
    required String trend,
  }) {
    const double width = 100;
    const double height = 60;

    if (values.isEmpty) return const SizedBox.shrink();

    final displayValues = values.length > 30 ? values.sublist(values.length - 30) : values;
    final spots = <FlSpot>[];
    for (int i = 0; i < displayValues.length; i++) {
      spots.add(FlSpot(i.toDouble(), displayValues[i]));
    }

    final minY = displayValues.reduce(min);
    final maxY = displayValues.reduce(max);
    final padding = (maxY - minY) * 0.1;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                trend,
                style: TextStyle(
                  color: trend == '↑' ? Colors.greenAccent : 
                         trend == '↓' ? Colors.redAccent : Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          color.withOpacity(0.3),
                          color.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                minY: minY - padding,
                maxY: maxY + padding,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Calculate Earth impact index for the displayed data window
  /// This shows where in the chart the solar wind currently hitting Earth was measured
  /// Data flows: L1 satellite (1.5M km away) -> ~X minutes later -> Earth
  int? _calculateEarthImpactIndexForDisplayedData(int dataLength) {
    if (widget.speed <= 0 || dataLength == 0) return null;

    // Distance from L1 to Earth in km
    const double l1ToEarthKm = 1500000.0;

    // Calculate delay in minutes: distance / speed / 60
    // Speed is in km/s, so divide by 60 to get minutes
    final delayMinutes = l1ToEarthKm / widget.speed / 60.0;

    // Assuming 1-minute data resolution, delay in minutes = data points back from current
    final dataPointsBack = delayMinutes.round();

    // Most recent data is at the END of the array
    final mostRecentIndex = dataLength - 1;

    // Earth impact shows conditions from X minutes ago
    final earthImpactIndex = mostRecentIndex - dataPointsBack;

    // Clamp to valid range
    if (earthImpactIndex < 0) return 0;
    if (earthImpactIndex >= dataLength) return dataLength - 1;

    return earthImpactIndex;
  }

  double _getEarthImpactDelay() {
    if (widget.speed <= 0) return 0.0;
    const double l1ToEarthKm = 1500000.0;
    return l1ToEarthKm / widget.speed / 60.0;
  }

  double _calculateBzH(List<double> values) {
    if (values.isEmpty) return 0.0;
    final recent = values.length > 60 ? values.skip(values.length - 60).toList() : values;
    final sum = recent.where((bz) => bz < 0).fold(0.0, (acc, bz) => acc + (-bz / 60));
    return double.parse(sum.toStringAsFixed(2));
  }

  double _getYLimit(List<double> values) {
    if (widget.btValues.isEmpty) return 10;
    final absMax = widget.btValues.map((e) => e.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    if (absMax <= 5) return 5;
    if (absMax <= 10) return 10;
    if (absMax <= 20) return 20;
    if (absMax <= 50) return 50;
    return 100;
  }

  String _getBzHDescription(double bzH) {
    if (bzH < 0.5) return 'Quiet Sun';
    if (bzH < 1.0) return 'Low Activity';
    if (bzH < 2.0) return 'Moderate';
    if (bzH < 3.0) return 'Active';
    return 'Storm!';
  }
}

/// Custom painter for background zones
class _ZoneBackgroundPainter extends CustomPainter {
  final double yLimit;

  _ZoneBackgroundPainter({required this.yLimit});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // Negative zone (bottom half) - subtle red tint (good for aurora)
    final negativeZonePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFFFF4444).withOpacity(0.02),
          const Color(0xFFFF4444).withOpacity(0.05),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, centerY, size.width, centerY));

    canvas.drawRect(
      Rect.fromLTWH(0, centerY, size.width, centerY),
      negativeZonePaint,
    );

    // Positive zone (top half) - subtle green tint
    final positiveZonePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF00FF88).withOpacity(0.02),
          const Color(0xFF00FF88).withOpacity(0.04),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, centerY));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, centerY),
      positiveZonePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}