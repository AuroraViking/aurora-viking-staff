import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/auth/auth_controller.dart';
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
    _loadTodayBookings();
  }

  void _loadTodayBookings() {
    final controller = context.read<PickupController>();
    final authController = context.read<AuthController>();
    
    // Set the current user in the pickup controller
    if (authController.currentUser != null) {
      controller.setCurrentUser(authController.currentUser!);
    }
    
    controller.loadBookingsForDate(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pickup List'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(),
            tooltip: 'Select date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodayBookings,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<PickupController>(
        builder: (context, controller, child) {
          if (controller.isLoading) {
            return const LoadingWidget(message: 'Loading your pickup list...');
          }

          if (controller.hasError) {
            return CustomErrorWidget(
              message: controller.errorMessage,
              onRetry: _loadTodayBookings,
            );
          }

          final selectedDate = controller.selectedDate;
          final bookings = controller.currentUserBookings;
          final totalGuests = bookings.fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
          final pickedUpGuests = bookings.where((booking) => booking.isArrived).fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);

          return Column(
            children: [
              // Date Header with Stats
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    // Date row
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: AppColors.primary, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        if (selectedDate.day == DateTime.now().day &&
                            selectedDate.month == DateTime.now().month &&
                            selectedDate.year == DateTime.now().year)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'TODAY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Stats row
                    if (bookings.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Guests',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '$totalGuests',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Picked Up',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '$pickedUpGuests of $totalGuests',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: pickedUpGuests == totalGuests ? AppColors.success : AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pickups',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '${bookings.length}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'No pickups assigned for this date',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Pickup List
              Expanded(
                child: bookings.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _refreshData();
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: bookings.length,
                        itemBuilder: (context, index) {
                        final booking = bookings[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Pickup place at the top (bold)
                                Text(
                                  booking.pickupPlaceName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.primary,
                                  ),
                                ),
                                
                                const SizedBox(height: 4),
                                
                                // Customer name with arrived button and action buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        booking.customerFullName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          decoration: booking.isNoShow ? TextDecoration.lineThrough : null,
                                          color: booking.isNoShow ? AppColors.error : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    
                                    // Arrived checkbox
                                    Row(
                                      children: [
                                        Checkbox(
                                          value: booking.isArrived,
                                          onChanged: (value) => _markAsArrived(booking.id, value ?? false),
                                          activeColor: AppColors.primary,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        const Text(
                                          'Arrived',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    
                                    // Action buttons
                                    if (booking.phoneNumber.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.call, color: Colors.green, size: 18),
                                        onPressed: () => _makePhoneCall(booking.phoneNumber),
                                        tooltip: 'Call customer',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    
                                    // No show button (only if not arrived)
                                    if (!booking.isArrived)
                                      IconButton(
                                        icon: const Icon(Icons.no_transfer, color: Colors.red, size: 18),
                                        onPressed: () => _markAsNoShow(booking.id),
                                        tooltip: 'Mark as No Show',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                                
                                const SizedBox(height: 4),
                                
                                // Time and guest count on same line
                                Text(
                                  '${_formatTime(booking.pickupTime)} - ${booking.numberOfGuests} guest${booking.numberOfGuests > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                
                                // Phone number (if available)
                                if (booking.phoneNumber.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    booking.phoneNumber,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                
                                // Status indicators
                                if (booking.isNoShow || booking.isArrived)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        if (booking.isNoShow)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.error,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'NO SHOW',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        else if (booking.isArrived)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.success,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'ARRIVED',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                

                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
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
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Pickups Assigned',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You don\'t have any pickups assigned for today',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
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

  void _markAsArrived(String bookingId, bool arrived) {
    final controller = context.read<PickupController>();
    controller.markBookingAsArrived(bookingId, arrived);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(arrived ? 'Customer marked as arrived' : 'Arrival status removed'),
          backgroundColor: arrived ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  void _markAsNoShow(String bookingId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as No Show'),
        content: const Text('Are you sure you want to mark this customer as a no-show?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final controller = context.read<PickupController>();
              final success = await controller.markBookingAsNoShow(bookingId);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Customer marked as no-show'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not launch phone app'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _sendArrivalEmail(String email, String customerName) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Pickup Arrival - ${customerName}&body=Hi ${customerName},\n\nI have arrived at the pickup location but cannot find you. Please contact me as soon as possible.\n\nBest regards,\nYour Guide',
    );
    
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not launch email app'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshData() async {
    final controller = context.read<PickupController>();
    final authController = context.read<AuthController>();
    
    // Set the current user in the pickup controller
    if (authController.currentUser != null) {
      controller.setCurrentUser(authController.currentUser!);
    }
    
    await controller.loadBookingsForDate(controller.selectedDate);
  }

  Future<void> _selectDate() async {
    final controller = context.read<PickupController>();
    final authController = context.read<AuthController>();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: controller.selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (selectedDate != null) {
      // Set the current user in the pickup controller
      if (authController.currentUser != null) {
        controller.setCurrentUser(authController.currentUser!);
      }
      
      await controller.loadBookingsForDate(selectedDate);
    }
  }
} 