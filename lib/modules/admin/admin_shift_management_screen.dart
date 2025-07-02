// Admin shift management screen for reviewing and approving/rejecting shift applications

import 'package:flutter/material.dart';
import '../../core/models/admin_models.dart';
import '../../core/theme/colors.dart';
import 'admin_service.dart';

class AdminShiftManagementScreen extends StatefulWidget {
  const AdminShiftManagementScreen({super.key});

  @override
  State<AdminShiftManagementScreen> createState() => _AdminShiftManagementScreenState();
}

class _AdminShiftManagementScreenState extends State<AdminShiftManagementScreen> {
  List<AdminShift> _shifts = [];
  List<AdminShift> _filteredShifts = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _selectedType = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadShifts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shifts = await AdminService.getShifts();
      setState(() {
        _shifts = shifts;
        _filteredShifts = shifts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading shifts: $e')),
      );
    }
  }

  void _filterShifts() {
    setState(() {
      _filteredShifts = _shifts.where((shift) {
        bool matchesStatus = _selectedStatus == 'all' || shift.status == _selectedStatus;
        bool matchesType = _selectedType == 'all' || shift.type == _selectedType;
        bool matchesSearch = _searchController.text.isEmpty ||
            shift.guideName.toLowerCase().contains(_searchController.text.toLowerCase());
        
        return matchesStatus && matchesType && matchesSearch;
      }).toList();
    });
  }

  Future<void> _approveShift(AdminShift shift) async {
    final notesController = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Approve ${shift.guideName}\'s ${shift.type.replaceAll('_', ' ')} shift for ${_formatDate(shift.date)}?'),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, notesController.text),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final success = await AdminService.approveShift(shift.id, notes: result);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shift approved successfully')),
          );
          _loadShifts();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving shift: $e')),
        );
      }
    }
  }

  Future<void> _rejectShift(AdminShift shift) async {
    final reasonController = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject ${shift.guideName}\'s ${shift.type.replaceAll('_', ' ')} shift for ${_formatDate(shift.date)}?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection *',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: reasonController.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, reasonController.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final success = await AdminService.rejectShift(shift.id, result);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shift rejected successfully')),
          );
          _loadShifts();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting shift: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadShifts,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                // Search
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by guide name...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => _filterShifts(),
                ),
                const SizedBox(height: 12),
                // Status and Type filters
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                          const DropdownMenuItem(value: 'pending', child: Text('Pending')),
                          const DropdownMenuItem(value: 'approved', child: Text('Approved')),
                          const DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                          const DropdownMenuItem(value: 'completed', child: Text('Completed')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value!;
                          });
                          _filterShifts();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('All Types')),
                          const DropdownMenuItem(value: 'day_tour', child: Text('Day Tour')),
                          const DropdownMenuItem(value: 'northern_lights', child: Text('Northern Lights')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedType = value!;
                          });
                          _filterShifts();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Shifts list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredShifts.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_off, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No shifts found',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredShifts.length,
                        itemBuilder: (context, index) {
                          final shift = _filteredShifts[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              shift.guideName,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              shift.type.replaceAll('_', ' ').toUpperCase(),
                                              style: TextStyle(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(shift.status).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: _getStatusColor(shift.status)),
                                        ),
                                        child: Text(
                                          shift.status.toUpperCase(),
                                          style: TextStyle(
                                            color: _getStatusColor(shift.status),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Date: ${_formatDate(shift.date)}',
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Applied: ${_formatDateTime(shift.appliedAt)}',
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  if (shift.approvedAt != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Approved: ${_formatDateTime(shift.approvedAt!)}',
                                          style: const TextStyle(color: Colors.green),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (shift.rejectionReason != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.cancel, size: 16, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Reason: ${shift.rejectionReason}',
                                            style: const TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (shift.status == 'pending') ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _approveShift(shift),
                                            icon: const Icon(Icons.check),
                                            label: const Text('Approve'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _rejectShift(shift),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Reject'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              side: const BorderSide(color: Colors.red),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
} 