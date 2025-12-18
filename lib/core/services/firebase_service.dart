import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/pickup_models.dart';

class FirebaseService {
  static firebase_auth.FirebaseAuth? _auth;
  static FirebaseFirestore? _firestore;
  static bool _initialized = false;
  static bool _initializing = false;

  // Authentication methods
  static firebase_auth.User? get currentUser => _auth?.currentUser;

  static Stream<firebase_auth.User?> get authStateChanges => 
      _auth?.authStateChanges() ?? Stream.value(null);

  // Initialize Firebase - only once
  static Future<void> initialize() async {
    // Prevent multiple simultaneous initializations
    if (_initializing) {
      print('⚠️ Firebase initialization already in progress, waiting...');
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    
    // Prevent multiple initializations
    if (_initialized) {
      print('✅ Firebase already initialized, skipping...');
      return;
    }
    
    _initializing = true;
    
    try {
      await Firebase.initializeApp();
      _auth = firebase_auth.FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _initialized = true;
      print('✅ Firebase initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize Firebase: $e');
      _initialized = false;
      // Don't rethrow - allow app to continue without Firebase
    } finally {
      _initializing = false;
    }
  }

  static bool get isInitialized => _initialized;

  // Sign in with email and password
  static Future<firebase_auth.UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    if (!_initialized || _auth == null) {
      throw Exception('Firebase not initialized');
    }
    
    try {
      final credential = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  // Create user with email and password
  static Future<firebase_auth.UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    if (!_initialized || _auth == null) {
      throw Exception('Firebase not initialized');
    }
    
    try {
      final credential = await _auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  // Send password reset email
  static Future<void> sendPasswordResetEmail(String email) async {
    if (!_initialized || _auth == null) {
      throw Exception('Firebase not initialized');
    }
    
    try {
      await _auth!.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  // Sign out
  static Future<void> signOut() async {
    if (!_initialized || _auth == null) {
      return; // Nothing to do if Firebase isn't initialized
    }
    
    try {
      await _auth!.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }

  // Get user data from Firestore - create if doesn't exist
  static Future<User?> getUserData(String uid) async {
    if (!_initialized || _firestore == null) {
      return null; // Return null if Firebase isn't initialized
    }
    
    try {
      final doc = await _firestore!.collection('users').doc(uid).get();
      if (doc.exists) {
        print('✅ User document found for: $uid');
        return User.fromJson(doc.data()!);
      } else {
        print('⚠️ No user document found for: $uid, creating one...');
        // Create user document from Firebase Auth user
        final firebaseUser = _auth!.currentUser;
        if (firebaseUser != null && firebaseUser.uid == uid) {
          final newUser = User(
            id: uid,
            fullName: firebaseUser.displayName ?? firebaseUser.email?.split('@').first ?? 'Unknown User',
            email: firebaseUser.email ?? '',
            phoneNumber: firebaseUser.phoneNumber ?? '',
            role: 'guide', // Default role
            profilePictureUrl: firebaseUser.photoURL,
            createdAt: DateTime.now(),
            isActive: true,
          );
          
          // Save the new user document
          await saveUserData(newUser);
          print('✅ Created new user document for: ${firebaseUser.email}');
          return newUser;
        } else {
          print('❌ Firebase user not found or UID mismatch');
          return null;
        }
      }
    } catch (e) {
      print('❌ Failed to get/create user data: $e');
      return null;
    }
  }

  // Create or update user data
  static Future<void> saveUserData(User user) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping user data save');
      return;
    }
    
    try {
      await _firestore!.collection('users').doc(user.id).set(user.toJson());
      print('✅ User data saved successfully for: ${user.email}');
    } catch (e) {
      print('❌ Failed to save user data: $e');
    }
  }

  // Booking status management
  static Future<void> updateBookingStatus({
    required String bookingId,
    required String date,
    bool? isArrived,
    bool? isNoShow,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping booking status update');
      return;
    }
    
    try {
      final updates = <String, dynamic>{};
      if (isArrived != null) updates['isArrived'] = isArrived;
      if (isNoShow != null) updates['isNoShow'] = isNoShow;
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedBy'] = currentUser?.uid;

      await _firestore!
          .collection('booking_status')
          .doc('${date}_$bookingId')
          .set(updates, SetOptions(merge: true));
    } catch (e) {
      print('❌ Failed to update booking status: $e');
    }
  }

  // Get booking status for a specific date
  static Future<Map<String, Map<String, dynamic>>> getBookingStatuses(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - returning empty booking statuses');
      return {};
    }
    
    try {
      final querySnapshot = await _firestore!
          .collection('booking_status')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: '${date}_')
          .where(FieldPath.documentId, isLessThan: '${date}_\uf8ff')
          .get();

      final statuses = <String, Map<String, dynamic>>{};
      for (final doc in querySnapshot.docs) {
        final bookingId = doc.id.split('_').last;
        statuses[bookingId] = doc.data();
      }
      return statuses;
    } catch (e) {
      print('❌ Failed to get booking statuses: $e');
      return {};
    }
  }

  // Get all booking statuses for a date range
  static Future<Map<String, Map<String, dynamic>>> getBookingStatusesForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - returning empty booking statuses for date range');
      return {};
    }
    
    try {
      final statuses = <String, Map<String, dynamic>>{};
      
      DateTime currentDate = startDate;
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        final dateStr = '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
        final dateStatuses = await getBookingStatuses(dateStr);
        statuses.addAll(dateStatuses);
        currentDate = currentDate.add(const Duration(days: 1));
      }
      
      return statuses;
    } catch (e) {
      print('❌ Failed to get booking statuses for date range: $e');
      return {};
    }
  }

  // Save pickup assignments
  static Future<void> savePickupAssignments({
    required String date,
    required List<GuidePickupList> guideLists,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping pickup assignments save');
      return;
    }
    
    try {
      final batch = _firestore!.batch();
      
      // Clear existing assignments for the date
      final existingAssignments = await _firestore!
          .collection('pickup_assignments')
          .where('date', isEqualTo: date)
          .get();
      
      for (final doc in existingAssignments.docs) {
        batch.delete(doc.reference);
      }
      
      // Save new assignments
      for (final guideList in guideLists) {
        final docRef = _firestore!.collection('pickup_assignments').doc();
        batch.set(docRef, {
          'date': date,
          'guideId': guideList.guideId,
          'guideName': guideList.guideName,
          'bookings': guideList.bookings.map((b) => b.toJson()).toList(),
          'totalPassengers': guideList.totalPassengers,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
    } catch (e) {
      print('❌ Failed to save pickup assignments: $e');
    }
  }

  // Get pickup assignments for a date
  static Future<List<GuidePickupList>> getPickupAssignments(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - returning empty pickup assignments');
      return [];
    }
    
    try {
      final querySnapshot = await _firestore!
          .collection('pickup_assignments')
          .where('date', isEqualTo: date)
          .get();

      final guideLists = <GuidePickupList>[];
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final bookings = (data['bookings'] as List<dynamic>)
            .map((b) => PickupBooking.fromJson(b))
            .toList();
        
        guideLists.add(GuidePickupList(
          guideId: data['guideId'],
          guideName: data['guideName'],
          bookings: bookings,
          totalPassengers: data['totalPassengers'],
          date: DateTime.parse(data['date']),
        ));
      }
      
      return guideLists;
    } catch (e) {
      print('❌ Failed to get pickup assignments: $e');
      return [];
    }
  }

  // Get individual pickup assignments for a date
  static Future<Map<String, Map<String, dynamic>>> getIndividualPickupAssignments(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - returning empty individual pickup assignments');
      return {};
    }
    
    try {
      // Query for documents that start with the date
      final querySnapshot = await _firestore!
          .collection('pickup_assignments')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: '${date}_')
          .where(FieldPath.documentId, isLessThan: '${date}_\uf8ff')
          .get();

      final assignments = <String, Map<String, dynamic>>{};
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final bookingId = data['bookingId'] as String?;
        if (bookingId != null) {
          assignments[bookingId] = {
            'guideId': data['guideId'],
            'guideName': data['guideName'],
            'date': data['date'],
          };
        }
      }
      
      print('✅ Loaded ${assignments.length} individual pickup assignments for date: $date');
      return assignments;
    } catch (e) {
      print('❌ Failed to get individual pickup assignments: $e');
      return {};
    }
  }

  // Save individual pickup assignment
  static Future<void> savePickupAssignment({
    required String bookingId,
    required String guideId,
    required String guideName,
    required DateTime date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping pickup assignment save');
      return;
    }
    
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      await _firestore!
          .collection('pickup_assignments')
          .doc('${dateStr}_$bookingId')
          .set({
        'bookingId': bookingId,
        'guideId': guideId,
        'guideName': guideName,
        'date': dateStr,
        'assignedAt': FieldValue.serverTimestamp(),
        'assignedBy': currentUser?.uid,
      }, SetOptions(merge: true));
      
      print('✅ Pickup assignment saved: $bookingId -> $guideName');
    } catch (e) {
      print('❌ Failed to save pickup assignment: $e');
    }
  }

  // Remove pickup assignment
  static Future<void> removePickupAssignment(String bookingId) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping pickup assignment removal');
      return;
    }
    
    try {
      // Find and delete the assignment document
      final querySnapshot = await _firestore!
          .collection('pickup_assignments')
          .where('bookingId', isEqualTo: bookingId)
          .get();
      
      final batch = _firestore!.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      print('✅ Pickup assignment removed: $bookingId');
    } catch (e) {
      print('❌ Failed to remove pickup assignment: $e');
    }
  }

  // Save reordered booking list for a guide
  static Future<void> saveReorderedBookings({
    required String guideId,
    required String date,
    required List<String> bookingIds,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping reordered bookings save');
      return;
    }
    
    try {
      await _firestore!
          .collection('reordered_bookings')
          .doc('${date}_$guideId')
          .set({
        'guideId': guideId,
        'date': date,
        'bookingIds': bookingIds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('✅ Reordered bookings saved for guide $guideId: ${bookingIds.length} bookings');
    } catch (e) {
      print('❌ Failed to save reordered bookings: $e');
    }
  }

  // Get reordered booking list for a guide
  static Future<List<String>> getReorderedBookings({
    required String guideId,
    required String date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - returning empty reordered bookings');
      return [];
    }
    
    try {
      final doc = await _firestore!
          .collection('reordered_bookings')
          .doc('${date}_$guideId')
          .get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final bookingIds = List<String>.from(data['bookingIds'] ?? []);
        print('✅ Loaded reordered bookings for guide $guideId: ${bookingIds.length} bookings');
        return bookingIds;
      }
      
      return [];
    } catch (e) {
      print('❌ Failed to get reordered bookings: $e');
      return [];
    }
  }

  // Remove reordered bookings for a guide
  static Future<void> removeReorderedBookings({
    required String guideId,
    required String date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping reordered bookings removal');
      return;
    }
    
    try {
      await _firestore!
          .collection('reordered_bookings')
          .doc('${date}_$guideId')
          .delete();
      
      print('✅ Reordered bookings removed for guide $guideId');
    } catch (e) {
      print('❌ Failed to remove reordered bookings: $e');
    }
  }

  // Save updated pickup place for a booking
  static Future<void> saveUpdatedPickupPlace({
    required String bookingId,
    required String date,
    required String pickupPlace,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping pickup place update');
      return;
    }
    
    try {
      await _firestore!
          .collection('updated_pickup_places')
          .doc('${date}_$bookingId')
          .set({
        'bookingId': bookingId,
        'date': date,
        'pickupPlace': pickupPlace,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('✅ Updated pickup place saved for booking $bookingId: $pickupPlace');
    } catch (e) {
      print('❌ Failed to save updated pickup place: $e');
    }
  }

  // Get updated pickup places for a date
  static Future<Map<String, String>> getUpdatedPickupPlaces(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - returning empty updated pickup places');
      return {};
    }
    
    try {
      final querySnapshot = await _firestore!
          .collection('updated_pickup_places')
          .where('date', isEqualTo: date)
          .get();

      final pickupPlaces = <String, String>{};
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final bookingId = data['bookingId'] as String?;
        final pickupPlace = data['pickupPlace'] as String?;
        if (bookingId != null && pickupPlace != null) {
          pickupPlaces[bookingId] = pickupPlace;
        }
      }
      
      print('✅ Loaded ${pickupPlaces.length} updated pickup places for date $date');
      return pickupPlaces;
    } catch (e) {
      print('❌ Failed to get updated pickup places: $e');
      return {};
    }
  }

  // Save bus-guide assignment for a specific date
  static Future<void> saveBusGuideAssignment({
    required String guideId,
    required String guideName,
    required String busId,
    required String busName,
    required String date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping bus-guide assignment save');
      return;
    }
    
    // Check if user is authenticated
    final currentUser = _auth?.currentUser;
    if (currentUser == null) {
      print('❌ User not authenticated - cannot save bus-guide assignment');
      throw Exception('User not authenticated. Please log in again.');
    }
    
    print('👤 Current user: ${currentUser.uid} (${currentUser.email})');
    
    try {
      final docPath = '${date}_$guideId';
      print('💾 Attempting to save to: bus_guide_assignments/$docPath');
      
      await _firestore!
          .collection('bus_guide_assignments')
          .doc(docPath)
          .set({
        'guideId': guideId,
        'guideName': guideName,
        'busId': busId,
        'busName': busName,
        'date': date,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('✅ Bus-guide assignment saved: $busName -> $guideName for date $date');
    } catch (e) {
      print('❌ Failed to save bus-guide assignment: $e');
      print('📋 Error details: ${e.toString()}');
      // Re-throw so caller can handle permission errors
      if (e.toString().contains('permission') || e.toString().contains('PERMISSION_DENIED')) {
        throw Exception('Permission denied: Please check Firestore security rules for bus_guide_assignments collection. User: ${currentUser.uid}');
      }
      rethrow;
    }
  }

  // Get bus assignment for a guide on a specific date
  static Future<Map<String, String>?> getBusAssignmentForGuide({
    required String guideId,
    required String date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping bus assignment load');
      return null;
    }
    
    try {
      final doc = await _firestore!
          .collection('bus_guide_assignments')
          .doc('${date}_$guideId')
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        return {
          'busId': data['busId'] as String? ?? '',
          'busName': data['busName'] as String? ?? '',
        };
      }
      
      return null;
    } catch (e) {
      print('❌ Failed to get bus assignment for guide: $e');
      return null;
    }
  }

  // Get guide assignment for a bus on a specific date
  static Future<Map<String, String>?> getGuideAssignmentForBus({
    required String busId,
    required String date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping guide assignment load');
      return null;
    }
    
    try {
      final query = await _firestore!
          .collection('bus_guide_assignments')
          .where('busId', isEqualTo: busId)
          .where('date', isEqualTo: date)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        return {
          'guideId': data['guideId'] as String? ?? '',
          'guideName': data['guideName'] as String? ?? '',
        };
      }
      
      return null;
    } catch (e) {
      print('❌ Failed to get guide assignment for bus: $e');
      return null;
    }
  }

  // Remove bus-guide assignment
  static Future<void> removeBusGuideAssignment({
    required String guideId,
    required String date,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping bus-guide assignment removal');
      return;
    }
    
    try {
      await _firestore!
          .collection('bus_guide_assignments')
          .doc('${date}_$guideId')
          .delete();
      
      print('✅ Bus-guide assignment removed for guide $guideId on date $date');
    } catch (e) {
      print('❌ Failed to remove bus-guide assignment: $e');
    }
  }
} 