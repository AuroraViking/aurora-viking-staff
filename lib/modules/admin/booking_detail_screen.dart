// Booking Detail Screen - View and manage individual bookings
// Allows rescheduling and cancellation

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/services/firebase_service.dart';
import '../pickup/pickup_service.dart';
import 'booking_service.dart';

class BookingDetailScreen extends StatefulWidget {
  final Booking booking;
  final VoidCallback? onUpdated;

  const BookingDetailScreen({
    Key? key,
    required this.booking,
    this.onUpdated,
  }) : super(key: key);

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final BookingService _service = BookingService();
  bool _isLoading = false;
  late Booking _booking;
  String? _pickupFromFirebase; // Pickup loaded from Firebase (same as Pickup Management)

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    _loadPickupFromPickupService();
  }

  Future<void> _loadPickupFromPickupService() async {
    try {
      // Use PickupService like Pickup Management does - fetches from Bokun API
      final pickupService = PickupService();
      final bookings = await pickupService.fetchBookingsForDate(_booking.startDate);
      
      // Find the matching booking by ID or confirmation code
      for (final pb in bookings) {
        if (pb.bookingId == _booking.id || 
            pb.confirmationCode == _booking.confirmationCode ||
            pb.id == _booking.id) {
          if (pb.pickupPlaceName.isNotEmpty && mounted) {
            print('📍 Found pickup from PickupService: ${pb.pickupPlaceName}');
            setState(() {
              _pickupFromFirebase = pb.pickupPlaceName;
            });
            return;
          }
        }
      }
      print('ℹ️ No pickup found from PickupService for booking ${_booking.id}');
    } catch (e) {
      print('⚠️ Error loading pickup from PickupService: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_booking.confirmationCode.isNotEmpty 
            ? _booking.confirmationCode 
            : 'Booking #${_booking.id}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _booking.confirmationCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking code copied')),
              );
            },
            tooltip: 'Copy booking code',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildCustomerCard(),
                  const SizedBox(height: 16),
                  _buildBookingDetailsCard(),
                  const SizedBox(height: 16),
                  if (_booking.pickup != null) ...[
                    _buildPickupCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_booking.participants.isNotEmpty) ...[
                    _buildParticipantsCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_booking.notes != null && _booking.notes!.isNotEmpty) ...[
                    _buildNotesCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildActionsCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final statusColor = _booking.isConfirmed
        ? AppColors.success
        : _booking.isCancelled
            ? AppColors.error
            : AppColors.warning;

    return Card(
      color: statusColor.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _booking.isConfirmed
                    ? Icons.check_circle
                    : _booking.isCancelled
                        ? Icons.cancel
                        : Icons.pending,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _booking.statusDisplay,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Created ${DateFormat('MMM d, yyyy').format(_booking.createdAt)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_booking.totalPrice.toStringAsFixed(0)} ${_booking.currency}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_booking.totalParticipants} passenger${_booking.totalParticipants == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    // Use Firebase pickup first (same as Pickup Management), fallback to API pickup
    final pickupLocation = _pickupFromFirebase ?? _booking.pickup?.location;
    final hasPickup = pickupLocation != null && pickupLocation.isNotEmpty;
    
    return _buildCard(
      title: 'Customer',
      icon: Icons.person,
      children: [
        _buildInfoRow('Name', _booking.customer.fullName),
        if (_booking.customer.email.isNotEmpty)
          _buildInfoRow('Email', _booking.customer.email, copyable: true),
        if (_booking.customer.phone.isNotEmpty)
          _buildInfoRow('Phone', _booking.customer.phone, copyable: true),
        if (hasPickup)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pickup Location',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        Text(
                          pickupLocation!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                        if (_booking.pickup?.time != null && _booking.pickup!.time.isNotEmpty)
                          Text(
                            _booking.pickup!.time,
                            style: const TextStyle(color: AppColors.primary, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBookingDetailsCard() {
    return _buildCard(
      title: 'Booking Details',
      icon: Icons.confirmation_number,
      children: [
        _buildInfoRow('Product', _booking.productTitle),
        _buildInfoRow(
          'Date',
          DateFormat('EEEE, MMMM d, yyyy').format(_booking.startDate),
        ),
        if (_booking.confirmationCode.isNotEmpty)
          _buildInfoRow('Confirmation Code', _booking.confirmationCode, copyable: true),
        if (_booking.productId != null)
          _buildInfoRow('Product ID', _booking.productId!),
      ],
    );
  }

  Widget _buildPickupCard() {
    return _buildCard(
      title: 'Pickup',
      icon: Icons.location_on,
      children: [
        _buildInfoRow('Location', _booking.pickup!.location),
        if (_booking.pickup!.time.isNotEmpty)
          _buildInfoRow('Time', _booking.pickup!.time),
        if (_booking.pickup!.address.isNotEmpty)
          _buildInfoRow('Address', _booking.pickup!.address),
      ],
    );
  }

  Widget _buildParticipantsCard() {
    return _buildCard(
      title: 'Participants (${_booking.participants.length})',
      icon: Icons.people,
      children: [
        ...List.generate(_booking.participants.length, (index) {
          final p = _booking.participants[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.fullName.isNotEmpty ? p.fullName : 'Participant ${index + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    p.category,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNotesCard() {
    return _buildCard(
      title: 'Internal Notes',
      icon: Icons.note,
      children: [
        Text(
          _booking.notes!,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildActionsCard() {
    final canModify = _booking.isConfirmed;
    
    return Card(
      color: const Color(0xFF1A1A2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Actions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canModify ? _showRescheduleDialog : null,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Reschedule'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                      disabledForegroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canModify ? _showCancelDialog : null,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                      disabledForegroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            if (!canModify)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'This booking cannot be modified',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),
            // Change Pickup button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: canModify ? _showChangePickupDialog : null,
                icon: const Icon(Icons.location_on),
                label: const Text('Change Pickup Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      color: const Color(0xFF1A1A2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              color: Colors.white54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showRescheduleDialog() {
    DateTime selectedDate = _booking.startDate;
    final reasonController = TextEditingController();
    List<PickupPlace> pickupPlaces = [];
    PickupPlace? selectedPickup;
    bool loadingPickups = true;
    
    // Load pickup places
    void loadPickups(StateSetter setDialogState) async {
      try {
        // Extract productId from booking
        final productId = _booking.productId;
        print('🔍 DEBUG: Product ID = $productId');
        print('🔍 DEBUG: Booking ID = ${_booking.id}');
        
        if (productId != null && productId.isNotEmpty) {
          print('📍 Calling getPickupPlaces for product: $productId');
          final places = await _service.getPickupPlaces(productId);
          print('📍 Got ${places.length} pickup places');
          
          setDialogState(() {
            pickupPlaces = places;
            loadingPickups = false;
            // Pre-select current pickup if exists
            final currentPickup = _booking.pickup?.location;
            if (currentPickup != null && currentPickup.isNotEmpty) {
              selectedPickup = pickupPlaces.where((p) => 
                p.title.toLowerCase().contains(currentPickup.toLowerCase()) ||
                currentPickup.toLowerCase().contains(p.title.toLowerCase())
              ).firstOrNull;
            }
          });
        } else {
          print('⚠️ DEBUG: No productId found on booking!');
          setDialogState(() => loadingPickups = false);
        }
      } catch (e) {
        print('❌ Error loading pickups: $e');
        setDialogState(() => loadingPickups = false);
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Load pickups on first build
          if (loadingPickups && pickupPlaces.isEmpty) {
            loadPickups(setDialogState);
          }
          
          return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text(
            'Reschedule Booking',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current date: ${DateFormat('MMMM d, yyyy').format(_booking.startDate)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select new date:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TableCalendar(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: selectedDate,
                      selectedDayPredicate: (day) => isSameDay(selectedDate, day),
                      calendarFormat: CalendarFormat.month,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(color: Colors.white, fontSize: 14),
                        leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white, size: 20),
                        rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white, size: 20),
                      ),
                      calendarStyle: CalendarStyle(
                        defaultTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
                        weekendTextStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                        outsideDaysVisible: false,
                        todayDecoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(color: Colors.white54, fontSize: 10),
                        weekendStyle: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                      onDaySelected: (selected, focused) {
                        setDialogState(() {
                          selectedDate = selected;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Pickup dropdown
                  const Text(
                    'Pickup Location:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (loadingPickups)
                    const Center(child: CircularProgressIndicator())
                  else if (pickupPlaces.isEmpty)
                    Text(
                      'No pickup locations available',
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<PickupPlace>(
                          value: selectedPickup,
                          hint: const Text('Select pickup location', style: TextStyle(color: Colors.white54)),
                          dropdownColor: const Color(0xFF1A1A2E),
                          isExpanded: true,
                          items: pickupPlaces.map((place) => DropdownMenuItem(
                            value: place,
                            child: Text(place.title, style: const TextStyle(color: Colors.white)),
                          )).toList(),
                          onChanged: (value) {
                            setDialogState(() => selectedPickup = value);
                          },
                        ),
                      ),
                    ),
                  if (_booking.pickup?.location != null && _booking.pickup!.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Current: ${_booking.pickup?.location}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Reason for reschedule',
                      labelStyle: const TextStyle(color: Colors.white54),
                      hintText: 'e.g., Customer requested change',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSameDay(selectedDate, _booking.startDate)
                  ? null
                  : () {
                      Navigator.pop(context);
                      _executeReschedule(
                        selectedDate, 
                        reasonController.text,
                        pickupPlaceId: selectedPickup?.id,
                        pickupPlaceName: selectedPickup?.title,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Reschedule'),
            ),
          ],
        );
        },
      ),
    );
  }

  void _showChangePickupDialog() {
    List<PickupPlace> pickupPlaces = [];
    PickupPlace? selectedPickup;
    bool loadingPickups = true;
    bool isUpdating = false;
    
    void loadPickups(StateSetter setDialogState) async {
      try {
        final productId = _booking.productId;
        if (productId != null && productId.isNotEmpty) {
          final places = await _service.getPickupPlaces(productId);
          setDialogState(() {
            pickupPlaces = places;
            loadingPickups = false;
          });
        } else {
          setDialogState(() => loadingPickups = false);
        }
      } catch (e) {
        print('Error loading pickups: $e');
        setDialogState(() => loadingPickups = false);
      }
    }
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (loadingPickups && pickupPlaces.isEmpty) {
            loadPickups(setDialogState);
          }
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('Change Pickup Location', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_booking.pickup?.location != null) ...[
                  Text(
                    'Current: ${_booking.pickup?.location}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Select new pickup:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (loadingPickups)
                  const Center(child: CircularProgressIndicator())
                else if (pickupPlaces.isEmpty)
                  const Text('No pickup locations available', style: TextStyle(color: Colors.white54))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<PickupPlace>(
                        value: selectedPickup,
                        hint: const Text('Select pickup location', style: TextStyle(color: Colors.white54)),
                        dropdownColor: const Color(0xFF1A1A2E),
                        isExpanded: true,
                        items: pickupPlaces.map((place) => DropdownMenuItem(
                          value: place,
                          child: Text(place.title, style: const TextStyle(color: Colors.white)),
                        )).toList(),
                        onChanged: (value) => setDialogState(() => selectedPickup = value),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isUpdating ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedPickup == null || isUpdating
                    ? null
                    : () async {
                        setDialogState(() => isUpdating = true);
                        try {
                          await _service.updatePickupLocation(
                            bookingId: _booking.id,
                            pickupPlaceId: selectedPickup!.id,
                            pickupPlaceName: selectedPickup!.title,
                          );
                          Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Pickup updated to ${selectedPickup!.title}'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                            widget.onUpdated?.call();
                          }
                        } catch (e) {
                          setDialogState(() => isUpdating = false);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update pickup: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: isUpdating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Update Pickup'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCancelDialog() {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 8),
            Text('Cancel Booking', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel booking ${_booking.confirmationCode}?',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'This action may not be reversible.',
              style: TextStyle(color: AppColors.error),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason for cancellation *',
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'e.g., Customer requested cancellation',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep Booking'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason for cancellation'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.pop(context);
              _executeCancel(reasonController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeReschedule(
    DateTime newDate, 
    String reason, {
    int? pickupPlaceId,
    String? pickupPlaceName,
  }) async {
    setState(() => _isLoading = true);
    
    try {
      await _service.rescheduleBooking(
        bookingId: _booking.id,
        confirmationCode: _booking.confirmationCode,
        newDate: newDate,
        reason: reason.isNotEmpty ? reason : 'Rescheduled via admin app',
        pickupPlaceId: pickupPlaceId,
        pickupPlaceName: pickupPlaceName,
      );
      
      if (mounted) {
        // Check if manual action is required
        final portalLink = _service.getLastReschedulePortalLink();
        final availabilityConfirmed = _service.getLastRescheduleAvailabilityConfirmed();
        
        if (portalLink != null) {
          // Show dialog with portal link
          setState(() => _isLoading = false);
          _showManualActionDialog(newDate, portalLink, availabilityConfirmed);
        } else {
          // Fully completed
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Booking rescheduled to ${DateFormat('MMM d, yyyy').format(newDate)}',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          
          widget.onUpdated?.call();
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reschedule: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showManualActionDialog(DateTime newDate, String portalLink, bool availabilityConfirmed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            Icon(
              availabilityConfirmed ? Icons.check_circle : Icons.info,
              color: availabilityConfirmed ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Complete in Bokun',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (availabilityConfirmed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Availability CONFIRMED for ${DateFormat('MMM d').format(newDate)}',
                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'Due to Bokun API limitations, please complete this reschedule in the Bokun portal:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'Steps:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Open the Bokun portal link below\n'
              '2. Click "Edit Booking"\n'
              '3. Change the date to the new date\n'
              '4. Confirm the changes',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onUpdated?.call();
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Open Bokun portal
              final uri = Uri.parse(portalLink);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Bokun'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeCancel(String reason) async {
    setState(() => _isLoading = true);
    
    try {
      await _service.cancelBooking(
        bookingId: _booking.id,
        confirmationCode: _booking.confirmationCode,
        reason: reason,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking cancelled successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        
        widget.onUpdated?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
