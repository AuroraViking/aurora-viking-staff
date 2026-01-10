// Admin guide management screen for viewing and managing all registered guides

import 'package:flutter/material.dart';
import '../../core/models/admin_models.dart';
import '../../core/theme/colors.dart';
import 'admin_service.dart';

class AdminGuideManagementScreen extends StatefulWidget {
  const AdminGuideManagementScreen({super.key});

  @override
  State<AdminGuideManagementScreen> createState() => _AdminGuideManagementScreenState();
}

class _AdminGuideManagementScreenState extends State<AdminGuideManagementScreen> {
  List<AdminGuide> _guides = [];
  List<AdminGuide> _filteredGuides = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGuides();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGuides() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final guides = await AdminService.getGuides();
      setState(() {
        _guides = guides;
        _filteredGuides = guides;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading guides: $e')),
      );
    }
  }

  void _filterGuides() {
    setState(() {
      _filteredGuides = _guides.where((guide) {
        bool matchesStatus = _selectedStatus == 'all' || guide.status == _selectedStatus;
        bool matchesSearch = _searchController.text.isEmpty ||
            guide.name.toLowerCase().contains(_searchController.text.toLowerCase()) ||
            guide.email.toLowerCase().contains(_searchController.text.toLowerCase());
        
        return matchesStatus && matchesSearch;
      }).toList();
    });
  }

  Future<void> _updateGuideStatus(AdminGuide guide, String newStatus) async {
    try {
      final success = await AdminService.updateGuideStatus(guide.id, newStatus);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${guide.name}\'s status updated to $newStatus')),
        );
        _loadGuides();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating guide status: $e')),
      );
    }
  }

  Future<void> _deleteGuide(AdminGuide guide) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Guide'),
        content: Text('Are you sure you want to delete ${guide.name}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await AdminService.deleteGuide(guide.id);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${guide.name} has been deleted'),
            backgroundColor: Colors.green,
          ),
        );
        _loadGuides();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting guide: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showGuideDetails(AdminGuide guide) async {
    final detailedGuide = await AdminService.getGuideById(guide.id);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detailedGuide.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (detailedGuide.profileImageUrl.isNotEmpty)
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(detailedGuide.profileImageUrl),
                    onBackgroundImageError: (_, __) {},
                    child: detailedGuide.profileImageUrl.isEmpty
                        ? const Icon(Icons.person, size: 40)
                        : null,
                  ),
                ),
              const SizedBox(height: 16),
              _buildDetailRow('Email', detailedGuide.email),
              _buildDetailRow('Phone', detailedGuide.phone),
              _buildDetailRow('Status', detailedGuide.status.toUpperCase()),
              _buildDetailRow('Join Date', _formatDate(detailedGuide.joinDate)),
              _buildDetailRow('Total Shifts', detailedGuide.totalShifts.toString()),
              _buildDetailRow('Rating', '${detailedGuide.rating}/5.0'),
              if (detailedGuide.lastActive != null)
                _buildDetailRow('Last Active', _formatDateTime(detailedGuide.lastActive!)),
              const SizedBox(height: 8),
              const Text(
                'Certifications:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...detailedGuide.certifications.map((cert) => Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(cert),
                  ],
                ),
              )),
              if (detailedGuide.preferences.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Preferences:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...detailedGuide.preferences.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 2),
                  child: Text('${entry.key}: ${entry.value}'),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (detailedGuide.status != 'suspended')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _updateGuideStatus(detailedGuide, 'suspended');
              },
              child: const Text('Suspend', style: TextStyle(color: Colors.red)),
            ),
          if (detailedGuide.status == 'suspended')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _updateGuideStatus(detailedGuide, 'active');
              },
              child: const Text('Activate', style: TextStyle(color: Colors.green)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGuide(detailedGuide);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getTimeAgo(DateTime? lastActive) {
    if (lastActive == null) return 'Never';
    
    final difference = DateTime.now().difference(lastActive);
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadGuides,
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
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => _filterGuides(),
                ),
                const SizedBox(height: 12),
                // Status filter
                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    const DropdownMenuItem(value: 'active', child: Text('Active')),
                    const DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    const DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value!;
                    });
                    _filterGuides();
                  },
                ),
              ],
            ),
          ),
          
          // Guides list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredGuides.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No guides found',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredGuides.length,
                        itemBuilder: (context, index) {
                          final guide = _filteredGuides[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: guide.profileImageUrl.isNotEmpty
                                    ? NetworkImage(guide.profileImageUrl)
                                    : null,
                                child: guide.profileImageUrl.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(
                                guide.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(guide.email),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(guide.status).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: _getStatusColor(guide.status)),
                                        ),
                                        child: Text(
                                          guide.status.toUpperCase(),
                                          style: TextStyle(
                                            color: _getStatusColor(guide.status),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${guide.totalShifts} shifts',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.star, size: 12, color: Colors.amber),
                                          Text(
                                            '${guide.rating}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Last active: ${_getTimeAgo(guide.lastActive)}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'view':
                                      _showGuideDetails(guide);
                                      break;
                                    case 'suspend':
                                      _updateGuideStatus(guide, 'suspended');
                                      break;
                                    case 'activate':
                                      _updateGuideStatus(guide, 'active');
                                      break;
                                    case 'delete':
                                      _deleteGuide(guide);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'view',
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility),
                                        SizedBox(width: 8),
                                        Text('View Details'),
                                      ],
                                    ),
                                  ),
                                  if (guide.status != 'suspended')
                                    const PopupMenuItem(
                                      value: 'suspend',
                                      child: Row(
                                        children: [
                                          Icon(Icons.block, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Suspend', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  if (guide.status == 'suspended')
                                    const PopupMenuItem(
                                      value: 'activate',
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.green),
                                          SizedBox(width: 8),
                                          Text('Activate', style: TextStyle(color: Colors.green)),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _showGuideDetails(guide),
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