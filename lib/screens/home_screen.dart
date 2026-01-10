// Home screen as the central hub with bottom navigation or side drawer for module access 
// Now with web compatibility - Photos and Tracking tabs hidden on web!

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../modules/shifts/shifts_screen.dart';
import '../modules/tracking/tracking_screen.dart';
import '../modules/photos/photo_upload_screen.dart';
import '../modules/profile/profile_screen.dart';
import '../modules/profile/settings_screen.dart';
import '../modules/pickup/pickup_screen.dart';
import '../modules/forecast/forecast_screen.dart';
import '../modules/admin/admin_dashboard.dart';
import '../modules/admin/admin_controller.dart';
import '../core/auth/auth_controller.dart';
import '../core/utils/platform_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
  }

  // Build screens list based on platform capabilities
  List<Widget> get _screens {
    final screens = <Widget>[
      const ForecastScreen(),
      const ShiftsScreen(),
    ];
    
    // Only add Photos tab on mobile (requires native file system)
    if (PlatformFeatures.uploadTab) {
      screens.add(const PhotoUploadScreen());
    }
    
    // Only add Tracking tab on mobile (requires native GPS)
    if (PlatformFeatures.trackingTab) {
      screens.add(const TrackingScreen());
    }
    
    // Pickup list works on all platforms
    screens.add(const PickupScreen());
    
    return screens;
  }

  // Build navigation items based on platform capabilities
  List<BottomNavigationBarItem> get _navItems {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.auto_awesome),
        label: 'Forecast',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.work),
        label: 'Shifts',
      ),
    ];
    
    // Only add Photos tab on mobile
    if (PlatformFeatures.uploadTab) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.camera_alt),
        label: 'Photos',
      ));
    }
    
    // Only add Tracking tab on mobile
    if (PlatformFeatures.trackingTab) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.location_on),
        label: 'Tracking',
      ));
    }
    
    // Pickup list works on all platforms
    items.add(const BottomNavigationBarItem(
      icon: Icon(Icons.assignment),
      label: 'Pickup',
    ));
    
    return items;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2D3748), // Dark theme background for consistency
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6), // White with opacity for better visibility
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: const Text(
                'View Profile',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white),
              title: const Text(
                'Settings',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final authController = context.read<AuthController>();
                await authController.signOut();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Successfully logged out'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            // Show platform info on web
            if (isWeb) ...[
              const Divider(color: Colors.white24),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Web version - Some features require the mobile app',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: isWeb
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'WEB',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              )
            : null,
        centerTitle: true,
        leading: Consumer<AdminController>(
          builder: (context, adminController, child) {
            return IconButton(
              icon: Icon(
                adminController.isAdminMode ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                color: adminController.isAdminMode ? Colors.amber : Colors.white,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminDashboard()),
                );
              },
              tooltip: adminController.isAdminMode ? 'Admin Dashboard (Active)' : 'Admin Dashboard',
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications - Coming Soon')),
              );
            },
          ),
          // Profile button as username
          Consumer<AuthController>(
            builder: (context, authController, child) {
              final userName = authController.currentUser?.fullName ?? 'User';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: TextButton.icon(
                  onPressed: _showProfileMenu,
                  icon: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, size: 16, color: Colors.white),
                  ),
                  label: Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: _navItems,
      ),
    );
  }
} 