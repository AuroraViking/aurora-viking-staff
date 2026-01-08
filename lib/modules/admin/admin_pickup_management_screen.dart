import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
import '../../core/theme/colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import '../pickup/pickup_controller.dart';
import 'admin_service.dart';
import '../../core/models/admin_models.dart';
import '../../core/services/firebase_service.dart'; // Added import for FirebaseService
import '../../core/services/bus_management_service.dart';

class AdminPickupManagementScreen extends StatefulWidget {
  const AdminPickupManagementScreen({Key? key}) : super(key: key);

  @override
  State<AdminPickupManagementScreen> createState() => _AdminPickupManagementScreenState();
}

class _AdminPickupManagementScreenState extends State<AdminPickupManagementScreen> with SingleTickerProviderStateMixin {
  List<AdminGuide> _guides = [];
  bool _isLoadingGuides = false;
  late TabController _tabController;
  
  // State to track reordered booking lists for each guide
  Map<String, List<PickupBooking>> _reorderedBookings = {};
  
  // State to track bus assignments for each guide
  Map<String, Map<String, String>> _busAssignments = {}; // guideId -> {busId, busName}
  List<Map<String, dynamic>> _availableBuses = [];
  final BusManagementService _busService = BusManagementService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<PickupController>();
      // Force refresh on initial load to ensure fresh data
      await controller.loadBookingsForDate(controller.selectedDate, forceRefresh: true);
      await _loadGuides();
      await _loadBuses();
      await _loadBusAssignments(controller);
      
      // Load reordered bookings from Firebase after data is loaded
      await _updateReorderedBookings(controller);
      
