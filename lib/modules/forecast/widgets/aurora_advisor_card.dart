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
          _buildSection('Space Weather', Icons.wb_sunny, rec.spaceWeatherAnalysis),
          const SizedBox(height: 16),
          if (rec.cloudMovement != null) ...[
            _buildSection('Cloud Movement', Icons.cloud, rec.cloudMovement!.analysis),
            const SizedBox(height: 16),
          ],
          _buildSection('AI Reasoning', Icons.psychology, rec.reasoning),
          if (rec.appliedLearnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Applied Learnings:', style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rec.appliedLearnings.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: Colors.tealAccent)),
                  Expanded(child: Text(l, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12))),
                ],
              ),
            )),
          ],
          if (rec.alternatives.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Alternatives:', style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rec.alternatives.map((alt) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(alt.destination, style: const TextStyle(color: Colors.white))),
                  Text('${(alt.probability * 100).toInt()}%', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('${alt.distanceKm.toInt()} km', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                ],
              ),
            )),
          ],
        ],
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
