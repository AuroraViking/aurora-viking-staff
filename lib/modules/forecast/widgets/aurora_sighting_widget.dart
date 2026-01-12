import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/auth_controller.dart';

class AuroraSightingWidget extends StatefulWidget {
  const AuroraSightingWidget({super.key});

  @override
  State<AuroraSightingWidget> createState() => _AuroraSightingWidgetState();
}

class _AuroraSightingWidgetState extends State<AuroraSightingWidget> {
  bool _isReporting = false;
  String? _lastReportedLevel;
  DateTime? _lastReportTime;

  // Aurora intensity levels with colors and emojis
  static const List<Map<String, dynamic>> _auroraLevels = [
    {
      'level': 'weak',
      'label': 'Weak',
      'emoji': '🌌',
      'color': Color(0xFF4A5568), // Gray
      'description': 'Faint glow visible',
    },
    {
      'level': 'medium',
      'label': 'Medium',
      'emoji': '✨',
      'color': Color(0xFF38A169), // Green
      'description': 'Clear aurora bands',
    },
    {
      'level': 'strong',
      'label': 'Strong',
      'emoji': '🔥',
      'color': Color(0xFFD69E2E), // Yellow/Gold
      'description': 'Bright, dancing lights',
    },
    {
      'level': 'exceptional',
      'label': 'Exceptional',
      'emoji': '🤯',
      'color': Color(0xFFE53E3E), // Red
      'description': 'Once in a lifetime!',
    },
  ];

  Future<void> _reportAuroraSighting(String level, String label) async {
    // Prevent spam - only allow one report every 5 minutes
    if (_lastReportTime != null) {
      final timeSinceLastReport = DateTime.now().difference(_lastReportTime!);
      if (timeSinceLastReport.inMinutes < 5) {
        final remainingMinutes = 5 - timeSinceLastReport.inMinutes;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please wait $remainingMinutes more minute(s) before reporting again'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isReporting = true);

    try {
      final authController = context.read<AuthController>();
      final currentUser = authController.currentUser;
      
      if (currentUser == null) {
        throw Exception('Not logged in');
      }

      // Get guide's current location from bus_locations
      Map<String, dynamic>? locationData;
      String? busId;
      
      // Find the bus this guide is tracking
      final busLocationsSnapshot = await FirebaseFirestore.instance
          .collection('bus_locations')
          .where('userId', isEqualTo: currentUser.id)
          .where('isTracking', isEqualTo: true)
          .limit(1)
          .get();

      if (busLocationsSnapshot.docs.isNotEmpty) {
        final busDoc = busLocationsSnapshot.docs.first;
        locationData = busDoc.data();
        busId = busDoc.id;
      }

      // Create the aurora sighting document
      final sightingData = {
        'guideId': currentUser.id,
        'guideName': currentUser.fullName,
        'guideEmail': currentUser.email,
        'level': level,
        'levelLabel': label,
        'timestamp': FieldValue.serverTimestamp(),
        'date': DateTime.now().toIso8601String().split('T')[0], // YYYY-MM-DD
        // Location data (if tracking)
        'hasLocation': locationData != null,
        'latitude': locationData?['latitude'],
        'longitude': locationData?['longitude'],
        'busId': busId,
        // For the Cloud Function to process
        'processed': false,
      };

      // Save to Firestore - this will trigger the Cloud Function
      await FirebaseFirestore.instance
          .collection('aurora_sightings')
          .add(sightingData);

      setState(() {
        _lastReportedLevel = level;
        _lastReportTime = DateTime.now();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('$label aurora reported! Admins notified 🌌'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Error reporting aurora sighting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReporting = false);
      }
    }
  }

  void _showConfirmationDialog(Map<String, dynamic> levelInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Text(levelInfo['emoji'], style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Text(
              'Report ${levelInfo['label']} Aurora?',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              levelInfo['description'],
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (levelInfo['color'] as Color).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (levelInfo['color'] as Color).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: levelInfo['color'], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will notify all admins with your location',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _reportAuroraSighting(levelInfo['level'], levelInfo['label']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: levelInfo['color'],
              foregroundColor: Colors.white,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withOpacity(0.3),
            Colors.blue.withOpacity(0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.campaign, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Report Aurora Sighting',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isReporting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amber,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to alert admins about aurora activity',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          
          // Aurora level buttons
          Row(
            children: _auroraLevels.map((levelInfo) {
              final isSelected = _lastReportedLevel == levelInfo['level'];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildLevelButton(levelInfo, isSelected),
                ),
              );
            }).toList(),
          ),
          
          // Last report indicator
          if (_lastReportTime != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Last report: ${_lastReportedLevel} at ${_lastReportTime!.hour.toString().padLeft(2, '0')}:${_lastReportTime!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelButton(Map<String, dynamic> levelInfo, bool isSelected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isReporting ? null : () => _showConfirmationDialog(levelInfo),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (levelInfo['color'] as Color).withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? levelInfo['color']
                  : Colors.white.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                levelInfo['emoji'],
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                levelInfo['label'],
                style: TextStyle(
                  color: isSelected ? levelInfo['color'] : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


