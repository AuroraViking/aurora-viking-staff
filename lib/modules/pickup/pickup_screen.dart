import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<PickupController>();
      controller.loadBookingsForDate(controller.selectedDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickup List'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
          ),
        ],
      ),
      body: Consumer<PickupController>(
        builder: (context, controller, child) {
          if (controller.isLoading) {
            return const LoadingWidget();
          }

          if (controller.error != null) {
            return CustomErrorWidget(
              message: controller.error!,
              onRetry: () => controller.loadBookingsForDate(controller.selectedDate),
            );
          }

          final currentUser = controller.currentUser;
          if (currentUser == null) {
            return const Center(
              child: Text('Please log in to view pickup lists'),
            );
          }

          final userBookings = controller.currentUserBookings;
          
          if (userBookings.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              _buildDateHeader(controller),
              _buildStatsCard(userBookings),
              Expanded(
                child: _buildBookingsList(userBookings, controller),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateHeader(PickupController controller) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.primary.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.calendar_today, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '${controller.selectedDate.day}/${controller.selectedDate.month}/${controller.selectedDate.year}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const Spacer(),
          Text(
            '${controller.currentUserBookings.length} pickups',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(List<PickupBooking> bookings) {
    final totalPassengers = bookings.fold(0, (sum, booking) => sum + booking.numberOfGuests);
    final noShows = bookings.where((booking) => booking.isNoShow).length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                'Total Guests',
                totalPassengers.toString(),
                Icons.people,
                AppColors.primary,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'Pickups',
                bookings.length.toString(),
                Icons.location_on,
                AppColors.secondary,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'No Shows',
                noShows.toString(),
                Icons.cancel,
                AppColors.error,
              ),
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
            fontSize: 20,
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
        ),
      ],
    );
  }

  Widget _buildBookingsList(List<PickupBooking> bookings, PickupController controller) {
    // Sort bookings by pickup time
    final sortedBookings = List<PickupBooking>.from(bookings)
      ..sort((a, b) => a.pickupTime.compareTo(b.pickupTime));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedBookings.length,
      itemBuilder: (context, index) {
        final booking = sortedBookings[index];
        return _buildBookingCard(booking, controller);
      },
    );
  }

  Widget _buildBookingCard(PickupBooking booking, PickupController controller) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          border: booking.isNoShow 
            ? Border.all(color: AppColors.error, width: 2)
            : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking.customerFullName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: booking.isNoShow ? AppColors.error : AppColors.textPrimary,
                        decoration: booking.isNoShow ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (booking.isNoShow)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'NO SHOW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.location_on, booking.pickupPlaceName),
              _buildInfoRow(Icons.access_time, _formatTime(booking.pickupTime)),
              _buildInfoRow(Icons.people, '${booking.numberOfGuests} guests'),
              _buildInfoRow(Icons.phone, booking.phoneNumber),
              _buildInfoRow(Icons.email, booking.email),
              const SizedBox(height: 12),
              if (!booking.isNoShow)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showNoShowDialog(booking, controller),
                    icon: const Icon(Icons.cancel),
                    label: const Text('Mark as No Show'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No pickups assigned',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You don\'t have any pickups assigned for this date',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _selectDate() async {
    final controller = context.read<PickupController>();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: controller.selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (selectedDate != null) {
      controller.changeDate(selectedDate);
    }
  }

  void _showNoShowDialog(PickupBooking booking, PickupController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as No Show'),
        content: Text(
          'Are you sure you want to mark ${booking.customerFullName} as a no-show?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await controller.markBookingAsNoShow(booking.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${booking.customerFullName} marked as no-show'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
} 