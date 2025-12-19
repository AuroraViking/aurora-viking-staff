// Admin shift management screen with calendar interface for reviewing and approving/rejecting shift applications

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:io' if (dart.library.html) '../../core/utils/file_stub.dart' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async'; // Added for Timer
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/shift_model.dart';
import '../../core/auth/auth_controller.dart';
import '../shifts/shifts_service.dart';
import '../../core/services/bus_management_service.dart';
import '../../theme/colors.dart';
import '../pickup/pickup_service.dart';

class AdminShiftManagementScreen extends StatefulWidget {
  const AdminShiftManagementScreen({super.key});

  @override
  State<AdminShiftManagementScreen> createState() => _AdminShiftManagementScreenState();
}

class _AdminShiftManagementScreenState extends State<AdminShiftManagementScreen> {
  final ShiftsService _shiftsService = ShiftsService();
  final BusManagementService _busService = BusManagementService();
  final PickupService _pickupService = PickupService();
  List<Shift> _allShifts = [];
  List<Map<String, dynamic>> _availableBuses = [];
  bool _isLoading = false;
  Map<String, dynamic> _statistics = {};
  
  // Calendar state
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late CalendarFormat _calendarFormat;
  Map<DateTime, List<Shift>> _shiftsByDate = {};
  Timer? _autoCompleteTimer;
  
  // Booking data by date (for displaying passenger/guide counts)
  Map<String, Map<String, dynamic>> _bookingsByDate = {}; // dateKey -> {passengers, guides}

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
      _loadAvailableBuses();
      _loadBookingsForMonth(_focusedDay);
      
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
    _shiftsService.getAllShifts().listen((shifts) {
      if (mounted) {
        setState(() {
          _allShifts = shifts;
          _organizeShiftsByDate();
        });
      }
    });
    
    // Auto-complete past accepted shifts
    _shiftsService.autoCompletePastShifts();
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

  void _loadAvailableBuses() {
    _busService.getActiveBuses().listen((buses) {
      if (mounted) {
        setState(() {
          _availableBuses = buses;
        });
      }
    });
  }

