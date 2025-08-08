// Admin shift management screen with calendar interface for reviewing and approving/rejecting shift applications

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/models/shift_model.dart';
import '../../core/auth/auth_controller.dart';
import '../shifts/shifts_service.dart';

class AdminShiftManagementScreen extends StatefulWidget {
  const AdminShiftManagementScreen({super.key});

  @override
  State<AdminShiftManagementScreen> createState() => _AdminShiftManagementScreenState();
}

class _AdminShiftManagementScreenState extends State<AdminShiftManagementScreen> {
  final ShiftsService _shiftsService = ShiftsService();
  List<Shift> _allShifts = [];
  bool _isLoading = false;
  Map<String, dynamic> _statistics = {};
  
  // Calendar state
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late CalendarFormat _calendarFormat;
  Map<DateTime, List<Shift>> _shiftsByDate = {};

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;
    
    // Set the auth controller in the shifts service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authController = context.read<AuthController>();
      _shiftsService.setAuthController(authController);
      _loadShifts();
      _loadStatistics();
    });
  }

  void _loadShifts() {
    _shiftsService.getAllShifts().listen((shifts) {
      if (mounted) {
        setState(() {
          _allShifts = shifts;
          _organizeShiftsByDate();
        });
      }
    });
  }

  void _organizeShiftsByDate() {
    _shiftsByDate.clear();
    for (final shift in _allShifts) {
      final date = DateTime(shift.date.year, shift.date.month, shift.date.day);
      if (_shiftsByDate[date] == null) {
        _shiftsByDate[date] = [];
      }
      _shiftsByDate[date]!.add(shift);
    }
  }

  List<Shift> _getShiftsForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return _shiftsByDate[date] ?? [];
  }

  void _loadStatistics() async {
    final stats = await _shiftsService.getShiftStatistics();
    if (mounted) {
      setState(() {
        _statistics = stats;
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Management'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadStatistics();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Statistics Cards
          _buildStatisticsCards(),
          
          // Calendar
          _buildCalendar(),
          
          // Selected Day Shifts
          Expanded(
            child: _buildSelectedDayShifts(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TableCalendar<Shift>(
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 365)),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) {
          return isSameDay(_selectedDay, day);
        },
        eventLoader: _getShiftsForDay,
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        onFormatChanged: (format) {
          setState(() {
            _calendarFormat = format;
          });
        },
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay;
        },
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: false,
          weekendTextStyle: TextStyle(color: Colors.red),
          holidayTextStyle: TextStyle(color: Colors.red),
          markerDecoration: BoxDecoration(
            color: Colors.transparent,
          ),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, events) {
            if (events.isNotEmpty) {
              final shifts = events as List<Shift>;
              final color = _getMarkerColor(shifts);
              if (color != Colors.transparent) {
                return Positioned(
                  bottom: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }
            }
            return null;
          },
        ),
      ),
    );
  }

  Color _getMarkerColor(List<Shift> shifts) {
    if (shifts.isEmpty) return Colors.transparent;
    
    // Check if any shift is applied
    if (shifts.any((shift) => shift.status == ShiftStatus.applied)) {
      return Colors.orange;
    }
    // Check if any shift is accepted
    if (shifts.any((shift) => shift.status == ShiftStatus.accepted)) {
      return Colors.green;
    }
    // Check if any shift is completed
    if (shifts.any((shift) => shift.status == ShiftStatus.completed)) {
      return Colors.blue;
    }
    // Check if any shift is cancelled
    if (shifts.any((shift) => shift.status == ShiftStatus.cancelled)) {
      return Colors.red;
    }
    
    return Colors.transparent;
  }

  Widget _buildSelectedDayShifts() {
    final selectedDayShifts = _getShiftsForDay(_selectedDay);
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected Date Header
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat('EEEE, MMMM d, y').format(_selectedDay),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Shifts for selected day
          if (selectedDayShifts.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No shifts for this date',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: selectedDayShifts.length,
                itemBuilder: (context, index) {
                  final shift = selectedDayShifts[index];
                  return _buildShiftCard(shift);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total',
              _statistics['total']?.toString() ?? '0',
              Colors.blue,
              Icons.calendar_today,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Applied',
              _statistics['applied']?.toString() ?? '0',
              Colors.orange,
              Icons.pending,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Accepted',
              _statistics['accepted']?.toString() ?? '0',
              Colors.green,
              Icons.check_circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Completed',
              _statistics['completed']?.toString() ?? '0',
              Colors.purple,
              Icons.done_all,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
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
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildShiftCard(Shift shift) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  shift.type == ShiftType.dayTour ? Icons.wb_sunny : Icons.nightlight,
                  color: shift.type == ShiftType.dayTour ? Colors.orange : Colors.indigo,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift.type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, MMMM d, y').format(shift.date),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(shift.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusText(shift.status),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Guide Info
            if (shift.guideId != null) ...[
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Guide: ${shift.guideName ?? 'Unknown Guide'}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            
            // Action Buttons
            if (shift.status == ShiftStatus.applied) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _updateShiftStatus(shift.id, ShiftStatus.accepted),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _updateShiftStatus(shift.id, ShiftStatus.cancelled),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (shift.status == ShiftStatus.accepted) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _updateShiftStatus(shift.id, ShiftStatus.cancelled),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            
            // Delete Button (for all statuses)
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _deleteShift(shift.id),
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateShiftStatus(String shiftId, ShiftStatus status) async {
    setState(() {
      _isLoading = true;
    });

    String? adminNote;
    if (status == ShiftStatus.cancelled) {
      adminNote = await _showNoteDialog('Rejection Note (Optional)');
    }

    final success = await _shiftsService.updateShiftStatus(
      shiftId: shiftId,
      status: status,
      adminNote: adminNote,
    );

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shift ${_getStatusText(status).toLowerCase()} successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStatistics();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update shift status.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteShift(String shiftId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Shift'),
        content: const Text('Are you sure you want to delete this shift? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    final success = await _shiftsService.deleteShift(shiftId);

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift deleted successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStatistics();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete shift.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _showNoteDialog(String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter a note (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ShiftStatus status) {
    switch (status) {
      case ShiftStatus.applied:
        return Colors.orange;
      case ShiftStatus.accepted:
        return Colors.green;
      case ShiftStatus.completed:
        return Colors.blue;
      case ShiftStatus.cancelled:
        return Colors.red;
      case ShiftStatus.available:
        return Colors.grey;
    }
  }

  String _getStatusText(ShiftStatus status) {
    switch (status) {
      case ShiftStatus.applied:
        return 'Applied';
      case ShiftStatus.accepted:
        return 'Accepted';
      case ShiftStatus.completed:
        return 'Completed';
      case ShiftStatus.cancelled:
        return 'Cancelled';
      case ShiftStatus.available:
        return 'Available';
    }
  }
} 