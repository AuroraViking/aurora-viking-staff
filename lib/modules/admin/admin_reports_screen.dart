// Admin reports and analytics screen for viewing detailed reports and performance analytics

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  
  // New data for Tour Reports, Shifts, and Pickups
  List<Map<String, dynamic>> _tourReports = [];
  Map<String, dynamic>? _shiftsStats;
  Map<String, dynamic>? _pickupStats;
  bool _isLoadingTourReports = false;
  bool _isLoadingShifts = false;
  bool _isLoadingPickups = false;
  bool _isGeneratingReport = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadMonthlyReport();
    _loadTourReports();
    _loadShiftsStats();
    _loadPickupStats();
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

  Future<void> _loadShiftsStats() async {
    setState(() {
      _isLoadingShifts = true;
    });

    try {
      final stats = await AdminService.getShiftsStatistics();
      setState(() {
        _shiftsStats = stats;
        _isLoadingShifts = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingShifts = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading shifts statistics: $e')),
        );
      }
    }
  }

  Future<void> _loadPickupStats() async {
    setState(() {
      _isLoadingPickups = true;
    });

    try {
      final stats = await AdminService.getPickupStatistics();
      setState(() {
        _pickupStats = stats;
        _isLoadingPickups = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPickups = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading pickup statistics: $e')),
        );
      }
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
                      return _buildGuideSection(guides[index]);
                    } else if (report['unassigned'] != null) {
                      return _buildGuideSection(report['unassigned']);
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

  Widget _buildGuideSection(Map<String, dynamic> guide) {
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

  Widget _buildBookingTile(Map<String, dynamic> booking) {
    final isArrived = booking['isArrived'] == true;
    final isCompleted = booking['isCompleted'] == true;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green.withOpacity(0.2)
                  : isArrived
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted
                  ? Icons.check_circle
                  : isArrived
                      ? Icons.location_on
                      : Icons.schedule,
              color: isCompleted
                  ? Colors.green
                  : isArrived
                      ? Colors.orange
                      : Colors.grey,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // Booking details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking['customerName'] ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  booking['pickupLocation'] ?? 'Unknown location',
                  style: TextStyle(
                    color: Colors.grey[600],
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
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${booking['participants'] ?? 0} pax',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTodayReport() async {
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
      // Get today's date in YYYY-MM-DD format
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Call the Cloud Function
      // Use the explicit region (us-central1) which matches our function
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('generateTourReportManual');
      
      // Ensure we have a fresh auth token (this refreshes if needed)
      await user.getIdToken(true);
      print('🔑 Calling function as authenticated user: ${user.uid} (${user.email})');
      
      final result = await callable.call({'date': todayStr});

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
                  'Tour report for $todayStr has been created.\n\n'
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
              _loadStats();
              _loadMonthlyReport();
              _loadTourReports();
              _loadShiftsStats();
              _loadPickupStats();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh All',
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
                            'Total Guides',
                            _monthlyReport!['totalGuides'].toString(),
                            Icons.people,
                            Colors.blue,
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
                          trailing: Text(
                            '${guide['shifts']} shifts',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
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
                                        'Guides',
                                        monthly.totalGuides.toString(),
                                        Colors.green,
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
                  
                  // Tour Reports Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tour Reports (Last 30 Days)',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isGeneratingReport ? null : _generateTodayReport,
                          icon: _isGeneratingReport
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(_isGeneratingReport ? 'Generating Report...' : 'Test: Generate Today\'s Report'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingTourReports)
                    const Center(child: CircularProgressIndicator())
                  else if (_tourReports.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No tour reports available',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._tourReports.take(10).map((report) {
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
                  
                  // Shifts Analytics Section
                  Text(
                    'Shifts Analytics',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingShifts)
                    const Center(child: CircularProgressIndicator())
                  else if (_shiftsStats != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildReportCard(
                            'Total Shifts',
                            _shiftsStats!['totalShifts'].toString(),
                            Icons.work,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReportCard(
                            'Day Tours',
                            (_shiftsStats!['byType'] as Map?)?['dayTour']?.toString() ?? '0',
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
                            (_shiftsStats!['byType'] as Map?)?['northernLights']?.toString() ?? '0',
                            Icons.nightlight,
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReportCard(
                            'Accepted',
                            (_shiftsStats!['byStatus'] as Map?)?['accepted']?.toString() ?? '0',
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    if ((_shiftsStats!['byGuide'] as Map?) != null && 
                        (_shiftsStats!['byGuide'] as Map).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Top Guides by Shifts',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_shiftsStats!['byGuide'] as Map).entries.take(5).map((entry) {
                        final guideData = entry.value as Map<String, dynamic>;
                        final guideName = guideData['guideName'] ?? entry.key;
                        final count = guideData['count'] ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.person, size: 20),
                            title: Text(guideName),
                            trailing: Text(
                              '$count shifts',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                  
                  const SizedBox(height: 32),
                  
                  // Pickup Statistics Section
                  Text(
                    'Pickup Lists Statistics',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingPickups)
                    const Center(child: CircularProgressIndicator())
                  else if (_pickupStats != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildReportCard(
                            'Total Assignments',
                            _pickupStats!['totalAssignments'].toString(),
                            Icons.assignment,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReportCard(
                            'Total Passengers',
                            _pickupStats!['totalPassengers'].toString(),
                            Icons.people,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    if ((_pickupStats!['byGuide'] as Map?) != null && 
                        (_pickupStats!['byGuide'] as Map).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Guides by Pickup Assignments',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_pickupStats!['byGuide'] as Map).entries.take(5).map((entry) {
                        final guideData = entry.value as Map<String, dynamic>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.directions_bus, size: 20),
                            title: Text(guideData['guideName'] ?? entry.key),
                            subtitle: Text(
                              '${guideData['totalPassengers']} passengers • ${guideData['totalBookings']} bookings',
                            ),
                            trailing: Text(
                              '${guideData['totalAssignments']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    if ((_pickupStats!['byDate'] as List?) != null && 
                        (_pickupStats!['byDate'] as List).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Recent Dates',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_pickupStats!['byDate'] as List).take(5).map((dateData) {
                        final data = dateData as Map<String, dynamic>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.calendar_today, size: 20),
                            title: Text(data['date'] ?? 'Unknown'),
                            subtitle: Text('${data['totalGuides']} guides'),
                            trailing: Text(
                              '${data['totalPassengers']} passengers',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }),
                    ],
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