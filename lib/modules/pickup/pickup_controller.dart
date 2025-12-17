import 'package:flutter/material.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
import 'pickup_service.dart';
import '../../core/services/firebase_service.dart';

class PickupController extends ChangeNotifier {
  final PickupService _pickupService = PickupService();

  DateTime _selectedDate = DateTime.now();
  List<PickupBooking> _currentUserBookings = [];
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  // Properties for calendar functionality
  Map<DateTime, List<PickupBooking>> _monthData = {};

  // Properties for admin functionality
  List<PickupBooking> _bookings = [];
  List<GuidePickupList> _guideLists = [];
  PickupListStats? _stats;

  // Getters
  DateTime get selectedDate => _selectedDate;
  List<PickupBooking> get currentUserBookings => _currentUserBookings;
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Calendar getters
  bool get hasError => _error != null;
  String get errorMessage => _error ?? 'Unknown error';
  Map<DateTime, List<PickupBooking>> get monthData => _monthData;

  // Admin getters
  List<PickupBooking> get bookings => _bookings;
  List<GuidePickupList> get guideLists => _guideLists;
  PickupListStats? get stats => _stats;

  // Get unassigned bookings
  List<PickupBooking> get unassignedBookings =>
      _bookings.where((booking) => booking.assignedGuideId == null).toList();

  // Load bookings for a specific date with Firebase statuses
  // FIX: Added comprehensive error handling and guaranteed loading state reset
  Future<void> loadBookingsForDate(DateTime date) async {
    // FIX: Guard against calling when user is null
    if (_currentUser == null) {
      print('⚠️ Cannot load bookings: current user is null');
      _currentUserBookings = [];
      _error = null; // Don't show error for this expected case
      notifyListeners();
      return;
    }

    _setLoading(true);
    _error = null;

    try {
      print('📥 Loading bookings for date: $date, user: ${_currentUser!.fullName} (${_currentUser!.id})');

      final bookings = await _pickupService.fetchBookingsForDate(date);

      // Don't clear existing bookings if API returns empty - might be a temporary issue
      if (bookings.isEmpty && _bookings.isNotEmpty) {
        print('⚠️ API returned empty bookings but we have existing bookings. Keeping existing data.');
        _setLoading(false);
        return;
      }

      // Load statuses from Firebase
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      // FIX: Wrap Firebase calls in individual try-catch blocks
      Map<String, Map<String, dynamic>> statuses = {};
      Map<String, Map<String, dynamic>> assignments = {};
      Map<String, String> updatedPickupPlaces = {};

      try {
        statuses = await FirebaseService.getBookingStatuses(dateStr);
      } catch (e) {
        print('⚠️ Failed to load booking statuses: $e');
      }

      try {
        assignments = await FirebaseService.getIndividualPickupAssignments(dateStr);
      } catch (e) {
        print('⚠️ Failed to load pickup assignments: $e');
      }

      try {
        updatedPickupPlaces = await FirebaseService.getUpdatedPickupPlaces(dateStr);
      } catch (e) {
        print('⚠️ Failed to load updated pickup places: $e');
      }

      // Apply statuses and assignments to bookings
      final updatedBookings = bookings.map((booking) {
        // Apply status
        final status = statuses[booking.id];
        var updatedBooking = booking;
        if (status != null) {
          updatedBooking = updatedBooking.copyWith(
            isArrived: status['isArrived'] ?? false,
            isNoShow: status['isNoShow'] ?? false,
          );
        }

        // Apply assignment
        final assignment = assignments[booking.id];
        if (assignment != null) {
          updatedBooking = updatedBooking.copyWith(
            assignedGuideId: assignment['guideId'],
            assignedGuideName: assignment['guideName'],
          );
          print('✅ Applied assignment for booking ${booking.id}: ${assignment['guideName']}');
        }

        // Apply updated pickup place
        final updatedPickupPlace = updatedPickupPlaces[booking.id];
        if (updatedPickupPlace != null) {
          updatedBooking = updatedBooking.copyWith(
            pickupPlaceName: updatedPickupPlace,
          );
          print('✅ Applied updated pickup place for booking ${booking.id}: $updatedPickupPlace');
        }

        return updatedBooking;
      }).toList();

      // Sort bookings alphabetically by pickup place name
      updatedBookings.sort((a, b) => a.pickupPlaceName.compareTo(b.pickupPlaceName));

      // Filter bookings for current user if set
      // FIX: Additional null check here
      if (_currentUser != null) {
        final userBookings = updatedBookings
            .where((booking) => booking.assignedGuideId == _currentUser!.id)
            .toList();

        // FIX: Only try to load reordered bookings if user has assignments
        if (userBookings.isEmpty) {
          print('👤 No pickups assigned to current user: ${_currentUser!.fullName}');
          _currentUserBookings = [];
        } else {
          // Try to load saved reordered list (with timeout protection)
          try {
            final reorderedList = await _loadReorderedBookings(userBookings)
                .timeout(const Duration(seconds: 5), onTimeout: () {
              print('⚠️ Timeout loading reordered bookings, using default order');
              return userBookings;
            });
            _currentUserBookings = reorderedList;
          } catch (e) {
            print('⚠️ Failed to load reordered bookings: $e');
            _currentUserBookings = userBookings;
          }
        }

        print('👤 Filtered ${_currentUserBookings.length} bookings for current user: ${_currentUser!.fullName}');
      } else {
        _currentUserBookings = updatedBookings;
      }

      _bookings = updatedBookings; // Also update admin bookings
      _selectedDate = date;

      // FIX: Wrap stats loading in try-catch
      try {
        _stats = await _pickupService.getPickupListStats(date);
      } catch (e) {
        print('⚠️ Failed to load stats: $e');
      }

      // Update guide lists from the bookings with assignments
      _updateGuideLists();

      print('📊 Loaded ${updatedBookings.length} bookings with ${assignments.length} assignments');
      print('👥 Updated guide lists: ${_guideLists.length} guides with assignments');
    } catch (e) {
      print('❌ Error loading bookings: $e');
      _error = e.toString();
      // FIX: Don't leave user with stale data that might cause confusion
      // Keep existing data if we have some, otherwise clear it
      if (_bookings.isEmpty) {
        _currentUserBookings = [];
      }
    } finally {
      // FIX: ALWAYS reset loading state - this was the main bug causing infinite loading
      _setLoading(false);
    }
  }

