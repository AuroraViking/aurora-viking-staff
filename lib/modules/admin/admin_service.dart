// Admin service for handling all admin-related API calls and data management

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/admin_models.dart';
import '../../core/models/user_model.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/shift_model.dart';
import '../../core/utils/constants.dart';
import '../../core/services/firebase_service.dart';

class AdminService {
  static const String baseUrl = AppConstants.apiBaseUrl;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Headers for API requests
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    // TODO: Add authentication headers when API is ready
    // 'Authorization': 'Bearer $token',
  };

  // ==================== STATISTICS & DASHBOARD ====================
  
  /// Get admin dashboard statistics from Firebase
  static Future<AdminStats> getDashboardStats() async {
    try {
      // Get real data from Firebase
      final usersSnapshot = await _firestore.collection('users').get();
      final shiftsSnapshot = await _firestore.collection('shifts').get();
      final pickupAssignmentsSnapshot = await _firestore.collection('pickup_assignments').get();
      
      // Calculate statistics
      final allUsers = usersSnapshot.docs.map((doc) => User.fromJson(doc.data())).toList();
      final guides = allUsers.where((user) => user.role == 'guide').toList();
      final activeGuides = guides.where((guide) => guide.isActive).length;
      
      final allShifts = shiftsSnapshot.docs.map((doc) => Shift.fromJson(doc.data())).toList();
      final pendingShifts = allShifts.where((shift) => shift.status == 'pending').length;
      
      // Get today's date
      final today = DateTime.now();
      final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      // Get today's pickup assignments
      final todayPickups = pickupAssignmentsSnapshot.docs
          .where((doc) => doc.data()['date'] == todayString)
          .length;
      
      // Calculate alerts (simplified for now)
      final alerts = 0; // TODO: Implement real alert system
      
      // Calculate average rating
      final totalRating = guides.fold<double>(0.0, (sum, guide) => sum + 4.5); // Placeholder
      final averageRating = guides.isNotEmpty ? totalRating / guides.length : 0.0;
      
      // Calculate shifts by type
      final shiftsByType = <String, int>{};
      for (final shift in allShifts) {
        shiftsByType[shift.type.name] = (shiftsByType[shift.type.name] ?? 0) + 1;
      }
      
      // Calculate shifts by status
      final shiftsByStatus = <String, int>{};
      for (final shift in allShifts) {
        shiftsByStatus[shift.status.name] = (shiftsByStatus[shift.status.name] ?? 0) + 1;
      }
      
      return AdminStats(
        totalGuides: guides.length,
        activeGuides: activeGuides,
        pendingShifts: pendingShifts,
        todayTours: todayPickups,
        alerts: alerts,
        averageRating: averageRating,
        shiftsByType: shiftsByType,
        shiftsByStatus: shiftsByStatus,
        monthlyStats: [
          MonthlyStats(
            month: 'Current Month',
            totalShifts: allShifts.length,
            dayTours: shiftsByType['dayTour'] ?? 0,
            northernLights: shiftsByType['northernLights'] ?? 0,
            averageRating: averageRating,
            totalGuides: guides.length,
          ),
        ],
      );
    } catch (e) {
      throw Exception('Failed to load dashboard stats: $e');
    }
  }

  // ==================== GUIDE MANAGEMENT ====================
  
  /// Get all guides from Firebase with pagination and filters
  static Future<List<AdminGuide>> getGuides({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
  }) async {
    try {
      Query query = _firestore.collection('users').where('role', isEqualTo: 'guide');
      
      // Apply status filter
      if (status != null) {
        query = query.where('isActive', isEqualTo: status == 'active');
      }
      
      // Apply search filter
      if (search != null && search.isNotEmpty) {
        query = query.where('fullName', isGreaterThanOrEqualTo: search)
                    .where('fullName', isLessThan: search + '\uf8ff');
      }
      
      // Apply pagination
      query = query.limit(limit);
      
      final snapshot = await query.get();
      
      return snapshot.docs.map((doc) {
        final userData = doc.data() as Map<String, dynamic>;
        final user = User.fromJson(userData);
        
        return AdminGuide(
          id: user.id,
          name: user.fullName,
          email: user.email,
          phone: user.phoneNumber,
          profileImageUrl: user.profilePictureUrl ?? '',
          status: user.isActive ? 'active' : 'inactive',
          joinDate: user.createdAt,
          totalShifts: 0, // TODO: Calculate from shifts collection
          rating: 4.5, // TODO: Calculate from ratings
          certifications: [], // TODO: Add certifications field to User model
          preferences: {}, // TODO: Add preferences field to User model
          lastActive: user.createdAt, // TODO: Add lastActive field to User model
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to load guides: $e');
    }
  }

  /// Get a specific guide by ID from Firebase
  static Future<AdminGuide> getGuideById(String guideId) async {
    try {
      final doc = await _firestore.collection('users').doc(guideId).get();
      
      if (!doc.exists) {
        throw Exception('Guide not found');
      }
      
      final userData = doc.data() as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      return AdminGuide(
        id: user.id,
        name: user.fullName,
        email: user.email,
        phone: user.phoneNumber,
        profileImageUrl: user.profilePictureUrl ?? '',
        status: user.isActive ? 'active' : 'inactive',
        joinDate: user.createdAt,
        totalShifts: 0, // TODO: Calculate from shifts collection
        rating: 4.5, // TODO: Calculate from ratings
        certifications: [], // TODO: Add certifications field to User model
        preferences: {}, // TODO: Add preferences field to User model
        lastActive: user.createdAt, // TODO: Add lastActive field to User model
      );
    } catch (e) {
      throw Exception('Failed to load guide: $e');
    }
  }

  /// Update guide status in Firebase
  static Future<bool> updateGuideStatus(String guideId, String status) async {
    try {
      await _firestore.collection('users').doc(guideId).update({
        'isActive': status == 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      throw Exception('Failed to update guide status: $e');
    }
  }

  // ==================== SHIFT MANAGEMENT ====================
  
  /// Get all shifts from Firebase with filters
  static Future<List<AdminShift>> getShifts({
    String? status,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    String? guideId,
  }) async {
    try {
      Query query = _firestore.collection('shifts');
      
      // Apply filters
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      if (type != null) {
        query = query.where('type', isEqualTo: type);
      }
      if (guideId != null) {
        query = query.where('guideId', isEqualTo: guideId);
      }
      if (startDate != null) {
        query = query.where('date', isGreaterThanOrEqualTo: startDate);
      }
      if (endDate != null) {
        query = query.where('date', isLessThanOrEqualTo: endDate);
      }
      
      final snapshot = await query.get();
      
      return snapshot.docs.map((doc) {
        final shiftData = doc.data() as Map<String, dynamic>;
        final shift = Shift.fromJson(shiftData);
        
        // Get guide name from users collection
        String guideName = 'Unknown Guide';
        if (shift.guideId != null) {
          // TODO: Get guide name from users collection
          guideName = 'Guide ${shift.guideId}';
        }
        
        return AdminShift(
          id: shift.id,
          guideId: shift.guideId ?? '',
          guideName: guideName,
          type: shift.type.name,
          date: shift.date,
          status: shift.status.name,
          appliedAt: shift.createdAt ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to load shifts: $e');
    }
  }

  /// Approve a shift application in Firebase
  static Future<bool> approveShift(String shiftId, {String? notes}) async {
    try {
      await _firestore.collection('shifts').doc(shiftId).update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'notes': notes,
      });
      return true;
    } catch (e) {
      throw Exception('Failed to approve shift: $e');
    }
  }

  /// Reject a shift application in Firebase
  static Future<bool> rejectShift(String shiftId, String reason) async {
    try {
      await _firestore.collection('shifts').doc(shiftId).update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
      });
      return true;
    } catch (e) {
      throw Exception('Failed to reject shift: $e');
    }
  }

  // ==================== PICKUP MANAGEMENT ====================
  
  /// Get pickup assignments for a specific date
  static Future<List<GuidePickupList>> getPickupAssignments(String date) async {
    try {
      return await FirebaseService.getPickupAssignments(date);
    } catch (e) {
      throw Exception('Failed to load pickup assignments: $e');
    }
  }
  
  /// Save pickup assignments to Firebase
  static Future<bool> savePickupAssignments({
    required String date,
    required List<GuidePickupList> guideLists,
  }) async {
    try {
      await FirebaseService.savePickupAssignments(
        date: date,
        guideLists: guideLists,
      );
      return true;
    } catch (e) {
      throw Exception('Failed to save pickup assignments: $e');
    }
  }

  // ==================== LIVE TRACKING ====================
  
  /// Get live tracking data for all active guides
  static Future<List<LiveTrackingData>> getLiveTrackingData() async {
    try {
      // TODO: Implement real tracking data from location service
      // For now, return mock data
      await Future.delayed(const Duration(milliseconds: 200));
      return [
        LiveTrackingData(
          guideId: '1',
          guideName: 'John Smith',
          busId: 'bus_001',
          busName: 'Aurora Express 1',
          latitude: 64.9631,
          longitude: -19.0208,
          lastUpdate: DateTime.now().subtract(const Duration(minutes: 2)),
          status: 'active',
          currentShiftId: 'shift_001',
          currentShiftType: 'day_tour',
          speed: 45.0,
          heading: 180.0,
        ),
        LiveTrackingData(
          guideId: '2',
          guideName: 'Sarah Johnson',
          busId: 'bus_002',
          busName: 'Aurora Express 2',
          latitude: 64.9631,
          longitude: -19.0208,
          lastUpdate: DateTime.now().subtract(const Duration(minutes: 5)),
          status: 'idle',
          currentShiftId: null,
          currentShiftType: null,
          speed: 0.0,
          heading: null,
        ),
      ];
    } catch (e) {
      throw Exception('Failed to load tracking data: $e');
    }
  }

  // ==================== ALERTS & NOTIFICATIONS ====================
  
  /// Get all alerts
  static Future<List<AdminAlert>> getAlerts({bool? unreadOnly}) async {
    try {
      // TODO: Implement real alert system
      // For now, return mock data
      await Future.delayed(const Duration(milliseconds: 300));
      return [
        AdminAlert(
          id: '1',
          type: 'shift_conflict',
          title: 'Shift Conflict Detected',
          message: 'John Smith and Sarah Johnson have overlapping shifts on March 15th',
          severity: 'high',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          isRead: false,
          relatedId: 'shift_001',
        ),
        AdminAlert(
          id: '2',
          type: 'weather_warning',
          title: 'Weather Warning',
          message: 'Severe weather conditions expected for Northern Lights tours tonight',
          severity: 'medium',
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          isRead: true,
          relatedId: null,
        ),
      ];
    } catch (e) {
      throw Exception('Failed to load alerts: $e');
    }
  }

  /// Mark alert as read
  static Future<bool> markAlertAsRead(String alertId) async {
    try {
      // TODO: Implement real alert system
      await Future.delayed(const Duration(milliseconds: 200));
      return true;
    } catch (e) {
      throw Exception('Failed to mark alert as read: $e');
    }
  }

  // ==================== REPORTS & ANALYTICS ====================
  
  /// Get monthly report from Firebase data
  static Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    try {
      // Get shifts for the specified month
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0);
      
      final shiftsSnapshot = await _firestore
          .collection('shifts')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();
      
      final shifts = shiftsSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Shift.fromJson(data);
      }).toList();
      
      // Get guides
      final guidesSnapshot = await _firestore.collection('users').where('role', isEqualTo: 'guide').get();
      final guides = guidesSnapshot.docs.map((doc) => User.fromJson(doc.data())).toList();
      
      // Calculate statistics
      final totalShifts = shifts.length;
      final dayTours = shifts.where((shift) => shift.type == ShiftType.dayTour).length;
      final northernLights = shifts.where((shift) => shift.type == ShiftType.northernLights).length;
      final totalGuides = guides.length;
      
      // Calculate top guides
      final guideShifts = <String, int>{};
      for (final shift in shifts) {
        if (shift.guideId != null) {
          guideShifts[shift.guideId!] = (guideShifts[shift.guideId!] ?? 0) + 1;
        }
      }
      
      final topGuides = guideShifts.entries
          .take(5)
          .map((entry) => {
                'name': guides.firstWhere((g) => g.id == entry.key).fullName,
                'shifts': entry.value,
                'rating': 4.5, // TODO: Calculate real rating
              })
          .toList();
      
      return {
        'month': '$year-$month',
        'totalShifts': totalShifts,
        'dayTours': dayTours,
        'northernLights': northernLights,
        'totalGuides': totalGuides,
        'averageRating': 4.5, // TODO: Calculate real average
        'topGuides': topGuides,
        'revenue': 125000, // TODO: Calculate from bookings
        'expenses': 45000, // TODO: Calculate from expenses
        'profit': 80000, // TODO: Calculate profit
      };
    } catch (e) {
      throw Exception('Failed to load monthly report: $e');
    }
  }

  /// Get guide performance report from Firebase
  static Future<Map<String, dynamic>> getGuidePerformanceReport(String guideId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore.collection('shifts').where('guideId', isEqualTo: guideId);
      
      if (startDate != null) {
        query = query.where('date', isGreaterThanOrEqualTo: startDate);
      }
      if (endDate != null) {
        query = query.where('date', isLessThanOrEqualTo: endDate);
      }
      
      final shiftsSnapshot = await query.get();
      final shifts = shiftsSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Shift.fromJson(data);
      }).toList();
      
      // Get guide info
      final guideDoc = await _firestore.collection('users').doc(guideId).get();
      final guideData = guideDoc.data() as Map<String, dynamic>;
      final guide = User.fromJson(guideData);
      
      // Calculate statistics
      final totalShifts = shifts.length;
      final dayTours = shifts.where((shift) => shift.type == ShiftType.dayTour).length;
      final northernLights = shifts.where((shift) => shift.type == ShiftType.northernLights).length;
      final totalHours = totalShifts * 8; // Assuming 8 hours per shift
      
      // Calculate monthly breakdown
      final monthlyBreakdown = <Map<String, dynamic>>[];
      final months = <String>{};
      
      for (final shift in shifts) {
        final monthKey = '${shift.date.year}-${shift.date.month.toString().padLeft(2, '0')}';
        months.add(monthKey);
      }
      
      for (final month in months) {
        final monthShifts = shifts.where((shift) {
          final shiftMonth = '${shift.date.year}-${shift.date.month.toString().padLeft(2, '0')}';
          return shiftMonth == month;
        }).length;
        
        monthlyBreakdown.add({
          'month': month,
          'shifts': monthShifts,
          'rating': 4.5, // TODO: Calculate real rating
        });
      }
      
      return {
        'guideId': guideId,
        'guideName': guide.fullName,
        'totalShifts': totalShifts,
        'dayTours': dayTours,
        'northernLights': northernLights,
        'averageRating': 4.5, // TODO: Calculate real rating
        'totalHours': totalHours,
        'onTimePercentage': 95.5, // TODO: Calculate from tracking data
        'customerSatisfaction': 4.5, // TODO: Calculate from ratings
        'monthlyBreakdown': monthlyBreakdown,
      };
    } catch (e) {
      throw Exception('Failed to load guide performance report: $e');
    }
  }

  // ==================== UTILITY METHODS ====================
  
  /// Send notification to guide
  static Future<bool> sendNotificationToGuide(String guideId, String message) async {
    try {
      // TODO: Implement real notification system
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    } catch (e) {
      throw Exception('Failed to send notification: $e');
    }
  }

  /// Export data to CSV/Excel
  static Future<String> exportData(String dataType, {
    DateTime? startDate,
    DateTime? endDate,
    String? format,
  }) async {
    try {
      // TODO: Implement real export functionality
      await Future.delayed(const Duration(milliseconds: 1000));
      return 'export_${dataType}_${DateTime.now().millisecondsSinceEpoch}.csv';
    } catch (e) {
      throw Exception('Failed to export data: $e');
    }
  }
} 