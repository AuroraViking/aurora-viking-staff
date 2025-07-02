// Forecast screen for Aurora/weather forecast tools 
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme/colors.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isLoading = true;
  String? error;
  Position? currentPosition;

  // Sample data (replace with real API calls)
  double kp = 2.3;
  double speed = 450.0;
  double density = 3.2;
  double bt = 5.1;
  double bz = -2.1;
  double bzH = 1.8;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      // Get current position
      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // TODO: Load real forecast data from APIs
      await Future.delayed(const Duration(seconds: 2)); // Simulate API call

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Color _getStatusColor(double kp, double bzH) {
    if (kp >= 5.0 || bzH >= 3.0) return Colors.red;
    if (kp >= 3.0 || bzH >= 1.5) return Colors.orange;
    if (kp >= 2.0 || bzH >= 0.5) return Colors.yellow;
    return Colors.green;
  }

  String _getAuroraMessage(double kp, double bzH) {
    if (kp >= 5.0 || bzH >= 3.0) {
      return 'Strong aurora activity expected!';
    } else if (kp >= 3.0 || bzH >= 1.5) {
      return 'Moderate aurora activity possible';
    } else if (kp >= 2.0 || bzH >= 0.5) {
      return 'Weak aurora activity possible';
    } else {
      return 'Low aurora activity expected';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Error: $error',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final statusColor = _getStatusColor(kp, bzH);
    final auroraMessage = _getAuroraMessage(kp, bzH);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'Nowcast'),
              Tab(text: 'Aurora Forecast'),
              Tab(text: 'Cloud Cover'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Nowcast Tab
          RefreshIndicator(
            color: Colors.tealAccent,
            backgroundColor: Colors.black.withOpacity(0.8),
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Aurora Status Box
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withOpacity(0.2),
                          statusColor.withOpacity(0.1),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          auroraMessage,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: statusColor.withOpacity(0.5), blurRadius: 10),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Check cloud cover and weather conditions for optimal viewing',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Current Conditions
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.tealAccent.withOpacity(0.1),
                          Colors.cyanAccent.withOpacity(0.05),
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.tealAccent.withOpacity(0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.tealAccent.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speed, color: Colors.tealAccent),
                            SizedBox(width: 8),
                            Text(
                              'Current Conditions',
                              style: TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDataRow('-BzH', bzH.toStringAsFixed(2), Colors.white, isHighlighted: true),
                                  const SizedBox(height: 8),
                                  _buildDataRow('Kp Index', kp.toStringAsFixed(1), Colors.white70),
                                  const SizedBox(height: 8),
                                  _buildDataRow('Bt', '${bt.toStringAsFixed(1)} nT', Colors.white70),
                                  const SizedBox(height: 8),
                                  _buildDataRow('Bz', '${bz.toStringAsFixed(1)} nT', Colors.white70),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDataRow('Speed', '${speed.toStringAsFixed(0)} km/s', Colors.white70),
                                  const SizedBox(height: 8),
                                  _buildDataRow('Density', '${density.toStringAsFixed(1)} p/cm³', Colors.white70),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.tealAccent.withOpacity(0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.satellite_alt, color: Colors.tealAccent, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Data from DSCOVR satellite at L1 point (1.5 million km from Earth)',
                                  style: TextStyle(
                                    color: Colors.tealAccent,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Placeholder for chart
                  Container(
                    height: 300,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.show_chart, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Solar Wind Chart',
                            style: TextStyle(color: Colors.grey, fontSize: 18),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Chart integration coming soon',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Cloud cover placeholder
                  Container(
                    height: 200,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Cloud Cover Map',
                            style: TextStyle(color: Colors.grey, fontSize: 18),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Map integration coming soon',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          // Aurora Forecast Tab
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Sun Info
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.orange.withOpacity(0.1),
                        Colors.amber.withOpacity(0.05),
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.6),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.wb_sunny, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Sun & Daylight',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSunInfo(),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Moon Info
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.tealAccent.withOpacity(0.1),
                        Colors.cyanAccent.withOpacity(0.05),
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.tealAccent.withOpacity(0.6),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.nightlight_round, color: Colors.tealAccent),
                          SizedBox(width: 8),
                          Text(
                            'Moon Phase',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMoonInfo(),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Kp Forecast
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.tealAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            '24-Hour Kp Forecast',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.tealAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildKpForecastList(),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Cloud Cover Tab
          currentPosition != null
              ? Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[700]!),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Cloud Cover Forecast',
                          style: TextStyle(color: Colors.grey, fontSize: 18),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Cloud cover integration coming soon',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : const Center(
                  child: Text(
                    'Waiting for location...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value, Color color, {bool isHighlighted = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: isHighlighted ? 12 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isHighlighted ? 8 : 6,
              vertical: isHighlighted ? 4 : 2,
            ),
            decoration: isHighlighted
                ? BoxDecoration(
                    color: Colors.tealAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.tealAccent.withOpacity(0.3),
                      width: 0.5,
                    ),
                  )
                : null,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: isHighlighted ? 14 : 12,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                shadows: isHighlighted
                    ? [
                        Shadow(
                          color: Colors.tealAccent.withOpacity(0.5),
                          blurRadius: 8,
                        )
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSunInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataRow('Sunrise', '06:30', Colors.white),
                  const SizedBox(height: 8),
                  _buildDataRow('Sunset', '18:45', Colors.white70),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataRow('Day Length', '12h 15m', Colors.white70),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataRow('Astro. Twilight Start', '20:15', Colors.white70),
                  const SizedBox(height: 8),
                  _buildDataRow('Astro. Twilight End', '04:45', Colors.white70),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.orange.withOpacity(0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Astronomical Twilight: Dark enough to see the aurora',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMoonInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataRow('Phase', 'Waxing Crescent', Colors.white),
                  const SizedBox(height: 8),
                  _buildDataRow('Illumination', '25%', Colors.white70),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataRow('Moonrise', '10:30', Colors.white70),
                  const SizedBox(height: 8),
                  _buildDataRow('Moonset', '22:15', Colors.white70),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.tealAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.tealAccent.withOpacity(0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.tealAccent, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Next Phase: First Quarter in 3 days',
                  style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpForecastList() {
    // Sample Kp forecast data
    final forecasts = [
      {'time': 'Now', 'kp': 2.3, 'color': Colors.green},
      {'time': '3h', 'kp': 2.8, 'color': Colors.yellow},
      {'time': '6h', 'kp': 3.2, 'color': Colors.orange},
      {'time': '9h', 'kp': 2.9, 'color': Colors.yellow},
      {'time': '12h', 'kp': 2.5, 'color': Colors.green},
      {'time': '15h', 'kp': 2.1, 'color': Colors.green},
      {'time': '18h', 'kp': 1.8, 'color': Colors.green},
      {'time': '21h', 'kp': 2.0, 'color': Colors.green},
    ];

    return Column(
      children: forecasts.map((forecast) => _buildKpForecastCard(forecast)).toList(),
    );
  }

  Widget _buildKpForecastCard(Map<String, dynamic> forecast) {
    final color = forecast['color'] as Color;
    final kp = forecast['kp'] as double;
    final time = forecast['time'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withOpacity(0.15),
            Colors.black.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                'Kp ${kp.toStringAsFixed(1)}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getKpDescription(kp),
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getKpDescription(double kp) {
    if (kp >= 5.0) return 'Strong Aurora';
    if (kp >= 3.0) return 'Moderate Aurora';
    if (kp >= 2.0) return 'Weak Aurora';
    return 'Low Activity';
  }
} 