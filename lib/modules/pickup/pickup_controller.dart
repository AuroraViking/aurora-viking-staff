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
  
  // New properties for calendar functionality
  Map<DateTime, List<PickupBooking>> _monthData = {};

  // Getters
  DateTime get selectedDate => _selectedDate;
  List<PickupBooking> get currentUserBookings => _currentUserBookings;
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // New getters for calendar
  bool get hasError => _error != null;
  String get errorMessage => _error ?? 'Unknown error';
  Map<DateTime, List<PickupBooking>> get monthData => _monthData;

  // Load bookings for a specific date
  Future<void> loadBookingsForDate(DateTime date) async {
    _setLoading(true);
    _error = null;
    
    try {
      final bookings = await _pickupService.fetchBookingsForDate(date);
      _currentUserBookings = bookings;
      _selectedDate = date;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // New method to fetch month data for calendar
  Future<void> fetchMonthData(DateTime month) async {
    _setLoading(true);
    _error = null;
    
    try {
      final startDate = DateTime(month.year, month.month, 1);
      final endDate = DateTime(month.year, month.month + 1, 0);
      
      _monthData.clear();
      
      // Fetch data for each day in the month
      for (int day = 1; day <= endDate.day; day++) {
        final date = DateTime(month.year, month.month, day);
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

  // Mark booking as no-show
  Future<bool> markBookingAsNoShow(String bookingId) async {
    try {
      // TODO: Implement no-show functionality
      // For now, just update the local state
      final bookingIndex = _currentUserBookings.indexWhere((b) => b.id == bookingId);
      if (bookingIndex != -1) {
        _currentUserBookings[bookingIndex] = _currentUserBookings[bookingIndex].copyWith(
          isNoShow: true,
        );
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Set current user
  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  // Helper method to set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
} 