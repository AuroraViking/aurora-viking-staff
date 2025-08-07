import 'package:flutter/material.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
import 'pickup_service.dart';

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

  // Load bookings for a specific date
  Future<void> loadBookingsForDate(DateTime date) async {
    _setLoading(true);
    _error = null;
    
    try {
      final bookings = await _pickupService.fetchBookingsForDate(date);
      _currentUserBookings = bookings;
      _bookings = bookings; // Also update admin bookings
      _selectedDate = date;
      
      // Update stats and guide lists for admin
      _stats = await _pickupService.getPickupListStats(date);
      _guideLists = _stats?.guideLists ?? [];
    } catch (e) {
      _error = e.toString();
    } finally {
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
      
      final startDate = DateTime(month.year, month.month, 1);
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
      final success = await _pickupService.assignBookingToGuide(bookingId, guideId, guideName);
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

  // Mark booking as no-show
  Future<bool> markBookingAsNoShow(String bookingId) async {
    try {
      final success = await _pickupService.markBookingAsNoShow(bookingId);
      if (success) {
        // Update local state
        final bookingIndex = _bookings.indexWhere((booking) => booking.id == bookingId);
        if (bookingIndex != -1) {
          _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(isNoShow: true);
          _updateGuideLists();
          notifyListeners();
        }
      }
      return success;
    } catch (e) {
      _error = 'Failed to mark booking as no-show: $e';
      notifyListeners();
      return false;
    }
  }

  // Distribute bookings among guides
  Future<void> distributeBookings(List<User> guides) async {
    _setLoading(true);
    _error = null;
    
    try {
      _guideLists = await _pickupService.distributeBookings(
        unassignedBookings,
        guides,
        _selectedDate,
      );
      
      // Update bookings with assignments
      for (final guideList in _guideLists) {
        for (final booking in guideList.bookings) {
          final bookingIndex = _bookings.indexWhere((b) => b.id == booking.id);
          if (bookingIndex != -1) {
            _bookings[bookingIndex] = booking;
          }
        }
      }
      
      _updateGuideLists();
      _setLoading(false);
    } catch (e) {
      _error = 'Failed to distribute bookings: $e';
      _setLoading(false);
    }
  }

  // Move booking between guides (drag and drop)
  Future<bool> moveBookingBetweenGuides(
    String bookingId,
    String fromGuideId,
    String toGuideId,
    String toGuideName,
  ) async {
    try {
      // Remove from source guide
      final sourceGuideIndex = _guideLists.indexWhere((list) => list.guideId == fromGuideId);
      if (sourceGuideIndex != -1) {
        final sourceGuide = _guideLists[sourceGuideIndex];
        final updatedBookings = sourceGuide.bookings.where((b) => b.id != bookingId).toList();
        final newTotalPassengers = updatedBookings.fold(0, (sum, b) => sum + b.numberOfGuests);
        
        _guideLists[sourceGuideIndex] = sourceGuide.copyWith(
          bookings: updatedBookings,
          totalPassengers: newTotalPassengers,
        );
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
    _currentUser = user;
    notifyListeners();
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
    final guideGroups = <String, List<PickupBooking>>{};
    
    for (final booking in _bookings) {
      if (booking.assignedGuideId != null) {
        guideGroups.putIfAbsent(booking.assignedGuideId!, () => []);
        guideGroups[booking.assignedGuideId]!.add(booking);
      }
    }

    _guideLists = guideGroups.entries.map((entry) {
      final totalPassengers = entry.value.fold(0, (sum, booking) => sum + booking.numberOfGuests);
      return GuidePickupList(
        guideId: entry.key,
        guideName: entry.value.first.assignedGuideName ?? 'Unknown Guide',
        bookings: entry.value,
        totalPassengers: totalPassengers,
        date: _selectedDate,
      );
    }).toList();
  }
} 