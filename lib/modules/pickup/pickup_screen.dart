import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/theme/colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import 'pickup_controller.dart';

class PickupScreen extends StatefulWidget {
  const PickupScreen({Key? key}) : super(key: key);

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, int> _guestCounts = {};

  @override
  void initState() {
    super.initState();
    _loadMonthData();
  }

  void _loadMonthData() {
    final controller = context.read<PickupController>();
    controller.fetchMonthData(_focusedDay).then((_) {
      _updateGuestCounts();
    });
  }

  void _updateGuestCounts() {
    final controller = context.read<PickupController>();
    final monthData = controller.monthData;
    
    setState(() {
      _guestCounts.clear();
      monthData.forEach((date, bookings) {
        final totalGuests = bookings.fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
        _guestCounts[date] = totalGuests;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickup Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMonthData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<PickupController>(
        builder: (context, controller, child) {
          if (controller.isLoading) {
            return const LoadingWidget(message: 'Loading pickup data...');
          }

          if (controller.hasError) {
            return CustomErrorWidget(
              message: controller.errorMessage,
              onRetry: _loadMonthData,
            );
          }

          return Column(
            children: [
              // Calendar Section
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  calendarFormat: CalendarFormat.month,
                  eventLoader: (day) {
                    final guestCount = _guestCounts[DateTime(day.year, day.month, day.day)];
                    return guestCount != null && guestCount > 0 ? [guestCount] : [];
                  },
                  calendarStyle: const CalendarStyle(
                    outsideDaysVisible: false,
                    weekendTextStyle: TextStyle(color: Colors.red),
                    holidayTextStyle: TextStyle(color: Colors.red),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    _showDayDetails(selectedDay);
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                    _loadMonthData();
                  },
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, date, events) {
                      if (events.isNotEmpty) {
                        final guestCount = events.first as int;
                        return Positioned(
                          bottom: 1,
                          right: 1,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              guestCount.toString(),
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
                  ),
                ),
              ),
              
              // Summary Section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Month Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryCard(
                          'Total Bookings',
                          controller.monthData.values.fold<int>(0, (sum, bookings) => sum + bookings.length).toString(),
                          Icons.calendar_today,
                          Colors.blue,
                        ),
                        _buildSummaryCard(
                          'Total Guests',
                          controller.monthData.values.fold<int>(0, (sum, bookings) => 
                            sum + bookings.fold<int>(0, (bookingSum, booking) => bookingSum + booking.numberOfGuests)
                          ).toString(),
                          Icons.people,
                          Colors.green,
                        ),
                        _buildSummaryCard(
                          'Days with Bookings',
                          controller.monthData.length.toString(),
                          Icons.event,
                          Colors.orange,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showDayDetails(DateTime date) {
    final controller = context.read<PickupController>();
    final bookings = controller.monthData[DateTime(date.year, date.month, date.day)] ?? [];
    
    if (bookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No bookings for ${date.day}/${date.month}/${date.year}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: bookings.length,
                itemBuilder: (context, index) {
                  final booking = bookings[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        booking.customerFullName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📍 ${booking.pickupPlaceName}'),
                          Text('🕐 ${_formatTime(booking.pickupTime)}'),
                          Text('👥 ${booking.numberOfGuests} guests'),
                          if (booking.phoneNumber.isNotEmpty)
                            Text('📞 ${booking.phoneNumber}'),
                          if (booking.email.isNotEmpty)
                            Text('📧 ${booking.email}'),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.no_transfer, color: Colors.red),
                        onPressed: () => _markAsNoShow(booking.id),
                        tooltip: 'Mark as No Show',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _markAsNoShow(String bookingId) {
    // TODO: Implement no-show functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No-show functionality coming soon!'),
        backgroundColor: Colors.orange,
      ),
    );
  }
} 