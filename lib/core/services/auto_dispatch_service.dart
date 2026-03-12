// Auto-dispatch service for automated pickup distribution
// Handles: guide need calculation, guide/bus ranking selection,
// 30-min pre-pickup auto-distribute, and 10-min last-minute re-distribute

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/pickup_models.dart';
import 'firebase_service.dart';
import 'bus_management_service.dart';
import '../../modules/shifts/shifts_service.dart';
import '../models/shift_model.dart';
import '../../modules/pickup/pickup_controller.dart';

class AutoDispatchService {
  static final AutoDispatchService _instance = AutoDispatchService._internal();
  factory AutoDispatchService() => _instance;
  AutoDispatchService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ShiftsService _shiftsService = ShiftsService();
  final BusManagementService _busService = BusManagementService();

  // Track which dates have been auto-dispatched to avoid repeating
  final Set<String> _dispatchedDates = {};
  // Track last-minute re-dispatch timestamps
  final Map<String, DateTime> _lastReDispatchTime = {};

  /// Calculate how many guides are needed for a given passenger count.
  /// Formula: ceil(totalPax / 18) — 18 per bus with 1 seat buffer.
  static int calculateGuidesNeeded(int totalPassengers) {
    if (totalPassengers <= 0) return 0;
    return (totalPassengers / 18).ceil();
  }

  /// Get guides who have accepted shifts for a given date, sorted by priority (highest first).
  Future<List<User>> getAvailableGuides(DateTime date) async {
    try {
      // Get all shifts for the date
      final shifts = await _shiftsService.getAllShiftsForDate(date);
      
      // Filter to accepted shifts only
      final acceptedShifts = shifts.where(
        (s) => s.status == ShiftStatus.accepted && s.guideId != null,
      ).toList();

      if (acceptedShifts.isEmpty) return [];

      // Get guide user docs to read priority
      final guideIds = acceptedShifts.map((s) => s.guideId!).toSet().toList();
      final List<User> guides = [];

      for (final guideId in guideIds) {
        try {
          final doc = await _firestore.collection('users').doc(guideId).get();
          if (doc.exists) {
            final userData = doc.data()!;
            final user = User.fromJson(userData);
            // Attach priority for sorting
            guides.add(user);
          }
        } catch (e) {
          print('⚠️ Could not load guide $guideId: $e');
        }
      }

      // Sort by priority descending (read from Firestore)
      // We need to re-fetch priority since User model may not have it
      final priorityMap = <String, int>{};
      for (final guideId in guideIds) {
        try {
          final doc = await _firestore.collection('users').doc(guideId).get();
          if (doc.exists) {
            priorityMap[guideId] = (doc.data()?['priority'] as int?) ?? 0;
          }
        } catch (_) {}
      }

      guides.sort((a, b) => (priorityMap[b.id] ?? 0).compareTo(priorityMap[a.id] ?? 0));

      return guides;
    } catch (e) {
      print('❌ Error getting available guides: $e');
      return [];
    }
  }

  /// Get active buses sorted by priority (highest first).
  /// Returns a one-shot list (not a stream).
  Future<List<Map<String, dynamic>>> getAvailableBuses() async {
    try {
      final snapshot = await _firestore
          .collection('buses')
          .where('isActive', isEqualTo: true)
          .get();

      final buses = snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();

      // Sort by priority descending
      buses.sort((a, b) => ((b['priority'] as int?) ?? 0).compareTo((a['priority'] as int?) ?? 0));

      return buses;
    } catch (e) {
      print('❌ Error getting available buses: $e');
      return [];
    }
  }

  /// Check if bookings for a date have already been distributed to guides.
  bool _isAlreadyDistributed(PickupController controller) {
    return controller.guideLists.isNotEmpty &&
        controller.guideLists.any((gl) => gl.bookings.isNotEmpty);
  }

