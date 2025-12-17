import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../core/theme/colors.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/pickup_models.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import 'pickup_controller.dart';

class PickupScreen extends StatefulWidget {
  const PickupScreen({Key? key}) : super(key: key);

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  // Timer state for no-show countdowns (bookingId -> Timer)
  final Map<String, Timer> _noShowTimers = {};
  final Map<String, int> _noShowTimeRemaining = {}; // bookingId -> seconds remaining

  // FIX: Track initialization state
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // FIX: Use post-frame callback to ensure context is fully available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndLoad();
    });
  }

  @override
  void dispose() {
    // Cancel all timers
    for (final timer in _noShowTimers.values) {
      timer.cancel();
    }
    _noShowTimers.clear();
    _noShowTimeRemaining.clear();
    super.dispose();
  }

  // FIX: Better initialization with retry logic
  Future<void> _initializeAndLoad() async {
    if (!mounted) return;

    final authController = context.read<AuthController>();
    final pickupController = context.read<PickupController>();

    // FIX: Wait for auth to be ready if it's still loading
    int retries = 0;
    while (authController.isLoading && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      retries++;
      if (!mounted) return;
    }

    // FIX: Check if we have a valid user
    if (authController.currentUser == null) {
      print('⚠️ PickupScreen: No authenticated user found');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      return;
    }

    // Set the current user in the pickup controller
    pickupController.setCurrentUser(authController.currentUser!);

    // Load bookings
    await pickupController.loadBookingsForDate(DateTime.now());

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _loadTodayBookings() {
    final controller = context.read<PickupController>();
    final authController = context.read<AuthController>();

    // FIX: Guard against null user
    if (authController.currentUser == null) {
      print('⚠️ Cannot load bookings: user not authenticated');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to view your pickup list'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Set the current user in the pickup controller
    controller.setCurrentUser(authController.currentUser!);
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
      body: Consumer2<PickupController, AuthController>(
        builder: (context, controller, authController, child) {
          // FIX: Check auth state first
          if (authController.currentUser == null) {
            return _buildNotAuthenticatedState();
          }

          // FIX: Show loading only during actual loading, not initialization
          if (!_isInitialized || controller.isLoading) {
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

          // Stop timers for bookings that are no longer marked as no-show
          final noShowBookingIds = bookings.where((b) => b.isNoShow).map((b) => b.id).toSet();
          _noShowTimers.keys.toList().forEach((id) {
            if (!noShowBookingIds.contains(id)) {
              _stopNoShowTimer(id);
            }
          });

          return Column(
            children: [
              // Summary card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Date', '${selectedDate.day}/${selectedDate.month}'),
                    _buildStat('Pickups', '${bookings.length}'),
                    _buildStat('Picked Up', '$pickedUpGuests / $totalGuests'),
                  ],
                ),
              ),

              // FIX: Better empty state handling
              Expanded(
                child: bookings.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                  onRefresh: () async {
                    await _refreshData();
                  },
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: bookings.length,
                    onReorder: (oldIndex, newIndex) {
                      // Adjust newIndex for the removal
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }

                      final reorderedBookings = List<PickupBooking>.from(bookings);
                      final item = reorderedBookings.removeAt(oldIndex);
                      reorderedBookings.insert(newIndex, item);

                      controller.updateCurrentUserBookingsOrder(reorderedBookings);
                    },
                    itemBuilder: (context, index) {
                      final booking = bookings[index];
                      return Card(
                        key: ValueKey(booking.id),
                        margin: const EdgeInsets.only(bottom: 4),
                        color: const Color(0xFF2D3748),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pickup place and customer name in one row
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          booking.pickupPlaceName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          booking.customerFullName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            decoration: booking.isNoShow ? TextDecoration.lineThrough : null,
                                            color: booking.isNoShow ? AppColors.error : Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Arrived checkbox (compact)
                                  Checkbox(
                                    value: booking.isArrived,
                                    onChanged: (value) => _markAsArrived(booking.id, value ?? false),
                                    activeColor: AppColors.success,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 4),

                              // Guest count and contact buttons in one row
                              Row(
                                children: [
                                  Icon(Icons.group, size: 14, color: Colors.white54),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${booking.numberOfGuests}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                  const Spacer(),
                                  // Phone button
                                  if (booking.phoneNumber.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.phone, size: 16),
                                      color: AppColors.success,
                                      onPressed: () => _makePhoneCall(booking.phoneNumber),
                                      tooltip: 'Call',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  // Email button
                                  if (booking.email.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.email, size: 16),
                                      color: AppColors.info,
                                      onPressed: () => _sendArrivalEmail(booking),
                                      tooltip: 'Email',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),

                              // No-show button (compact)
                              if (booking.isNoShow && _noShowTimeRemaining.containsKey(booking.id))
                                _buildNoShowTimer(booking)
                              else if (booking.isNoShow)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TextButton(
                                    onPressed: () => _unmarkNoShow(booking.id),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 24),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Undo No-Show', style: TextStyle(color: Colors.orange, fontSize: 11)),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TextButton(
                                    onPressed: () => _showNoShowDialog(booking),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 24),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('No-Show', style: TextStyle(color: AppColors.error, fontSize: 11)),
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

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  // FIX: Improved empty state with more helpful messaging
  Widget _buildEmptyState() {
    final authController = context.read<AuthController>();
    final userName = authController.currentUser?.fullName ?? 'there';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.directions_bus_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'Hey $userName! 👋',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No pickups assigned to you today.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'If you expect to have pickups, please check with your admin.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTodayBookings,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FIX: New widget for not authenticated state
  Widget _buildNotAuthenticatedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'Not Logged In',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please log in to view your pickup list.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoShowTimer(PickupBooking booking) {
    final remaining = _noShowTimeRemaining[booking.id] ?? 0;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '⏱️ Leaving in: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: () => _unmarkNoShow(booking.id),
            child: const Text('Cancel', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _markAsArrived(String bookingId, bool arrived) {
    final controller = context.read<PickupController>();
    controller.markBookingAsArrived(bookingId, arrived);

    if (arrived) {
      // Stop no-show timer if customer arrives
      _stopNoShowTimer(bookingId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer marked as arrived ✅'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _startNoShowTimer(String bookingId, String customerName, String pickupPlace) {
    // Stop any existing timer
    _stopNoShowTimer(bookingId);

    // Set 3 minutes (180 seconds)
    setState(() {
      _noShowTimeRemaining[bookingId] = 180;
    });

    // Start countdown timer
    _noShowTimers[bookingId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        final remaining = (_noShowTimeRemaining[bookingId] ?? 0) - 1;
        if (remaining <= 0) {
          // Timer finished
          timer.cancel();
          _noShowTimers.remove(bookingId);
          _noShowTimeRemaining.remove(bookingId);

          // Show notification that driver can leave
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⏰ Time\'s up! You can leave $pickupPlace'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        } else {
          _noShowTimeRemaining[bookingId] = remaining;
        }
      });
    });
  }

  void _stopNoShowTimer(String bookingId) {
    _noShowTimers[bookingId]?.cancel();
    _noShowTimers.remove(bookingId);
    setState(() {
      _noShowTimeRemaining.remove(bookingId);
    });
  }

  void _showNoShowDialog(PickupBooking booking) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as No-Show?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer: ${booking.customerFullName}'),
            Text('Location: ${booking.pickupPlaceName}'),
            const SizedBox(height: 12),
            if (booking.email.isNotEmpty)
              const Text(
                'An email will be sent to the customer informing them that:\n\n• Their phone has been called\n• The driver will wait 3 minutes before leaving',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              )
            else
              const Text(
                'Note: No email will be sent (customer email not available)',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final controller = context.read<PickupController>();

              // Mark as no-show
              final success = await controller.markBookingAsNoShow(booking.id);

              if (success && mounted) {
                // Start 3-minute timer
                _startNoShowTimer(booking.id, booking.customerFullName, booking.pickupPlaceName);

                // Send email if email is available
                if (booking.email.isNotEmpty) {
                  await _sendNoShowEmail(booking);
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(booking.email.isNotEmpty
                        ? 'Customer marked as no-show. Email sent. 3-minute timer started.'
                        : 'Customer marked as no-show. 3-minute timer started.'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
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

  void _unmarkNoShow(String bookingId) {
    // Stop the timer if running
    _stopNoShowTimer(bookingId);

    final controller = context.read<PickupController>();
    controller.markBookingAsNoShow(bookingId, isNoShow: false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No-show status removed. Timer cancelled.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _sendNoShowEmail(PickupBooking booking) async {
    try {
      final authController = context.read<AuthController>();
      final guideName = authController.currentUser?.fullName ?? 'Your Guide';
      final pickupPlace = booking.pickupPlaceName;
      final phoneNumber = booking.phoneNumber.isNotEmpty ? booking.phoneNumber : 'your phone number';
      final customerName = booking.customerFullName;

      // Encode subject and body properly
      final subject = Uri.encodeComponent('Pickup Notice - $customerName');
      final body = Uri.encodeComponent(
        'Hi $customerName,\n\n'
        'This is an automated message from your tour guide ($guideName).\n\n'
        'I have arrived at the pickup location: $pickupPlace\n\n'
        'I have tried calling $phoneNumber but was unable to reach you.\n\n'
        'Please note that I will wait for 3 minutes before departing.\n\n'
        'If you are nearby, please hurry to the pickup point.\n\n'
        'Thank you.'
      );

      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: booking.email,
        query: 'subject=$subject&body=$body',
      );

      final launched = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open email app. Please send email manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        print('✅ Email app launched successfully');
      }
    } catch (e) {
      print('❌ Error sending no-show email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending email: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _makePhoneCall(String phoneNumber) async {
    try {
      print('📞 Attempting to call: $phoneNumber');

      // Clean the phone number
      String cleanedNumber = phoneNumber.trim().replaceAll(RegExp(r'[^\d+]'), '');

      print('📞 Cleaned phone number: $cleanedNumber');

      if (cleanedNumber.isEmpty) {
        print('❌ Phone number is empty after cleaning');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid phone number format'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final Uri phoneUri = Uri(scheme: 'tel', path: cleanedNumber);

      final launched = await launchUrl(
        phoneUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch phone app.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error making phone call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making call: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _sendArrivalEmail(PickupBooking booking) async {
    try {
      final authController = context.read<AuthController>();
      final guideName = authController.currentUser?.fullName ?? 'Your Guide';
      final pickupPlace = booking.pickupPlaceName;
      final phoneNumber = booking.phoneNumber.isNotEmpty ? booking.phoneNumber : 'your phone number';
      final customerName = booking.customerFullName;

      // Encode subject and body properly
      final subject = Uri.encodeComponent('Pickup Arrival - $customerName');
      final body = Uri.encodeComponent(
        'Hi $customerName,\n\n'
        'This is an automated message from your tour guide ($guideName).\n\n'
        'I have arrived at the pickup location: $pickupPlace\n\n'
        'I have tried calling $phoneNumber but was unable to reach you.\n\n'
        'Please note that I will wait for 3 minutes before departing.\n\n'
        'If you are nearby, please hurry to the pickup point.\n\n'
        'Thank you.'
      );
      
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: booking.email,
        query: 'subject=$subject&body=$body',
      );

      final launched = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch email app'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error sending email: $e');
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

    // FIX: Guard against null user
    if (authController.currentUser == null) {
      print('⚠️ Cannot refresh: user not authenticated');
      return;
    }

    // Set the current user in the pickup controller
    controller.setCurrentUser(authController.currentUser!);

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
      // FIX: Guard against null user
      if (authController.currentUser == null) {
        print('⚠️ Cannot select date: user not authenticated');
        return;
      }

      // Set the current user in the pickup controller
      controller.setCurrentUser(authController.currentUser!);

      await controller.loadBookingsForDate(selectedDate);
    }
  }
}