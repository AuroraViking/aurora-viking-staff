// Admin guide management screen for viewing and managing all registered guides

import 'package:flutter/material.dart';
import '../../core/models/admin_models.dart';
import '../../core/theme/colors.dart';
import '../../core/services/guide_gamification.dart';
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
  final GuideGamificationService _gamificationService = GuideGamificationService();
  final Map<String, GuideStats> _guideStats = {};

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
      // Load gamification stats for all guides in background
      _loadGuideStats(guides);
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

  Future<void> _toggleGuideSms(AdminGuide guide) async {
    try {
      await AdminService.toggleGuideSms(guide.id, !guide.smsEnabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SMS ${!guide.smsEnabled ? "enabled" : "disabled"} for ${guide.name}'),
            backgroundColor: Colors.green,
          ),
        );
        _loadGuides();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
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

  Future<void> _loadGuideStats(List<AdminGuide> guides) async {
    for (final guide in guides) {
      try {
        final stats = await _gamificationService.calculateGuideStats(guide.id, guideName: guide.name);
        if (mounted) {
          setState(() {
            _guideStats[guide.id] = stats;
          });
        }
      } catch (e) {
        print('⚠️ Could not load stats for ${guide.name}: $e');
      }
    }
  }

  Future<void> _editPhoneNumber(AdminGuide guide) async {
    final phoneController = TextEditingController(text: guide.phone);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Phone Number'),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+354 xxx xxxx',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, phoneController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    phoneController.dispose();
    if (result != null && result != guide.phone) {
      try {
        await AdminService.updateGuidePhone(guide.id, result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Updated phone for ${guide.name}'),
              backgroundColor: Colors.green,
            ),
          );
          _loadGuides();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showGuideDetails(AdminGuide guide) async {
    final detailedGuide = await AdminService.getGuideById(guide.id);
    // Get gamification stats
    GuideStats? stats = _guideStats[guide.id];
    stats ??= await _gamificationService.calculateGuideStats(guide.id, guideName: guide.name);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text('${stats!.currentLevel.badge} '),
            Expanded(child: Text(detailedGuide.name)),
          ],
        ),
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
              const SizedBox(height: 8),
              // Level title
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.withOpacity(0.3),
                        Colors.blue.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Lv.${stats.currentLevel.level} ${stats.currentLevel.title}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // XP progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${stats.totalXP} XP', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (stats.nextLevel != null)
                        Text('${stats.nextLevel!.xpRequired} XP', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: stats.levelProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
                    ),
                  ),
                  if (stats.nextLevel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Next: Lv.${stats.nextLevel!.level} ${stats.nextLevel!.title}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Badges
              if (stats.earnedBadges.isNotEmpty) ...[
                const Text('Badges:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: stats.earnedBadges.map((badge) => Tooltip(
                    message: '${badge.name} — ${badge.description}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${badge.emoji} ${badge.name}', style: const TextStyle(fontSize: 12)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
              ],
              // Stats
              const Text('Stats:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              _buildDetailRow('Shifts', '${stats.completedShifts}'),
              _buildDetailRow('Aurora', '${stats.auroraSightings} sightings (${stats.strongAuroraSightings} strong)'),
              _buildDetailRow('Passengers', '${stats.totalPassengersServed} served'),
              const Divider(),
              _buildDetailRow('Email', detailedGuide.email),
              Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text('Phone:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text(detailedGuide.phone.isEmpty ? 'Not set' : detailedGuide.phone),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    onPressed: () {
                      Navigator.pop(context);
                      _editPhoneNumber(detailedGuide);
                    },
                  ),
                ],
              ),
              _buildDetailRow('Status', detailedGuide.status.toUpperCase()),
              _buildDetailRow('Joined', _formatDate(detailedGuide.joinDate)),
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
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredGuides.length,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) newIndex -= 1;
                          setState(() {
                            final guide = _filteredGuides.removeAt(oldIndex);
                            _filteredGuides.insert(newIndex, guide);
                            // Also reorder in _guides
                            _guides = List.from(_filteredGuides);
                          });
                          _saveGuidePriorities();
                        },
                        itemBuilder: (context, index) {
                          final guide = _filteredGuides[index];
                          final rank = index + 1;
                          return Card(
                            key: ValueKey(guide.id),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Rank badge
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: rank <= 3
                                          ? (rank == 1 ? Colors.amber : rank == 2 ? Colors.grey[400] : Colors.brown[300])
                                          : AppColors.primary.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$rank',
                                        style: TextStyle(
                                          color: rank <= 3 ? Colors.black87 : Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundImage: guide.profileImageUrl.isNotEmpty
                                        ? NetworkImage(guide.profileImageUrl)
                                        : null,
                                    child: guide.profileImageUrl.isEmpty
                                        ? const Icon(Icons.person, size: 18)
                                        : null,
                                  ),
                                ],
                              ),
                              title: Text(
                                guide.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Level badge + email
                                  if (_guideStats.containsKey(guide.id))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        '${_guideStats[guide.id]!.currentLevel.badge} Lv.${_guideStats[guide.id]!.currentLevel.level} ${_guideStats[guide.id]!.currentLevel.title} • ${_guideStats[guide.id]!.totalXP} XP',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.purple[300],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  Text(guide.email, style: const TextStyle(fontSize: 12)),
                                  if (guide.phone.isNotEmpty)
                                    Text('📱 ${guide.phone}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                                      const Icon(Icons.drag_handle, size: 16, color: Colors.grey),
                                      const Text(
                                        'Drag to rank',
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'view':
                                      _showGuideDetails(guide);
                                      break;
                                    case 'edit_phone':
                                      _editPhoneNumber(guide);
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
                                    case 'toggle_sms':
                                      _toggleGuideSms(guide);
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
                                  const PopupMenuItem(
                                    value: 'edit_phone',
                                    child: Row(
                                      children: [
                                        Icon(Icons.phone),
                                        SizedBox(width: 8),
                                        Text('Edit Phone'),
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
                                  PopupMenuItem(
                                    value: 'toggle_sms',
                                    child: Row(
                                      children: [
                                        Icon(
                                          guide.smsEnabled ? Icons.sms : Icons.sms_failed,
                                          color: guide.smsEnabled ? Colors.green : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(guide.smsEnabled ? 'SMS: ON' : 'SMS: OFF'),
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

  Future<void> _saveGuidePriorities() async {
    // Highest rank (index 0) gets highest priority value
    final priorities = <String, int>{};
    for (int i = 0; i < _filteredGuides.length; i++) {
      priorities[_filteredGuides[i].id] = _filteredGuides.length - i;
    }
    try {
      await AdminService.updateGuidePriorities(priorities);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving priorities: $e')),
        );
      }
    }
  }
} 