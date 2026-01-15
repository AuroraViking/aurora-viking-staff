import 'package:flutter/material.dart';
import '../services/aurora_advisor_service.dart';

class AuroraAdvisorCard extends StatefulWidget {
  final AuroraRecommendation? recommendation;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback? onNavigateToDestination;
  final String? currentLocationName;

  const AuroraAdvisorCard({
    super.key,
    this.recommendation,
    this.isLoading = false,
    required this.onRefresh,
    this.onNavigateToDestination,
    this.currentLocationName,
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
    final prob = widget.recommendation!.combinedProbability;
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
              Icon(Icons.auto_awesome, color: Colors.tealAccent, size: 24),
              SizedBox(width: 12),
              Text('HEIMDALLR ANALYZING...', style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent)),
          const SizedBox(height: 16),
          Text('Analyzing space weather and cloud patterns...', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
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
          Text('Get AI-powered recommendation for optimal aurora viewing', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.auto_awesome),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _getGradientColor().withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.auto_awesome, color: _getGradientColor(), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('HEIMDALLR RECOMMENDS', style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 2),
                if (rec.learningsUsed > 0)
                  Text('Using ${rec.learningsUsed} learned patterns', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text('${(rec.confidence * 100).toInt()}%', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: widget.onRefresh, icon: const Icon(Icons.refresh, color: Colors.white70), tooltip: 'Refresh'),
        ],
      ),
    );
  }

  Widget _buildMainRecommendation(AuroraRecommendation rec) {
    return InkWell(
      onTap: widget.onNavigateToDestination,
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Current location
            if (widget.currentLocationName != null && widget.currentLocationName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.my_location, size: 14, color: Colors.white.withOpacity(0.6)),
                    const SizedBox(width: 6),
                    Text(
                      'From: ${widget.currentLocationName}',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
            Text(rec.recommendation, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.3), textAlign: TextAlign.center),
            if (rec.destination != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildInfoChip(Icons.navigation, '${rec.distanceKm.toInt()} km ${rec.direction}'),
                  const SizedBox(width: 12),
                  _buildInfoChip(Icons.timer, '${rec.travelTimeMinutes} min'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.tealAccent),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildProbabilityMeters(AuroraRecommendation rec) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: _buildMeter('Aurora', rec.auroraProbability, Icons.auto_awesome, Colors.purpleAccent)),
          const SizedBox(width: 12),
          Expanded(child: _buildMeter('Clear Sky', rec.clearSkyProbability, Icons.cloud_off, Colors.lightBlue)),
          const SizedBox(width: 12),
          Expanded(child: _buildMeter('Viewing', rec.combinedProbability, Icons.visibility, _getGradientColor())),
        ],
      ),
    );
  }

  Widget _buildMeter(String label, double value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text('${(value * 100).toInt()}%', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: value, backgroundColor: Colors.white.withOpacity(0.1), valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 6),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(AuroraRecommendation rec) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Space Weather Analysis Section
          _buildSpaceWeatherSection(rec),
          const SizedBox(height: 20),
          
          // Cloud Cover Analysis Section
          _buildCloudCoverSection(rec),
          const SizedBox(height: 20),
          
          // Viewing Recommendation Section
          _buildViewingSection(rec),
          
          // Navigation button if available
          if (rec.navigationUrl != null && rec.navigationUrl!.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildNavigationButton(rec),
          ],
        ],
      ),
    );
  }

  Widget _buildSpaceWeatherSection(AuroraRecommendation rec) {
    final analysis = rec.analysis;
    final bzPosition = analysis?['bz_position'] ?? 'unknown';
    final bzTrend = analysis?['bz_trend'] ?? 'stable';
    final favorable = analysis?['aurora_favorable'] == true;
    
    String statusText;
    Color statusColor;
    IconData statusIcon;
    
    if (bzPosition == 'below_zero' || bzPosition.contains('below')) {
      statusText = 'FAVORABLE';
      statusColor = Colors.greenAccent;
      statusIcon = Icons.check_circle;
    } else if (bzPosition == 'above_zero' || bzPosition.contains('above')) {
      statusText = 'QUIET';
      statusColor = Colors.orangeAccent;
      statusIcon = Icons.remove_circle;
    } else {
      statusText = 'NEUTRAL';
      statusColor = Colors.amber;
      statusIcon = Icons.circle_outlined;
    }
    
    String trendText = bzTrend == 'improving' 
        ? 'Trend: Improving ↓' 
        : bzTrend == 'worsening' 
            ? 'Trend: Worsening ↑'
            : 'Trend: Stable →';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.wb_sunny, color: Colors.purpleAccent, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('SPACE WEATHER', style: TextStyle(color: Colors.purpleAccent, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bz Status: $statusText', style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(trendText, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Kp ${rec.kpIndex?.toStringAsFixed(1) ?? "N/A"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        if (rec.viewingTip != null && rec.viewingTip!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.tips_and_updates, size: 14, color: Colors.amber.withOpacity(0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rec.viewingTip!,
                  style: TextStyle(color: Colors.amber.withOpacity(0.9), fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCloudCoverSection(AuroraRecommendation rec) {
    final analysis = rec.analysis;
    final clearDirs = (analysis?['clear_directions'] as List?)?.cast<String>() ?? [];
    final cloudyDirs = (analysis?['cloudy_directions'] as List?)?.cast<String>() ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.lightBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud, color: Colors.lightBlue, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('CLOUD COVER', style: TextStyle(color: Colors.lightBlue, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Clear skies
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
                        Icon(Icons.cloud_off, color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 6),
                        const Text('Clear', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      clearDirs.isNotEmpty ? clearDirs.join(', ') : 'Limited visibility',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Cloudy
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud, color: Colors.grey, size: 16),
                        const SizedBox(width: 6),
                        const Text('Overcast', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cloudyDirs.isNotEmpty ? cloudyDirs.join(', ') : 'None detected',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewingSection(AuroraRecommendation rec) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.psychology, color: Colors.tealAccent, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('RECOMMENDATION', style: TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.2)),
          ),
          child: Text(
            rec.description ?? rec.reasoning,
            style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 14, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButton(AuroraRecommendation rec) {
    return InkWell(
      onTap: () async {
        final url = rec.navigationUrl;
        if (url != null) {
          // Launch URL - requires url_launcher package
          // For now, just show a snackbar with the coordinates
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Navigate to: ${rec.destination?.name ?? rec.direction}'),
                action: SnackBarAction(
                  label: 'OPEN MAP',
                  onPressed: () {
                    // Could use url_launcher here
                  },
                ),
              ),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.blue.shade900],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.navigation, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              'Navigate to ${rec.destination?.name ?? rec.direction}',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSection(String title, IconData icon, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.tealAccent, size: 16),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Text(content, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, height: 1.5)),
      ],
    );
  }

  Widget _buildExpandButton() {
    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isExpanded ? 'Show Less' : 'Show Reasoning', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white.withOpacity(0.7), size: 20),
          ],
        ),
      ),
    );
  }
}
