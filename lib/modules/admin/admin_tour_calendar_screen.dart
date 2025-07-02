import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/models/tour_models.dart';
import '../../core/theme/colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import 'tour_management_service.dart';

class AdminTourCalendarScreen extends StatefulWidget {
  const AdminTourCalendarScreen({Key? key}) : super(key: key);

  @override
  State<AdminTourCalendarScreen> createState() => _AdminTourCalendarScreenState();
}

class _AdminTourCalendarScreenState extends State<AdminTourCalendarScreen> {
  final TourManagementService _service = TourManagementService();
  
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, TourDate> _tourData = {};
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTourData();
  }

  Future<void> _loadTourData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tourData = await _service.fetchTourDataForMonth(_focusedDay);
      setState(() {
        _tourData = tourData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load tour data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour Calendar'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTourData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCalendar(),
          Expanded(
            child: _buildSelectedDayContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return TableCalendar<DateTime>(
      firstDay: DateTime.utc(2024, 1, 1),
      lastDay: DateTime.utc(2025, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: CalendarFormat.month,
      eventLoader: (day) {
        final tourDate = _tourData[DateTime(day.year, day.month, day.day)];
        if (tourDate != null && tourDate.totalBookings > 0) {
          return [day]; // Return the day as an event if it has bookings
        }
        return [];
      },
      calendarStyle: const CalendarStyle(
        markersMaxCount: 1,
        markerDecoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      ),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = focusedDay;
        });
        _loadTourData();
      },
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          final tourDate = _tourData[DateTime(date.year, date.month, date.day)];
          if (tourDate != null && tourDate.totalBookings > 0) {
            return Positioned(
              bottom: 1,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${tourDate.totalBookings}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }
          return null;
        },
        defaultBuilder: (context, date, _) {
          final tourDate = _tourData[DateTime(date.year, date.month, date.day)];
          if (tourDate != null && tourDate.totalBookings > 0) {
            return Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${tourDate.totalPassengers}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSelectedDayContent() {
    if (_selectedDay == null) {
      return const Center(
        child: Text('Select a date to view tour details'),
      );
    }

    final tourDate = _tourData[DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day)];
    
    if (tourDate == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No tours scheduled',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select another date or create a new tour',
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTourDateHeader(tourDate),
          const SizedBox(height: 16),
          _buildGuideApplications(tourDate),
          const SizedBox(height: 16),
          _buildBusAssignments(tourDate),
        ],
      ),
    );
  }

  Widget _buildTourDateHeader(TourDate tourDate) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tourDate.date.day}/${tourDate.date.month}/${tourDate.date.year}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total Bookings',
                    '${tourDate.totalBookings}',
                    Icons.assignment,
                    AppColors.primary,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Total Passengers',
                    '${tourDate.totalPassengers}',
                    Icons.people,
                    AppColors.secondary,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Guide Applications',
                    '${tourDate.guideApplications.length}',
                    Icons.person_add,
                    AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGuideApplications(TourDate tourDate) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Guide Applications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAssignGuideDialog(tourDate),
                  icon: const Icon(Icons.add),
                  label: const Text('Assign Guide'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (tourDate.guideApplications.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No guide applications yet'),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tourDate.guideApplications.length,
              itemBuilder: (context, index) {
                final application = tourDate.guideApplications[index];
                return _buildGuideApplicationTile(application, tourDate);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGuideApplicationTile(GuideApplication application, TourDate tourDate) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getTourTypeColor(application.tourType),
        child: Text(
          application.guideName[0],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(application.guideName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_getTourTypeDisplayName(application.tourType)),
          Text('Applied: ${_formatDateTime(application.appliedAt)}'),
        ],
      ),
      trailing: _buildApplicationStatusChip(application),
      onTap: () => _showGuideDetailsDialog(application, tourDate),
    );
  }

  Widget _buildApplicationStatusChip(GuideApplication application) {
    Color color;
    String text;
    
    switch (application.status) {
      case 'approved':
        color = AppColors.success;
        text = 'Approved';
        break;
      case 'rejected':
        color = AppColors.error;
        text = 'Rejected';
        break;
      default:
        color = AppColors.warning;
        text = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBusAssignments(TourDate tourDate) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Bus Assignments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showCreateBusAssignmentDialog(tourDate),
                  icon: const Icon(Icons.directions_bus),
                  label: const Text('Add Bus'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (tourDate.busAssignments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No bus assignments yet'),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tourDate.busAssignments.length,
              itemBuilder: (context, index) {
                final assignment = tourDate.busAssignments[index];
                return _buildBusAssignmentTile(assignment);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBusAssignmentTile(BusAssignment assignment) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: assignment.isFull ? AppColors.error : AppColors.success,
        child: const Icon(
          Icons.directions_bus,
          color: Colors.white,
        ),
      ),
      title: Text(assignment.busName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Guide: ${assignment.assignedGuideName}'),
          Text('${assignment.totalPassengers}/${assignment.maxPassengers} passengers'),
          Text(_getTourTypeDisplayName(assignment.tourType)),
        ],
      ),
      trailing: assignment.isFull
          ? const Icon(Icons.warning, color: AppColors.error)
          : null,
      onTap: () => _showBusDetailsDialog(assignment),
    );
  }

  Color _getTourTypeColor(String tourType) {
    switch (tourType) {
      case 'day_tour':
        return AppColors.primary;
      case 'northern_lights':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getTourTypeDisplayName(String tourType) {
    switch (tourType) {
      case 'day_tour':
        return 'Day Tour';
      case 'northern_lights':
        return 'Northern Lights';
      default:
        return tourType;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showAssignGuideDialog(TourDate tourDate) {
    // Implementation for assigning guides to buses
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Guide to Bus'),
        content: const Text('This feature will be implemented to assign guides to specific buses.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGuideDetailsDialog(GuideApplication application, TourDate tourDate) {
    // Implementation for showing guide details and assignment options
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(application.guideName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tour Type: ${_getTourTypeDisplayName(application.tourType)}'),
            Text('Status: ${application.status}'),
            Text('Applied: ${_formatDateTime(application.appliedAt)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showCreateBusAssignmentDialog(TourDate tourDate) {
    // Implementation for creating new bus assignments
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Bus Assignment'),
        content: const Text('This feature will be implemented to create new bus assignments.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showBusDetailsDialog(BusAssignment assignment) {
    // Implementation for showing bus details
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(assignment.busName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guide: ${assignment.assignedGuideName}'),
            Text('Passengers: ${assignment.totalPassengers}/${assignment.maxPassengers}'),
            Text('Tour Type: ${_getTourTypeDisplayName(assignment.tourType)}'),
            if (assignment.isFull)
              const Text(
                '⚠️ Bus is full!',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
} 