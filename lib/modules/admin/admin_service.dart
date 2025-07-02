// Admin service for handling all admin-related API calls and data management

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/admin_models.dart';
import '../../core/utils/constants.dart';

class AdminService {
  static const String baseUrl = AppConstants.apiBaseUrl;
  
  // Headers for API requests
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    // TODO: Add authentication headers when API is ready
    // 'Authorization': 'Bearer $token',
  };

  // ==================== STATISTICS & DASHBOARD ====================
  
  /// Get admin dashboard statistics
  static Future<AdminStats> getDashboardStats() async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/stats'),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   return AdminStats.fromJson(json.decode(response.body));
      // } else {
      //   throw Exception('Failed to load dashboard stats');
      // }
      
      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 500));
      return AdminStats(
        totalGuides: 15,
        activeGuides: 12,
        pendingShifts: 8,
        todayTours: 5,
        alerts: 2,
        averageRating: 4.7,
        shiftsByType: {
          'day_tour': 45,
          'northern_lights': 32,
        },
        shiftsByStatus: {
          'pending': 8,
          'approved': 15,
          'completed': 54,
        },
        monthlyStats: [
          MonthlyStats(
            month: 'January',
            totalShifts: 45,
            dayTours: 28,
            northernLights: 17,
            averageRating: 4.6,
            totalGuides: 12,
          ),
          MonthlyStats(
            month: 'February',
            totalShifts: 52,
            dayTours: 31,
            northernLights: 21,
            averageRating: 4.8,
            totalGuides: 14,
          ),
        ],
      );
    } catch (e) {
      throw Exception('Failed to load dashboard stats: $e');
    }
  }

  // ==================== GUIDE MANAGEMENT ====================
  
  /// Get all guides with pagination and filters
  static Future<List<AdminGuide>> getGuides({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
  }) async {
    try {
      // TODO: Replace with actual API call
      // final queryParams = {
      //   'page': page.toString(),
      //   'limit': limit.toString(),
      //   if (status != null) 'status': status,
      //   if (search != null) 'search': search,
      // };
      // 
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/guides').replace(queryParameters: queryParams),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   final List<dynamic> guidesJson = json.decode(response.body)['guides'];
      //   return guidesJson.map((json) => AdminGuide.fromJson(json)).toList();
      // } else {
      //   throw Exception('Failed to load guides');
      // }
      
      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 300));
      return [
        AdminGuide(
          id: '1',
          name: 'John Smith',
          email: 'john.smith@auroraviking.com',
          phone: '+1 (555) 123-4567',
          profileImageUrl: 'https://example.com/john.jpg',
          status: 'active',
          joinDate: DateTime(2023, 1, 15),
          totalShifts: 45,
          rating: 4.8,
          certifications: ['First Aid', 'Tour Guide License'],
          preferences: {'preferred_shift': 'day_tour'},
          lastActive: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        AdminGuide(
          id: '2',
          name: 'Sarah Johnson',
          email: 'sarah.johnson@auroraviking.com',
          phone: '+1 (555) 234-5678',
          profileImageUrl: 'https://example.com/sarah.jpg',
          status: 'active',
          joinDate: DateTime(2023, 3, 10),
          totalShifts: 38,
          rating: 4.9,
          certifications: ['First Aid', 'Tour Guide License', 'Wilderness Safety'],
          preferences: {'preferred_shift': 'northern_lights'},
          lastActive: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
      ];
    } catch (e) {
      throw Exception('Failed to load guides: $e');
    }
  }

  /// Get a specific guide by ID
  static Future<AdminGuide> getGuideById(String guideId) async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/guides/$guideId'),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   return AdminGuide.fromJson(json.decode(response.body));
      // } else {
      //   throw Exception('Failed to load guide');
      // }
      
      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 200));
      return AdminGuide(
        id: guideId,
        name: 'John Smith',
        email: 'john.smith@auroraviking.com',
        phone: '+1 (555) 123-4567',
        profileImageUrl: 'https://example.com/john.jpg',
        status: 'active',
        joinDate: DateTime(2023, 1, 15),
        totalShifts: 45,
        rating: 4.8,
        certifications: ['First Aid', 'Tour Guide License'],
        preferences: {'preferred_shift': 'day_tour'},
        lastActive: DateTime.now().subtract(const Duration(hours: 2)),
      );
    } catch (e) {
      throw Exception('Failed to load guide: $e');
    }
  }

  /// Update guide status
  static Future<bool> updateGuideStatus(String guideId, String status) async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.patch(
      //   Uri.parse('$baseUrl/admin/guides/$guideId/status'),
      //   headers: _headers,
      //   body: json.encode({'status': status}),
      // );
      
      // return response.statusCode == 200;
      
      // Mock success for now
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    } catch (e) {
      throw Exception('Failed to update guide status: $e');
    }
  }

  // ==================== SHIFT MANAGEMENT ====================
  
  /// Get all shifts with filters
  static Future<List<AdminShift>> getShifts({
    String? status,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    String? guideId,
  }) async {
    try {
      // TODO: Replace with actual API call
      // final queryParams = {
      //   if (status != null) 'status': status,
      //   if (type != null) 'type': type,
      //   if (startDate != null) 'startDate': startDate.toIso8601String(),
      //   if (endDate != null) 'endDate': endDate.toIso8601String(),
      //   if (guideId != null) 'guideId': guideId,
      // };
      // 
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/shifts').replace(queryParameters: queryParams),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   final List<dynamic> shiftsJson = json.decode(response.body)['shifts'];
      //   return shiftsJson.map((json) => AdminShift.fromJson(json)).toList();
      // } else {
      //   throw Exception('Failed to load shifts');
      // }
      
      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 400));
      return [
        AdminShift(
          id: '1',
          guideId: '1',
          guideName: 'John Smith',
          type: 'day_tour',
          date: DateTime.now().add(const Duration(days: 2)),
          status: 'pending',
          appliedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        AdminShift(
          id: '2',
          guideId: '2',
          guideName: 'Sarah Johnson',
          type: 'northern_lights',
          date: DateTime.now().add(const Duration(days: 1)),
          status: 'pending',
          appliedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];
    } catch (e) {
      throw Exception('Failed to load shifts: $e');
    }
  }

  /// Approve a shift application
  static Future<bool> approveShift(String shiftId, {String? notes}) async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.post(
      //   Uri.parse('$baseUrl/admin/shifts/$shiftId/approve'),
      //   headers: _headers,
      //   body: json.encode({'notes': notes}),
      // );
      
      // return response.statusCode == 200;
      
      // Mock success for now
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      throw Exception('Failed to approve shift: $e');
    }
  }

  /// Reject a shift application
  static Future<bool> rejectShift(String shiftId, String reason) async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.post(
      //   Uri.parse('$baseUrl/admin/shifts/$shiftId/reject'),
      //   headers: _headers,
      //   body: json.encode({'reason': reason}),
      // );
      
      // return response.statusCode == 200;
      
      // Mock success for now
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      throw Exception('Failed to reject shift: $e');
    }
  }

  // ==================== LIVE TRACKING ====================
  
  /// Get live tracking data for all active guides
  static Future<List<LiveTrackingData>> getLiveTrackingData() async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/tracking/live'),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   final List<dynamic> trackingJson = json.decode(response.body)['tracking'];
      //   return trackingJson.map((json) => LiveTrackingData.fromJson(json)).toList();
      // } else {
      //   throw Exception('Failed to load tracking data');
      // }
      
      // Mock data for now
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
      // TODO: Replace with actual API call
      // final queryParams = {
      //   if (unreadOnly != null) 'unreadOnly': unreadOnly.toString(),
      // };
      // 
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/alerts').replace(queryParameters: queryParams),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   final List<dynamic> alertsJson = json.decode(response.body)['alerts'];
      //   return alertsJson.map((json) => AdminAlert.fromJson(json)).toList();
      // } else {
      //   throw Exception('Failed to load alerts');
      // }
      
      // Mock data for now
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
      // TODO: Replace with actual API call
      // final response = await http.patch(
      //   Uri.parse('$baseUrl/admin/alerts/$alertId/read'),
      //   headers: _headers,
      // );
      
      // return response.statusCode == 200;
      
      // Mock success for now
      await Future.delayed(const Duration(milliseconds: 200));
      return true;
    } catch (e) {
      throw Exception('Failed to mark alert as read: $e');
    }
  }

  // ==================== REPORTS & ANALYTICS ====================
  
  /// Get monthly report
  static Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/reports/monthly/$year/$month'),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   return json.decode(response.body);
      // } else {
      //   throw Exception('Failed to load monthly report');
      // }
      
      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 600));
      return {
        'month': '$year-$month',
        'totalShifts': 45,
        'dayTours': 28,
        'northernLights': 17,
        'totalGuides': 12,
        'averageRating': 4.7,
        'topGuides': [
          {'name': 'John Smith', 'shifts': 8, 'rating': 4.9},
          {'name': 'Sarah Johnson', 'shifts': 7, 'rating': 4.8},
        ],
        'revenue': 125000,
        'expenses': 45000,
        'profit': 80000,
      };
    } catch (e) {
      throw Exception('Failed to load monthly report: $e');
    }
  }

  /// Get guide performance report
  static Future<Map<String, dynamic>> getGuidePerformanceReport(String guideId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // TODO: Replace with actual API call
      // final queryParams = {
      //   if (startDate != null) 'startDate': startDate.toIso8601String(),
      //   if (endDate != null) 'endDate': endDate.toIso8601String(),
      // };
      // 
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/reports/guides/$guideId/performance')
      //       .replace(queryParameters: queryParams),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   return json.decode(response.body);
      // } else {
      //   throw Exception('Failed to load guide performance report');
      // }
      
      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 400));
      return {
        'guideId': guideId,
        'guideName': 'John Smith',
        'totalShifts': 45,
        'dayTours': 28,
        'northernLights': 17,
        'averageRating': 4.8,
        'totalHours': 360,
        'onTimePercentage': 95.5,
        'customerSatisfaction': 4.9,
        'monthlyBreakdown': [
          {'month': 'January', 'shifts': 8, 'rating': 4.7},
          {'month': 'February', 'shifts': 7, 'rating': 4.9},
        ],
      };
    } catch (e) {
      throw Exception('Failed to load guide performance report: $e');
    }
  }

  // ==================== UTILITY METHODS ====================
  
  /// Send notification to guide
  static Future<bool> sendNotificationToGuide(String guideId, String message) async {
    try {
      // TODO: Replace with actual API call
      // final response = await http.post(
      //   Uri.parse('$baseUrl/admin/notifications/send'),
      //   headers: _headers,
      //   body: json.encode({
      //     'guideId': guideId,
      //     'message': message,
      //   }),
      // );
      
      // return response.statusCode == 200;
      
      // Mock success for now
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
      // TODO: Replace with actual API call
      // final queryParams = {
      //   'dataType': dataType,
      //   if (startDate != null) 'startDate': startDate.toIso8601String(),
      //   if (endDate != null) 'endDate': endDate.toIso8601String(),
      //   'format': format ?? 'csv',
      // };
      // 
      // final response = await http.get(
      //   Uri.parse('$baseUrl/admin/export').replace(queryParameters: queryParams),
      //   headers: _headers,
      // );
      
      // if (response.statusCode == 200) {
      //   return response.body;
      // } else {
      //   throw Exception('Failed to export data');
      // }
      
      // Mock success for now
      await Future.delayed(const Duration(milliseconds: 1000));
      return 'export_${dataType}_${DateTime.now().millisecondsSinceEpoch}.csv';
    } catch (e) {
      throw Exception('Failed to export data: $e');
    }
  }
} 