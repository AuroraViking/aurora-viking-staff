// Admin reports and analytics screen for viewing detailed reports and performance analytics

import 'package:flutter/material.dart';
import '../../core/models/admin_models.dart';
import '../../core/theme/colors.dart';
import 'admin_service.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  AdminStats? _stats;
  bool _isLoading = true;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  Map<String, dynamic>? _monthlyReport;
  bool _isLoadingReport = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadMonthlyReport();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final stats = await AdminService.getDashboardStats();
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stats: $e')),
      );
    }
  }

  Future<void> _loadMonthlyReport() async {
    setState(() {
      _isLoadingReport = true;
    });

    try {
      final report = await AdminService.getMonthlyReport(_selectedYear, _selectedMonth);
      setState(() {
        _monthlyReport = report;
        _isLoadingReport = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingReport = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading monthly report: $e')),
      );
    }
  }

  void _onYearChanged(int year) {
    setState(() {
      _selectedYear = year;
    });
    _loadMonthlyReport();
  }

  void _onMonthChanged(int month) {
    setState(() {
      _selectedMonth = month;
    });
    _loadMonthlyReport();
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadStats,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview Stats
                  Text(
                    'Overview',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_stats != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Total Guides',
                            _stats!.totalGuides.toString(),
                            Icons.people,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Active Guides',
                            _stats!.activeGuides.toString(),
                            Icons.person,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Pending Shifts',
                            _stats!.pendingShifts.toString(),
                            Icons.schedule,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Today\'s Tours',
                            _stats!.todayTours.toString(),
                            Icons.directions_bus,
                            Colors.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Average Rating',
                            '${_stats!.averageRating}/5.0',
                            Icons.star,
                            Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Active Alerts',
                            _stats!.alerts.toString(),
                            Icons.warning,
                            Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  
                  // Monthly Report
                  Text(
                    'Monthly Report',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Month/Year Selector
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedMonth,
                          decoration: const InputDecoration(
                            labelText: 'Month',
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(12, (index) => index + 1)
                              .map((month) => DropdownMenuItem(
                                    value: month,
                                    child: Text(_getMonthName(month)),
                                  ))
                              .toList(),
                          onChanged: (value) => _onMonthChanged(value!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(5, (index) => DateTime.now().year - 2 + index)
                              .map((year) => DropdownMenuItem(
                                    value: year,
                                    child: Text(year.toString()),
                                  ))
                              .toList(),
                          onChanged: (value) => _onYearChanged(value!),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  if (_isLoadingReport)
                    const Center(child: CircularProgressIndicator())
                  else if (_monthlyReport != null) ...[
                    // Monthly Stats Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildReportCard(
                            'Total Shifts',
                            _monthlyReport!['totalShifts'].toString(),
                            Icons.work,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReportCard(
                            'Day Tours',
                            _monthlyReport!['dayTours'].toString(),
                            Icons.wb_sunny,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildReportCard(
                            'Northern Lights',
                            _monthlyReport!['northernLights'].toString(),
                            Icons.nightlight,
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReportCard(
                            'Revenue',
                            '\$${_monthlyReport!['revenue'].toString()}',
                            Icons.attach_money,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildReportCard(
                            'Profit',
                            '\$${_monthlyReport!['profit'].toString()}',
                            Icons.trending_up,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReportCard(
                            'Avg Rating',
                            '${_monthlyReport!['averageRating']}/5.0',
                            Icons.star,
                            Colors.amber,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Top Guides
                    if (_monthlyReport!['topGuides'] != null) ...[
                      Text(
                        'Top Performing Guides',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...(_monthlyReport!['topGuides'] as List<dynamic>).map((guide) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(
                              guide['name'].toString().split(' ').map((e) => e[0]).join(''),
                              style: TextStyle(color: AppColors.primary),
                            ),
                          ),
                          title: Text(guide['name']),
                          subtitle: Text('${guide['shifts']} shifts completed'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 16, color: Colors.amber),
                              Text('${guide['rating']}'),
                            ],
                          ),
                        ),
                      )),
                    ],
                  ],
                  
                  const SizedBox(height: 32),
                  
                  // Shift Type Breakdown
                  if (_stats != null) ...[
                    Text(
                      'Shift Type Breakdown',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: _stats!.shiftsByType.entries.map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Icon(
                                  entry.key == 'day_tour' ? Icons.wb_sunny : Icons.nightlight,
                                  color: entry.key == 'day_tour' ? Colors.orange : Colors.purple,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    entry.key.replaceAll('_', ' ').toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Monthly Trends
                    Text(
                      'Monthly Trends',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: _stats!.monthlyStats.map((monthly) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  monthly.month,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildMiniStat(
                                        'Total',
                                        monthly.totalShifts.toString(),
                                        Colors.blue,
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildMiniStat(
                                        'Day Tours',
                                        monthly.dayTours.toString(),
                                        Colors.orange,
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildMiniStat(
                                        'Northern Lights',
                                        monthly.northernLights.toString(),
                                        Colors.purple,
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildMiniStat(
                                        'Rating',
                                        '${monthly.averageRating}',
                                        Colors.amber,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  
                  // Export Options
                  Text(
                    'Export Data',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final filename = await AdminService.exportData('shifts');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Exported to $filename')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Export failed: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Export Shifts'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final filename = await AdminService.exportData('guides');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Exported to $filename')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Export failed: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Export Guides'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
} 