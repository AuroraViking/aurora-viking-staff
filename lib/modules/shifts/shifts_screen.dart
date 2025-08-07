// Shifts screen for viewing, accepting, and marking shifts as completed 
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../core/models/shift_model.dart';

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late CalendarFormat _calendarFormat;
  
  // Track applied shifts
  Map<DateTime, List<Shift>> _appliedShifts = {};

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;
  }

  // Get events for a specific day
  List<Shift> _getEventsForDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    return _appliedShifts[dayStart] ?? [];
  }

  // Get marker color based on shift status
  Color _getMarkerColor(List<Shift> shifts) {
    if (shifts.isEmpty) return Colors.transparent;
    
    // Check if any shift is accepted
    if (shifts.any((shift) => shift.status == ShiftStatus.accepted)) {
      return Colors.green;
    }
    // Check if any shift is applied
    if (shifts.any((shift) => shift.status == ShiftStatus.applied)) {
      return Colors.orange;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Calendar Section
          Container(
            height: 400, // Fixed height to prevent calendar from taking too much space
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
              eventLoader: _getEventsForDay,
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
          ),
          
          // Selected Day Application Options
          Expanded(
            child: _buildApplicationOptions(),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationOptions() {
    final dateFormat = DateFormat('EEEE, MMMM d, y');
    final selectedDayShifts = _getEventsForDay(_selectedDay);
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
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
                    dateFormat.format(_selectedDay),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Show existing applications if any
            if (selectedDayShifts.isNotEmpty) ...[
              const Text(
                'Your Applications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...selectedDayShifts.map((shift) => _buildAppliedShiftCard(shift)),
              const SizedBox(height: 16),
            ],
            
            // Application Options
            const Text(
              'Apply for Shifts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            // Day Tour Option
            _buildShiftOption(
              'Day Tour',
              Icons.wb_sunny,
              Colors.orange,
              selectedDayShifts.any((shift) => shift.type == ShiftType.dayTour),
              () => _applyForShift(ShiftType.dayTour),
            ),
            
            const SizedBox(height: 8),
            
            // Northern Lights Option
            _buildShiftOption(
              'Northern Lights',
              Icons.nightlight,
              Colors.indigo,
              selectedDayShifts.any((shift) => shift.type == ShiftType.northernLights),
              () => _applyForShift(ShiftType.northernLights),
            ),
            
            // Add some bottom padding for better scrolling
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAppliedShiftCard(Shift shift) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _getStatusText(shift.status),
                    style: TextStyle(
                      color: _getStatusColor(shift.status),
                      fontSize: 12,
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
      ),
    );
  }

  Widget _buildShiftOption(
    String title,
    IconData icon,
    Color color,
    bool isApplied,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: isApplied ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isApplied ? 'Already applied' : 'Tap to apply for this shift',
                      style: TextStyle(
                        color: isApplied ? Colors.grey[500] : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isApplied)
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                )
              else
                Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 20,
                ),
            ],
          ),
        ),
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

  void _applyForShift(ShiftType type) {
    // Check if already applied for this type on this date
    final selectedDayShifts = _getEventsForDay(_selectedDay);
    if (selectedDayShifts.any((shift) => shift.type == type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already applied for this shift type on this date.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply for Shift'),
        content: Text(
          'Are you sure you want to apply for the ${type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights'} shift on ${DateFormat('MMMM d, y').format(_selectedDay)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Create and add the shift
              final shift = Shift(
                id: 'shift_${DateTime.now().millisecondsSinceEpoch}',
                type: type,
                date: _selectedDay,
                startTime: '',
                endTime: '',
                status: ShiftStatus.applied,
                createdAt: DateTime.now(),
              );

              setState(() {
                final dayStart = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
                final existingShifts = _appliedShifts[dayStart] ?? [];
                existingShifts.add(shift);
                _appliedShifts[dayStart] = existingShifts;
              });

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Successfully applied for ${type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights'} shift!',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
} 