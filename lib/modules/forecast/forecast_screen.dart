import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'services/substorm_alert_service.dart';
import 'services/solar_wind_service.dart';
import 'services/kp_service.dart';
import 'services/aurora_message_service.dart';
import 'services/weather_service.dart';
import 'services/sunrise_sunset_service.dart';
import 'services/permission_util.dart';
import 'widgets/forecast_chart_widget.dart';
import 'widgets/cloud_cover_map.dart';
import 'widgets/aurora_sighting_widget.dart';
import '../../widgets/common/logo_widget.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  final SubstormAlertService _substormService = SubstormAlertService();
  final WeatherService _weatherService = WeatherService();
  final SunriseSunsetService _sunService = SunriseSunsetService();
  
  // Default coordinates for Iceland (Reykjavik) - used as fallback
  static const double _icelandLatitude = 64.1466;
  static const double _icelandLongitude = -21.9426;
  
  Map<String, dynamic>? _substormStatus;
  Map<String, dynamic>? _weatherData;
  Map<String, dynamic>? _sunData;
  Position? _currentPosition;
  
  bool _isLoadingSubstorm = true;
  bool _isLoadingData = true;
  String? _error;

  // Solar wind and Kp data
  List<double> _bzValues = [];
  List<double> _btValues = [];
  double _kp = 0.0;
  double _speed = 0.0;
  double _density = 0.0;
  double _bt = 0.0;

  // Timer for auto-refreshing Bz data every minute
  Timer? _bzRefreshTimer;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadAllData();
    
    // Start timer to refresh Bz data every minute
    _startBzRefreshTimer();
  }

  @override
  void dispose() {
    _bzRefreshTimer?.cancel();
    super.dispose();
  }

  void _startBzRefreshTimer() {
    // Cancel existing timer if any
    _bzRefreshTimer?.cancel();
    
    // Refresh Bz data every minute
    _bzRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        print('🔄 Auto-refreshing Bz data...');
        _loadSolarWindData();
      } else {
        timer.cancel();
      }
    });
    
    print('⏱️ Started Bz auto-refresh timer (every 1 minute)');
  }

  Future<void> _requestLocationPermission() async {
    // Skip permission request on web - we use Iceland coordinates directly
    if (kIsWeb) {
      return;
    }
    
    final granted = await PermissionUtil.requestLocationPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required for accurate aurora forecasts. Using default Iceland location.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoadingData = true;
      _error = null;
    });

    try {
      // On web, skip geolocation and use Iceland coordinates directly
      // On mobile, try to get current position, fallback to Iceland if it fails
      if (kIsWeb) {
        // Use Iceland coordinates directly for web users
        _currentPosition = Position(
          latitude: _icelandLatitude,
          longitude: _icelandLongitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      } else {
        // On mobile, try to get actual location
        try {
          _currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
        } catch (e) {
          // If geolocation fails, fallback to Iceland coordinates
          print('⚠️ Geolocation failed, using Iceland fallback: $e');
          _currentPosition = Position(
            latitude: _icelandLatitude,
            longitude: _icelandLongitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
        }
      }

      // Load all data in parallel
      await Future.wait([
        _loadSubstormStatus(),
        _loadSolarWindData(),
        _loadWeatherData(),
        _loadSunData(),
      ]);

      setState(() {
        _isLoadingData = false;
      });
    } catch (e) {
      // Even if data loading fails, set a fallback position
      if (_currentPosition == null) {
        _currentPosition = Position(
          latitude: _icelandLatitude,
          longitude: _icelandLongitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
      
      setState(() {
        _error = e.toString();
        _isLoadingData = false;
      });
    }
  }

  Future<void> _loadSubstormStatus() async {
    setState(() => _isLoadingSubstorm = true);
    try {
      final status = await _substormService.getSubstormStatus();
      setState(() {
        _substormStatus = status;
        _isLoadingSubstorm = false;
      });
    } catch (e) {
      setState(() => _isLoadingSubstorm = false);
    }
  }

  Future<void> _loadSolarWindData() async {
    try {
      final swData = await SolarWindService.fetchData();
      final bzRes = await SolarWindService.fetchBzHistory();
      final kpIndex = await KpService.fetchCurrentKp();

      setState(() {
        _bzValues = bzRes.bzValues;
        _btValues = bzRes.btValues; // Add this line to populate btValues
        _kp = kpIndex;
        _speed = swData.speed;
        _density = swData.density;
        _bt = swData.bt;
        
        // Debug: Print data for chart
        print('Chart Data - Bz: ${_bzValues.length} values, Bt: ${_btValues.length} values');
        if (_bzValues.isNotEmpty) print('Bz range: ${_bzValues.first.toStringAsFixed(2)} to ${_bzValues.last.toStringAsFixed(2)}');
        if (_btValues.isNotEmpty) print('Bt range: ${_btValues.first.toStringAsFixed(2)} to ${_btValues.last.toStringAsFixed(2)}');
      });
    } catch (e) {
      // Handle error silently for now
    }
  }

  Future<void> _loadWeatherData() async {
    if (_currentPosition == null) return;
    
    try {
      final weather = await _weatherService.getWeatherData(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      setState(() {
        _weatherData = weather;
      });
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadSunData() async {
    if (_currentPosition == null) return;
    
    try {
      final sun = await _sunService.getSunData(_currentPosition!);
      setState(() {
        _sunData = sun;
      });
    } catch (e) {
      // Handle error silently
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

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

  double _calculateBzH(List<double> values) {
    if (values.isEmpty) return 0.0;
    final recent = values.length > 60 ? values.skip(values.length - 60).toList() : values;
    final sum = recent.where((bz) => bz < 0).fold(0.0, (acc, bz) => acc + (-bz / 60));
    return double.parse(sum.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoSmall(),
            SizedBox(width: 12),
            Text(
              'Aurora Nowcast',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAllData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoadingData
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.tealAccent,
              ),
            )
          : _error != null
              ? _buildErrorView()
              : RefreshIndicator(
                  color: Colors.tealAccent,
                  backgroundColor: Colors.black.withOpacity(0.8),
                  onRefresh: _loadAllData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const AuroraSightingWidget(),
                        const SizedBox(height: 8),
                        _buildAuroraStatusCard(),
                        const SizedBox(height: 16),
                        _buildBzChart(),
                        const SizedBox(height: 16),
                        _buildCloudCoverMap(),
                        const SizedBox(height: 16),
                        _buildSubstormTracker(),
                        const SizedBox(height: 16),
                        _buildSolarWindCard(),
                        const SizedBox(height: 16),
                        _buildWeatherCard(),
                        const SizedBox(height: 16),
                        _buildSunDataCard(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadAllData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuroraStatusCard() {
    final bzH = _calculateBzH(_bzValues);
    final combinedMessage = AuroraMessageService.getCombinedAuroraMessage(_kp, bzH);
    final statusColor = AuroraMessageService.getStatusColor(_kp, bzH);
    final auroraAdvice = AuroraMessageService.getAuroraAdvice(_kp, bzH);

    bool isNoDarkness = false;
    if (_sunData != null) {
      final astroStart = _sunData!['astronomicalTwilightStart'] ?? 'N/A';
      final astroEnd = _sunData!['astronomicalTwilightEnd'] ?? 'N/A';

      isNoDarkness = (astroStart == '00:00' && astroEnd == '00:00') ||
                     (astroStart == '0:00' && astroEnd == '0:00') ||
                     (astroStart == '0:00' && astroEnd == '00:00') ||
                     (astroStart == '00:00' && astroEnd == '0:00');
    }

    return Container(
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
          // Primary aurora status - always shown
          Text(
            combinedMessage,
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
          const SizedBox(height: 12),
          Text(
            auroraAdvice,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          
          // Darkness warning - shown below if applicable
          if (isNoDarkness) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Limited Darkness Tonight',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'It will not be dark enough at your location tonight for optimal aurora spotting',
              style: TextStyle(
                color: Colors.red.withOpacity(0.8),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubstormTracker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _substormStatus?['isActive'] == true 
                      ? Icons.flash_on 
                      : Icons.flash_off,
                  color: _substormStatus?['isActive'] == true 
                      ? Colors.amber 
                      : Colors.white70,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Substorm Tracker',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingSubstorm)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.tealAccent,
                ),
              )
            else if (_substormStatus == null)
              const Text(
                'Unable to load substorm data',
                style: TextStyle(color: Colors.white70),
              )
            else ...[
              Text(
                _substormService.getSubstormDescription(
                  _substormStatus!['aeValue'] as int,
                ),
                style: TextStyle(
                  color: _substormStatus!['isActive'] == true 
                      ? Colors.amber 
                      : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AE Index: ${_substormStatus!['aeValue']} nT',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Last updated: ${_formatTimestamp(_substormStatus!['timestamp'] as DateTime)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSolarWindCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Solar Wind Conditions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSolarWindMetric('Kp Index', _kp.toStringAsFixed(1), Colors.orange),
                ),
                Expanded(
                  child: _buildSolarWindMetric('Speed', '${_speed.toStringAsFixed(0)} km/s', Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSolarWindMetric('Density', '${_density.toStringAsFixed(1)} cm⁻³', Colors.green),
                ),
                Expanded(
                  child: _buildSolarWindMetric('Bt', '${_bt.toStringAsFixed(1)} nT', Colors.purple),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'BzH: ${_calculateBzH(_bzValues).toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.tealAccent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolarWindMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBzChart() {
    if (_bzValues.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7, // 70% of screen height for tablet
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ForecastChartWidget(
            bzValues: _bzValues,
            times: _generateTimeLabels(_bzValues.length),
            kp: _kp,
            speed: _speed,
            density: _density,
            bt: _bt,
            btValues: _btValues,
          ),
        ),
      ),
    );
  }

  List<String> _generateTimeLabels(int count) {
    final now = DateTime.now();
    return List.generate(count, (index) {
      final time = now.subtract(Duration(minutes: count - 1 - index));
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    });
  }

  Widget _buildCloudCoverMap() {
    if (_weatherData == null || _weatherData!.containsKey('error')) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cloud Cover Map',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            CloudCoverMap(
              position: _currentPosition ?? Position(
                latitude: _icelandLatitude, // Default to Reykjavik
                longitude: _icelandLongitude,
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                heading: 0,
                speed: 0,
                speedAccuracy: 0,
                altitudeAccuracy: 0,
                headingAccuracy: 0,
              ),
              cloudCover: (_weatherData?['cloudCover'] as num?)?.toDouble() ?? 0.0,
              weatherDescription: _weatherData?['description'] ?? 'Unknown',
              weatherIcon: _weatherData?['icon'] ?? '01d',
              isNowcast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    if (_weatherData == null || _weatherData!.containsKey('error')) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Weather',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildWeatherMetric('Temperature', '${_weatherData!['temperature']?.toStringAsFixed(1)}°C', Colors.red),
                ),
                Expanded(
                  child: _buildWeatherMetric('Humidity', '${_weatherData!['humidity']}%', Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildWeatherMetric('Wind', '${_weatherData!['windSpeed']?.toStringAsFixed(1)} m/s', Colors.green),
                ),
                Expanded(
                  child: _buildWeatherMetric('Clouds', '${_weatherData!['cloudCover']}%', Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSunDataCard() {
    if (_sunData == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sun & Twilight Times',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSunMetric('Sunrise', _sunData!['sunrise'] ?? 'N/A', Colors.orange),
                ),
                Expanded(
                  child: _buildSunMetric('Sunset', _sunData!['sunset'] ?? 'N/A', Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSunMetric('Astro Start', _sunData!['astronomicalTwilightStart'] ?? 'N/A', Colors.indigo),
                ),
                Expanded(
                  child: _buildSunMetric('Astro End', _sunData!['astronomicalTwilightEnd'] ?? 'N/A', Colors.indigo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSunMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
} 