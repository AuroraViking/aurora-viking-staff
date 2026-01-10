// Admin reports and analytics screen for viewing detailed reports and performance analytics

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/colors.dart';
import '../../core/services/firebase_service.dart';
import 'admin_service.dart';
import 'gps_trail_viewer.dart';
import 'widgets/financial_analytics_widget.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  // Month/Year for Financial Analytics filtering (defaults to current month)
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  
  // Tour Reports data
  List<Map<String, dynamic>> _tourReports = [];
  bool _isLoadingTourReports = false;
  bool _isGeneratingReport = false;
  
  // Date search for tour reports
  DateTime? _searchDate;
  Map<String, dynamic>? _searchedReport;
  bool _isSearching = false;
  
  // Date for generating reports
  DateTime? _generateReportDate;

  @override
  void initState() {
    super.initState();
    _loadTourReports();
  }

  Future<void> _loadTourReports() async {
    setState(() {
      _isLoadingTourReports = true;
    });

    try {
      final reports = await AdminService.getTourReports(days: 30);
      setState(() {
        _tourReports = reports;
        _isLoadingTourReports = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingTourReports = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tour reports: $e')),
        );
      }
    }
  }

  bool _isInSelectedMonth(String? dateStr) {
    if (dateStr == null) return false;
    try {
      final parts = dateStr.split('-');
      return parts.length >= 2 &&
             int.parse(parts[0]) == _selectedYear &&
             int.parse(parts[1]) == _selectedMonth;
    } catch (e) {
      return false;
    }
  }


  Future<void> _openSheetUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Sheet')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening sheet: $e')),
        );
      }
    }
  }

  Future<void> _openReport(String url) async {
    await _openSheetUrl(url);
  }

  void _openGpsTrail(Map<String, dynamic> report, {Map<String, dynamic>? guide}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GpsTrailViewer(
          date: report['date'] as String,
          busId: guide?['busId'] as String?,
          busName: guide?['busName'] as String?,
          guideName: guide?['guideName'] as String?,
        ),
      ),
    );
  }

  Future<void> _searchReportByDate(DateTime date) async {
    setState(() {
      _isSearching = true;
      _searchedReport = null;
    });

    try {
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final report = await FirebaseService.getTourReport(dateKey);
      
      setState(() {
        _searchDate = date;
        _searchedReport = report;
        _isSearching = false;
      });

      if (report == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No report found for ${dateKey}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _searchDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      await _searchReportByDate(picked);
    }
  }

  Widget _buildQuickDateChip(String label, DateTime date) {
    final isSelected = _searchDate != null &&
        _searchDate!.year == date.year &&
        _searchDate!.month == date.month &&
        _searchDate!.day == date.day;

    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected ? AppColors.primary : const Color(0xFF252540),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[400],
        fontSize: 12,
      ),
      onPressed: () => _searchReportByDate(date),
    );
  }

  Widget _buildQuickDateButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildQuickDateChip('Yesterday', DateTime.now().subtract(const Duration(days: 1))),
        _buildQuickDateChip('2 days ago', DateTime.now().subtract(const Duration(days: 2))),
        _buildQuickDateChip('1 week ago', DateTime.now().subtract(const Duration(days: 7))),
        _buildQuickDateChip('2 weeks ago', DateTime.now().subtract(const Duration(days: 14))),
        _buildQuickDateChip('1 month ago', DateTime.now().subtract(const Duration(days: 30))),
      ],
    );
  }

  Widget _buildReportSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Search Reports',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Search bar
        InkWell(
          onTap: _showDatePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF252540),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[700]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _searchDate != null
                        ? '${_searchDate!.day}/${_searchDate!.month}/${_searchDate!.year}'
                        : 'Tap to select a date...',
                    style: TextStyle(
                      color: _searchDate != null ? Colors.white : Colors.grey[500],
                      fontSize: 16,
                    ),
                  ),
                ),
                if (_isSearching)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.search, color: Colors.grey),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Quick date buttons
        _buildQuickDateButtons(),
        
        const SizedBox(height: 16),
        
        // Search result
        if (_searchedReport != null)
          Card(
            color: const Color(0xFF252540),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description, color: AppColors.primary),
              ),
              title: Text(
                'Report: ${_searchedReport!['date']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_searchedReport!['totalGuides'] ?? 0} guides • ${_searchedReport!['totalPassengers'] ?? 0} passengers',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  if (_searchedReport!['auroraSummary'] != null)
                    Text(
                      '🌌 ${(_searchedReport!['auroraSummary'] as Map)['display'] ?? 'Unknown'}',
                      style: TextStyle(
                        color: _getAuroraColor((_searchedReport!['auroraSummary'] as Map)['rating']),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchedReport!['sheetUrl'] != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, color: Colors.green),
                      tooltip: 'Open Google Sheet',
                      onPressed: () => _openReport(_searchedReport!['sheetUrl']),
                    ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              onTap: () => _showReportDetail(_searchedReport!),
            ),
          )
        else if (_searchDate != null && !_isSearching)
          Card(
            color: const Color(0xFF252540),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 12),
                  Text(
                    'No report found for this date',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reports are generated when guides submit end-of-shift reports',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _openTourReport(Map<String, dynamic> report) async {
    final sheetUrl = report['sheetUrl'] as String?;
    
    if (sheetUrl != null && sheetUrl.isNotEmpty) {
      // Open Google Sheet
      await _openSheetUrl(sheetUrl);
    } else {
      // No sheet URL - show in-app detail view
      _showReportDetail(report);
    }
  }

  void _showReportDetail(Map<String, dynamic> report) {
    final auroraSummary = report['auroraSummary'] as Map<String, dynamic>?;
    final guidesWithReports = report['guidesWithReports'] ?? 0;
    final totalGuides = report['totalGuides'] ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tour Report - ${report['date']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Report status
                          Text(
                            '$guidesWithReports/$totalGuides guides reported',
                            style: TextStyle(
                              color: guidesWithReports == totalGuides 
                                  ? Colors.green 
                                  : Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.route, color: Colors.green),
                      tooltip: 'View GPS Trail',
                      onPressed: () {
                        Navigator.pop(context);
                        _openGpsTrail(report);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Aurora summary banner
              if (auroraSummary != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getAuroraColor(auroraSummary['rating']).withOpacity(0.3),
                        _getAuroraColor(auroraSummary['rating']).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getAuroraColor(auroraSummary['rating']).withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('🌌', style: TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aurora Tonight',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              auroraSummary['display'] ?? 'Unknown',
                              style: TextStyle(
                                color: _getAuroraColor(auroraSummary['rating']),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Text('🌌', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 12),
                      Text(
                        'No aurora reports yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
            
              // Summary stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildStatChip(
                      '${report['totalGuides'] ?? 0}',
                      'Guides',
                      Icons.person,
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      '${report['totalPassengers'] ?? 0}',
                      'Passengers',
                      Icons.people,
                      Colors.green,
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      '${report['totalBookings'] ?? (report['guides'] as List?)?.fold<int>(0, (sum, g) => sum + ((g['bookingCount'] as num?)?.toInt() ?? (g['bookings'] as List?)?.length ?? 0)) ?? 0}',
                      'Bookings',
                      Icons.assignment,
                      Colors.orange,
                    ),
                  ],
                ),
              ),
              // No-show summary
              _buildNoShowSummary(report),
              const SizedBox(height: 16),
              const Divider(color: Colors.grey),
              // Guide list with bookings
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: ((report['guides'] as List?)?.length ?? 0) + (report['unassigned'] != null ? 1 : 0),
                itemBuilder: (context, index) {
                  final guides = report['guides'] as List? ?? [];
                  if (index < guides.length) {
                    return _buildGuideSection(report, guides[index]);
                  } else if (report['unassigned'] != null) {
                    return _buildGuideSection(report, report['unassigned']);
                  }
                  return const SizedBox.shrink();
                },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getAuroraColor(String? rating) {
    switch (rating) {
      case 'not_seen':
        return Colors.grey;
      case 'camera_only':
        return Colors.blueGrey;
      case 'a_little':
        return Colors.amber;
      case 'good':
        return Colors.lightGreen;
      case 'great':
        return Colors.green;
      case 'exceptional':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildGuideSection(Map<String, dynamic> report, Map<String, dynamic> guide) {
    final bookings = guide['bookings'] as List? ?? [];
    final busName = guide['busName'] as String?;
    final auroraRating = guide['auroraRating'] as String?;
    final auroraDisplay = guide['auroraRatingDisplay'] as String?;
    final shouldRequestReviews = guide['shouldRequestReviews'];
    final shiftNotes = guide['shiftNotes'] as String?;
    final hasSubmittedReport = guide['hasSubmittedReport'] == true;

    return Card(
      color: const Color(0xFF252540),
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Text(
            (guide['guideName'] ?? 'U')[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                guide['guideName'] ?? 'Unknown Guide',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // GPS Trail button
            if (guide['busId'] != null)
              IconButton(
                icon: const Icon(Icons.route, size: 20),
                color: Colors.green,
                tooltip: 'View GPS Trail',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Navigator.pop(context);
                  _openGpsTrail(report, guide: guide);
                },
              ),
            const SizedBox(width: 8),
            // Aurora rating badge
            if (auroraDisplay != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getAuroraColor(auroraRating).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  auroraDisplay,
                  style: TextStyle(
                    color: _getAuroraColor(auroraRating),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (!hasSubmittedReport)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '⏳ Pending',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // Stats row
            Row(
              children: [
                Text(
                  '${bookings.length} bookings • ${guide['totalPassengers'] ?? 0} pax',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                // Bus info
                if (busName != null && busName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.directions_bus, size: 14, color: Colors.blue[300]),
                  const SizedBox(width: 4),
                  Text(
                    busName,
                    style: TextStyle(color: Colors.blue[300], fontSize: 12),
                  ),
                ],
              ],
            ),
            // Review request indicator
            if (shouldRequestReviews == false)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.star_border, size: 14, color: Colors.orange[300]),
                    const SizedBox(width: 4),
                    Text(
                      'Reviews NOT requested',
                      style: TextStyle(color: Colors.orange[300], fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.grey,
        children: [
          // Shift notes (if present)
          if (shiftNotes != null && shiftNotes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Guide Notes',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shiftNotes,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Booking list
          ...bookings.map<Widget>((booking) => _buildBookingTile(booking)).toList(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Map<String, dynamic> booking) {
    final isNoShow = booking['isNoShow'] == true;
    final isArrived = booking['isArrived'] == true;
    final isCompleted = booking['isCompleted'] == true;
    
    if (isNoShow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off, size: 14, color: Colors.red),
            SizedBox(width: 4),
            Text(
              'NO SHOW',
              style: TextStyle(
                color: Colors.red,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '✅',
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    
    if (isArrived) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '📍',
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '⏳',
        style: TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildBookingTile(Map<String, dynamic> booking) {
    final isNoShow = booking['isNoShow'] == true;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isNoShow ? Colors.red.withOpacity(0.05) : null,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Status badge
          _buildStatusBadge(booking),
          const SizedBox(width: 12),
          // Booking details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking['customerName'] ?? 'Unknown',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    decoration: isNoShow ? TextDecoration.lineThrough : null,
                    color: isNoShow ? Colors.grey : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  booking['pickupLocation'] ?? 'Unknown location',
                  style: TextStyle(
                    color: isNoShow ? Colors.grey[500] : Colors.grey[600],
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Passenger count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isNoShow 
                  ? Colors.grey.withOpacity(0.1) 
                  : AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${booking['participants'] ?? 0} pax',
              style: TextStyle(
                color: isNoShow ? Colors.grey : AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: isNoShow ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGenerateReportDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _generateReportDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _generateReportDate = picked;
      });
    }
  }

  Future<void> _generateReportForDate(DateTime date) async {
    // Check if user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Please log in to generate reports'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isGeneratingReport = true;
    });

    try {
      // Format date in YYYY-MM-DD format
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      // Call the Cloud Function
      // Use the explicit region (us-central1) which matches our function
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('generateTourReportManual');
      
      // Ensure we have a fresh auth token (this refreshes if needed)
      await user.getIdToken(true);
      print('🔑 Calling function as authenticated user: ${user.uid} (${user.email})');
      print('📅 Generating report for date: $dateStr');
      
      final result = await callable.call({'date': dateStr});

      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Report generated successfully! ${data['sheetUrl'] != null ? 'Google Sheet created.' : ''}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );

          // Refresh the tour reports list
          await _loadTourReports();

          // If there's a sheet URL, offer to open it
          if (data['sheetUrl'] != null) {
            final shouldOpen = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Report Generated'),
                content: Text(
                  'Tour report for $dateStr has been created.\n\n'
                  'Total Guides: ${data['totalGuides'] ?? 0}\n'
                  'Total Passengers: ${data['totalPassengers'] ?? 0}\n\n'
                  'Would you like to open the Google Sheet?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Later'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Open Sheet'),
                  ),
                ],
              ),
            );

            if (shouldOpen == true && data['sheetUrl'] != null) {
              await _openSheetUrl(data['sheetUrl']);
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ ${data['message'] ?? 'Failed to generate report'}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error generating report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingReport = false;
        });
      }
    }
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
            onPressed: () {
              _loadTourReports();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== FINANCIAL ANALYTICS =====
                  FinancialAnalyticsWidget(
                    totalPassengers: _tourReports
                        .where((r) => _isInSelectedMonth(r['date'] as String?))
                        .fold(0, (sum, r) => sum + ((r['totalPassengers'] as int?) ?? 0)),
                    totalTours: _tourReports
                        .where((r) => _isInSelectedMonth(r['date'] as String?))
                        .length,
                    totalGuidesWorked: _tourReports
                        .where((r) => _isInSelectedMonth(r['date'] as String?))
                        .fold(0, (sum, r) => sum + ((r['totalGuides'] as int?) ?? 0)),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // ===== SEARCH REPORTS =====
                  _buildReportSearchSection(),
                  
                  const SizedBox(height: 32),
                  
                  // ===== GENERATE TOUR REPORT =====
                  Text(
                    'Generate Tour Report',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Date selector and generate button row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _isGeneratingReport ? null : _showGenerateReportDatePicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252540),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[700]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, color: AppColors.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _generateReportDate != null
                                        ? '${_generateReportDate!.day}/${_generateReportDate!.month}/${_generateReportDate!.year}'
                                        : 'Select date to generate report...',
                                    style: TextStyle(
                                      color: _generateReportDate != null ? Colors.white : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: (_isGeneratingReport || _generateReportDate == null) 
                            ? null 
                            : () => _generateReportForDate(_generateReportDate!),
                        icon: _isGeneratingReport
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_isGeneratingReport ? 'Generating...' : 'Generate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // ===== RECENT TOUR REPORTS =====
                  Text(
                    'Recent Tour Reports',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_isLoadingTourReports)
                    const Center(child: CircularProgressIndicator())
                  else if (_tourReports.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('No tour reports found'),
                      ),
                    )
                  else
                    ..._tourReports.take(30).map((report) {
                      final date = report['date'] as String? ?? 'Unknown';
                      final sheetUrl = report['sheetUrl'] as String?;
                      final totalGuides = report['totalGuides'] ?? 0;
                      final totalPassengers = report['totalPassengers'] ?? 0;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.description, color: AppColors.primary),
                          ),
                          title: Text(
                            'Tour Report - $date',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('$totalGuides guides • $totalPassengers passengers'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sheetUrl != null)
                                const Icon(Icons.table_chart, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _openTourReport(report),
                        ),
                      );
                    }),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildNoShowSummary(Map<String, dynamic> report) {
    // Count no-shows from all guides
    int totalNoShows = 0;
    int noShowPassengers = 0;
    
    final guides = report['guides'] as List? ?? [];
    for (final guide in guides) {
      final bookings = guide['bookings'] as List? ?? [];
      for (final booking in bookings) {
        if (booking['isNoShow'] == true) {
          totalNoShows++;
          noShowPassengers += (booking['participants'] as int?) ?? 0;
        }
      }
    }
    
    // Also check unassigned bookings
    if (report['unassigned'] != null) {
      final unassignedBookings = report['unassigned']['bookings'] as List? ?? [];
      for (final booking in unassignedBookings) {
        if (booking['isNoShow'] == true) {
          totalNoShows++;
          noShowPassengers += (booking['participants'] as int?) ?? 0;
        }
      }
    }
    
    if (totalNoShows == 0) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_off, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Text(
            '$totalNoShows no-show${totalNoShows > 1 ? 's' : ''} ($noShowPassengers pax)',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
} 