import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/hemispheric_power_service.dart';

/// Widget that displays hemispheric power data in a mirrored bar chart
/// North hemisphere power extends upward, South extends downward
class HemisphericPowerWidget extends StatefulWidget {
  const HemisphericPowerWidget({super.key});

  @override
  State<HemisphericPowerWidget> createState() => _HemisphericPowerWidgetState();
}

class _HemisphericPowerWidgetState extends State<HemisphericPowerWidget> {
  final HemisphericPowerService _service = HemisphericPowerService();
  List<HemisphericPowerReading>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _service.fetchHemisphericPowerData();
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Get bar color based on power level
  Color _getBarColor(int power) {
    if (power >= 80) {
      return Colors.red;
    } else if (power >= 50) {
      return Colors.orange;
    } else if (power >= 20) {
      return Colors.yellow;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_isLoading)
            _buildLoading()
          else if (_error != null)
            _buildError()
          else if (_data == null || _data!.isEmpty)
            _buildNoData()
          else
            _buildChart(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final latestReading = _data?.isNotEmpty == true ? _data!.last : null;
    
    return Row(
      children: [
        Icon(
          Icons.bolt,
          color: latestReading != null && latestReading.northPower >= 50
              ? Colors.amber
              : Colors.tealAccent,
          size: 24,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Hemispheric Power',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (latestReading != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getBarColor(latestReading.northPower).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _getBarColor(latestReading.northPower).withOpacity(0.5),
              ),
            ),
            child: Text(
              '${latestReading.northPower} GW',
              style: TextStyle(
                color: _getBarColor(latestReading.northPower),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      ),
    );
  }

  Widget _buildError() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text(
              'Unable to load data',
              style: TextStyle(color: Colors.white70),
            ),
            TextButton(
              onPressed: _loadData,
              child: const Text('Retry', style: TextStyle(color: Colors.tealAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoData() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildChart() {
    // Take last 60 readings (~5 hours of data at 5-min intervals)
    final displayData = _data!.length > 60 
        ? _data!.sublist(_data!.length - 60) 
        : _data!;

    return Column(
      children: [
        SizedBox(
          height: 280,
          child: _buildBarChart(displayData),
        ),
        const SizedBox(height: 12),
        _buildLegend(),
        const SizedBox(height: 8),
        _buildCurrentValues(),
      ],
    );
  }

  Widget _buildBarChart(List<HemisphericPowerReading> displayData) {
    // Find the index closest to current time for the Earth line
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

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        minY: -100,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.black87,
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < displayData.length) {
                final reading = displayData[groupIndex];
                final time = '${reading.observationTime.hour.toString().padLeft(2, '0')}:${reading.observationTime.minute.toString().padLeft(2, '0')}';
                final isForecast = reading.observationTime.isAfter(now);
                return BarTooltipItem(
                  '$time${isForecast ? " (forecast)" : ""}\nN: ${reading.northPower} GW\nS: ${reading.southPower} GW',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }
              return null;
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.abs().toInt()}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (displayData.length / 4).floorToDouble().clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < displayData.length) {
                  final time = displayData[index].observationTime;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 50,
          getDrawingHorizontalLine: (value) {
            if (value == 0) {
              return const FlLine(color: Colors.white38, strokeWidth: 1);
            }
            return FlLine(color: Colors.white10, strokeWidth: 0.5);
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(displayData.length, (index) {
          final reading = displayData[index];
          return BarChartGroupData(
            x: index,
            barRods: [
              // North hemisphere (upward bars)
              BarChartRodData(
                toY: reading.northPower.toDouble(),
                color: _getBarColor(reading.northPower),
                width: displayData.length > 30 ? 2 : 4,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(2),
                ),
              ),
              // South hemisphere (downward bars)
              BarChartRodData(
                toY: -reading.southPower.toDouble(),
                color: _getBarColor(reading.southPower),
                width: displayData.length > 30 ? 2 : 4,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(2),
                  bottomRight: Radius.circular(2),
                ),
              ),
            ],
          );
        }),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 0,
              color: Colors.white24,
              strokeWidth: 1,
            ),
          ],
          verticalLines: earthIndex != null ? [
            VerticalLine(
              x: earthIndex.toDouble(),
              color: Colors.amber,
              strokeWidth: 2,
              dashArray: [4, 4],
              label: VerticalLineLabel(
                show: true,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(bottom: 4),
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                labelResolver: (line) => '🌍 Now',
              ),
            ),
          ] : [],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(Colors.green, 'Quiet'),
        const SizedBox(width: 16),
        _legendItem(Colors.yellow, 'Moderate'),
        const SizedBox(width: 16),
        _legendItem(Colors.orange, 'Active'),
        const SizedBox(width: 16),
        _legendItem(Colors.red, 'Storm'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildCurrentValues() {
    if (_data == null || _data!.isEmpty) return const SizedBox.shrink();
    
    final latest = _data!.last;
    final northLevel = HemisphericPowerReading.getActivityLevel(latest.northPower);
    final southLevel = HemisphericPowerReading.getActivityLevel(latest.southPower);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.north, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    const Text(
                      'North',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${latest.northPower} GW',
                  style: TextStyle(
                    color: _getBarColor(latest.northPower),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  northLevel,
                  style: TextStyle(
                    color: _getBarColor(latest.northPower).withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white24,
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.south, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    const Text(
                      'South',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${latest.southPower} GW',
                  style: TextStyle(
                    color: _getBarColor(latest.southPower),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  southLevel,
                  style: TextStyle(
                    color: _getBarColor(latest.southPower).withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
