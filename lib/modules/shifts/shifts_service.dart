import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/models/shift_model.dart';
import '../../core/auth/auth_controller.dart';

class ShiftsService {
  static final ShiftsService _instance = ShiftsService._internal();
  factory ShiftsService() => _instance;
  ShiftsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  AuthController? _authController;

  static const String _collectionName = 'shifts';

  // Set the auth controller reference
  void setAuthController(AuthController authController) {
    _authController = authController;
  }

  // Get all shifts for a guide (their applications)
  Stream<List<Shift>> getGuideShifts() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection(_collectionName)
        .where('guideId', isEqualTo: user.uid)
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Shift.fromJson({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList());
  }

  // Get all shifts (admin view)
  Stream<List<Shift>> getAllShifts() {
    return _firestore
        .collection(_collectionName)
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Shift.fromJson({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList());
  }

  // Get shifts for a specific date
  Stream<List<Shift>> getShiftsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _firestore
        .collection(_collectionName)
        .where('date', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
        .where('date', isLessThan: endOfDay.toIso8601String())
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Shift.fromJson({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList());
  }

  // Apply for a shift
  Future<bool> applyForShift({
    required ShiftType type,
    required DateTime date,
    String? startTime,
    String? endTime,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      // Check if already applied for this type on this date
      final existingShifts = await _firestore
          .collection(_collectionName)
          .where('guideId', isEqualTo: user.uid)
          .where('type', isEqualTo: type.name)
          .where('date', isEqualTo: date.toIso8601String())
          .get();

      if (existingShifts.docs.isNotEmpty) {
        print('❌ Already applied for this shift type on this date');
        return false;
      }

      // Get guide name from AuthController if available, otherwise fallback to Firebase Auth
      String guideName = 'Unknown Guide';
      if (_authController?.currentUser != null) {
        guideName = _authController!.currentUser!.fullName;
        print('🔍 Debug: Using AuthController name = "$guideName"');
      } else {
        guideName = user.displayName ?? 'Unknown Guide';
        print('🔍 Debug: Using Firebase Auth displayName = "${user.displayName}"');
      }
      print('🔍 Debug: Final guideName = "$guideName"');
      
      final shiftData = {
        'type': type.name,
        'date': date.toIso8601String(),
        'startTime': startTime ?? '',
        'endTime': endTime ?? '',
        'status': ShiftStatus.applied.name,
        'guideId': user.uid,
        'guideName': guideName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection(_collectionName).add(shiftData);
      print('✅ Successfully applied for shift: ${type.name} on ${date.toString()}');
      return true;
    } catch (e) {
      print('❌ Error applying for shift: $e');
      return false;
    }
  }

  // Update shift status (admin function)
  Future<bool> updateShiftStatus({
    required String shiftId,
    required ShiftStatus status,
    String? adminNote,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      final updateData = <String, dynamic>{
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      };

      if (adminNote != null && adminNote.isNotEmpty) {
        updateData['adminNote'] = adminNote;
      }

      await _firestore.collection(_collectionName).doc(shiftId).update(updateData);
      print('✅ Successfully updated shift status: $shiftId to ${status.name}');
      return true;
    } catch (e) {
      print('❌ Error updating shift status: $e');
      return false;
    }
  }

  // Cancel a shift application (guide function)
  Future<bool> cancelShiftApplication(String shiftId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      // Verify the shift belongs to the current user
      final shiftDoc = await _firestore.collection(_collectionName).doc(shiftId).get();
      if (!shiftDoc.exists) {
        print('❌ Shift not found');
        return false;
      }

      final shiftData = shiftDoc.data()!;
      if (shiftData['guideId'] != user.uid) {
        print('❌ Not authorized to cancel this shift');
        return false;
      }

      // Only allow cancellation if status is 'applied'
      if (shiftData['status'] != ShiftStatus.applied.name) {
        print('❌ Can only cancel shifts with "applied" status');
        return false;
      }

      await _firestore.collection(_collectionName).doc(shiftId).update({
        'status': ShiftStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'cancelledBy': user.uid,
      });

      print('✅ Successfully cancelled shift application: $shiftId');
      return true;
    } catch (e) {
      print('❌ Error cancelling shift application: $e');
      return false;
    }
  }

  // Mark shift as completed (guide function)
  Future<bool> markShiftCompleted(String shiftId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      // Verify the shift belongs to the current user and is accepted
      final shiftDoc = await _firestore.collection(_collectionName).doc(shiftId).get();
      if (!shiftDoc.exists) {
        print('❌ Shift not found');
        return false;
      }

      final shiftData = shiftDoc.data()!;
      if (shiftData['guideId'] != user.uid) {
        print('❌ Not authorized to complete this shift');
        return false;
      }

      if (shiftData['status'] != ShiftStatus.accepted.name) {
        print('❌ Can only complete shifts with "accepted" status');
        return false;
      }

      await _firestore.collection(_collectionName).doc(shiftId).update({
        'status': ShiftStatus.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Successfully marked shift as completed: $shiftId');
      return true;
    } catch (e) {
      print('❌ Error marking shift as completed: $e');
      return false;
    }
  }

  // Get shift statistics for admin dashboard
  Future<Map<String, dynamic>> getShiftStatistics() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      final shiftsQuery = await _firestore
          .collection(_collectionName)
          .where('date', isGreaterThanOrEqualTo: startOfMonth.toIso8601String())
          .where('date', isLessThanOrEqualTo: endOfMonth.toIso8601String())
          .get();

      final shifts = shiftsQuery.docs.map((doc) => Shift.fromJson({
        'id': doc.id,
        ...doc.data(),
      })).toList();

      final stats = {
        'total': shifts.length,
        'applied': shifts.where((s) => s.status == ShiftStatus.applied).length,
        'accepted': shifts.where((s) => s.status == ShiftStatus.accepted).length,
        'completed': shifts.where((s) => s.status == ShiftStatus.completed).length,
        'cancelled': shifts.where((s) => s.status == ShiftStatus.cancelled).length,
        'dayTours': shifts.where((s) => s.type == ShiftType.dayTour).length,
        'northernLights': shifts.where((s) => s.type == ShiftType.northernLights).length,
      };

      return stats;
    } catch (e) {
      print('❌ Error getting shift statistics: $e');
      return {
        'total': 0,
        'applied': 0,
        'accepted': 0,
        'completed': 0,
        'cancelled': 0,
        'dayTours': 0,
        'northernLights': 0,
      };
    }
  }

  // Delete a shift (admin function)
  Future<bool> deleteShift(String shiftId) async {
    try {
      await _firestore.collection(_collectionName).doc(shiftId).delete();
      print('✅ Successfully deleted shift: $shiftId');
      return true;
    } catch (e) {
      print('❌ Error deleting shift: $e');
      return false;
    }
  }
} 