import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/aurora_advisor_service.dart';

class AuroraAdvisorCard extends StatefulWidget {
  final AuroraRecommendation? recommendation;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback? onNavigateToDestination;
  final String? currentLocationName;
  final Map<String, dynamic>? weatherData;

  const AuroraAdvisorCard({
    super.key,
    this.recommendation,
    this.isLoading = false,
    required this.onRefresh,
    this.onNavigateToDestination,
    this.currentLocationName,
    this.weatherData,
  });

  @override
  State<AuroraAdvisorCard> createState() => _AuroraAdvisorCardState();
}

class _AuroraAdvisorCardState extends State<AuroraAdvisorCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_getGradientColor().withOpacity(0.15), Colors.black.withOpacity(0.3)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _getGradientColor().withOpacity(0.5), width: 1.5),
          boxShadow: [BoxShadow(color: _getGradientColor().withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: widget.isLoading ? _buildLoadingState() : _buildContent(),
        ),
      ),
    );
  }

  Color _getGradientColor() {
    if (widget.recommendation == null || widget.recommendation!.hasError) return Colors.grey;
    final prob = widget.recommendation!.viewingProbability;
    if (prob >= 0.7) return Colors.green;
    if (prob >= 0.5) return Colors.tealAccent;
    if (prob >= 0.3) return Colors.amber;
    return Colors.grey;
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.psychology, color: Colors.tealAccent, size: 24),
              SizedBox(width: 12),
              Text('ANALYZING CONDITIONS...', style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent)),
          const SizedBox(height: 16),
          Text('Checking satellite images and space weather...', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final rec = widget.recommendation;
    if (rec == null) return _buildNoDataState();
    if (rec.hasError) return _buildErrorState(rec.errorMessage ?? 'Unknown error');

    return Column(
      children: [
        _buildHeader(rec),
        _buildMainRecommendation(rec),
        _buildProbabilityMeters(rec),
        if (_isExpanded) _buildExpandedContent(rec),
        _buildExpandButton(),
      ],
    );
  }

  Widget _buildNoDataState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.psychology, color: Colors.white38, size: 48),
          const SizedBox(height: 16),
          const Text('Aurora Advisor', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Get a recommendation for optimal aurora viewing', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Get Recommendation'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AuroraRecommendation rec) {
    final isStay = rec.action == 'STAY';
    final headerColor = isStay ? Colors.greenAccent : Colors.tealAccent;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: headerColor.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: headerColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(isStay ? Icons.location_on : Icons.navigation, color: headerColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isStay ? 'STAY HERE' : 'DRIVE',
                  style: TextStyle(color: headerColor, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
                if (widget.currentLocationName != null)
                  Text(
                    'From: ${widget.currentLocationName}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                  ),
              ],
            ),
          ),
          IconButton(onPressed: widget.onRefresh, icon: const Icon(Icons.refresh, color: Colors.white70), tooltip: 'Refresh'),
        ],
      ),
    );
  }

  Widget _buildMainRecommendation(AuroraRecommendation rec) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Summary text (normal guide language)
          Text(
            rec.summary,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500, height: 1.4),
            textAlign: TextAlign.center,
          ),
          
          // Destination info if driving
          if (rec.action == 'DRIVE' && rec.destination != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.place, color: Colors.tealAccent, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          rec.destination!.name,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildInfoChip(Icons.straighten, '${rec.distanceKm.toInt()} km'),
                      const SizedBox(width: 8),
                      _buildInfoChip(Icons.timer, '${rec.travelTimeMinutes} min'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildProbabilityMeters(AuroraRecommendation rec) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: _buildMeter('Aurora', rec.auroraProbability, Icons.auto_awesome, Colors.pinkAccent)),
          const SizedBox(width: 10),
          Expanded(child: _buildMeter('Clear Sky', rec.clearSkyProbability, Icons.cloud_off, Colors.cyanAccent)),
          const SizedBox(width: 10),
          Expanded(child: _buildMeter('Viewing', rec.viewingProbability, Icons.visibility, _getGradientColor())),
        ],
      ),
    );
  }

  Widget _buildMeter(String label, double value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text('${(value * 100).toInt()}%', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: value, backgroundColor: Colors.white.withOpacity(0.1), valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 4),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(AuroraRecommendation rec) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Safety Warnings Section (if any)
          _buildSafetyWarningsSection(),
          
          // Space Weather Section
          _buildSpaceWeatherSection(rec),
          const SizedBox(height: 16),
          
          // Darkness & Moon Section
          _buildDarknessAndMoonSection(rec),
          const SizedBox(height: 16),
          
          // Cloud Cover Section
          _buildCloudCoverSection(rec),
          const SizedBox(height: 16),
          
          // Photography Direction Section
          _buildPhotographySection(rec),
          const SizedBox(height: 16),
          
          // Hunting Tips Section
          _buildHuntingTipsSection(rec),
          const SizedBox(height: 16),
          
          // Factors Summary
          if (rec.factors != null && rec.factors!.isNotEmpty) ...[
            _buildFactorsSummary(rec),
            const SizedBox(height: 16),
          ],
          
          // Disclaimer
          _buildDisclaimer(rec.disclaimer),
          
          // Navigation button
          if (rec.action == 'DRIVE' && rec.navigationUrl != null) ...[
            const SizedBox(height: 16),
            _buildNavigationButton(rec),
          ],
        ],
      ),
    );
  }

  Widget _buildSafetyWarningsSection() {
    // Get weather data from widget
    final weather = widget.weatherData;
    if (weather == null || weather.containsKey('error')) {
      return const SizedBox.shrink();
    }

    final windSpeed = (weather['windSpeed'] as num?)?.toDouble() ?? 0;
    final temperature = (weather['temperature'] as num?)?.toDouble() ?? 10;

    final warnings = SafetyWarning.generateWarnings(
      windSpeed: windSpeed,
      temperature: temperature,
    );

    if (warnings.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasDanger = warnings.any((w) => w.level == WarningLevel.danger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (hasDanger ? Colors.red : Colors.orange).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (hasDanger ? Colors.red : Colors.orange).withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasDanger ? Icons.warning_amber : Icons.info_outline,
                    color: hasDanger ? Colors.red : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasDanger ? 'Safety Alert' : 'Heads Up',
                    style: TextStyle(
                      color: hasDanger ? Colors.red : Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...warnings.map((warning) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(warning.icon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        warning.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSpaceWeatherSection(AuroraRecommendation rec) {
    final statusColor = {
      'STRONG': Colors.greenAccent,
      'MODERATE': Colors.amber,
      'WEAK': Colors.orangeAccent,
      'QUIET': Colors.grey,
    }[rec.bzStatus] ?? Colors.grey;
    
    final trendIcon = rec.bzTrend == 'IMPROVING' ? Icons.trending_up : 
                      rec.bzTrend == 'DECLINING' ? Icons.trending_down : 
                      Icons.trending_flat;
    final trendColor = rec.bzTrend == 'IMPROVING' ? Colors.greenAccent : 
                       rec.bzTrend == 'DECLINING' ? Colors.orangeAccent : 
                       Colors.white54;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('SPACE WEATHER', Icons.wb_sunny, Colors.purpleAccent),
        const SizedBox(height: 10),
        Row(
          children: [
            // Bz Status
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bz Status', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(rec.bzStatus, style: TextStyle(color: statusColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Icon(trendIcon, size: 14, color: trendColor),
                        const SizedBox(width: 4),
                        Text(rec.bzTrend.toLowerCase(), style: TextStyle(color: trendColor, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // BzH Value
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text('BzH Index', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(
                    rec.bzHValue.toStringAsFixed(2),
                    style: TextStyle(
                      color: rec.bzHValue > 3 ? Colors.greenAccent : rec.bzHValue > 1 ? Colors.amber : Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Kp
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text('Kp', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(rec.kpIndex.toStringAsFixed(0), style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDarknessAndMoonSection(AuroraRecommendation rec) {
    final darkness = rec.darkness ?? {};
    final moon = rec.moon ?? {};
    final isDark = darkness['isDark'] == true;
    final moonIllumination = (moon['illumination'] as num?)?.toInt() ?? 0;
    final moonPhase = moon['phase']?.toString() ?? '';
    final moonSignificant = moon['isSignificant'] == true;
    
    return Row(
      children: [
        // Darkness
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(isDark ? Icons.nightlight : Icons.wb_sunny, color: isDark ? Colors.indigoAccent : Colors.orangeAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Darkness', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                      Text(
                        isDark ? 'Dark enough ✓' : 'Wait until ${darkness['startsAt'] ?? 'later'}',
                        style: TextStyle(color: isDark ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      if (darkness['startsAt'] != null && darkness['endsAt'] != null)
                        Text('${darkness['startsAt']} - ${darkness['endsAt']}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Moon
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: moonSignificant ? Colors.amber.withOpacity(0.1) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: moonSignificant ? Border.all(color: Colors.amber.withOpacity(0.3)) : null,
            ),
            child: Row(
              children: [
                Icon(Icons.brightness_3, color: moonSignificant ? Colors.amber : Colors.white54, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Moon', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                      Text('$moonIllumination%', style: TextStyle(color: moonSignificant ? Colors.amber : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                      Text(moonPhase, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                      if (moonSignificant)
                        Text('May wash out faint aurora', style: TextStyle(color: Colors.amber.withOpacity(0.8), fontSize: 9)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloudCoverSection(AuroraRecommendation rec) {
    final cloudTruth = rec.cloudTruth ?? {};
    final observations = cloudTruth['observations'] as Map<String, dynamic>? ?? {};
    final clearest = (cloudTruth['clearest_directions'] as List?)?.cast<String>() ?? [];
    final cloudiest = (cloudTruth['cloudiest_directions'] as List?)?.cast<String>() ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('CLOUD COVER', Icons.cloud, Colors.lightBlue),
        const SizedBox(height: 10),
        Row(
          children: [
            // Clear directions
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_off, color: Colors.greenAccent, size: 14),
                        const SizedBox(width: 6),
                        Text('Clear', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(clearest.isNotEmpty ? clearest.join(', ') : 'Limited', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Cloudy directions
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud, color: Colors.grey, size: 14),
                        const SizedBox(width: 6),
                        Text('Overcast', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(cloudiest.isNotEmpty ? cloudiest.join(', ') : 'None', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotographySection(AuroraRecommendation rec) {
    final tip = AuroraAdvisorService.getPhotographyDirection(rec.kpIndex, rec.bzHValue);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('WHERE TO LOOK', Icons.explore, Colors.tealAccent),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.tealAccent.withOpacity(0.15),
                Colors.cyanAccent.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              // Direction indicator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.north, color: Colors.tealAccent, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      tip.direction,
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tip.intensity,
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tip.message,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Camera settings
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.white54, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      tip.cameraSettings,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHuntingTipsSection(AuroraRecommendation rec) {
    final activity = AuroraAdvisorService.calculateAuroraActivity(rec.kpIndex, rec.bzHValue);
    final tips = AuroraAdvisorService.getAuroraHuntingTips(
      cloudCover: (1 - rec.clearSkyProbability) * 100,
      auroraActivity: activity,
    );
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('TIPS FOR TONIGHT', Icons.lightbulb_outline, Colors.amber),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: tips.take(4).map((tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                tip,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFactorsSummary(AuroraRecommendation rec) {
    final factors = rec.factors!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('CONDITIONS', Icons.checklist, Colors.tealAccent),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              if (factors['clouds'] != null) _buildFactorRow('☁️', factors['clouds'].toString()),
              if (factors['space_weather'] != null) _buildFactorRow('🌞', factors['space_weather'].toString()),
              if (factors['darkness'] != null) _buildFactorRow('🌙', factors['darkness'].toString()),
              if (factors['moon'] != null) _buildFactorRow('🌕', factors['moon'].toString()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFactorRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.amber, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildNavigationButton(AuroraRecommendation rec) {
    return InkWell(
      onTap: () async {
        final url = rec.navigationUrl;
        if (url != null) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade600, Colors.blue.shade800]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.navigation, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('Navigate to ${rec.destination?.name ?? rec.direction}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildExpandButton() {
    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isExpanded ? 'Show Less' : 'Show Details', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white.withOpacity(0.7), size: 20),
          ],
        ),
      ),
    );
  }
}