  // Fetch month data for calendar
  Future<void> fetchMonthData(DateTime month) async {
    _setLoading(true);
    _error = null;

    try {
      // Check if month is too far in the past
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      if (month.isBefore(currentMonth)) {
        print('ℹ️ Month ${month.toString()} is in the past, skipping data fetch');
        _monthData.clear();
        _setLoading(false);
        return;
      }

      final endDate = DateTime(month.year, month.month + 1, 0);

      _monthData.clear();

      // Fetch data for each day in the month
      for (int day = 1; day <= endDate.day; day++) {
        final date = DateTime(month.year, month.month, day);

        // Skip dates that are too far in the past
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        if (date.isBefore(thirtyDaysAgo)) {
          continue;
        }

        try {
          final bookings = await _pickupService.fetchBookingsForDate(date);
          if (bookings.isNotEmpty) {
            _monthData[date] = bookings;
          }
        } catch (e) {
          print('Error fetching data for $date: $e');
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // Change selected date
  void changeDate(DateTime date) {
    _selectedDate = date;
    loadBookingsForDate(date);
  }

  // Admin methods
  Future<bool> assignBookingToGuide(String bookingId, String guideId, String guideName) async {
    try {
      final success = await _pickupService.assignBookingToGuide(bookingId, guideId, guideName, date: _selectedDate);
      if (success) {
        // Update local state
        final bookingIndex = _bookings.indexWhere((booking) => booking.id == bookingId);
        if (bookingIndex != -1) {
          _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(
            assignedGuideId: guideId,
            assignedGuideName: guideName,
          );

          // Update guide lists
          _updateGuideLists();
          notifyListeners();
        }
      }
      return success;
    } catch (e) {
      _error = 'Failed to assign booking: $e';
      notifyListeners();
      return false;
    }
  }

  // Mark or unmark booking as no-show
  Future<bool> markBookingAsNoShow(String bookingId, {bool isNoShow = true}) async {
    try {
      final success = await _pickupService.markBookingAsNoShow(bookingId, isNoShow: isNoShow);
      if (success) {
        // Update local state
        final bookingIndex = _bookings.indexWhere((booking) => booking.id == bookingId);
        if (bookingIndex != -1) {
          _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(isNoShow: isNoShow);

          // Also update current user bookings if this booking is in the list
          final userBookingIndex = _currentUserBookings.indexWhere((booking) => booking.id == bookingId);
          if (userBookingIndex != -1) {
            _currentUserBookings[userBookingIndex] = _currentUserBookings[userBookingIndex].copyWith(isNoShow: isNoShow);
          }

          _updateGuideLists();
          notifyListeners();
        }

        // Save to Firebase
        final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
        await FirebaseService.updateBookingStatus(
          bookingId: bookingId,
          date: dateStr,
          isNoShow: isNoShow,
        );
      }
      return success;
    } catch (e) {
      _error = 'Failed to ${isNoShow ? "mark" : "unmark"} booking as no-show: $e';
      notifyListeners();
      return false;
    }
  }

  // Mark booking as arrived
  void markBookingAsArrived(String bookingId, bool arrived) {
    try {
      // Update local state
      final bookingIndex = _bookings.indexWhere((booking) => booking.id == bookingId);
      if (bookingIndex != -1) {
        _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(isArrived: arrived);
        _updateGuideLists();
        notifyListeners();
      }

      // Also update current user bookings if this is for the current user
      final currentUserBookingIndex = _currentUserBookings.indexWhere((booking) => booking.id == bookingId);
      if (currentUserBookingIndex != -1) {
        _currentUserBookings[currentUserBookingIndex] = _currentUserBookings[currentUserBookingIndex].copyWith(isArrived: arrived);
        notifyListeners();
      }

      // Save to Firebase
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      FirebaseService.updateBookingStatus(
        bookingId: bookingId,
        date: dateStr,
        isArrived: arrived,
      );
    } catch (e) {
      _error = 'Failed to mark booking as arrived: $e';
      notifyListeners();
    }
  }

  // Distribute bookings among guides
  Future<void> distributeBookings(List<User> guides) async {
    _setLoading(true);
    _error = null;

    try {
      _guideLists = await _pickupService.distributeBookings(_bookings, guides, _selectedDate);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to distribute bookings: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Move booking between guides (alias for compatibility)
  Future<bool> moveBookingBetweenGuides(String bookingId, String? fromGuideId, String toGuideId, String toGuideName) async {
    return moveBookingToGuide(bookingId, fromGuideId, toGuideId, toGuideName);
  }

  // Move booking between guides
  Future<bool> moveBookingToGuide(String bookingId, String? fromGuideId, String toGuideId, String toGuideName) async {
    try {
      // Remove from source guide if it was assigned
      if (fromGuideId != null) {
        final sourceGuideIndex = _guideLists.indexWhere((list) => list.guideId == fromGuideId);
        if (sourceGuideIndex != -1) {
          final sourceGuide = _guideLists[sourceGuideIndex];
          final updatedBookings = List<PickupBooking>.from(sourceGuide.bookings)
            ..removeWhere((b) => b.id == bookingId);
          final newTotalPassengers = updatedBookings.fold(0, (sum, b) => sum + b.numberOfGuests);

          _guideLists[sourceGuideIndex] = sourceGuide.copyWith(
            bookings: updatedBookings,
            totalPassengers: newTotalPassengers,
          );
        }
      }

      // Add to destination guide
      final destGuideIndex = _guideLists.indexWhere((list) => list.guideId == toGuideId);
      if (destGuideIndex != -1) {
        final destGuide = _guideLists[destGuideIndex];
        final booking = _bookings.firstWhere((b) => b.id == bookingId);
        final updatedBooking = booking.copyWith(
          assignedGuideId: toGuideId,
          assignedGuideName: toGuideName,
        );

        final updatedBookings = List<PickupBooking>.from(destGuide.bookings)..add(updatedBooking);
        final newTotalPassengers = updatedBookings.fold(0, (sum, b) => sum + b.numberOfGuests);

        // Check passenger limit
        if (newTotalPassengers > _pickupService.maxPassengersPerBus) {
          _error = 'Cannot move booking: would exceed passenger limit (${_pickupService.maxPassengersPerBus})';
          notifyListeners();
          return false;
        }

        _guideLists[destGuideIndex] = destGuide.copyWith(
          bookings: updatedBookings,
          totalPassengers: newTotalPassengers,
        );
      }

      // Update booking in main list
      final bookingIndex = _bookings.indexWhere((b) => b.id == bookingId);
      if (bookingIndex != -1) {
        _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(
          assignedGuideId: toGuideId,
          assignedGuideName: toGuideName,
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to move booking: $e';
      notifyListeners();
      return false;
    }
  }

  // Get guide list for a specific guide
  GuidePickupList? getGuideList(String guideId) {
    try {
      return _guideLists.firstWhere((list) => list.guideId == guideId);
    } catch (e) {
      return null;
    }
  }

  // Validate passenger count for a guide
  bool validatePassengerCount(String guideId, int additionalPassengers) {
    final guideList = getGuideList(guideId);
    if (guideList == null) return true;

    return _pickupService.validatePassengerCount(
      guideList.totalPassengers,
      additionalPassengers,
    );
  }

  // Set current user
  void setCurrentUser(User user) {
    print('👤 Setting current user: ${user.fullName} (${user.id})');
    _currentUser = user;
    notifyListeners();
  }

  // Update current user bookings order
  void updateCurrentUserBookingsOrder(List<PickupBooking> reorderedBookings) {
    _currentUserBookings = reorderedBookings;
    notifyListeners();

    // Save the reordered list to Firebase for persistence
    _saveReorderedBookings(reorderedBookings);
  }

  // Reset to alphabetical order
  void resetToAlphabeticalOrder() {
    if (_currentUserBookings.isNotEmpty) {
      final sortedBookings = List<PickupBooking>.from(_currentUserBookings)
        ..sort((a, b) => a.pickupPlaceName.compareTo(b.pickupPlaceName));

      _currentUserBookings = sortedBookings;
      notifyListeners();

      // Remove saved reordered list from Firebase
      _removeReorderedBookings();
    }
  }

  // Update pickup place for a booking
  Future<void> updatePickupPlace(String bookingId, String newPickupPlace) async {
    // Update in current user bookings
    final currentUserIndex = _currentUserBookings.indexWhere((booking) => booking.id == bookingId);
    if (currentUserIndex != -1) {
      _currentUserBookings[currentUserIndex] = _currentUserBookings[currentUserIndex].copyWith(
        pickupPlaceName: newPickupPlace,
      );
      notifyListeners();
    }

    // Update in main bookings
    final mainIndex = _bookings.indexWhere((booking) => booking.id == bookingId);
    if (mainIndex != -1) {
      _bookings[mainIndex] = _bookings[mainIndex].copyWith(
        pickupPlaceName: newPickupPlace,
      );
    }

    // Save to Firebase
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    await FirebaseService.saveUpdatedPickupPlace(
      bookingId: bookingId,
      date: dateStr,
      pickupPlace: newPickupPlace,
    );
  }

  // Save reordered bookings to Firebase
  Future<void> _saveReorderedBookings(List<PickupBooking> reorderedBookings) async {
    if (_currentUser == null) return;

    try {
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final bookingIds = reorderedBookings.map((b) => b.id).toList();

      await FirebaseService.saveReorderedBookings(
        guideId: _currentUser!.id,
        date: dateStr,
        bookingIds: bookingIds,
      );

      print('💾 Saved reordered bookings for guide ${_currentUser!.fullName} on $dateStr');
    } catch (e) {
      print('❌ Failed to save reordered bookings: $e');
    }
  }

  // Remove reordered bookings from Firebase
  Future<void> _removeReorderedBookings() async {
    if (_currentUser == null) return;

    try {
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      await FirebaseService.removeReorderedBookings(
        guideId: _currentUser!.id,
        date: dateStr,
      );

      print('🗑️ Removed reordered bookings for guide ${_currentUser!.fullName} on $dateStr');
    } catch (e) {
      print('❌ Failed to remove reordered bookings: $e');
    }
  }

  // Load reordered bookings from Firebase
  // FIX: Added better error handling and empty list handling
  Future<List<PickupBooking>> _loadReorderedBookings(List<PickupBooking> userBookings) async {
    if (_currentUser == null) return userBookings;

    // FIX: If userBookings is empty, return immediately
    if (userBookings.isEmpty) {
      print('📋 No bookings to reorder for user');
      return userBookings;
    }

    try {
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      // Try to load existing reordered list from Firebase
      final savedBookingIds = await FirebaseService.getReorderedBookings(
        guideId: _currentUser!.id,
        date: dateStr,
      );

      if (savedBookingIds.isNotEmpty) {
        // Reconstruct list from saved order
        final reorderedList = <PickupBooking>[];
        final processedIds = <String>{};

        for (final bookingId in savedBookingIds) {
          // FIX: Use try-catch with orElse instead of firstWhere which throws
          final booking = userBookings.cast<PickupBooking?>().firstWhere(
                (b) => b?.id == bookingId,
            orElse: () => null,
          );

          if (booking != null) {
            reorderedList.add(booking);
            processedIds.add(bookingId);
          } else {
            print('⚠️ Booking $bookingId not found in user bookings, skipping');
          }
        }

        // Add any new bookings that weren't in the saved order
        for (final booking in userBookings) {
          if (!processedIds.contains(booking.id)) {
            reorderedList.add(booking);
          }
        }

        print('🔄 Loaded saved reordered list for guide ${_currentUser!.fullName}: ${reorderedList.length} bookings');
        return reorderedList;
      } else {
        // No saved order, return original sorted list
        return userBookings;
      }
    } catch (e) {
      print('❌ Failed to load reordered bookings: $e');
      return userBookings;
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Helper method to set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Update guide lists from current bookings
  void _updateGuideLists() {
    print('🔄 Updating guide lists from ${_bookings.length} bookings...');

    final guideGroups = <String, List<PickupBooking>>{};

    for (final booking in _bookings) {
      if (booking.assignedGuideId != null) {
        guideGroups.putIfAbsent(booking.assignedGuideId!, () => []);
        guideGroups[booking.assignedGuideId]!.add(booking);
        print('📋 Added booking ${booking.customerFullName} to guide ${booking.assignedGuideName}');
      }
    }

    _guideLists = guideGroups.entries.map((entry) {
      final totalPassengers = entry.value.fold(0, (sum, booking) => sum + booking.numberOfGuests);
      final guideList = GuidePickupList(
        guideId: entry.key,
        guideName: entry.value.first.assignedGuideName ?? 'Unknown Guide',
        bookings: entry.value,
        totalPassengers: totalPassengers,
        date: _selectedDate,
      );
      print('👥 Created guide list for ${guideList.guideName}: ${guideList.bookings.length} bookings, ${guideList.totalPassengers} passengers');
      return guideList;
    }).toList();

    print('✅ Updated guide lists: ${_guideLists.length} guides total');
  }
}