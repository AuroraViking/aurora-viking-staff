// Home screen as the central hub with bottom navigation or side drawer for module access 
// Now with web compatibility - Photos and Tracking tabs hidden on web!

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:provider/provider.dart';
import '../modules/shifts/shifts_screen.dart';
import '../modules/tracking/tracking_screen.dart';
import '../modules/photos/photo_upload_screen.dart';
import '../modules/photos/web_photo_upload_stub.dart'
    if (dart.library.html) '../modules/photos/web_photo_upload_screen.dart';
import '../modules/profile/profile_screen.dart';
import '../modules/profile/settings_screen.dart';
import '../modules/pickup/pickup_screen.dart';
import '../modules/forecast/forecast_screen.dart';
import '../modules/admin/admin_dashboard.dart';
import '../modules/admin/admin_controller.dart';
import '../core/auth/auth_controller.dart';
import '../core/utils/platform_utils.dart';
import '../core/services/guide_gamification.dart';
import '../modules/radio/radio_screen.dart';
import '../modules/radio/radio_controller.dart';
import '../modules/guide_map/guide_map_screen.dart';
import '../core/services/notification_service.dart';
import '../modules/inbox/unified_inbox_screen.dart';
import '../core/services/bus_management_service.dart';
import '../core/services/location_service.dart';
import '../core/services/platform_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final GuideGamificationService _gamificationService = GuideGamificationService();
  GuideStats? _guideStats;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  bool _hasShownTrackingPopup = false;

  @override
  void initState() {
    super.initState();
    // Initialize radio controller globally so autoplay works from any screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthController>();
      final userId = auth.currentUser?.id ?? '';
      final userName = auth.currentUser?.fullName ?? 'Unknown';
      if (userId.isNotEmpty) {
        context.read<RadioController>().init(userId, userName);
        _loadGamification(userId, userName);
        // Show tracking reminder popup on mobile only
        if (PlatformFeatures.trackingTab && !_hasShownTrackingPopup) {
          _hasShownTrackingPopup = true;
          _showTrackingReminderPopup();
        }
      }
    });

    // Listen for notification taps and navigate accordingly.
    _notificationSub = NotificationService.onNotificationTap.listen(_handleNotificationTap);
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  /// Route the user to the correct screen based on the notification payload.
  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    print('🔔 Handling notification tap: type=$type, data=$data');

    switch (type) {
      case 'radio_message':
        final channelId = data['channelId'] as String?;
        // Open the radio screen and switch to the right channel.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RadioScreen()),
        );
        // Switch channel after a brief delay to let the screen init.
        if (channelId != null && channelId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              context.read<RadioController>().switchChannel(channelId);
            }
          });
        }
        break;
      case 'website_chat':
        // Open the unified inbox.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UnifiedInboxScreen()),
        );
        break;
      // Add more cases here as needed.
      default:
        print('⚠️ Unknown notification type: $type');
    }
  }

  Future<void> _loadGamification(String userId, String userName) async {
    try {
      final stats = await _gamificationService.calculateGuideStats(userId, guideName: userName);
      if (mounted) {
        setState(() => _guideStats = stats);
      }
    } catch (e) {
      print('⚠️ Could not load gamification: $e');
    }
  }

  /// Show a popup asking the guide to select a vehicle for GPS tracking.
  /// Skips if the native tracking service is already running.
  Future<void> _showTrackingReminderPopup() async {
    // Check if already tracking — no need to annoy them
    try {
      final alreadyTracking = await PlatformService.isLocationServiceRunning();
      if (alreadyTracking) {
        print('🚌 Already tracking — skipping reminder popup');
        return;
      }
    } catch (_) {
      // PlatformService not available (e.g. web) — skip
    }

    if (!mounted) return;

    // Load buses
    final busService = BusManagementService();
    List<Map<String, dynamic>> buses = [];
    try {
      buses = await busService.getActiveBuses().first;
    } catch (e) {
      print('⚠️ Could not load buses for tracking popup: $e');
      return;
    }

    if (buses.isEmpty || !mounted) return;

    String? selectedBusId;
    String? selectedBusName;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.directions_bus, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Start Tracking?',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select the vehicle you are driving today so we can track your location.',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedBusId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Choose a vehicle',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500),
                    dropdownColor: Colors.white,
                    icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade700),
                    items: buses.map((bus) {
                      return DropdownMenuItem<String>(
                        value: bus['id'] as String,
                        child: Text(
                          '${bus['name']} (${bus['licensePlate']})',
                          style: const TextStyle(color: Colors.black87, fontSize: 16),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedBusId = value;
                        selectedBusName = buses.firstWhere((b) => b['id'] == value)['name'] as String?;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Skip', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                ),
                ElevatedButton.icon(
                  onPressed: selectedBusId == null
                      ? null
                      : () async {
                          Navigator.pop(dialogContext);
                          // Start tracking
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null && selectedBusId != null) {
                            final locationService = LocationService();
                            final success = await locationService.startTracking(selectedBusId!, user.uid);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? '🚌 Tracking started: $selectedBusName'
                                        : '❌ Failed to start tracking',
                                  ),
                                  backgroundColor: success ? Colors.green : Colors.red,
                                ),
                              );
                              // Switch to the Tracking tab
                              if (success) {
                                final trackingIndex = _navItems.indexWhere((item) => item.label == 'Tracking');
                                if (trackingIndex >= 0) {
                                  setState(() => _selectedIndex = trackingIndex);
                                }
                              }
                            }
                          }
                        },
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start Tracking'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Build screens list based on platform capabilities
  List<Widget> get _screens {
    final screens = <Widget>[
      const ForecastScreen(),
      const ShiftsScreen(),
    ];
    
    // Photos tab: web uses file picker, mobile uses SAF camera access
    if (PlatformFeatures.uploadTab) {
      screens.add(kIsWeb ? WebPhotoUploadScreen() : const PhotoUploadScreen());
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
    
    // Photos tab on all platforms
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
          // Guide Map button
          IconButton(
            icon: const Icon(Icons.map, color: Color(0xFF69F0AE)),
            tooltip: 'Guide Map',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GuideMapScreen()),
              );
            },
          ),
          // Voice Radio button
          IconButton(
            icon: const Icon(Icons.cell_tower, color: Color(0xFF00E5FF)),
            tooltip: 'Voice Radio',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RadioScreen()),
              );
            },
          ),
          // Profile button as username with level
          Consumer<AuthController>(
            builder: (context, authController, child) {
              final userName = authController.currentUser?.fullName ?? 'User';
              final levelText = _guideStats != null
                  ? 'Lv.${_guideStats!.currentLevel.level} '
                  : '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextButton(
                  onPressed: _showProfileMenu,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: Text(
                    '$levelText$userName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
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