  /// Format date as YYYY-MM-DD string
  String _dateStr(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parse earliest pickup time from bookings.
  /// Returns null if no valid pickup times found.
  DateTime? _getEarliestPickupTime(List<PickupBooking> bookings, DateTime date) {
    DateTime? earliest;
    for (final booking in bookings) {
      final pickupDateTime = DateTime(
        date.year, date.month, date.day,
        booking.pickupTime.hour, booking.pickupTime.minute,
      );
      if (earliest == null || pickupDateTime.isBefore(earliest)) {
        earliest = pickupDateTime;
      }
    }
    return earliest;
  }

  /// Main auto-dispatch check — call this on every refresh.
  /// Returns true if auto-dispatch was triggered.
  Future<bool> autoDispatchIfNeeded(PickupController controller) async {
    final date = controller.selectedDate;
    final dateKey = _dateStr(date);
    final bookings = controller.bookings;

    if (bookings.isEmpty) return false;

    // Already dispatched this session?
    if (_dispatchedDates.contains(dateKey) && _isAlreadyDistributed(controller)) {
      return false;
    }

    // Get total passengers
    final totalPax = bookings.fold<int>(0, (sum, b) => sum + b.numberOfGuests);
    if (totalPax <= 0) return false;

    // Get earliest pickup time
    final earliestPickup = _getEarliestPickupTime(bookings, date);
    if (earliestPickup == null) return false;

    final now = DateTime.now();
    final minutesUntilPickup = earliestPickup.difference(now).inMinutes;

    // Check 30-minute trigger: not yet distributed
    if (minutesUntilPickup <= 30 && minutesUntilPickup > 0 && !_isAlreadyDistributed(controller)) {
      print('🤖 Auto-dispatch triggered: ${minutesUntilPickup}min until pickup, $totalPax passengers');
      final success = await _executeAutoDispatch(controller, date, totalPax);
      if (success) {
        _dispatchedDates.add(dateKey);
      }
      return success;
    }

    return false;
  }

  /// Handle a last-minute booking detected ≤10 min before departure.
  /// Re-distributes to the EXISTING guides (doesn't add new ones).
  Future<bool> handleLastMinuteBooking(PickupController controller) async {
    final date = controller.selectedDate;
    final dateKey = _dateStr(date);
    final bookings = controller.bookings;

    if (bookings.isEmpty) return false;
    if (!_isAlreadyDistributed(controller)) return false;

    final earliestPickup = _getEarliestPickupTime(bookings, date);
    if (earliestPickup == null) return false;

    final now = DateTime.now();
    final minutesUntilPickup = earliestPickup.difference(now).inMinutes;

    // Only trigger within 10 minutes of departure
    if (minutesUntilPickup > 10 || minutesUntilPickup <= 0) return false;

    // Throttle: don't re-dispatch more than once per 5 minutes
    final lastRun = _lastReDispatchTime[dateKey];
    if (lastRun != null && now.difference(lastRun).inMinutes < 5) return false;

    // Check if there are unassigned bookings (the new last-minute ones)
    final unassigned = bookings.where((b) => b.assignedGuideId == null).toList();
    if (unassigned.isEmpty) return false;

    print('🤖 Last-minute re-dispatch: ${unassigned.length} new bookings, ${minutesUntilPickup}min until pickup');

    // Get the current guides (from existing guide lists)
    final existingGuides = <User>[];
    for (final gl in controller.guideLists) {
      try {
        final doc = await _firestore.collection('users').doc(gl.guideId).get();
        if (doc.exists) {
          existingGuides.add(User.fromJson(doc.data()!));
        }
      } catch (_) {}
    }

    if (existingGuides.isEmpty) return false;

    // Re-distribute with existing guides
    await controller.distributeBookings(existingGuides);
    await controller.autoSortAllGuides();

    _lastReDispatchTime[dateKey] = now;
    return true;
  }

  /// Execute auto-dispatch: select guides by rank, assign buses, distribute, sort.
  Future<bool> _executeAutoDispatch(PickupController controller, DateTime date, int totalPax) async {
    try {
      // 1. Calculate guides needed
      final guidesNeeded = calculateGuidesNeeded(totalPax);
      print('📊 Need $guidesNeeded guides for $totalPax passengers');

      // 2. Get available guides (accepted shifts, sorted by priority)
      final availableGuides = await getAvailableGuides(date);
      if (availableGuides.isEmpty) {
        print('⚠️ No guides with accepted shifts for this date');
        return false;
      }

      // Take only as many as needed
      final selectedGuides = availableGuides.take(guidesNeeded).toList();
      print('👤 Selected ${selectedGuides.length} guides: ${selectedGuides.map((g) => g.fullName).join(', ')}');

      // 3. Get available buses (sorted by priority)
      final availableBuses = await getAvailableBuses();

      // 4. Distribute bookings
      await controller.distributeBookings(selectedGuides);

      // 5. Auto-sort
      await controller.autoSortAllGuides();

      // 6. Assign buses (one per guide, by priority order)
      final dateStr = _dateStr(date);
      for (int i = 0; i < selectedGuides.length && i < availableBuses.length; i++) {
        final guide = selectedGuides[i];
        final bus = availableBuses[i];
        
        await FirebaseService.saveBusGuideAssignment(
          guideId: guide.id,
          guideName: guide.fullName,
          busId: bus['id'] as String,
          busName: bus['name'] as String? ?? 'Unknown Bus',
          date: dateStr,
        );
        print('🚌 Assigned bus ${bus['name']} to ${guide.fullName}');
      }

      print('✅ Auto-dispatch complete: ${selectedGuides.length} guides, ${availableBuses.length} buses');
      return true;
    } catch (e) {
      print('❌ Auto-dispatch failed: $e');
      return false;
    }
  }

  /// Reset dispatch tracking (call when date changes)
  void resetForDate(String dateKey) {
    _dispatchedDates.remove(dateKey);
    _lastReDispatchTime.remove(dateKey);
  }
}
