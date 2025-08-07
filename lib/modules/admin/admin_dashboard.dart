// Admin dashboard for accepting/declining shifts, viewing map, and messaging guides 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/colors.dart';
import '../../core/models/admin_models.dart';
import 'admin_controller.dart';
import 'admin_service.dart';
import 'admin_map_screen.dart';
import 'admin_shift_management_screen.dart';
import 'admin_guide_management_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_pickup_management_screen.dart';
import 'admin_tour_calendar_screen.dart';
import 'tour_management_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  AdminStats? _stats;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (!context.read<AdminController>().isAdminMode) return;
    
    setState(() {
      _isLoadingStats = true;
    });

    try {
      final stats = await AdminService.getDashboardStats();
      
      setState(() {
        _stats = stats;
        _isLoadingStats = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStats = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading dashboard data: $e')),
      );
    }
  }

  void _showAdminLoginDialog() {
    _passwordController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Admin Login'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter admin password to access administrative features.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) => _loginToAdmin(),
              ),
              if (context.watch<AdminController>().errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.watch<AdminController>().errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.read<AdminController>().clearError();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: context.watch<AdminController>().isLoading
                  ? null
                  : _loginToAdmin,
              child: context.watch<AdminController>().isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        );
      },
    );
  }

  void _loginToAdmin() async {
    final success = await context
        .read<AdminController>()
        .loginToAdminMode(_passwordController.text);
    
    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin mode activated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadDashboardData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminController>(
      builder: (context, adminController, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              if (adminController.isAdminMode) ...[
                IconButton(
                  onPressed: _loadDashboardData,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Data',
                ),
                IconButton(
                  onPressed: () {
                    adminController.logoutFromAdminMode();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Admin mode deactivated'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout from Admin Mode',
                ),
              ],
            ],
          ),
          body: adminController.isAdminMode
              ? _buildAdminContent()
              : _buildLoginPrompt(),
        );
      },
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.admin_panel_settings,
              size: 80,
              color: AppColors.primary.withOpacity(0.6),
            ),
            const SizedBox(height: 24),
            Text(
              'Admin Access Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'To access administrative features, you need to log in with admin credentials.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showAdminLoginDialog,
                icon: const Icon(Icons.login),
                label: const Text('Login to Admin Mode'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin Status Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Admin Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Quick Stats
          Text(
            'Quick Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isLoadingStats)
            const Center(child: CircularProgressIndicator())
          else if (_stats != null) ...[
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Active Guides',
                    _stats!.activeGuides.toString(),
                    Icons.people,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Pending Shifts',
                    _stats!.pendingShifts.toString(),
                    Icons.schedule,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Today\'s Tours',
                    _stats!.todayTours.toString(),
                    Icons.directions_bus,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Alerts',
                    _stats!.alerts.toString(),
                    Icons.warning,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 32),
          
          // Admin Actions
          Text(
            'Admin Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildActionCard(
            'Live Tracking Map',
            'Monitor all active tours and guide locations in real-time',
            Icons.map,
            Colors.blue,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminMapScreen(),
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          _buildActionCard(
            'Shift Management',
            'Review and approve pending shift applications',
            Icons.work,
            Colors.orange,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminShiftManagementScreen(),
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          _buildActionCard(
            'Pickup Management',
            'Distribute pickup lists to guides',
            Icons.assignment,
            Colors.teal,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminPickupManagementScreen(),
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          _buildActionCard(
            'Tour Calendar',
            'View bookings and assign guides to buses',
            Icons.calendar_month,
            Colors.indigo,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminTourCalendarScreen(),
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          _buildActionCard(
            'Test API Connection',
            'Test Bokun API connection and view response',
            Icons.api,
            Colors.orange,
            () => _testApiConnection(),
          ),
          
          _buildActionCard(
            'Guide Management',
            'View and manage all registered guides',
            Icons.people,
            Colors.green,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminGuideManagementScreen(),
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          _buildActionCard(
            'Reports & Analytics',
            'View detailed reports and performance analytics',
            Icons.analytics,
            Colors.purple,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminReportsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _testApiConnection() async {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Testing API Connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Testing Bokun API connection...'),
          ],
        ),
      ),
    );

    try {
      final service = TourManagementService();
      final result = await service.testApiConnection();
      
      Navigator.of(context).pop(); // Close loading dialog
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result['success'] ? '✅ API Test Successful' : '❌ API Test Failed'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Status: ${result['success'] ? 'SUCCESS' : 'FAILED'}'),
                if (result['statusCode'] != null) Text('Status Code: ${result['statusCode']}'),
                if (result['bookingsCount'] != null) Text('Bookings Found: ${result['bookingsCount']}'),
                if (result['responsePreview'] != null) ...[
                  const SizedBox(height: 8),
                  const Text('Response Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(result['responsePreview']),
                ],
                if (result['error'] != null) ...[
                  const SizedBox(height: 8),
                  const Text('Error:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(result['error']),
                ],
                if (result['responseBody'] != null) ...[
                  const SizedBox(height: 8),
                  const Text('Response Body:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      result['responseBody'],
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                if (result['accessKey'] != null) Text('Access Key: ${result['accessKey']}'),
                if (result['secretKey'] != null) Text('Secret Key: ${result['secretKey']}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ API Test Error'),
          content: Text('Error testing API connection: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
} 