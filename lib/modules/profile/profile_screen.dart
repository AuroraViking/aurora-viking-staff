import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart' as av;
import '../../core/auth/auth_controller.dart';
import '../shifts/shifts_screen.dart';
import '../shifts/shifts_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ShiftsService _shiftsService = ShiftsService();

  // Dynamic stats populated from Firebase
  int _totalShiftsAllTime = 0;
  int _avgPerMonth = 0;
  int _thisMonthShifts = 0;
  int _prevMonthDayTours = 0;
  int _prevMonthNorthernLights = 0;

  // Profile data
  String _userName = 'Unknown Guide';
  String _userRole = 'Tour Guide';
  String _userEmail = '';
  String _userPhone = '';
  String _emergencyContact = 'Not provided';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
      _loadShiftStats();
    });
  }

  void _loadUserData() {
    final authController = context.read<AuthController>();
    final user = authController.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.fullName;
        _userRole = user.role == 'admin' ? 'Administrator' : 'Tour Guide';
        _userEmail = user.email;
        _userPhone = user.phoneNumber.isNotEmpty ? user.phoneNumber : 'Not provided';
      });
    }
  }

  void _loadShiftStats() {
    // Compute stats from guide's shifts
    _shiftsService.getGuideShifts().listen((shifts) {
      if (!mounted) return;

      final now = DateTime.now();
      final thisMonthStart = DateTime(now.year, now.month, 1);
      final prevMonthStart = DateTime(now.year, now.month - 1, 1);
      final prevMonthEnd = DateTime(now.year, now.month, 0);

      final total = shifts.length;
      // Group by month for average (over distinct months present)
      final months = <String, int>{};
      for (final s in shifts) {
        final key = '${s.date.year}-${s.date.month}';
        months[key] = (months[key] ?? 0) + 1;
      }
      final avg = months.isNotEmpty
          ? (months.values.reduce((a, b) => a + b) / months.length).round()
          : 0;

      final thisMonth = shifts.where((s) => s.date.isAfter(thisMonthStart.subtract(const Duration(days: 1))) && s.date.month == now.month && s.date.year == now.year).length;

      final prevMonthDay = shifts.where((s) => s.type.name == 'dayTour' && s.date.isAfter(prevMonthStart.subtract(const Duration(days: 1))) && s.date.isBefore(prevMonthEnd.add(const Duration(days: 1)))).length;
      final prevMonthNl = shifts.where((s) => s.type.name == 'northernLights' && s.date.isAfter(prevMonthStart.subtract(const Duration(days: 1))) && s.date.isBefore(prevMonthEnd.add(const Duration(days: 1)))).length;

      setState(() {
        _totalShiftsAllTime = total;
        _avgPerMonth = avg;
        _thisMonthShifts = thisMonth;
        _prevMonthDayTours = prevMonthDay;
        _prevMonthNorthernLights = prevMonthNl;
      });
    });
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: av.AVColors.slateElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: av.AVColors.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: av.AVColors.textLow,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: av.AVColors.textHigh,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _editProfile() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        return _EditProfileDialog(
          currentName: _userName,
          currentRole: _userRole,
          currentEmail: _userEmail,
          currentPhone: _userPhone,
          currentEmergency: _emergencyContact,
        );
      },
    );

    if (result != null) {
      setState(() {
        _userName = result['name'] ?? _userName;
        _userRole = result['role'] ?? _userRole;
        _userEmail = result['email'] ?? _userEmail;
        _userPhone = result['phone'] ?? _userPhone;
        _emergencyContact = result['emergency'] ?? _emergencyContact;
      });

      try {
        final authController = context.read<AuthController>();
        final currentUser = authController.currentUser;
        if (currentUser != null) {
          final updatedUser = currentUser.copyWith(
            fullName: _userName,
            email: _userEmail,
            phoneNumber: _userPhone,
            role: _userRole.toLowerCase().contains('admin') ? 'admin' : 'guide',
          );
          await authController.updateUserProfile(updatedUser);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _viewSchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('My Schedule'),
            backgroundColor: av.AVColors.slate,
            foregroundColor: av.AVColors.textHigh,
            elevation: 0,
          ),
          body: const ShiftsScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: av.AVColors.slate,
        foregroundColor: av.AVColors.textHigh,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header (no picture, no rating)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: av.AVColors.slate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: av.AVColors.outline),
              ),
              child: Row(
                children: [
                  // Name and role only
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: av.AVColors.textHigh,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _userRole,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: av.AVColors.textLow,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _editProfile,
                    icon: const Icon(Icons.edit, color: av.AVColors.textHigh),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Contact Information
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: av.AVColors.slate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: av.AVColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact Information',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: av.AVColors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Email', _userEmail),
                  _buildInfoRow('Phone', _userPhone),
                  _buildInfoRow('Emergency Contact', _emergencyContact),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Shift Statistics (from Firebase)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: av.AVColors.slate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: av.AVColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shift Statistics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: av.AVColors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Previous Month Breakdown
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: av.AVColors.slateElev,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: av.AVColors.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Previous Month Breakdown',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: av.AVColors.textHigh,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Day Tours',
                                '$_prevMonthDayTours',
                                Icons.wb_sunny,
                                Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildStatCard(
                                'Northern Lights',
                                '$_prevMonthNorthernLights',
                                Icons.nightlight_round,
                                Colors.indigo,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Overall Statistics
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Total Shifts',
                          '$_totalShiftsAllTime',
                          Icons.work,
                          av.AVColors.primaryTeal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Avg/Month',
                          '$_avgPerMonth',
                          Icons.trending_up,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'This Month',
                          '$_thisMonthShifts',
                          Icons.calendar_month,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Quick Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: av.AVColors.slate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: av.AVColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: av.AVColors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _viewSchedule,
                      icon: const Icon(Icons.schedule),
                      label: const Text('View Schedule'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: av.AVColors.textLow,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: av.AVColors.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  final String currentName;
  final String currentRole;
  final String currentEmail;
  final String currentPhone;
  final String currentEmergency;

  const _EditProfileDialog({
    required this.currentName,
    required this.currentRole,
    required this.currentEmail,
    required this.currentPhone,
    required this.currentEmergency,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late TextEditingController _nameController;
  late TextEditingController _roleController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _emergencyController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _roleController = TextEditingController(text: widget.currentRole);
    _emailController = TextEditingController(text: widget.currentEmail);
    _phoneController = TextEditingController(text: widget.currentPhone);
    _emergencyController = TextEditingController(text: widget.currentEmergency);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emergencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emergencyController,
              decoration: const InputDecoration(
                labelText: 'Emergency Contact',
                border: OutlineInputBorder(),
              ),
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
          onPressed: () {
            Navigator.of(context).pop({
              'name': _nameController.text,
              'role': _roleController.text,
              'email': _emailController.text,
              'phone': _phoneController.text,
              'emergency': _emergencyController.text,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
} 