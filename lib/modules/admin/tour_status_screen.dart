import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../../core/theme/colors.dart';

class TourStatusScreen extends StatefulWidget {
  const TourStatusScreen({super.key});

  @override
  State<TourStatusScreen> createState() => _TourStatusScreenState();
}

class _TourStatusScreenState extends State<TourStatusScreen> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  
  bool _isLoading = true;
  String? _currentStatus;
  String? _lastUpdatedBy;
  DateTime? _lastUpdatedAt;
  List<Map<String, dynamic>> _history = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    
    try {
      // Use HTTP endpoint which we know works
      final uri = Uri.parse('https://us-central1-aurora-viking-staff.cloudfunctions.net/getTourStatus');
      final response = await _functions.httpsCallable('getTourStatusHistory').call({'limit': 14});
      
      // Also fetch from public endpoint for current status
      final httpResponse = await Uri.parse('https://us-central1-aurora-viking-staff.cloudfunctions.net/getTourStatus')
          .toString();
      
      // Parse history from callable
      final historyData = response.data;
      final history = (historyData['history'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      
      // Get current status from the first item in history or use today's
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      Map<String, dynamic>? todayStatus;
      
      for (final h in history) {
        if (h['date'] == today) {
          todayStatus = h;
          break;
        }
      }
      
      setState(() {
        _currentStatus = todayStatus?['status'] as String?;
        _lastUpdatedBy = todayStatus?['updatedByName'] as String?;
        if (todayStatus?['updatedAt'] != null) {
          final ts = todayStatus!['updatedAt'];
          if (ts is String) {
            _lastUpdatedAt = DateTime.tryParse(ts);
          }
        }
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading tour status: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load status: $e')),
        );
      }
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _isSaving = true);
    
    try {
      final result = await _functions.httpsCallable('setTourStatus').call({
        'status': status,
        'message': status == 'OFF' ? 'Tour canceled' : 'Tour is running',
      });
      
      if (result.data['success'] == true) {
        // Update status immediately from response
        setState(() {
          _currentStatus = result.data['status'] as String?;
          _lastUpdatedBy = result.data['updatedByName'] as String?;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tour status set to $status'),
            backgroundColor: status == 'ON' ? Colors.green : Colors.orange,
          ),
        );
        
        // Reload history in background
        _loadStatus();
      }
    } catch (e) {
      print('Error setting tour status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final displayDate = DateFormat('EEEE, MMMM d').format(today);
    final shortDate = DateFormat('d.MMM').format(today).toUpperCase();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour Status'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Today's Date
                  Text(
                    displayDate,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Current Status Display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _getStatusColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _getStatusColor().withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Northern Lights Tour',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              shortDate,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'is',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _getStatusColor(),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _currentStatus ?? 'NOT SET',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getStatusEmoji(),
                              style: const TextStyle(fontSize: 32),
                            ),
                          ],
                        ),
                        if (_lastUpdatedBy != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Updated by $_lastUpdatedBy',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Toggle Buttons
                  Text(
                    'Set Today\'s Status:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusButton(
                          'ON',
                          '✅',
                          Colors.green,
                          _currentStatus == 'ON',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatusButton(
                          'OFF',
                          '😞',
                          Colors.red,
                          _currentStatus == 'OFF',
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // History Section
                  if (_history.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent History',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._history.take(7).map((h) => _buildHistoryItem(h)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusButton(String status, String emoji, Color color, bool isSelected) {
    return GestureDetector(
      onTap: _isSaving ? null : () => _setStatus(status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
            if (_isSaving && !isSelected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final date = item['displayDate'] ?? item['date'] ?? 'Unknown';
    final status = item['status'] ?? 'UNKNOWN';
    final updatedBy = item['updatedByName'] ?? '';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            date,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'ON' ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (updatedBy.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              updatedBy,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (_currentStatus == 'ON') return Colors.green;
    if (_currentStatus == 'OFF') return Colors.red;
    return Colors.grey;
  }

  String _getStatusEmoji() {
    if (_currentStatus == 'ON') return '✅';
    if (_currentStatus == 'OFF') return '😞';
    return '❓';
  }
}
