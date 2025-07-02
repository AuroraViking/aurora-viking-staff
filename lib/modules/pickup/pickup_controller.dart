import 'package:flutter/material.dart';
import '../../core/models/pickup_models.dart';
import '../../core/models/user_model.dart';
import 'pickup_service.dart';

class PickupController extends ChangeNotifier {
  final PickupService _pickupService = PickupService();
  
  // State variables
  List<PickupBooking> _bookings = [];
  List<GuidePickupList> _guideLists = [];
  PickupListStats? _stats;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  String? _error;
  User? _currentUser;

  // Getters
  List<PickupBooking> get bookings => _bookings;
  List<GuidePickupList> get guideLists => _guideLists;
  PickupListStats? get stats => _stats;
  DateTime get selectedDate => _selectedDate;
  bool get isLoading => _isLoading;
  String? get error => _error;
  User? get currentUser => _currentUser;
  
  // Get unassigned bookings
  List<PickupBooking> get unassignedBookings => 
      _bookings.where((booking) => booking.assignedGuideId == null).toList();
  
  // Get bookings for current user (if staff)
  List<PickupBooking> get currentUserBookings {
    if (_currentUser == null) return [];
    return _bookings.where((booking) => booking.assignedGuideId == _currentUser!.id).toList();
  }

  // Set current user
  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  // Change selected date
  void changeDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
    loadBookingsForDate(date);
  }

  // Load bookings for a specific date
  Future<void> loadBookingsForDate(DateTime date) async {
    _setLoading(true);
    _error = null;
    
    try {
      _bookings = await _pickupService.fetchBookingsForDate(date);
      _stats = await _pickupService.getPickupListStats(date);
      _guideLists = _stats?.guideLists ?? [];
      _setLoading(false);
    } catch (e) {
      _error = 'Failed to load bookings: $e';
      _setLoading(false);
    }
  }

  // Assign booking to guide
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

  // Clear error
  void clearError() {
    _error = null;
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

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
} 