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
  int _lastBookingCount = 0; // To track if booking count has changed significantly

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<PickupController>();
      controller.loadBookingsForDate(controller.selectedDate);
      _loadGuides();
      
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

  void _onControllerDataChanged() {
    // Update reordered bookings when assignments change, but preserve custom order
    if (mounted) {
      final controller = context.read<PickupController>();
      
      // Update existing reordered lists with new assignment data
      _updateReorderedBookings(controller);
    }
  }

  // Update reordered bookings with new assignment data while preserving custom order
  void _updateReorderedBookings(PickupController controller) {
    final updatedReorderedBookings = <String, List<PickupBooking>>{};
    
    for (final guideList in controller.guideLists) {
      final existingReorderedList = _reorderedBookings[guideList.guideId];
      
      if (existingReorderedList != null && guideList.bookings.isNotEmpty) {
        // Preserve custom order but update booking data
        final updatedList = existingReorderedList.map((reorderedBooking) {
          // Find the updated booking data
          final updatedBooking = guideList.bookings.firstWhere(
            (booking) => booking.id == reorderedBooking.id,
            orElse: () => reorderedBooking,
          );
          return updatedBooking;
        }).toList();
        
        // Only keep bookings that still exist in the guide list
        final validBookings = updatedList.where((booking) => 
          guideList.bookings.any((b) => b.id == booking.id)
        ).toList();
        
        if (validBookings.isNotEmpty) {
          updatedReorderedBookings[guideList.guideId] = validBookings;
        }
      } else if (guideList.bookings.isNotEmpty) {
        // Initialize new reordered list for this guide
        final sortedList = List<PickupBooking>.from(guideList.bookings)
          ..sort((a, b) => a.pickupPlaceName.compareTo(b.pickupPlaceName));
        updatedReorderedBookings[guideList.guideId] = sortedList;
      }
    }
    
    setState(() {
      _reorderedBookings = updatedReorderedBookings;
    });
    
    print('🔄 Updated reordered bookings for ${updatedReorderedBookings.length} guides');
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

  // Reset reordered bookings when data changes
  void _resetReorderedBookings() {
    _reorderedBookings.clear();
    print('🔄 Reset reordered bookings');
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
              onRetry: () => controller.loadBookingsForDate(controller.selectedDate),
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
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
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
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
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
        unselectedLabelColor: AppColors.textSecondary,
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
    
    if (unassignedBookings.isEmpty) {
      return const Center(
        child: Text('All bookings have been assigned!'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: unassignedBookings.length,
      itemBuilder: (context, index) {
        final booking = unassignedBookings[index];
        return _buildUnassignedBookingCard(booking, controller);
      },
    );
  }

  Widget _buildUnassignedBookingCard(PickupBooking booking, PickupController controller) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          booking.customerFullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(booking.pickupPlaceName),
            Text('${_formatTime(booking.pickupTime)} - ${booking.numberOfGuests} guests'),
            Text('${booking.phoneNumber} • ${booking.email}'),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (guideId) => _assignBookingToGuide(booking, guideId, controller),
          itemBuilder: (context) => _buildGuideMenuItems(controller),
          child: const Icon(Icons.more_vert),
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
          child: Text('Loading guides...'),
        ),
      ];
    }

    if (_guides.isEmpty) {
      return [
        const PopupMenuItem(
          value: '',
          enabled: false,
          child: Text('No guides available'),
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
            Expanded(child: Text(guide.name)),
            Text('$currentPassengers/19'),
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
        child: Text('No guides have been assigned yet'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: guideLists.length,
      itemBuilder: (context, index) {
        final guideList = guideLists[index];
        return _buildGuideListCard(guideList, controller);
      },
    );
  }

  Widget _buildGuideListCard(GuidePickupList guideList, PickupController controller) {
    // Initialize reordered list if it doesn't exist for this guide
    if (!_reorderedBookings.containsKey(guideList.guideId)) {
      final sortedList = List<PickupBooking>.from(guideList.bookings)
        ..sort((a, b) => a.pickupPlaceName.compareTo(b.pickupPlaceName));
      _reorderedBookings[guideList.guideId] = sortedList;
      print('🔄 Initialized reordered list for guide ${guideList.guideName}: ${sortedList.length} bookings');
    }
    
    // Get the reordered list for this guide
    final reorderedList = _reorderedBookings[guideList.guideId]!;
    print('📋 Using reordered list for guide ${guideList.guideName}: ${reorderedList.map((b) => b.customerFullName).toList()}');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                guideList.guideName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
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
                setState(() {
                  _reorderedBookings.remove(guideList.guideId);
                  print('🔄 Reset order for guide ${guideList.guideName}');
                });
              },
              tooltip: 'Reset to alphabetical order',
            ),
          ],
        ),
        subtitle: Text('${guideList.bookings.length} pickups'),
        children: [
          Container(
            height: 300, // Fixed height for scrollable area
            child: ReorderableListView.builder(
              itemCount: reorderedList.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final item = reorderedList.removeAt(oldIndex);
                  reorderedList.insert(newIndex, item);
                  
                  // Update the reordered bookings map with the modified list
                  _reorderedBookings[guideList.guideId] = List.from(reorderedList);
                  
                  print('🔄 Reordered booking "${item.customerFullName}" from index $oldIndex to $newIndex for guide ${guideList.guideName}');
                  print('📋 New order: ${reorderedList.map((b) => b.customerFullName).toList()}');
                });
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
          Text(
            booking.customerFullName,
            style: TextStyle(
              fontSize: 14,
              decoration: booking.isNoShow ? TextDecoration.lineThrough : null,
              color: booking.isNoShow ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${_formatTime(booking.pickupTime)} - ${booking.numberOfGuests} guest${booking.numberOfGuests > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            booking.phoneNumber,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
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
                value: 'move',
                child: Text('Move to another guide'),
              ),
              const PopupMenuItem(
                value: 'unassign',
                child: Text('Unassign'),
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
      });
      controller.changeDate(selectedDate);
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
      case 'move':
        print('📤 Moving booking to another guide...');
        _showMoveBookingDialog(booking, guideList, controller);
        break;
      case 'unassign':
        print('❌ Unassigning booking...');
        _unassignBooking(booking, controller);
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
} 