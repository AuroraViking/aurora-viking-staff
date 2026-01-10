// Admin service for handling all admin-related API calls and data management

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

  /// Delete a guide from Firebase
  static Future<bool> deleteGuide(String guideId) async {
    try {
      // Delete the user document from Firestore
      await _firestore.collection('users').doc(guideId).delete();
      
      // Note: This only deletes the Firestore document.
      // To delete the Firebase Auth account, a Cloud Function would be needed.
      
      return true;
    } catch (e) {
      throw Exception('Failed to delete guide: $e');
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
      
      // Get total passengers for the month from tour_reports
      final totalPassengers = await getMonthlyPassengers(year, month);
      
      return {
        'month': '$year-$month',
        'totalShifts': totalShifts,
        'dayTours': dayTours,
        'northernLights': northernLights,
        'totalGuides': totalGuides,
        'totalPassengers': totalPassengers,
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

  /// Get total passengers for a month from tour reports
  static Future<int> getMonthlyPassengers(int year, int month) async {
    try {
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0);
      
      // Format dates as YYYY-MM-DD strings for querying tour_reports
      final startDateStr = _formatDate(startDate);
      final endDateStr = _formatDate(endDate);
      
      int totalPassengers = 0;
      
      // Query tour_reports collection for the month
      // Note: tour_reports use date as string in format YYYY-MM-DD
      final reportsSnapshot = await _firestore
          .collection('tour_reports')
          .where('date', isGreaterThanOrEqualTo: startDateStr)
          .where('date', isLessThanOrEqualTo: endDateStr)
          .get();
      
      for (final doc in reportsSnapshot.docs) {
        final data = doc.data();
        totalPassengers += (data['totalPassengers'] as int?) ?? 0;
      }
      
      return totalPassengers;
    } catch (e) {
      print('Error getting monthly passengers: $e');
      return 0;
    }
  }
  
  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

  // ==================== TOUR REPORTS ====================
  
  /// Get all tour reports (recent ones)
  static Future<List<Map<String, dynamic>>> getTourReports({int days = 30}) async {
    try {
      return await FirebaseService.getRecentTourReports();
    } catch (e) {
      throw Exception('Failed to load tour reports: $e');
    }
  }

  /// Get tour report for a specific date
  static Future<Map<String, dynamic>?> getTourReportForDate(String date) async {
    try {
      return await FirebaseService.getTourReport(date);
    } catch (e) {
      throw Exception('Failed to load tour report: $e');
    }
  }

  // ==================== SHIFTS ANALYTICS ====================
  
  /// Get detailed shifts statistics for a date range
  static Future<Map<String, dynamic>> getShiftsStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore.collection('shifts');
      
      if (startDate != null) {
        query = query.where('date', isGreaterThanOrEqualTo: startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.where('date', isLessThanOrEqualTo: endDate.toIso8601String());
      }
      
      final snapshot = await query.get();
      final shifts = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Shift.fromJson({'id': doc.id, ...data});
      }).toList();
      
      // Calculate statistics
      final totalShifts = shifts.length;
      final byStatus = <String, int>{};
      final byType = <String, int>{};
      final byGuide = <String, Map<String, dynamic>>{};
      
      for (final shift in shifts) {
        // Count by status
        byStatus[shift.status.name] = (byStatus[shift.status.name] ?? 0) + 1;
        
        // Count by type
        byType[shift.type.name] = (byType[shift.type.name] ?? 0) + 1;
        
        // Count by guide (use guideId as key, store name and count)
        if (shift.guideId != null) {
          if (!byGuide.containsKey(shift.guideId!)) {
            byGuide[shift.guideId!] = {
              'guideName': shift.guideName ?? 'Unknown Guide',
              'count': 0,
            };
          }
          byGuide[shift.guideId!]!['count'] = (byGuide[shift.guideId!]!['count'] as int) + 1;
        }
      }
      
      return {
        'totalShifts': totalShifts,
        'byStatus': byStatus,
        'byType': byType,
        'byGuide': byGuide,
        'shifts': shifts.map((s) => s.toJson()).toList(),
      };
    } catch (e) {
      throw Exception('Failed to load shifts statistics: $e');
    }
  }

  // ==================== PICKUP ANALYTICS ====================
  
  /// Get pickup assignments statistics for a date range
  static Future<Map<String, dynamic>> getPickupStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore.collection('pickup_assignments');
      
      final snapshot = await query.get();
      final assignments = snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      
      // Filter by date range if provided
      List<Map<String, dynamic>> filteredAssignments = assignments;
      if (startDate != null || endDate != null) {
        final startStr = startDate != null 
            ? '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}'
            : null;
        final endStr = endDate != null
            ? '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}'
            : null;
        
        filteredAssignments = assignments.where((assignment) {
          final date = assignment['date'] as String?;
          if (date == null) return false;
          if (startStr != null && date.compareTo(startStr) < 0) return false;
          if (endStr != null && date.compareTo(endStr) > 0) return false;
          return true;
        }).toList();
      }
      
      // Calculate statistics
      int totalAssignments = filteredAssignments.length;
      int totalPassengers = 0;
      final byGuide = <String, Map<String, dynamic>>{};
      final byDate = <String, Map<String, dynamic>>{};
      
      for (final assignment in filteredAssignments) {
        final date = assignment['date'] as String? ?? 'unknown';
        final guideId = assignment['guideId'] as String?;
        final guideName = assignment['guideName'] as String? ?? 'Unknown';
        final passengers = (assignment['totalPassengers'] as num?)?.toInt() ?? 0;
        final bookings = (assignment['bookings'] as List?)?.length ?? 0;
        
        totalPassengers += passengers;
        
        // Count by guide
        if (guideId != null) {
          if (!byGuide.containsKey(guideId)) {
            byGuide[guideId] = {
              'guideName': guideName,
              'totalAssignments': 0,
              'totalPassengers': 0,
              'totalBookings': 0,
            };
          }
          byGuide[guideId]!['totalAssignments'] = (byGuide[guideId]!['totalAssignments'] as int) + 1;
          byGuide[guideId]!['totalPassengers'] = (byGuide[guideId]!['totalPassengers'] as int) + passengers;
          byGuide[guideId]!['totalBookings'] = (byGuide[guideId]!['totalBookings'] as int) + bookings;
        }
        
        // Count by date
        if (!byDate.containsKey(date)) {
          byDate[date] = {
            'totalAssignments': 0,
            'totalPassengers': 0,
            'totalBookings': 0,
            'guides': <String>{},
          };
        }
        byDate[date]!['totalAssignments'] = (byDate[date]!['totalAssignments'] as int) + 1;
        byDate[date]!['totalPassengers'] = (byDate[date]!['totalPassengers'] as int) + passengers;
        byDate[date]!['totalBookings'] = (byDate[date]!['totalBookings'] as int) + bookings;
        if (guideId != null) {
          (byDate[date]!['guides'] as Set).add(guideId);
        }
      }
      
      // Convert sets to counts for dates
      final byDateList = byDate.entries.map<Map<String, dynamic>>((entry) {
        final guidesSet = entry.value['guides'] as Set;
        return {
          'date': entry.key,
          'totalAssignments': entry.value['totalAssignments'],
          'totalPassengers': entry.value['totalPassengers'],
          'totalBookings': entry.value['totalBookings'],
          'totalGuides': guidesSet.length,
        };
      }).toList();
      
      // Sort by date descending
      byDateList.sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));
      
      return {
        'totalAssignments': totalAssignments,
        'totalPassengers': totalPassengers,
        'byGuide': byGuide,
        'byDate': byDateList,
      };
    } catch (e) {
      throw Exception('Failed to load pickup statistics: $e');
    }
  }
} 