      // Add listener to reset reordered bookings when data changes
      controller.addListener(_onControllerDataChanged);
    });
  }

  @override
  void dispose() {
    final controller = context.read<PickupController>();
    controller.removeListener(_onControllerDataChanged);
    _tabController.dispose();
    super.dispose();
  }

  bool _isLoadingAssignments = false;
  
  void _onControllerDataChanged() {
    // Update reordered bookings when assignments change, but preserve custom order
    if (mounted) {
      final controller = context.read<PickupController>();
      
      // Only update if we have bookings - don't clear on empty data
      if (controller.bookings.isNotEmpty || _reorderedBookings.isNotEmpty) {
        // Update existing reordered lists with new assignment data
        _updateReorderedBookings(controller); // Now async, but we don't await it
        
        // Also reload bus assignments when data changes, but only if not already loading
        if (!_isLoadingAssignments) {
          _loadBusAssignments(controller); // Now async, but we don't await it
        }
      }
    }
  }

  // Update reordered bookings with new assignment data while preserving custom order
  Future<void> _updateReorderedBookings(PickupController controller) async {
    // Don't update if we have no bookings - might be a temporary API issue
    if (controller.bookings.isEmpty && _reorderedBookings.isNotEmpty) {
      print('⚠️ Controller has no bookings but we have reordered lists. Preserving existing order.');
      return;
    }
    
    final updatedReorderedBookings = <String, List<PickupBooking>>{};
    
    for (final guideList in controller.guideLists) {
      final existingReorderedList = _reorderedBookings[guideList.guideId];
      
      if (existingReorderedList != null && guideList.bookings.isNotEmpty) {
        // Preserve custom order but update booking data
        final updatedList = <PickupBooking>[];
        final processedIds = <String>{};
        
        // First, update existing bookings in their current order
        for (final reorderedBooking in existingReorderedList) {
          final updatedBooking = guideList.bookings.firstWhere(
            (booking) => booking.id == reorderedBooking.id,
            orElse: () => reorderedBooking,
          );
          // Only add if it still exists in the guide list
          if (guideList.bookings.any((b) => b.id == updatedBooking.id)) {
            updatedList.add(updatedBooking);
            processedIds.add(updatedBooking.id);
          }
        }
        
        // Then, add any new bookings that weren't in the reordered list (at the end)
        for (final booking in guideList.bookings) {
          if (!processedIds.contains(booking.id)) {
            updatedList.add(booking);
          }
        }
        
        if (updatedList.isNotEmpty) {
          updatedReorderedBookings[guideList.guideId] = updatedList;
        }
      } else if (guideList.bookings.isNotEmpty) {
        // Only initialize if we don't have an existing list - load from Firebase first
        if (!_reorderedBookings.containsKey(guideList.guideId)) {
          // Try to load from Firebase first
          final dateStr = '${controller.selectedDate.year}-${controller.selectedDate.month.toString().padLeft(2, '0')}-${controller.selectedDate.day.toString().padLeft(2, '0')}';
          final savedBookingIds = await FirebaseService.getReorderedBookings(
            guideId: guideList.guideId,
            date: dateStr,
          );
          
          if (savedBookingIds.isNotEmpty) {
            // Reconstruct list from saved order
            final reorderedList = <PickupBooking>[];
            for (final bookingId in savedBookingIds) {
              try {
                final booking = guideList.bookings.firstWhere(
                  (b) => b.id == bookingId,
                );
                reorderedList.add(booking);
              } catch (e) {
                // Booking not found, skip it
                print('⚠️ Booking $bookingId not found in guide list, skipping');
              }
            }
            
            // Add any new bookings that weren't in the saved order
            for (final booking in guideList.bookings) {
              if (!savedBookingIds.contains(booking.id)) {
                reorderedList.add(booking);
              }
            }
            
            print('🔄 Loaded saved reordered list from Firebase for guide ${guideList.guideName}: ${reorderedList.length} bookings');
            updatedReorderedBookings[guideList.guideId] = reorderedList;
          } else {
            // No saved order, create new sorted list
            final sortedList = List<PickupBooking>.from(guideList.bookings)
              ..sort((a, b) => a.pickupPlaceName.compareTo(b.pickupPlaceName));
            updatedReorderedBookings[guideList.guideId] = sortedList;
            print('🔄 Created new sorted list for guide ${guideList.guideName}: ${sortedList.length} bookings');
          }
        } else {
          // Keep existing list
          updatedReorderedBookings[guideList.guideId] = _reorderedBookings[guideList.guideId]!;
        }
      }
    }
    
    // Only update if we have changes
    if (updatedReorderedBookings.isNotEmpty) {
      setState(() {
        // Merge with existing to preserve lists that weren't updated
        _reorderedBookings.addAll(updatedReorderedBookings);
      });
      
      print('🔄 Updated reordered bookings for ${updatedReorderedBookings.length} guides');
    }
  }

  Future<void> _loadGuides() async {
    setState(() {
      _isLoadingGuides = true;
    });

    try {
      final guides = await AdminService.getGuides();
      setState(() {
        _guides = guides;
        _isLoadingGuides = false;
        // Only reset reordered bookings when guides are actually reloaded
        // This happens when the admin service is called, not on every data change
        _resetReorderedBookings();
      });
    } catch (e) {
      setState(() {
        _isLoadingGuides = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load guides: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Load available buses
  Future<void> _loadBuses() async {
    try {
      final busesStream = _busService.getActiveBuses();
      busesStream.listen((buses) {
        if (mounted) {
          setState(() {
            _availableBuses = buses;
          });
        }
      });
    } catch (e) {
      print('❌ Error loading buses: $e');
    }
  }

  // Load bus assignments for all guides on the selected date
  Future<void> _loadBusAssignments(PickupController controller) async {
    // Prevent multiple simultaneous loads
    if (_isLoadingAssignments) {
      print('⚠️ Already loading assignments, skipping...');
      return;
    }
    
    _isLoadingAssignments = true;
    
    try {
      final dateStr = '${controller.selectedDate.year}-${controller.selectedDate.month.toString().padLeft(2, '0')}-${controller.selectedDate.day.toString().padLeft(2, '0')}';
      final assignments = <String, Map<String, String>>{};
      
      print('🔍 Loading bus assignments for date $dateStr');
      print('📋 Guide lists count: ${controller.guideLists.length}');
      
      // Wait a bit to ensure guide lists are populated
      if (controller.guideLists.isEmpty) {
        print('⚠️ No guide lists yet, waiting...');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      for (final guideList in controller.guideLists) {
        print('🔍 Checking assignment for guide ${guideList.guideName} (${guideList.guideId})');
        try {
          final assignment = await FirebaseService.getBusAssignmentForGuide(
            guideId: guideList.guideId,
            date: dateStr,
          );
          print('📋 Assignment result for ${guideList.guideName}: $assignment');
          if (assignment != null && assignment['busId']!.isNotEmpty) {
            assignments[guideList.guideId] = assignment;
            print('✅ Loaded assignment: ${guideList.guideName} -> ${assignment['busName']}');
          } else {
            print('⚠️ No assignment found for ${guideList.guideName}');
          }
        } catch (e) {
          // Handle permission errors gracefully
          if (e.toString().contains('permission') || e.toString().contains('PERMISSION_DENIED')) {
            print('⚠️ Permission denied for guide ${guideList.guideName}, skipping...');
            // Don't fail completely, just skip this guide
            continue;
          } else {
            print('❌ Error loading assignment for ${guideList.guideName}: $e');
          }
        }
      }
      
      print('✅ Loaded ${assignments.length} bus assignments total');
      
      if (mounted) {
        setState(() {
          _busAssignments = assignments;
        });
      }
    } catch (e) {
      print('❌ Error loading bus assignments: $e');
    } finally {
      _isLoadingAssignments = false;
    }
  }

  // Assign bus to guide
  Future<void> _assignBusToGuide(String guideId, String guideName, String? busId, String? busName, PickupController controller) async {
    try {
      final dateStr = '${controller.selectedDate.year}-${controller.selectedDate.month.toString().padLeft(2, '0')}-${controller.selectedDate.day.toString().padLeft(2, '0')}';
      
      print('💾 Saving bus assignment: guide=$guideName ($guideId), bus=$busName ($busId), date=$dateStr');
      
      if (busId == null || busId.isEmpty) {
        // Remove assignment
        print('🗑️ Removing bus assignment for guide $guideName');
        await FirebaseService.removeBusGuideAssignment(
          guideId: guideId,
          date: dateStr,
        );
        if (mounted) {
          setState(() {
            _busAssignments.remove(guideId);
          });
        }
        print('✅ Bus assignment removed');
      } else {
        // Save assignment
        print('💾 Saving bus assignment to Firebase...');
        await FirebaseService.saveBusGuideAssignment(
          guideId: guideId,
          guideName: guideName,
          busId: busId,
          busName: busName ?? 'Unknown Bus',
          date: dateStr,
        );
        print('✅ Bus assignment saved to Firebase');
        
        if (mounted) {
          setState(() {
            _busAssignments[guideId] = {
              'busId': busId,
              'busName': busName ?? 'Unknown Bus',
            };
          });
          print('✅ Local state updated: ${_busAssignments[guideId]}');
        }
        
        // Verify the save by reloading
        print('🔍 Verifying save by reloading assignment...');
        await Future.delayed(const Duration(milliseconds: 500));
        final verification = await FirebaseService.getBusAssignmentForGuide(
          guideId: guideId,
          date: dateStr,
        );
        print('📋 Verification result: $verification');
      }
    } catch (e) {
      print('❌ Error assigning bus to guide: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign bus: $e')),
        );
      }
    }
  }

  // Reset reordered bookings when data changes - but only if really necessary
  void _resetReorderedBookings() {
    // Don't clear if we have existing reordered lists - preserve user's custom order
    // Only clear if we're actually reloading guides (which shouldn't happen often)
    print('🔄 Guides reloaded, but preserving existing reordered bookings');
    // Don't clear - let _updateReorderedBookings handle it
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
            icon: const Icon(Icons.add),
            onPressed: () => _showManualBookingDialog(context.read<PickupController>()),
            tooltip: 'Add Manual Booking',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _autoDistribute,
            tooltip: 'Auto Distribute',
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
              onRetry: () => controller.loadBookingsForDate(controller.selectedDate, forceRefresh: true),
            );
          }

          return Column(
            children: [
              _buildDateHeader(controller),
              _buildStatsCard(controller),
              _buildTabBar(),
              Expanded(
                child: _buildTabView(controller),
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
            '${controller.bookings.fold<int>(0, (sum, booking) => sum + booking.numberOfGuests)} total guests',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(PickupController controller) {
    final stats = controller.stats;
    if (stats == null) return const SizedBox.shrink();

    // Calculate guest counts
    final totalGuests = controller.bookings.fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
    final assignedGuests = controller.bookings
        .where((booking) => booking.assignedGuideId != null)
        .fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
    final unassignedGuests = controller.bookings
        .where((booking) => booking.assignedGuideId == null)
        .fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
    final noShowGuests = controller.bookings
        .where((booking) => booking.isNoShow)
        .fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);

    return Card(
      margin: const EdgeInsets.all(16),
      color: const Color(0xFF1A1A2E), // Dark background for better contrast
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                'Total Guests',
                '$totalGuests',
                Icons.people,
                AppColors.primary,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'Assigned Guests',
                '$assignedGuests',
                Icons.check_circle,
                AppColors.success,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'Unassigned Guests',
                '$unassignedGuests',
                Icons.pending,
                AppColors.warning,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'No Show Guests',
                '$noShowGuests',
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
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.7),
        indicatorColor: Colors.white,
        tabs: const [
          Tab(text: 'Unassigned'),
          Tab(text: 'Guide Lists'),
        ],
      ),
    );
  }

  Widget _buildTabView(PickupController controller) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildUnassignedTab(controller),
        _buildGuideListsTab(controller),
      ],
    );
  }

  Widget _buildUnassignedTab(PickupController controller) {
    final unassignedBookings = controller.unassignedBookings;
    
    // Group bookings by pickup place
    final bookingsByPlace = <String, List<PickupBooking>>{};
    for (final booking in unassignedBookings) {
      final place = booking.pickupPlaceName;
      bookingsByPlace.putIfAbsent(place, () => []).add(booking);
    }
    
    // Sort pickup places alphabetically
    final sortedPlaces = bookingsByPlace.keys.toList()..sort();
    
    return RefreshIndicator(
      onRefresh: () async {
        await _refreshData(controller);
        // Reload reordered bookings from Firebase after refresh
        await _updateReorderedBookings(controller);
      },
      child: unassignedBookings.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 100),
                Center(
                  child: Text(
                    'All bookings have been assigned!',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedPlaces.length,
              itemBuilder: (context, index) {
                final place = sortedPlaces[index];
                final bookings = bookingsByPlace[place]!;
                return _buildPickupPlaceGroup(place, bookings, controller);
              },
            ),
    );
  }

  Widget _buildPickupPlaceGroup(String place, List<PickupBooking> bookings, PickupController controller) {
    // Calculate total guests for this pickup place
    final totalGuests = bookings.fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
    
    // Truncate pickup place name to 12 characters
    final truncatedPlace = place.length > 12 ? '${place.substring(0, 12)}...' : place;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1A1A2E),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Row(
          children: [
            Icon(Icons.location_on, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                truncatedPlace,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              '${bookings.length}B • ${totalGuests}G',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        children: bookings.map((booking) => _buildCompactBookingCard(booking, controller)).toList(),
      ),
    );
  }

  Widget _buildCompactBookingCard(PickupBooking booking, PickupController controller) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.2),
          radius: 18,
          child: Text(
            booking.customerFullName.isNotEmpty ? booking.customerFullName[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                booking.customerFullName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
            if (booking.isUnpaid) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: booking.paidOnArrival ? AppColors.success : AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      booking.paidOnArrival ? Icons.check_circle : Icons.payment,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      booking.paidOnArrival ? 'Paid on Arrival' : 'Not Paid',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  _formatTime(booking.pickupTime),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 12),
                Icon(Icons.people, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  '${booking.numberOfGuests} guest${booking.numberOfGuests > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            if (booking.phoneNumber.isNotEmpty || booking.email.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (booking.phoneNumber.isNotEmpty) ...[
                    Icon(Icons.phone, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      booking.phoneNumber,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                  if (booking.phoneNumber.isNotEmpty && booking.email.isNotEmpty)
                    const Text(' • ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  if (booking.email.isNotEmpty) ...[
                    Icon(Icons.email, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        booking.email,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (booking.isUnpaid && booking.amountToPayOnArrival != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: booking.paidOnArrival 
                      ? AppColors.success.withOpacity(0.2)
                      : AppColors.warning.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: booking.paidOnArrival ? AppColors.success : AppColors.warning,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      booking.paidOnArrival ? Icons.check_circle : Icons.payment,
                      size: 12,
                      color: booking.paidOnArrival ? AppColors.success : AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      booking.paidOnArrival
                          ? 'Paid on Arrival: ${booking.amountToPayOnArrival!.toStringAsFixed(0)} ISK'
                          : 'Unpaid: ${booking.amountToPayOnArrival!.toStringAsFixed(0)} ISK',
                      style: TextStyle(
                        color: booking.paidOnArrival ? AppColors.success : AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (booking.isUnpaid) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: booking.paidOnArrival 
                      ? AppColors.success.withOpacity(0.2)
                      : AppColors.warning.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: booking.paidOnArrival ? AppColors.success : AppColors.warning,
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.payment, size: 12, color: AppColors.warning),
                    SizedBox(width: 4),
                    Text(
                      'Unpaid',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
              onPressed: () => _editPickupPlace(booking, controller),
              tooltip: 'Edit Pickup Place',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteBooking(booking, controller);
                } else {
                  _assignBookingToGuide(booking, value, controller);
                }
              },
              itemBuilder: (context) => [
                ..._buildGuideMenuItems(controller),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: AppColors.error),
                      SizedBox(width: 8),
                      Text(
                        'Delete Booking',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildGuideMenuItems(PickupController controller) {
    if (_isLoadingGuides) {
      return [
        const PopupMenuItem(
          value: '',
          enabled: false,
          child: Text(
            'Loading guides...',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ];
    }

    if (_guides.isEmpty) {
      return [
        const PopupMenuItem(
          value: '',
          enabled: false,
          child: Text(
            'No guides available',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ];
    }

    return _guides.map((guide) {
      final guideList = controller.getGuideList(guide.id);
      final currentPassengers = guideList?.totalPassengers ?? 0;
      final canAdd = controller.validatePassengerCount(guide.id, 1); // Assuming 1 passenger for menu check
      
      return PopupMenuItem<String>(
        value: guide.id,
        enabled: canAdd,
        child: Row(
          children: [
            Expanded(
              child: Text(
                guide.name,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            Text(
              '$currentPassengers/19',
              style: const TextStyle(color: Colors.white),
            ),
            if (!canAdd) const Icon(Icons.warning, color: AppColors.error, size: 16),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildGuideListsTab(PickupController controller) {
    final guideLists = controller.guideLists;
    
    if (guideLists.isEmpty) {
      return const Center(
        child: Text(
          'No guides have been assigned yet',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshData(controller);
        // Reload reordered bookings from Firebase after refresh
        await _updateReorderedBookings(controller);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: guideLists.length,
        itemBuilder: (context, index) {
          final guideList = guideLists[index];
          return _buildGuideListCard(guideList, controller);
        },
      ),
    );
  }

  Widget _buildGuideListCard(GuidePickupList guideList, PickupController controller) {
    // Initialize reordered list if it doesn't exist for this guide
    if (!_reorderedBookings.containsKey(guideList.guideId)) {
      _initializeReorderedList(guideList, controller);
    }
    
    // Get the reordered list for this guide
    final reorderedList = _reorderedBookings[guideList.guideId]!;
    print('📋 Using reordered list for guide ${guideList.guideName}: ${reorderedList.map((b) => b.customerFullName).toList()}');
    
    // Calculate picked up passengers count
    final pickedUpPassengers = guideList.bookings
        .where((booking) => booking.isArrived)
        .fold<int>(0, (sum, booking) => sum + booking.numberOfGuests);
    
    // Check if all pickups are complete (all bookings have isArrived = true)
    final allPickupsComplete = guideList.bookings.isNotEmpty && 
                                guideList.bookings.every((booking) => booking.isArrived);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF1A1A2E), // Dark background for better contrast
      child: ExpansionTile(
        title: Row(
          children: [
            // Completion status icon
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: allPickupsComplete 
                    ? AppColors.success.withOpacity(0.2)
                    : AppColors.warning.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                allPickupsComplete 
                    ? Icons.check_circle
                    : Icons.pending_actions,
                color: allPickupsComplete 
                    ? AppColors.success
                    : AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                guideList.guideName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: allPickupsComplete 
                      ? AppColors.success
                      : Colors.white,
                ),
              ),
            ),
            // Picked up count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pickedUpPassengers > 0 ? AppColors.primary : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$pickedUpPassengers',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Total passengers count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: guideList.totalPassengers > 19 ? AppColors.error : AppColors.success,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${guideList.totalPassengers}/19',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.sort, size: 20),
              onPressed: () {
                _resetGuideOrder(guideList, controller);
              },
              tooltip: 'Reset to alphabetical order',
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${guideList.bookings.length} pickups',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 4),
            _buildBusAssignmentWidget(guideList, controller),
          ],
        ),
        children: [
          Container(
            height: 300, // Fixed height for scrollable area
            child: ReorderableListView.builder(
              itemCount: reorderedList.length,
              onReorder: (oldIndex, newIndex) {
                _handleReorder(oldIndex, newIndex, reorderedList, guideList, controller);
              },
              itemBuilder: (context, index) {
                final booking = reorderedList[index];
                return _buildAssignedBookingTile(booking, guideList, controller, key: ValueKey(booking.id));
              },
            ),
          ),
        ],
      ),
    );
  }

  // Build bus assignment widget
  Widget _buildBusAssignmentWidget(GuidePickupList guideList, PickupController controller) {
    final assignment = _busAssignments[guideList.guideId];
    final assignedBusName = assignment?['busName'] ?? 'No bus assigned';
    
    return InkWell(
      onTap: () => _showBusSelectionDialog(guideList, controller),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: assignment != null ? AppColors.primary.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: assignment != null ? AppColors.primary : Colors.grey,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_bus,
              size: 16,
              color: assignment != null ? AppColors.primary : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              assignedBusName,
              style: TextStyle(
                color: assignment != null ? AppColors.primary : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.edit,
              size: 14,
              color: assignment != null ? AppColors.primary : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // Show bus selection dialog
  Future<void> _showBusSelectionDialog(GuidePickupList guideList, PickupController controller) async {
    final assignment = _busAssignments[guideList.guideId];
    String? initialSelectedBusId = assignment?['busId'];
    
    // Validate the stored busId exists in available buses
    // This fixes cases where the busId might have been corrupted (e.g., 'O' vs '0')
    if (initialSelectedBusId != null && initialSelectedBusId.isNotEmpty) {
      final busExists = _availableBuses.any((b) => b['id'] == initialSelectedBusId);
      if (!busExists) {
        print('⚠️ Stored busId "$initialSelectedBusId" not found in available buses. Clearing selection.');
        initialSelectedBusId = null;
      }
    }
    
    // Declare variable outside builder so it persists across rebuilds
    String? selectedBusId = initialSelectedBusId;
    
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: Text(
                'Assign Bus to ${guideList.guideName}',
                style: const TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableBuses.length + 1, // +1 for "None" option
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // "None" option to remove assignment
                      final isSelected = selectedBusId == null;
                      return ListTile(
                        title: const Text(
                          'No bus assigned',
                          style: TextStyle(color: Colors.white),
                        ),
                        leading: Radio<String?>(
                          value: null,
                          groupValue: selectedBusId,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedBusId = value;
                            });
                          },
                        ),
                        selected: isSelected,
                        onTap: () {
                          setDialogState(() {
                            selectedBusId = null;
                          });
                        },
                      );
                    }
                    
                    final bus = _availableBuses[index - 1];
                    final busId = bus['id'] as String;
                    final busName = bus['name'] as String;
                    final licensePlate = bus['licensePlate'] as String? ?? '';
                    final isSelected = selectedBusId == busId;
                    
                    return ListTile(
                      title: Text(
                        busName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        licensePlate.isNotEmpty ? 'License: $licensePlate' : '',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      leading: Radio<String?>(
                        value: busId,
                        groupValue: selectedBusId,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedBusId = value;
                          });
                        },
                      ),
                      selected: isSelected,
                      onTap: () {
                        setDialogState(() {
                          selectedBusId = busId;
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, selectedBusId);
                  },
                  child: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );
    
    // Handle the result
    if (result != null || (result == null && initialSelectedBusId != null)) {
      // User clicked Assign (result can be null to remove assignment)
      final finalBusId = result;
      if (finalBusId == null) {
        await _assignBusToGuide(guideList.guideId, guideList.guideName, null, null, controller);
      } else {
        // Validate that the busId exists in available buses to prevent mismatches
        final selectedBus = _availableBuses.firstWhere(
          (b) => b['id'] == finalBusId,
          orElse: () => throw Exception('Selected bus not found in available buses list'),
        );
        
        // Double-check: use the ID from the bus object, not the passed value
        // This ensures we're using the exact ID from Firestore
        final verifiedBusId = selectedBus['id'] as String;
        final verifiedBusName = selectedBus['name'] as String;
        
        print('✅ Verifying bus assignment: ID=$verifiedBusId, Name=$verifiedBusName');
        
        await _assignBusToGuide(
          guideList.guideId,
          guideList.guideName,
          verifiedBusId,  // Use the verified ID from the bus object
          verifiedBusName,
          controller,
        );
      }
    }
  }

  // Initialize reordered list for a guide
  Future<void> _initializeReorderedList(GuidePickupList guideList, PickupController controller) async {
    final dateStr = '${controller.selectedDate.year}-${controller.selectedDate.month.toString().padLeft(2, '0')}-${controller.selectedDate.day.toString().padLeft(2, '0')}';
    
    // Try to load existing reordered list from Firebase
    final savedBookingIds = await FirebaseService.getReorderedBookings(
      guideId: guideList.guideId,
      date: dateStr,
    );
    
    List<PickupBooking> reorderedList;
    
    if (savedBookingIds.isNotEmpty) {
      // Reconstruct list from saved order
      reorderedList = <PickupBooking>[];
      for (final bookingId in savedBookingIds) {
        try {
          final booking = guideList.bookings.firstWhere(
            (b) => b.id == bookingId,
          );
          reorderedList.add(booking);
        } catch (e) {
          // Booking not found, skip it
          print('⚠️ Booking $bookingId not found in guide list, skipping');
        }
      }
      
      // Add any new bookings that weren't in the saved order
      for (final booking in guideList.bookings) {
        if (!savedBookingIds.contains(booking.id)) {
          reorderedList.add(booking);
        }
      }
      
      print('🔄 Loaded saved reordered list for guide ${guideList.guideName}: ${reorderedList.length} bookings');
    } else {
      // Create new sorted list
      reorderedList = List<PickupBooking>.from(guideList.bookings)
        ..sort((a, b) => a.pickupPlaceName.compareTo(b.pickupPlaceName));
      print('🔄 Created new sorted list for guide ${guideList.guideName}: ${reorderedList.length} bookings');
    }
    
    setState(() {
      _reorderedBookings[guideList.guideId] = reorderedList;
    });
  }

  // Handle reordering
  void _handleReorder(int oldIndex, int newIndex, List<PickupBooking> reorderedList, GuidePickupList guideList, PickupController controller) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = reorderedList.removeAt(oldIndex);
      reorderedList.insert(newIndex, item);
      
      // Update the reordered bookings map
      _reorderedBookings[guideList.guideId] = List.from(reorderedList);
      
      print('🔄 Reordered booking "${item.customerFullName}" from index $oldIndex to $newIndex for guide ${guideList.guideName}');
      print('📋 New order: ${reorderedList.map((b) => b.customerFullName).toList()}');
    });
    
    // Save to Firebase
    _saveReorderedList(guideList, controller);
  }

  // Save reordered list to Firebase
  Future<void> _saveReorderedList(GuidePickupList guideList, PickupController controller) async {
    final reorderedList = _reorderedBookings[guideList.guideId];
    if (reorderedList != null) {
      final dateStr = '${controller.selectedDate.year}-${controller.selectedDate.month.toString().padLeft(2, '0')}-${controller.selectedDate.day.toString().padLeft(2, '0')}';
      final bookingIds = reorderedList.map((b) => b.id).toList();
      
      await FirebaseService.saveReorderedBookings(
        guideId: guideList.guideId,
        date: dateStr,
        bookingIds: bookingIds,
      );
    }
  }

  // Reset guide order
  void _resetGuideOrder(GuidePickupList guideList, PickupController controller) async {
    setState(() {
      _reorderedBookings.remove(guideList.guideId);
      print('🔄 Reset order for guide ${guideList.guideName}');
    });
    
    // Remove from Firebase
    final dateStr = '${controller.selectedDate.year}-${controller.selectedDate.month.toString().padLeft(2, '0')}-${controller.selectedDate.day.toString().padLeft(2, '0')}';
    await FirebaseService.removeReorderedBookings(
      guideId: guideList.guideId,
      date: dateStr,
    );
  }

  Widget _buildAssignedBookingTile(PickupBooking booking, GuidePickupList guideList, PickupController controller, {Key? key}) {
    return ListTile(
      key: key,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            booking.pickupPlaceName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: booking.isArrived,
                onChanged: (value) {
                  controller.markBookingAsArrived(booking.id, value ?? false);
                },
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        booking.customerFullName,
                        style: TextStyle(
                          fontSize: 14,
                          decoration: booking.isNoShow ? TextDecoration.lineThrough : null,
                          color: booking.isNoShow 
                              ? AppColors.error 
                              : booking.isArrived 
                                  ? Colors.green 
                                  : Colors.white,
                          fontWeight: booking.isArrived ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (booking.isUnpaid) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: booking.paidOnArrival ? AppColors.success : AppColors.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              booking.paidOnArrival ? Icons.check_circle : Icons.payment,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              booking.paidOnArrival ? 'Paid on Arrival' : 'Not Paid',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${_formatTime(booking.pickupTime)} - ${booking.numberOfGuests} guest${booking.numberOfGuests > 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
          ),
          Text(
            booking.phoneNumber,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
          ),
          if (booking.isUnpaid && booking.amountToPayOnArrival != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.warning, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payment, size: 12, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    'Unpaid: ${booking.amountToPayOnArrival!.toStringAsFixed(0)} ISK',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (booking.isUnpaid) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.warning, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payment, size: 12, color: AppColors.warning),
                  SizedBox(width: 4),
                  Text(
                    'Unpaid',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
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
            ),
          PopupMenuButton<String>(
            onSelected: (action) => _handleBookingAction(action, booking, guideList, controller),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text(
                  'Edit Pickup Place',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuItem(
                value: 'move',
                child: Text(
                  'Move to another guide',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuItem(
                value: 'unassign',
                child: Text(
                  'Unassign',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: AppColors.error),
                    SizedBox(width: 8),
                    Text(
                      'Delete Booking',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
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
      // Reset reordered bookings when date changes
      setState(() {
        _resetReorderedBookings();
        // Clear bus assignments for old date
        _busAssignments.clear();
      });
      // Change date and force refresh to get fresh data
      controller.changeDate(selectedDate);
      // Wait for bookings to load
      await Future.delayed(const Duration(milliseconds: 500));
      // Reload bus assignments for the new date
      await _loadBusAssignments(controller);
      // Reload reordered bookings for the new date
      await _updateReorderedBookings(controller);
    }
  }

  void _autoDistribute() async {
    final controller = context.read<PickupController>();
    
    if (_guides.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No guides available for distribution'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Convert AdminGuide to User for the controller
    final guides = _guides.map((adminGuide) => User(
      id: adminGuide.id,
      fullName: adminGuide.name,
      email: adminGuide.email,
      phoneNumber: adminGuide.phone,
      role: 'guide',
      profilePictureUrl: adminGuide.profileImageUrl,
      createdAt: adminGuide.joinDate,
      isActive: adminGuide.status == 'active',
    )).toList();

    await controller.distributeBookings(guides);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bookings distributed successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _assignBookingToGuide(PickupBooking booking, String guideId, PickupController controller) async {
    // Find the guide name from loaded guides
    final guide = _guides.firstWhere((g) => g.id == guideId, orElse: () => AdminGuide(
      id: guideId,
      name: 'Unknown Guide',
      email: '',
      phone: '',
      profileImageUrl: '',
      status: 'inactive',
      joinDate: DateTime.now(),
      totalShifts: 0,
      rating: 0.0,
      certifications: [],
      preferences: {},
    ));
    
    final success = await controller.assignBookingToGuide(booking.id, guideId, guide.name);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.customerFullName} assigned to ${guide.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _handleBookingAction(String action, PickupBooking booking, GuidePickupList guideList, PickupController controller) {
    print('🔧 Handling booking action: $action for booking: ${booking.customerFullName}');
    switch (action) {
      case 'edit':
        print('✏️ Editing pickup place...');
        _editPickupPlace(booking, controller);
        break;
      case 'move':
        print('📤 Moving booking to another guide...');
        _showMoveBookingDialog(booking, guideList, controller);
        break;
      case 'unassign':
        print('❌ Unassigning booking...');
        _unassignBooking(booking, controller);
        break;
      case 'delete':
        print('🗑️ Deleting booking...');
        _deleteBooking(booking, controller);
        break;
      default:
        print('⚠️ Unknown action: $action');
    }
  }

  void _showMoveBookingDialog(PickupBooking booking, GuidePickupList currentGuideList, PickupController controller) {
    if (_guides.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No guides available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _guides
              .where((guide) => guide.id != currentGuideList.guideId)
              .map((guide) {
            final guideList = controller.getGuideList(guide.id);
            final currentPassengers = guideList?.totalPassengers ?? 0;
            final canAdd = controller.validatePassengerCount(guide.id, booking.numberOfGuests);
            
            return ListTile(
              title: Text(guide.name),
              subtitle: Text('$currentPassengers/19 passengers'),
              trailing: canAdd ? null : const Icon(Icons.warning, color: AppColors.error),
              onTap: canAdd ? () {
                Navigator.of(context).pop();
                _moveBooking(booking, currentGuideList.guideId, guide.id, guide.name, controller);
              } : null,
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _moveBooking(PickupBooking booking, String fromGuideId, String toGuideId, String toGuideName, PickupController controller) async {
    print('🔄 Starting move process for: ${booking.customerFullName}');
    print('📤 From guide: $fromGuideId to guide: $toGuideId ($toGuideName)');
    final success = await controller.moveBookingBetweenGuides(booking.id, fromGuideId, toGuideId, toGuideName);
    print('✅ Move result: $success');
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.customerFullName} moved to $toGuideName'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to move ${booking.customerFullName}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _unassignBooking(PickupBooking booking, PickupController controller) async {
    print('🔄 Starting unassign process for: ${booking.customerFullName}');
    final success = await controller.assignBookingToGuide(booking.id, '', '');
    print('✅ Unassign result: $success');
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.customerFullName} unassigned'),
          backgroundColor: AppColors.warning,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to unassign ${booking.customerFullName}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _deleteBooking(PickupBooking booking, PickupController controller) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Delete Booking',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete the booking for ${booking.customerFullName}? This action cannot be undone.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      print('🗑️ Starting delete process for: ${booking.customerFullName}');
      final success = await controller.deleteBooking(booking.id);
      print('✅ Delete result: $success');
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${booking.customerFullName} deleted'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete ${booking.customerFullName}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _refreshData(PickupController controller) async {
    // Force refresh to always get fresh data from API and Firebase
    await controller.loadBookingsForDate(controller.selectedDate, forceRefresh: true);
    await _loadGuides();
    // Wait a bit for guide lists to be populated after bookings are loaded
    await Future.delayed(const Duration(milliseconds: 300));
    await _loadBusAssignments(controller);
  }

  void _editPickupPlace(PickupBooking booking, PickupController controller) {
    final TextEditingController textController = TextEditingController(text: booking.pickupPlaceName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Pickup Place'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Customer: ${booking.customerFullName}'),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Pickup Place',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newPickupPlace = textController.text.trim();
              if (newPickupPlace.isNotEmpty) {
                Navigator.of(context).pop();
                _savePickupPlaceEdit(booking, newPickupPlace, controller);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePickupPlaceEdit(PickupBooking booking, String newPickupPlace, PickupController controller) async {
    try {
      await controller.updatePickupPlace(booking.id, newPickupPlace);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pickup place updated for ${booking.customerFullName}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update pickup place: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Show manual booking dialog
  void _showManualBookingDialog(PickupController controller) {
    final nameController = TextEditingController();
    final pickupLocationController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final numberOfGuestsController = TextEditingController(text: '1');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Add Manual Booking',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pickupLocationController,
                decoration: const InputDecoration(
                  labelText: 'Pickup Location',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: numberOfGuestsController,
                decoration: const InputDecoration(
                  labelText: 'Number of Guests',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              print('🔵🔵🔵 Add Booking button pressed - START');
              try {
                print('🔵 Add Booking button pressed');
                final name = nameController.text.trim();
                final pickupLocation = pickupLocationController.text.trim();
                final email = emailController.text.trim();
                final phone = phoneController.text.trim();
                final numberOfGuestsStr = numberOfGuestsController.text.trim();
                
                print('🔵 Form values: name=$name, location=$pickupLocation, email=$email, phone=$phone, guests=$numberOfGuestsStr');
                
                if (name.isEmpty || pickupLocation.isEmpty) {
                  print('⚠️ Validation failed: name or location is empty');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name and Pickup Location are required'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                  return;
                }
                
                final numberOfGuests = int.tryParse(numberOfGuestsStr) ?? 1;
                if (numberOfGuests < 1) {
                  print('⚠️ Validation failed: number of guests < 1');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Number of guests must be at least 1'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                  return;
                }
                
                print('✅ Validation passed, closing dialog and creating booking...');
                Navigator.of(context).pop();
                
                print('🔵 Calling createManualBooking...');
                final success = await controller.createManualBooking(
                  customerName: name,
                  pickupLocation: pickupLocation,
                  email: email,
                  phoneNumber: phone,
                  numberOfGuests: numberOfGuests,
                );
                
                print('🔵 createManualBooking returned: $success');
                
                if (mounted) {
                  if (success) {
                    print('✅ Showing success message');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Manual booking added for $name'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else {
                    print('❌ Showing error message - booking creation failed');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to add manual booking'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                } else {
                  print('⚠️ Widget not mounted, cannot show message');
                }
              } catch (e, stackTrace) {
                print('❌ Error in Add Booking button handler: $e');
                print('❌ Stack trace: $stackTrace');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Add Booking'),
          ),
        ],
      ),
    );
  }
} 