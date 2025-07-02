import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
import '../../core/theme/colors.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import '../pickup/pickup_controller.dart';

class AdminPickupManagementScreen extends StatefulWidget {
  const AdminPickupManagementScreen({Key? key}) : super(key: key);

  @override
  State<AdminPickupManagementScreen> createState() => _AdminPickupManagementScreenState();
}

class _AdminPickupManagementScreenState extends State<AdminPickupManagementScreen> {
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
            '${controller.bookings.length} total bookings',
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

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                'Total',
                '${stats.totalBookings}',
                Icons.assignment,
                AppColors.primary,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'Assigned',
                '${stats.assignedBookings}',
                Icons.check_circle,
                AppColors.success,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'Unassigned',
                '${stats.unassignedBookings}',
                Icons.pending,
                AppColors.warning,
              ),
            ),
            Expanded(
              child: _buildStatItem(
                'No Shows',
                '${stats.noShows}',
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

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _showTab(0),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Unassigned'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _showTab(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Guide Lists'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabView(PickupController controller) {
    return DefaultTabController(
      length: 2,
      child: TabBarView(
        children: [
          _buildUnassignedTab(controller),
          _buildGuideListsTab(controller),
        ],
      ),
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
    // Mock guides - in real app, get from user service
    final guides = [
      User(id: '1', fullName: 'John Guide', email: 'john@auroraviking.com', phoneNumber: '+354 123 4567', role: 'staff', createdAt: DateTime.now()),
      User(id: '2', fullName: 'Sarah Guide', email: 'sarah@auroraviking.com', phoneNumber: '+354 234 5678', role: 'staff', createdAt: DateTime.now()),
      User(id: '3', fullName: 'Mike Guide', email: 'mike@auroraviking.com', phoneNumber: '+354 345 6789', role: 'staff', createdAt: DateTime.now()),
    ];

    return guides.map((guide) {
      final guideList = controller.getGuideList(guide.id);
      final currentPassengers = guideList?.totalPassengers ?? 0;
      final canAdd = controller.validatePassengerCount(guide.id, 1); // Assuming 1 passenger for menu check
      
      return PopupMenuItem<String>(
        value: guide.id,
        enabled: canAdd,
        child: Row(
          children: [
            Expanded(child: Text(guide.fullName)),
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
          ],
        ),
        subtitle: Text('${guideList.bookings.length} pickups'),
        children: guideList.bookings.map((booking) => _buildAssignedBookingTile(booking, guideList, controller)).toList(),
      ),
    );
  }

  Widget _buildAssignedBookingTile(PickupBooking booking, GuidePickupList guideList, PickupController controller) {
    return ListTile(
      title: Text(
        booking.customerFullName,
        style: TextStyle(
          decoration: booking.isNoShow ? TextDecoration.lineThrough : null,
          color: booking.isNoShow ? AppColors.error : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(booking.pickupPlaceName),
          Text('${_formatTime(booking.pickupTime)} - ${booking.numberOfGuests} guests'),
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
      controller.changeDate(selectedDate);
    }
  }

  void _autoDistribute() async {
    final controller = context.read<PickupController>();
    
    // Mock guides - in real app, get from user service
    final guides = [
      User(id: '1', fullName: 'John Guide', email: 'john@auroraviking.com', phoneNumber: '+354 123 4567', role: 'staff', createdAt: DateTime.now()),
      User(id: '2', fullName: 'Sarah Guide', email: 'sarah@auroraviking.com', phoneNumber: '+354 234 5678', role: 'staff', createdAt: DateTime.now()),
      User(id: '3', fullName: 'Mike Guide', email: 'mike@auroraviking.com', phoneNumber: '+354 345 6789', role: 'staff', createdAt: DateTime.now()),
    ];

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
    // Mock guide name - in real app, get from user service
    final guideName = 'Guide $guideId';
    
    final success = await controller.assignBookingToGuide(booking.id, guideId, guideName);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.customerFullName} assigned to $guideName'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _handleBookingAction(String action, PickupBooking booking, GuidePickupList guideList, PickupController controller) {
    switch (action) {
      case 'move':
        _showMoveBookingDialog(booking, guideList, controller);
        break;
      case 'unassign':
        _unassignBooking(booking, controller);
        break;
    }
  }

  void _showMoveBookingDialog(PickupBooking booking, GuidePickupList currentGuideList, PickupController controller) {
    // Mock guides - in real app, get from user service
    final guides = [
      User(id: '1', fullName: 'John Guide', email: 'john@auroraviking.com', phoneNumber: '+354 123 4567', role: 'staff', createdAt: DateTime.now()),
      User(id: '2', fullName: 'Sarah Guide', email: 'sarah@auroraviking.com', phoneNumber: '+354 234 5678', role: 'staff', createdAt: DateTime.now()),
      User(id: '3', fullName: 'Mike Guide', email: 'mike@auroraviking.com', phoneNumber: '+354 345 6789', role: 'staff', createdAt: DateTime.now()),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: guides
              .where((guide) => guide.id != currentGuideList.guideId)
              .map((guide) {
            final guideList = controller.getGuideList(guide.id);
            final currentPassengers = guideList?.totalPassengers ?? 0;
            final canAdd = controller.validatePassengerCount(guide.id, booking.numberOfGuests);
            
            return ListTile(
              title: Text(guide.fullName),
              subtitle: Text('$currentPassengers/19 passengers'),
              trailing: canAdd ? null : const Icon(Icons.warning, color: AppColors.error),
              onTap: canAdd ? () {
                Navigator.of(context).pop();
                _moveBooking(booking, currentGuideList.guideId, guide.id, guide.fullName, controller);
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
    final success = await controller.moveBookingBetweenGuides(booking.id, fromGuideId, toGuideId, toGuideName);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.customerFullName} moved to $toGuideName'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _unassignBooking(PickupBooking booking, PickupController controller) async {
    final success = await controller.assignBookingToGuide(booking.id, '', '');
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.customerFullName} unassigned'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  void _showTab(int index) {
    // This would be handled by TabBarView in a real implementation
  }
} 