// Photo Request Stats Widget for Admin Reports
// Shows usage analytics for the customer-facing photo delivery widget

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/colors.dart';

class PhotoRequestStatsWidget extends StatefulWidget {
  final int selectedYear;
  final int selectedMonth;

  const PhotoRequestStatsWidget({
    super.key,
    required this.selectedYear,
    required this.selectedMonth,
  });

  @override
  State<PhotoRequestStatsWidget> createState() => _PhotoRequestStatsWidgetState();
}

class _PhotoRequestStatsWidgetState extends State<PhotoRequestStatsWidget> {
  bool _isLoading = true;
  int _totalRequests = 0;
  int _successfulRequests = 0;
  Map<String, int> _guideCounts = {};
  List<Map<String, dynamic>> _recentRequests = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant PhotoRequestStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear ||
        oldWidget.selectedMonth != widget.selectedMonth) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;

      // Build month date range for filtering
      final monthStart = DateTime.utc(widget.selectedYear, widget.selectedMonth, 1);
      final monthEnd = DateTime.utc(widget.selectedYear, widget.selectedMonth + 1, 1);
      final startStr = monthStart.toIso8601String();
      final endStr = monthEnd.toIso8601String();

      print('📸 Loading photo stats for $startStr to $endStr');

      // Query photo_requests for this month
      // No orderBy to avoid needing a composite index — we sort client-side
      final snapshot = await firestore
          .collection('photo_requests')
          .where('timestamp', isGreaterThanOrEqualTo: startStr)
          .where('timestamp', isLessThan: endStr)
          .get();

      print('📸 Got ${snapshot.docs.length} photo request documents');

      int total = 0;
      int successful = 0;
      final guideCounts = <String, int>{};
      final allDocs = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        total++;
        if (data['success'] == true) successful++;

        final guide = data['guide']?.toString();
        if (guide != null && guide.isNotEmpty) {
          guideCounts[guide] = (guideCounts[guide] ?? 0) + 1;
        }

        allDocs.add(data);
      }

      // Sort by timestamp descending (newest first) client-side
      allDocs.sort((a, b) {
        final ta = a['timestamp']?.toString() ?? '';
        final tb = b['timestamp']?.toString() ?? '';
        return tb.compareTo(ta);
      });

      if (mounted) {
        setState(() {
          _totalRequests = total;
          _successfulRequests = successful;
          _guideCounts = guideCounts;
          _recentRequests = allDocs.take(10).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Failed to load photo request stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '📸 Photo Widget Usage',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_totalRequests == 0)
          _buildNoDataWidget()
        else ...[
          // Summary row
          Row(
            children: [
              Expanded(child: _buildStatCard(
                '📊 Total Requests',
                '$_totalRequests',
                'This month',
                AppColors.primary,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(
                '✅ Success Rate',
                _totalRequests > 0
                    ? '${(_successfulRequests / _totalRequests * 100).toStringAsFixed(0)}%'
                    : '0%',
                '$_successfulRequests found photos',
                Colors.green,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(
                '❌ Failed',
                '${_totalRequests - _successfulRequests}',
                'No photos found',
                Colors.red.shade400,
              )),
            ],
          ),

          // Top guides section
          if (_guideCounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTopGuidesSection(),
          ],

          // Recent requests
          if (_recentRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildRecentRequestsSection(),
          ],
        ],
      ],
    );
  }

  Widget _buildNoDataWidget() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF252540),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        children: [
          Icon(Icons.photo_camera_outlined, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            'No photo requests this month',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade300,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Stats will appear when customers use the photo widget on your website',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildTopGuidesSection() {
    // Sort guides by count descending
    final sorted = _guideCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252540),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '👤 Most Requested Guides',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 12),
          ...top5.map((entry) {
            final percentage = _totalRequests > 0
                ? (entry.value / _totalRequests * 100)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _totalRequests > 0 ? entry.value / _totalRequests : 0,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${entry.value} (${percentage.toStringAsFixed(0)}%)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecentRequestsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252540),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🕐 Recent Requests',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 12),
          ..._recentRequests.map((req) {
            final success = req['success'] == true;
            final guide = req['guide']?.toString() ?? 'Unknown';
            final date = req['date']?.toString() ?? '?';
            final error = req['error']?.toString();
            final timestamp = req['timestamp']?.toString() ?? '';

            // Parse timestamp for display
            String timeDisplay = '';
            try {
              final dt = DateTime.parse(timestamp);
              timeDisplay = '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (_) {
              timeDisplay = timestamp;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: success
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: success
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    success ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: success ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$guide • Tour: $date',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                        if (!success && error != null)
                          Text(
                            error,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade300,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    timeDisplay,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