  /// Load booking data for the focused month
  Future<void> _loadBookingsForMonth(DateTime month) async {
    try {
      final endOfMonth = DateTime(month.year, month.month + 1, 0);
      
      print('📅 Loading bookings for month: ${month.year}-${month.month}');
      
      // Load bookings for each day in the month
      for (int day = 1; day <= endOfMonth.day; day++) {
        final date = DateTime(month.year, month.month, day);
        final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        try {
          final bookings = await _pickupService.fetchBookingsForDate(date);
          
          if (bookings.isNotEmpty) {
            final totalPassengers = bookings.fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
            final guidesNeeded = (totalPassengers / 19).ceil(); // Assuming 19 passengers per bus
            
            _bookingsByDate[dateKey] = {
              'passengers': totalPassengers,
              'guides': guidesNeeded,
            };
          } else {
            // Clear if no bookings
            _bookingsByDate.remove(dateKey);
          }
        } catch (e) {
          print('⚠️ Error loading bookings for $dateKey: $e');
          // Don't fail the whole month if one day fails
        }
      }
      
      if (mounted) {
        setState(() {});
      }
      
      print('✅ Loaded booking data for ${_bookingsByDate.length} dates in month');
    } catch (e) {
      print('❌ Error loading bookings for month: $e');
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
            icon: const Icon(Icons.file_download),
            onPressed: () => _exportMonthlyShifts(),
            tooltip: 'Export Monthly Shifts',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadStatistics();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Statistics Cards
            _buildStatisticsCards(),
            
            // Calendar
            _buildCalendar(),
            
            // Spacing to prevent overflow
            const SizedBox(height: 20),
            
            // Selected Day Shifts
            _buildSelectedDayShifts(),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      height: 360,
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
      child: SizedBox(
        height: 360,
        child: ClipRect(
          clipBehavior: Clip.hardEdge,
          child: TableCalendar<Shift>(
        firstDay: DateTime.now().subtract(const Duration(days: 365)), // Allow viewing past year
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
          setState(() {
            _focusedDay = focusedDay;
          });
          // Load bookings for the new month
          _loadBookingsForMonth(focusedDay);
        },
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: const TextStyle(color: AVColors.textHigh, fontSize: 12),
          weekendTextStyle: const TextStyle(color: AVColors.textHigh, fontSize: 12),
          holidayTextStyle: const TextStyle(color: AVColors.textHigh, fontSize: 12),
          outsideTextStyle: const TextStyle(color: AVColors.textLow, fontSize: 12),
          cellPadding: EdgeInsets.zero,
          cellMargin: const EdgeInsets.all(1),
          todayDecoration: const BoxDecoration(
            color: Colors.transparent,
            border: Border.fromBorderSide(BorderSide(color: AVColors.primaryTeal, width: 1.2)),
            shape: BoxShape.circle,
          ),
          selectedDecoration: const BoxDecoration(
            color: AVColors.tealGlowMid,
            shape: BoxShape.circle,
          ),
          markerDecoration: const BoxDecoration(
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
          defaultBuilder: (context, date, _) {
            final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final bookingData = _bookingsByDate[dateKey];
            
            if (bookingData != null) {
              final passengers = bookingData['passengers'];
              final guides = bookingData['guides'];
              
              return Container(
                margin: const EdgeInsets.all(1),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${date.day}',
                      style: const TextStyle(
                        color: AVColors.textHigh,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${passengers}p • ${guides}g',
                      style: TextStyle(
                        color: AVColors.primaryTeal,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }
            
            return null;
          },
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
    final isPastDate = _selectedDay.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    
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
          
          // Shifts for selected day
          if (selectedDayShifts.isEmpty)
            const SizedBox(
              height: 200,
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
          else ...[
            // Header with View All button for past dates
            Row(
              children: [
                Text(
                  isPastDate ? 'Shift Details' : 'Shifts for Selected Date',
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
            SizedBox(
              height: 400,
              child: ListView.builder(
                itemCount: selectedDayShifts.length,
                itemBuilder: (context, index) {
                  final shift = selectedDayShifts[index];
                  return _buildShiftCard(shift);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            
            // Bus Info
            if (shift.busId != null) ...[
              Row(
                children: [
                  const Icon(Icons.directions_bus, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Bus: ${shift.busName ?? 'Unknown Bus'}',
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
                      onPressed: _isLoading ? null : () => _acceptShiftAndAssignBus(shift),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Accept & Assign Bus'),
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
                      onPressed: _isLoading ? null : () => _assignBusToShift(shift),
                      icon: const Icon(Icons.directions_bus, size: 16),
                      label: const Text('Assign/Change Bus'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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

  void _acceptShiftAndAssignBus(Shift shift) async {
    if (_availableBuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No buses available. Please add buses first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedBus = await _showBusSelectionDialog('Select Bus for ${shift.guideName}', shift);
    if (selectedBus == null) return;

    setState(() {
      _isLoading = true;
    });

    final success = await _shiftsService.acceptShiftAndAssignBus(
      shiftId: shift.id,
      busId: selectedBus['id'],
      busName: selectedBus['name'],
    );

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shift accepted and bus ${selectedBus['name']} assigned successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStatistics();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to accept shift and assign bus.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _assignBusToShift(Shift shift) async {
    if (_availableBuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No buses available. Please add buses first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedBus = await _showBusSelectionDialog('Change Bus for ${shift.guideName}', shift);
    if (selectedBus == null) return;

    setState(() {
      _isLoading = true;
    });

    final success = await _shiftsService.assignBusToShift(
      shiftId: shift.id,
      busId: selectedBus['id'],
      busName: selectedBus['name'],
    );

    setState(() {
      _isLoading = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bus changed to ${selectedBus['name']} successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to assign bus to shift.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _showBusSelectionDialog(String title, Shift shift) async {
    // Get available buses for this specific shift
    final availableBuses = await _getAvailableBusesForShift(shift);
    
    if (availableBuses.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Available Buses'),
          content: Text('All buses are already assigned to ${shift.type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights'} shifts on ${DateFormat('MMM d, y').format(shift.date)}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableBuses.length,
            itemBuilder: (context, index) {
              final bus = availableBuses[index];
              return ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text(bus['name']),
                subtitle: Text(bus['licensePlate'] ?? ''),
                onTap: () => Navigator.pop(context, bus),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getAvailableBusesForShift(Shift shift) async {
    final availableBuses = <Map<String, dynamic>>[];
    
    for (final bus in _availableBuses) {
      final isAvailable = await _shiftsService.isBusAvailableForShift(
        busId: bus['id'],
        shiftType: shift.type,
        date: shift.date,
        excludeShiftId: shift.id,
      );
      
      if (isAvailable) {
        availableBuses.add(bus);
      }
    }
    
    return availableBuses;
  }

  void _exportMonthlyShifts() async {
    // Show month selection dialog
    final selectedMonth = await _showMonthSelectionDialog();
    if (selectedMonth == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Get shifts for the selected month
      final monthShifts = await _getShiftsForMonth(selectedMonth);
      
      if (monthShifts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No shifts found for ${DateFormat('MMMM yyyy').format(selectedMonth)}'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Generate CSV content
      final csvContent = _generateMonthlyReport(monthShifts, selectedMonth);
      
      // Save and share file
      await _saveAndShareReport(csvContent, selectedMonth);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Monthly report exported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<DateTime?> _showMonthSelectionDialog() async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    
    return showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Month'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: 12, // Show last 12 months
            itemBuilder: (context, index) {
              final month = DateTime(now.year, now.month - index, 1);
              return ListTile(
                title: Text(DateFormat('MMMM yyyy').format(month)),
                onTap: () => Navigator.pop(context, month),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<List<Shift>> _getShiftsForMonth(DateTime month) async {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);
    
    // Get all shifts and filter by month
    final allShifts = await _shiftsService.getAllShifts().first;
    return allShifts.where((shift) => 
      shift.date.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
      shift.date.isBefore(endOfMonth.add(const Duration(days: 1)))
    ).toList();
  }

  String _generateMonthlyReport(List<Shift> shifts, DateTime month) {
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln('Aurora Viking Staff - Monthly Shift Report');
    buffer.writeln('Month: ${DateFormat('MMMM yyyy').format(month)}');
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buffer.writeln('');
    
    // Summary
    final totalShifts = shifts.length;
    final acceptedShifts = shifts.where((s) => s.status == ShiftStatus.accepted).length;
    final completedShifts = shifts.where((s) => s.status == ShiftStatus.completed).length;
    final dayTours = shifts.where((s) => s.type == ShiftType.dayTour).length;
    final northernLights = shifts.where((s) => s.type == ShiftType.northernLights).length;
    
    buffer.writeln('SUMMARY:');
    buffer.writeln('Total Shifts: $totalShifts');
    buffer.writeln('Accepted: $acceptedShifts');
    buffer.writeln('Completed: $completedShifts');
    buffer.writeln('Day Tours: $dayTours');
    buffer.writeln('Northern Lights: $northernLights');
    buffer.writeln('');
    
    // Guide Performance (Only Accepted Shifts)
    buffer.writeln('GUIDE PERFORMANCE (Accepted Shifts Only):');
    buffer.writeln('Guide Name,Day Tours,Northern Lights,Total Shifts,Completed Shifts');
    
    final guideStats = <String, Map<String, int>>{};
    
    // Filter for accepted and completed shifts only
    final acceptedShiftsForPerformance = shifts.where((shift) => 
      shift.status == ShiftStatus.accepted || shift.status == ShiftStatus.completed
    ).toList();
    
    for (final shift in acceptedShiftsForPerformance) {
      if (shift.guideName != null) {
        final guideName = shift.guideName!;
        guideStats.putIfAbsent(guideName, () => {
          'dayTours': 0,
          'northernLights': 0,
          'total': 0,
          'completed': 0,
        });
        
        guideStats[guideName]!['total'] = guideStats[guideName]!['total']! + 1;
        
        if (shift.type == ShiftType.dayTour) {
          guideStats[guideName]!['dayTours'] = guideStats[guideName]!['dayTours']! + 1;
        } else {
          guideStats[guideName]!['northernLights'] = guideStats[guideName]!['northernLights']! + 1;
        }
        
        if (shift.status == ShiftStatus.completed) {
          guideStats[guideName]!['completed'] = guideStats[guideName]!['completed']! + 1;
        }
      }
    }
    
    // Sort guides by total shifts (descending)
    final sortedGuides = guideStats.entries.toList()
      ..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));
    
    for (final entry in sortedGuides) {
      final stats = entry.value;
      buffer.writeln('${entry.key},${stats['dayTours']},${stats['northernLights']},${stats['total']},${stats['completed']}');
    }
    
    buffer.writeln('');
    
    // Detailed Shift List
    buffer.writeln('DETAILED SHIFT LIST:');
    buffer.writeln('Date,Type,Guide Name,Bus,Status,Start Time,End Time');
    
    final sortedShifts = shifts.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    
    for (final shift in sortedShifts) {
      final date = DateFormat('yyyy-MM-dd').format(shift.date);
      final type = shift.type == ShiftType.dayTour ? 'Day Tour' : 'Northern Lights';
      final guideName = shift.guideName ?? 'Unknown';
      final busName = shift.busName ?? 'Not Assigned';
      final status = _getStatusText(shift.status);
      final startTime = shift.startTime.isNotEmpty ? shift.startTime : 'TBD';
      final endTime = shift.endTime.isNotEmpty ? shift.endTime : 'TBD';
      
      buffer.writeln('$date,$type,$guideName,$busName,$status,$startTime,$endTime');
    }
    
    return buffer.toString();
  }

  Future<void> _saveAndShareReport(String content, DateTime month) async {
    if (kIsWeb) {
      // Web: Share text directly
      await Share.share(
        content,
        subject: 'Aurora Viking Staff - Monthly Shift Report for ${DateFormat('MMMM yyyy').format(month)}',
      );
      return;
    }
    
    // Mobile: Save to file and share (dart:io only)
    // This will only execute on non-web platforms where dart:io is available
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'shifts_report_${DateFormat('yyyy_MM').format(month)}.csv';
    final filePath = '${directory.path}/$fileName';
    
    // Use a helper to create the file - this avoids web compilation issues
    await _writeFileContent(filePath, content);
    
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Aurora Viking Staff - Monthly Shift Report for ${DateFormat('MMMM yyyy').format(month)}',
    );
  }
  
  Future<void> _writeFileContent(String filePath, String content) async {
    if (kIsWeb) return; // Should never be called on web
    
    // On non-web, io is dart:io.File which has a single-argument constructor
    // We need to use a workaround because dart:html.File has a different constructor
    // ignore: avoid_dynamic_calls
    // ignore: undefined_class
    // ignore: invalid_use_of_visible_for_testing_member
    // The File constructor is only valid on non-web platforms
    final file = _createFile(filePath);
    await file.writeAsString(content);
  }
  
  // Helper to create File object - only works on non-web platforms
  dynamic _createFile(String path) {
    if (kIsWeb) {
      throw UnsupportedError('File operations not supported on web');
    }
    // On non-web, io is dart:io which has File class
    // On web, io is file_stub.dart which also has File class (but throws on use)
    return io.File(path);
  }

  void _deleteShift(String shiftId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this shift? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed == true) {
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
                if (shift.busName != null)
                  Text(
                    'Bus: ${shift.busName}',
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