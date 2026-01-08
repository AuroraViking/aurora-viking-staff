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
  
  // Cache bookings by date to preserve data when switching dates
  Map<String, List<PickupBooking>> _bookingsCache = {};
  Map<String, List<GuidePickupList>> _guideListsCache = {};
  Map<String, PickupListStats?> _statsCache = {};

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

  /// Get normalized date key for caching (YYYY-MM-DD format)
  /// This ensures cache hits regardless of time component
  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get API-safe date for Bokun requests
  /// For "today": uses current time to avoid "too far in the past" error
  /// For other days: uses the provided date (midnight is fine for future/past days)
  DateTime _getApiSafeDate(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && 
                    date.month == now.month && 
                    date.day == now.day;
    
    if (isToday) {
      // For today, use current time to avoid Bokun rejecting midnight as "in the past"
      print('📅 Using current time for today\'s API request (avoiding midnight rejection)');
      return now;
    } else {
      // For other days, the original date is fine
      return date;
    }
  }

  // Load bookings for a specific date with Firebase statuses
  // FIX: Added comprehensive error handling and guaranteed loading state reset
  Future<void> loadBookingsForDate(DateTime date, {bool forceRefresh = false}) async {
    // FIX: Guard against calling when user is null (unless forceRefresh for admin)
    if (_currentUser == null && !forceRefresh) {
      print('⚠️ Cannot load bookings: current user is null');
      _currentUserBookings = [];
      _error = null; // Don't show error for this expected case
      notifyListeners();
      return;
    }

    _setLoading(true);
    _error = null;

    // FIX: Use normalized date key for caching (avoids time component mismatches)
    // Declare outside try block so it's accessible in catch block
    final dateKey = _getDateKey(date);
    // FIX: Use API-safe date (current time for today to avoid Bokun "too far in the past" error)
    final apiDate = _getApiSafeDate(date);

    try {
      print('📥 Loading bookings for date: $date (key: $dateKey)${forceRefresh ? ' (FORCE REFRESH)' : ''}');
      if (_currentUser != null) {
        print('   User: ${_currentUser!.fullName} (${_currentUser!.id})');
      }
      print('   API date: $apiDate');

      // Always fetch fresh data from API
      List<PickupBooking> bookings;
      try {
        // FIX: Use API-safe date for the Bokun request
        bookings = await _pickupService.fetchBookingsForDate(apiDate);
        print('📋 API returned ${bookings.length} bookings for date $dateKey');
        
        // Load manual bookings and merge with API bookings
        try {
          final manualBookings = await FirebaseService.getManualBookings(dateKey);
          if (manualBookings.isNotEmpty) {
            print('📋 Found ${manualBookings.length} manual bookings for date $dateKey');
            // Merge manual bookings with API bookings (avoid duplicates by ID)
            final existingIds = bookings.map((b) => b.id).toSet();
            for (final manualBooking in manualBookings) {
              if (!existingIds.contains(manualBooking.id)) {
                bookings.add(manualBooking);
                print('✅ Added manual booking: ${manualBooking.customerFullName}');
              }
            }
            print('📋 Total bookings after merge: ${bookings.length}');
          }
        } catch (e) {
          print('⚠️ Failed to load manual bookings: $e');
        }
      } catch (e) {
        // Handle API errors - check cache first, then existing data
        print('❌ API Error: $e');
        _error = 'Failed to load bookings: ${e.toString().replaceAll('Exception: ', '')}';
        
        // Always update selected date to show we're viewing this date
        _selectedDate = date;
        
        // FIX: Check cache using normalized date key
        if (_bookingsCache.containsKey(dateKey)) {
          print('💾 Restoring bookings from cache for date $dateKey');
          var cachedBookings = List<PickupBooking>.from(_bookingsCache[dateKey]!);
          
          // Also load manual bookings and merge
          try {
            final manualBookings = await FirebaseService.getManualBookings(dateKey);
            if (manualBookings.isNotEmpty) {
              print('📋 Found ${manualBookings.length} manual bookings for date $dateKey');
              final existingIds = cachedBookings.map((b) => b.id).toSet();
              for (final manualBooking in manualBookings) {
                if (!existingIds.contains(manualBooking.id)) {
                  cachedBookings.add(manualBooking);
                  print('✅ Added manual booking to cache: ${manualBooking.customerFullName}');
                }
              }
            }
          } catch (e) {
            print('⚠️ Failed to load manual bookings from cache: $e');
          }
          
          _bookings = cachedBookings;
          _guideLists = _guideListsCache[dateKey] ?? [];
          _stats = _statsCache[dateKey];
          
          // Update current user bookings
          if (_currentUser != null) {
            _currentUserBookings = _bookings
                .where((booking) => booking.assignedGuideId == _currentUser!.id)
                .toList();
          } else {
            _currentUserBookings = _bookings;
          }
          
          _setLoading(false);
          notifyListeners();
          return;
        }
        
        // If no cache, check if existing bookings match the requested date
        final requestedDateOnly = DateTime(date.year, date.month, date.day);
        final hasMatchingBookings = _bookings.any((booking) {
          final bookingDateOnly = DateTime(booking.pickupTime.year, booking.pickupTime.month, booking.pickupTime.day);
          return bookingDateOnly == requestedDateOnly;
        });
        
        if (hasMatchingBookings) {
          print('⚠️ API error but we have existing bookings for this date ($date). Keeping existing data.');
          _setLoading(false);
          notifyListeners();
          return;
        }
        
        // If no cache and no matching bookings, show empty state
        print('⚠️ API error for date $date with no cache or matching bookings. Showing empty state.');
        _bookings = [];
        _currentUserBookings = [];
        _guideLists = [];
        _stats = null;
        
        _setLoading(false);
        notifyListeners();
        return;
      }

      // If force refresh, always update (even if API returns empty) - this allows viewing past dates
      // If not force refresh and API returns empty but we have existing data, keep existing data
      if (bookings.isEmpty && _bookings.isNotEmpty && !forceRefresh) {
        print('⚠️ API returned empty bookings but we have existing bookings. Keeping existing data (not a refresh).');
        _setLoading(false);
        return;
      }
      
      // If force refresh and API returns empty, check cache first before clearing
      if (bookings.isEmpty && forceRefresh) {
        // FIX: Use normalized date key for cache lookup
        // If we have cached data, use it instead of clearing
        if (_bookingsCache.containsKey(dateKey) && _bookingsCache[dateKey]!.isNotEmpty) {
          print('💾 API returned empty but found cached bookings for date $dateKey. Restoring from cache.');
          var cachedBookings = List<PickupBooking>.from(_bookingsCache[dateKey]!);
          
          // Also load manual bookings and merge
          try {
            final manualBookings = await FirebaseService.getManualBookings(dateKey);
            if (manualBookings.isNotEmpty) {
              print('📋 Found ${manualBookings.length} manual bookings for date $dateKey');
              final existingIds = cachedBookings.map((b) => b.id).toSet();
              for (final manualBooking in manualBookings) {
                if (!existingIds.contains(manualBooking.id)) {
                  cachedBookings.add(manualBooking);
                  print('✅ Added manual booking to cache: ${manualBooking.customerFullName}');
                }
              }
            }
          } catch (e) {
            print('⚠️ Failed to load manual bookings: $e');
          }
          
          _bookings = cachedBookings;
          _guideLists = _guideListsCache[dateKey] ?? [];
          _stats = _statsCache[dateKey];
          
          // Update current user bookings
          if (_currentUser != null) {
            _currentUserBookings = _bookings
                .where((booking) => booking.assignedGuideId == _currentUser!.id)
                .toList();
          } else {
            _currentUserBookings = _bookings;
          }
          
          _selectedDate = date;
          _error = null;
          _setLoading(false);
          notifyListeners();
          return;
        }
        
        print('🔄 Force refresh: API returned empty for date $date, clearing existing bookings');
        // Clear all bookings for this date
        _bookings = [];
        _currentUserBookings = [];
        _guideLists = [];
        _stats = null;
        _selectedDate = date; // Update selected date even if no bookings
        _error = null; // Clear any previous errors
        
        // Also clear cache for this date
        _bookingsCache.remove(dateKey);
        _guideListsCache.remove(dateKey);
        _statsCache.remove(dateKey);
        
        _setLoading(false);
        notifyListeners();
        print('✅ Cleared all bookings for date $date - showing empty state');
        return;
      }
      
      // If not force refresh and API returns empty, but we're loading a different date, clear old data
      if (bookings.isEmpty && !forceRefresh && _selectedDate != date) {
        print('🔄 Loading different date ($date vs ${_selectedDate}): API returned empty, clearing old data');
        _bookings = [];
        _currentUserBookings = [];
        _guideLists = [];
        _stats = null;
        _selectedDate = date;
        _setLoading(false);
        notifyListeners();
        return;
      }
      
      // Clear any previous errors if we got successful data
      _error = null;

      // FIX: Use normalized date key for Firebase (same format as dateStr)
      final dateStr = dateKey;

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

      // Apply statuses and assignments to bookings (including manual bookings)
      final updatedBookings = bookings.map((booking) {
        // Apply status
        final status = statuses[booking.id];
        var updatedBooking = booking;
        if (status != null) {
          updatedBooking = updatedBooking.copyWith(
            isArrived: status['isArrived'] ?? false,
            isNoShow: status['isNoShow'] ?? false,
            paidOnArrival: status['paidOnArrival'] ?? false,
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
      
      // Debug: Log manual bookings in the list
      final manualBookingsInList = updatedBookings.where((b) => b.id.startsWith('manual_')).toList();
      if (manualBookingsInList.isNotEmpty) {
        print('✅ Found ${manualBookingsInList.length} manual bookings in updated list: ${manualBookingsInList.map((b) => b.customerFullName).join(", ")}');
      }

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

      print('📊 Setting _bookings to ${updatedBookings.length} bookings for date $date');

      // FIX: Wrap stats loading in try-catch, use API-safe date
      try {
        _stats = await _pickupService.getPickupListStats(apiDate);
      } catch (e) {
        print('⚠️ Failed to load stats: $e');
      }

      // Update guide lists from the bookings with assignments
      _updateGuideLists();

      print('📊 Loaded ${updatedBookings.length} bookings with ${assignments.length} assignments');
      print('👥 Updated guide lists: ${_guideLists.length} guides with assignments');
      print('✅ Final _bookings count: ${_bookings.length}');
      
      // ========================================
      // AUTO-CACHE: Save today's bookings to Firebase
      // So they're available tomorrow when "today" becomes "past"
      // ========================================
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selectedDateNormalized = DateTime(date.year, date.month, date.day);
      
      // Cache if this is today's data OR if it's recent (within last 7 days)
      // This ensures we always have a backup in Firebase
      final sevenDaysAgo = today.subtract(const Duration(days: 7));
      final shouldCache = selectedDateNormalized.isAtSameMomentAs(today) ||
                          (selectedDateNormalized.isAfter(sevenDaysAgo) && 
                           selectedDateNormalized.isBefore(today.add(const Duration(days: 1))));
      
      if (shouldCache && updatedBookings.isNotEmpty) {
        // Cache to Firebase for future retrieval (includes manual bookings)
        await FirebaseService.cacheBookings(
          date: dateKey,
          bookings: updatedBookings,
        );
        print('💾 Auto-cached ${updatedBookings.length} bookings to Firebase for date $dateKey (includes ${updatedBookings.where((b) => b.id.startsWith('manual_')).length} manual bookings)');
      }
      
      // Also cache to local memory (includes manual bookings)
      _bookingsCache[dateKey] = List.from(updatedBookings);
      _guideListsCache[dateKey] = List.from(_guideLists);
      _statsCache[dateKey] = _stats;
      
      // Debug: Verify manual bookings are in cache
      final manualInCache = _bookingsCache[dateKey]?.where((b) => b.id.startsWith('manual_')).toList() ?? [];
      if (manualInCache.isNotEmpty) {
        print('✅ Verified ${manualInCache.length} manual bookings in local cache: ${manualInCache.map((b) => b.customerFullName).join(", ")}');
      }
      print('💾 Cached bookings for date $dateKey: ${updatedBookings.length} bookings');
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
    final oldKey = _getDateKey(_selectedDate);
    final newKey = _getDateKey(date);
    print('📅 Changing date from $oldKey to $newKey');
    // Always force refresh when changing dates to get fresh data
    loadBookingsForDate(date, forceRefresh: true);
  }
  
  // Force refresh current date's bookings
  Future<void> refreshBookings() async {
    await loadBookingsForDate(_selectedDate, forceRefresh: true);
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
          
          // Update current user bookings if this assignment affects the current user
          if (_currentUser != null) {
            if (guideId == _currentUser!.id) {
              // Booking was assigned to current user - add it if not already there
              if (!_currentUserBookings.any((b) => b.id == bookingId)) {
                _currentUserBookings.add(_bookings[bookingIndex]);
                // Reload reordered list to include new booking
                try {
                  final reorderedList = await _loadReorderedBookings(_currentUserBookings)
                      .timeout(const Duration(seconds: 2), onTimeout: () => _currentUserBookings);
                  _currentUserBookings = reorderedList;
                } catch (e) {
                  print('⚠️ Failed to reload reordered list after assignment: $e');
                }
              }
            } else {
              // Booking was assigned to different guide - remove from current user if present
              _currentUserBookings.removeWhere((b) => b.id == bookingId);
            }
          }
          
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

  // Mark booking as paid on arrival
  void markBookingAsPaidOnArrival(String bookingId, bool paid) {
    try {
      // Update local state
      final bookingIndex = _bookings.indexWhere((booking) => booking.id == bookingId);
      if (bookingIndex != -1) {
        _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(paidOnArrival: paid);
        _updateGuideLists();
        notifyListeners();
      }

      // Also update current user bookings if this is for the current user
      final currentUserBookingIndex = _currentUserBookings.indexWhere((booking) => booking.id == bookingId);
      if (currentUserBookingIndex != -1) {
        _currentUserBookings[currentUserBookingIndex] = _currentUserBookings[currentUserBookingIndex].copyWith(paidOnArrival: paid);
        notifyListeners();
      }

      // Save to Firebase
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      FirebaseService.updateBookingStatus(
        bookingId: bookingId,
        date: dateStr,
        paidOnArrival: paid,
      );
    } catch (e) {
      _error = 'Failed to mark booking as paid on arrival: $e';
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

      // Update current user bookings if this affects the current user
      if (_currentUser != null) {
        if (toGuideId == _currentUser!.id) {
          // Booking was moved to current user - add it if not already there
          if (!_currentUserBookings.any((b) => b.id == bookingId)) {
            final updatedBooking = _bookings.firstWhere((b) => b.id == bookingId);
            _currentUserBookings.add(updatedBooking);
            // Reload reordered list
            try {
              final reorderedList = await _loadReorderedBookings(_currentUserBookings)
                  .timeout(const Duration(seconds: 2), onTimeout: () => _currentUserBookings);
              _currentUserBookings = reorderedList;
            } catch (e) {
              print('⚠️ Failed to reload reordered list after move: $e');
            }
          }
        } else {
          // Booking was moved away from current user - remove it
          _currentUserBookings.removeWhere((b) => b.id == bookingId);
        }
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

  // Create a manual booking
  Future<bool> createManualBooking({
    required String customerName,
    required String pickupLocation,
    required String email,
    required String phoneNumber,
    DateTime? pickupTime,
    int numberOfGuests = 1,
  }) async {
    try {
      // Generate a unique ID for the manual booking
      final bookingId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
      
      // Use provided pickup time or default to selected date at 9:00 AM
      final time = pickupTime ?? DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        9,
        0,
      );
      
      // Create the booking
      final manualBooking = PickupBooking(
        id: bookingId,
        customerFullName: customerName,
        pickupPlaceName: pickupLocation,
        pickupTime: time,
        numberOfGuests: numberOfGuests,
        phoneNumber: phoneNumber,
        email: email,
        createdAt: DateTime.now(),
      );
      
      // Add to bookings list
      _bookings.add(manualBooking);
      
      // Update guide lists
      _updateGuideLists();
      
      // Update stats
      _stats = PickupListStats.fromBookings(_bookings, _guideLists);
      
      // Save manual booking to Firebase (separate collection)
      final dateKey = _getDateKey(_selectedDate);
      print('💾 Saving manual booking for date: $dateKey');
      print('💾 Booking ID: ${manualBooking.id}');
      print('💾 Customer: ${manualBooking.customerFullName}');
      
      await FirebaseService.saveManualBooking(
        date: dateKey,
        booking: manualBooking,
      );
      print('✅ Manual booking saved to Firebase');
      
      // Also update the cache (includes the new manual booking)
      await FirebaseService.cacheBookings(
        date: dateKey,
        bookings: _bookings,
      );
      print('✅ Updated cache with ${_bookings.length} bookings (includes manual booking)');
      
      // Update local cache
      _bookingsCache[dateKey] = List.from(_bookings);
      _guideListsCache[dateKey] = List.from(_guideLists);
      _statsCache[dateKey] = _stats;
      
      notifyListeners();
      
      print('✅ Created manual booking: $customerName (ID: ${manualBooking.id})');
      return true;
    } catch (e, stackTrace) {
      print('❌ Error creating manual booking: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Delete a booking
  Future<bool> deleteBooking(String bookingId) async {
    try {
      // Check if this is a manual booking
      final isManualBooking = bookingId.startsWith('manual_');
      
      // Remove from bookings list
      _bookings.removeWhere((booking) => booking.id == bookingId);
      
      // Remove from current user bookings if present
      _currentUserBookings.removeWhere((booking) => booking.id == bookingId);
      
      // Remove assignment from Firebase
      await FirebaseService.removePickupAssignment(bookingId);
      
      // If it's a manual booking, delete from manual_bookings collection
      if (isManualBooking) {
        final dateKey = _getDateKey(_selectedDate);
        await FirebaseService.deleteManualBooking(
          date: dateKey,
          bookingId: bookingId,
        );
      }
      
      // Update guide lists
      _updateGuideLists();
      
      // Update stats
      _stats = PickupListStats.fromBookings(_bookings, _guideLists);
      
      // Update Firebase cache
      final dateKey = _getDateKey(_selectedDate);
      await FirebaseService.cacheBookings(
        date: dateKey,
        bookings: _bookings,
      );
      
      // Update local cache
      _bookingsCache[dateKey] = List.from(_bookings);
      _guideListsCache[dateKey] = List.from(_guideLists);
      _statsCache[dateKey] = _stats;
      
      notifyListeners();
      
      print('✅ Deleted booking: $bookingId');
      return true;
    } catch (e) {
      print('❌ Error deleting booking: $e');
      return false;
    }
  }
}