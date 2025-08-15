// Shifts screen for viewing, accepting, and marking shifts as completed 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../core/models/shift_model.dart';
import '../../core/auth/auth_controller.dart';
import 'shifts_service.dart';
import '../../theme/colors.dart';
import 'dart:async'; // Added for Timer

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late CalendarFormat _calendarFormat;
  
  final ShiftsService _shiftsService = ShiftsService();
  Map<DateTime, List<Shift>> _appliedShifts = {};
  bool _isLoading = false;
  Timer? _autoCompleteTimer;

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
      
      // Set up periodic auto-completion check (every hour)
      _autoCompleteTimer = Timer.periodic(const Duration(hours: 1), (timer) {
        if (mounted) {
          _shiftsService.autoCompletePastShifts();
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _autoCompleteTimer?.cancel();
    super.dispose();
  }

  void _loadShifts() {
    _shiftsService.getGuideShifts().listen((shifts) {
      if (mounted) {
        setState(() {
          _appliedShifts.clear();
          for (final shift in shifts) {
            final dayStart = DateTime(shift.date.year, shift.date.month, shift.date.day);
            final existingShifts = _appliedShifts[dayStart] ?? [];
            existingShifts.add(shift);
            _appliedShifts[dayStart] = existingShifts;
          }
        });
      }
    });
    
    // Auto-complete past accepted shifts
    _shiftsService.autoCompletePastShifts();
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
              color: AVColors.slate,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TableCalendar<Shift>(
              firstDay: DateTime.now().subtract(const Duration(days: 365)), // Allow viewing past year
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
                defaultTextStyle: TextStyle(color: AVColors.textHigh),
                weekendTextStyle: TextStyle(color: AVColors.textHigh),
                holidayTextStyle: TextStyle(color: AVColors.textHigh),
                outsideTextStyle: TextStyle(color: AVColors.textLow),
                todayDecoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.fromBorderSide(BorderSide(color: AVColors.primaryTeal, width: 1.2)),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: AVColors.tealGlowMid,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: AVColors.textLow),
                weekendStyle: TextStyle(color: AVColors.textLow),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                titleTextStyle: TextStyle(color: AVColors.textHigh, fontWeight: FontWeight.bold),
                formatButtonTextStyle: TextStyle(color: AVColors.textHigh),
                formatButtonDecoration: BoxDecoration(
                  color: AVColors.slateElev,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                leftChevronIcon: Icon(Icons.chevron_left, color: AVColors.textHigh),
                rightChevronIcon: Icon(Icons.chevron_right, color: AVColors.textHigh),
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
    final isPastDate = _selectedDay.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    final isToday = _selectedDay.day == DateTime.now().day && 
                    _selectedDay.month == DateTime.now().month && 
                    _selectedDay.year == DateTime.now().year;
    
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
                if (isPastDate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Past Date',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Show all shifts for the selected date
            if (selectedDayShifts.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    isPastDate ? 'Shift Details' : 'Your Applications',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (isPastDate)
                    TextButton.icon(
                      onPressed: () => _viewAllShiftsForDate(_selectedDay),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('View All'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...selectedDayShifts.map((shift) => _buildAppliedShiftCard(shift)),
              const SizedBox(height: 16),
            ],
            
            // Application Options (only show for current/future dates)
            if (!isPastDate) ...[
              Row(
                children: [
                  const Text(
                    'Apply for Shifts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
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
            ] else if (selectedDayShifts.isEmpty) ...[
              // Show message for past dates with no shifts
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No shifts recorded for this date',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            
            // Add some bottom padding for better scrolling
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAppliedShiftCard(Shift shift) {
    final isPastShift = shift.date.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: isPastShift ? () => _viewShiftDetails(shift) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        if (isPastShift) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${shift.startTime} - ${shift.endTime}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
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
              // Action buttons (only for current/future shifts)
              if (!isPastShift && (shift.status == ShiftStatus.applied || shift.status == ShiftStatus.accepted)) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (shift.status == ShiftStatus.applied)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _cancelShift(shift.id),
                          icon: const Icon(Icons.cancel, size: 16),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    if (shift.status == ShiftStatus.accepted) ...[
                      if (shift.status == ShiftStatus.applied) const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () => _completeShift(shift.id),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Mark Complete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              // Show "Click to view details" for past shifts
              if (isPastShift) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Click to view details',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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

  void _cancelShift(String shiftId) async {
    setState(() {
      _isLoading = true;
    });

    final success = await _shiftsService.cancelShiftApplication(shiftId);

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift application cancelled successfully.'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to cancel shift application.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _completeShift(String shiftId) async {
    setState(() {
      _isLoading = true;
    });

    final success = await _shiftsService.markShiftCompleted(shiftId);

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift marked as completed successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to mark shift as completed.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _applyForShift(ShiftType type) async {
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

    setState(() {
      _isLoading = true;
    });

    final success = await _shiftsService.applyForShift(
      type: type,
      date: _selectedDay,
    );

    setState(() {
      _isLoading = false;
    });

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully applied for ${type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights'} shift!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to apply for shift. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _viewAllShiftsForDate(DateTime date) async {
    final allShifts = await _shiftsService.getAllShiftsForDate(date);
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('All Shifts for ${DateFormat('MMMM d, y').format(date)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allShifts.isEmpty)
                  const Text('No shifts recorded for this date')
                else
                  ...allShifts.map((shift) => _buildShiftListItem(shift)),
              ],
            ),
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

  void _viewShiftDetails(Shift shift) async {
    final details = await _shiftsService.getShiftDetails(shift.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Shift Details for ${DateFormat('MMMM d, y').format(shift.date)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildShiftListItem(shift),
                if (details != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Guide: ${details.guideName ?? 'Unknown'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Status: ${_getStatusText(details.status)}',
                    style: TextStyle(
                      color: _getStatusColor(details.status),
                      fontSize: 14,
                    ),
                  ),
                  if (details.status == ShiftStatus.completed) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Status: Completed',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ],
            ),
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

  Widget _buildShiftListItem(Shift shift) {
    final statusColor = shift.status == ShiftStatus.accepted
        ? Colors.green
        : shift.status == ShiftStatus.applied
            ? Colors.orange
            : shift.status == ShiftStatus.completed
                ? Colors.blue
                : shift.status == ShiftStatus.cancelled
                    ? Colors.red
                    : Colors.grey;

    final typeIcon = shift.type == ShiftType.dayTour ? Icons.wb_sunny : Icons.nightlight_round;
    final typeColor = shift.type == ShiftType.dayTour ? Colors.orange : Colors.indigo;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(typeIcon, color: typeColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shift.type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (shift.guideName != null)
                  Text(
                    'Guide: ${shift.guideName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                Text(
                  '${shift.startTime} - ${shift.endTime}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              shift.status.name.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 