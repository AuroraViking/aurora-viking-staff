import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_options.dart';
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
      // Use platform-specific options (required for web!)
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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
    bool? paidOnArrival,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping booking status update');
      return;
    }
    
    try {
      final docId = '${date}_$bookingId';
      print('💾 Updating booking status:');
      print('   Document ID: $docId');
      print('   Booking ID: $bookingId');
      print('   Date: $date');
      print('   isArrived: $isArrived');
      print('   isNoShow: $isNoShow');
      print('   paidOnArrival: $paidOnArrival');
      
      final updates = <String, dynamic>{};
      if (isArrived != null) updates['isArrived'] = isArrived;
      if (isNoShow != null) updates['isNoShow'] = isNoShow;
      if (paidOnArrival != null) updates['paidOnArrival'] = paidOnArrival;
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedBy'] = currentUser?.uid;

      await _firestore!
          .collection('booking_status')
          .doc(docId)
          .set(updates, SetOptions(merge: true));
      
      print('✅ Booking status updated successfully in Firestore');
      print('   This should trigger Cloud Function onPickupCompleted or onNoShowMarked');
    } catch (e) {
      print('❌ Failed to update booking status: $e');
      print('   Stack trace: ${StackTrace.current}');
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
      print('   busId: $busId');
      print('   busName: $busName');
      print('   guideId: $guideId');
      print('   guideName: $guideName');
      print('   date: $date');
      
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
      print('   Document path: bus_guide_assignments/$docPath');
      print('   Saved busId field: $busId');
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
      print('🔍 Querying bus_guide_assignments for busId=$busId, date=$date');
      final query = await _firestore!
          .collection('bus_guide_assignments')
          .where('busId', isEqualTo: busId)
          .where('date', isEqualTo: date)
          .limit(1)
          .get();
      
      print('📋 Query returned ${query.docs.length} documents');
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        print('✅ Found assignment document:');
        print('   Document ID: ${doc.id}');
        print('   busId in doc: ${data['busId']}');
        print('   busName in doc: ${data['busName']}');
        print('   guideId: ${data['guideId']}');
        print('   guideName: ${data['guideName']}');
        print('   date in doc: ${data['date']}');
        return {
          'guideId': data['guideId'] as String? ?? '',
          'guideName': data['guideName'] as String? ?? '',
        };
      }
      
      print('⚠️ No assignment found for busId=$busId on date=$date');
      print('   Tried query: busId=$busId, date=$date');
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

  /// Save bookings to Firebase cache for future retrieval
  /// This allows us to access past bookings even when Bokun API blocks them
  static Future<void> cacheBookings({
    required String date, // YYYY-MM-DD format
    required List<PickupBooking> bookings,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping booking cache');
      return;
    }
    
    try {
      // Convert bookings to JSON-serializable format
      final bookingsData = bookings.map((b) => b.toJson()).toList();
      
      await _firestore!
          .collection('cached_bookings')
          .doc(date)
          .set({
        'date': date,
        'bookings': bookingsData,
        'cachedAt': FieldValue.serverTimestamp(),
        'count': bookings.length,
      });
      
      print('💾 Cached ${bookings.length} bookings for date $date to Firebase');
    } catch (e) {
      print('❌ Failed to cache bookings to Firebase: $e');
    }
  }

  /// Retrieve cached bookings from Firebase
  /// Also merges manual bookings for the date
  /// Returns empty list if no cache exists or on error
  static Future<List<PickupBooking>> getCachedBookings(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - cannot retrieve cached bookings');
      return [];
    }
    
    try {
      final doc = await _firestore!
          .collection('cached_bookings')
          .doc(date)
          .get();
      
      List<PickupBooking> bookings = [];
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final bookingsData = data['bookings'] as List<dynamic>? ?? [];
        final cachedAt = data['cachedAt'];
        
        print('📂 Found cached bookings for $date (cached at: $cachedAt)');
        
        bookings = bookingsData
            .map((b) => PickupBooking.fromJson(b as Map<String, dynamic>))
            .toList();
        
        print('✅ Retrieved ${bookings.length} cached bookings for date $date');
      } else {
        print('ℹ️ No cached bookings found for date $date');
      }
      
      // Always load and merge manual bookings
      try {
        final manualBookings = await getManualBookings(date);
        if (manualBookings.isNotEmpty) {
          print('📋 Found ${manualBookings.length} manual bookings for date $date');
          final existingIds = bookings.map((b) => b.id).toSet();
          for (final manualBooking in manualBookings) {
            if (!existingIds.contains(manualBooking.id)) {
              bookings.add(manualBooking);
              print('✅ Added manual booking to cached list: ${manualBooking.customerFullName}');
            }
          }
          print('📋 Total bookings after merging manual: ${bookings.length}');
        }
      } catch (e) {
        print('⚠️ Failed to load manual bookings when getting cache: $e');
      }
      
      return bookings;
    } catch (e) {
      print('❌ Failed to retrieve cached bookings from Firebase: $e');
      return [];
    }
  }

  /// Check if we have cached bookings for a date
  static Future<bool> hasCachedBookings(String date) async {
    if (!_initialized || _firestore == null) return false;
    
    try {
      final doc = await _firestore!
          .collection('cached_bookings')
          .doc(date)
          .get();
      
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Save manual booking to Firebase
  static Future<void> saveManualBooking({
    required String date, // YYYY-MM-DD format
    required PickupBooking booking,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping manual booking save');
      return;
    }
    
    try {
      final docId = '${date}_${booking.id}';
      final bookingData = booking.toJson();
      
      print('💾 Saving manual booking to Firebase:');
      print('   Collection: manual_bookings');
      print('   Document ID: $docId');
      print('   Date: $date');
      print('   Booking ID: ${booking.id}');
      print('   Customer: ${booking.customerFullName}');
      
      await _firestore!
          .collection('manual_bookings')
          .doc(docId)
          .set({
        'date': date,
        'booking': bookingData,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('✅ Successfully saved manual booking ${booking.id} for date $date');
      
      // Verify the save by reading it back
      final verifyDoc = await _firestore!
          .collection('manual_bookings')
          .doc(docId)
          .get();
      
      if (verifyDoc.exists) {
        print('✅ Verified: Manual booking exists in Firebase');
      } else {
        print('⚠️ Warning: Manual booking not found after save!');
      }
    } catch (e) {
      print('❌ Failed to save manual booking: $e');
      print('❌ Error details: ${e.toString()}');
      rethrow;
    }
  }

  /// Get manual bookings for a date
  static Future<List<PickupBooking>> getManualBookings(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - cannot retrieve manual bookings');
      return [];
    }
    
    try {
      print('🔍 Querying manual bookings for date: $date');
      final querySnapshot = await _firestore!
          .collection('manual_bookings')
          .where('date', isEqualTo: date)
          .get();
      
      print('📋 Found ${querySnapshot.docs.length} manual booking documents for date $date');
      
      final bookings = <PickupBooking>[];
      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          print('📄 Processing document: ${doc.id}');
          final bookingData = data['booking'] as Map<String, dynamic>?;
          if (bookingData == null) {
            print('⚠️ Document ${doc.id} has no booking data');
            continue;
          }
          final booking = PickupBooking.fromJson(bookingData);
          bookings.add(booking);
          print('✅ Parsed manual booking: ${booking.customerFullName} (ID: ${booking.id})');
        } catch (e) {
          print('⚠️ Error parsing manual booking ${doc.id}: $e');
          print('⚠️ Document data: ${doc.data()}');
        }
      }
      
      print('✅ Retrieved ${bookings.length} manual bookings for date $date');
      if (bookings.isNotEmpty) {
        print('📋 Manual bookings: ${bookings.map((b) => b.customerFullName).join(", ")}');
      }
      return bookings;
    } catch (e) {
      print('❌ Failed to retrieve manual bookings: $e');
      print('❌ Error details: ${e.toString()}');
      return [];
    }
  }

  /// Delete manual booking from Firebase
  static Future<void> deleteManualBooking({
    required String date,
    required String bookingId,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping manual booking deletion');
      return;
    }
    
    try {
      await _firestore!
          .collection('manual_bookings')
          .doc('${date}_$bookingId')
          .delete();
      
      print('✅ Deleted manual booking $bookingId for date $date');
    } catch (e) {
      print('❌ Failed to delete manual booking: $e');
    }
  }

  /// Clear old cached bookings (older than specified days)
  /// Call this periodically to clean up storage
  static Future<void> clearOldCachedBookings({int olderThanDays = 90}) async {
    if (!_initialized || _firestore == null) return;
    
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
      final cutoffKey = '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';
      
      // Get all cached bookings
      final querySnapshot = await _firestore!
          .collection('cached_bookings')
          .where('date', isLessThan: cutoffKey)
          .get();
      
      if (querySnapshot.docs.isEmpty) {
        print('ℹ️ No old cached bookings to clean up');
        return;
      }
      
      // Delete in batches
      final batch = _firestore!.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      print('🗑️ Cleaned up ${querySnapshot.docs.length} old cached booking records');
    } catch (e) {
      print('❌ Failed to clear old cached bookings: $e');
    }
  }

  /// Save daily distance for a bus (for service/maintenance tracking)
  static Future<void> saveBusDailyDistance({
    required String busId,
    required String date,
    required double distanceKm,
    required int trailPoints,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping distance save');
      return;
    }
    
    try {
      await _firestore!
          .collection('bus_distance_logs')
          .doc('${date}_$busId')
          .set({
        'busId': busId,
        'date': date,
        'distanceKm': distanceKm,
        'trailPoints': trailPoints,
        'recordedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('💾 Saved distance log: Bus $busId drove ${distanceKm.toStringAsFixed(1)} km on $date');
    } catch (e) {
      print('❌ Failed to save bus distance: $e');
    }
  }

  /// Get total distance for a bus over a date range
  static Future<double> getBusTotalDistance({
    required String busId,
    required String startDate,
    required String endDate,
  }) async {
    if (!_initialized || _firestore == null) return 0.0;
    
    try {
      final querySnapshot = await _firestore!
          .collection('bus_distance_logs')
          .where('busId', isEqualTo: busId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();
      
      double totalDistance = 0.0;
      for (final doc in querySnapshot.docs) {
        totalDistance += (doc.data()['distanceKm'] as num?)?.toDouble() ?? 0.0;
      }
      
      print('📊 Bus $busId total distance ($startDate to $endDate): ${totalDistance.toStringAsFixed(1)} km');
      return totalDistance;
    } catch (e) {
      print('❌ Failed to get bus total distance: $e');
      return 0.0;
    }
  }

  /// Get distance logs for all buses (for service dashboard)
  static Future<List<Map<String, dynamic>>> getAllBusDistanceLogs({
    required String startDate,
    required String endDate,
  }) async {
    if (!_initialized || _firestore == null) return [];
    
    try {
      final querySnapshot = await _firestore!
          .collection('bus_distance_logs')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: true)
          .get();
      
      final logs = querySnapshot.docs.map((doc) => {
        ...doc.data(),
        'id': doc.id,
      }).toList();
      
      print('📊 Retrieved ${logs.length} distance logs ($startDate to $endDate)');
      return logs;
    } catch (e) {
      print('❌ Failed to get bus distance logs: $e');
      return [];
    }
  }

  /// Get summary of distances by bus for a date range
  static Future<Map<String, double>> getBusDistanceSummary({
    required String startDate,
    required String endDate,
  }) async {
    if (!_initialized || _firestore == null) return {};
    
    try {
      final querySnapshot = await _firestore!
          .collection('bus_distance_logs')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();
      
      final summary = <String, double>{};
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final busId = data['busId'] as String;
        final distance = (data['distanceKm'] as num?)?.toDouble() ?? 0.0;
        
        summary[busId] = (summary[busId] ?? 0.0) + distance;
      }
      
      print('📊 Distance summary for ${summary.length} buses');
      return summary;
    } catch (e) {
      print('❌ Failed to get bus distance summary: $e');
      return {};
    }
  }

  /// Update bus odometer/service info
  static Future<void> updateBusServiceInfo({
    required String busId,
    double? totalOdometer,
    DateTime? lastServiceDate,
    double? kmSinceLastService,
    String? notes,
  }) async {
    if (!_initialized || _firestore == null) return;
    
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (totalOdometer != null) updateData['totalOdometer'] = totalOdometer;
      if (lastServiceDate != null) updateData['lastServiceDate'] = lastServiceDate.toIso8601String();
      if (kmSinceLastService != null) updateData['kmSinceLastService'] = kmSinceLastService;
      if (notes != null) updateData['serviceNotes'] = notes;
      
      await _firestore!
          .collection('bus_service_info')
          .doc(busId)
          .set(updateData, SetOptions(merge: true));
      
      print('✅ Updated service info for bus $busId');
    } catch (e) {
      print('❌ Failed to update bus service info: $e');
    }
  }

  /// Get bus service info
  static Future<Map<String, dynamic>?> getBusServiceInfo(String busId) async {
    if (!_initialized || _firestore == null) return null;
    
    try {
      final doc = await _firestore!
          .collection('bus_service_info')
          .doc(busId)
          .get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ Failed to get bus service info: $e');
      return null;
    }
  }

  /// Get tour report for a specific date
  static Future<Map<String, dynamic>?> getTourReport(String date) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized');
      return null;
    }
    
    try {
      final doc = await _firestore!
          .collection('tour_reports')
          .doc(date)
          .get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ Failed to get tour report: $e');
      return null;
    }
  }

  /// Get all tour reports (last 30 days)
  static Future<List<Map<String, dynamic>>> getRecentTourReports() async {
    if (!_initialized || _firestore == null) {
      return [];
    }
    
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final dateStr = '${thirtyDaysAgo.year}-${thirtyDaysAgo.month.toString().padLeft(2, '0')}-${thirtyDaysAgo.day.toString().padLeft(2, '0')}';
      
      final querySnapshot = await _firestore!
          .collection('tour_reports')
          .where('date', isGreaterThanOrEqualTo: dateStr)
          .orderBy('date', descending: true)
          .get();
      
      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Failed to get recent tour reports: $e');
      return [];
    }
  }

  /// Get all bus-guide assignments for a date
  static Future<List<Map<String, dynamic>>> getBusGuideAssignments(String date) async {
    if (!_initialized || _firestore == null) return [];
    
    try {
      final querySnapshot = await _firestore!
          .collection('bus_guide_assignments')
          .where('date', isEqualTo: date)
          .get();
      
      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Failed to get bus guide assignments: $e');
      return [];
    }
  }

  /// Save end of shift report
  static Future<void> saveEndOfShiftReport({
    required String date,
    required String guideId,
    required String guideName,
    String? busId,
    String? busName,
    required String auroraRating,
    required bool shouldRequestReviews,
    String? notes,
  }) async {
    if (!_initialized || _firestore == null) {
      print('⚠️ Firebase not initialized - skipping end of shift report save');
      return;
    }
    
    try {
      final docId = '${date}_$guideId';
      
      await _firestore!
          .collection('end_of_shift_reports')
          .doc(docId)
          .set({
        'id': docId,
        'date': date,
        'guideId': guideId,
        'guideName': guideName,
        'busId': busId,
        'busName': busName,
        'auroraRating': auroraRating,
        'shouldRequestReviews': shouldRequestReviews,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ End of shift report saved for guide $guideName on $date');
    } catch (e) {
      print('❌ Failed to save end of shift report: $e');
      rethrow;
    }
  }

  /// Get end of shift report for a specific guide and date
  static Future<Map<String, dynamic>?> getEndOfShiftReport({
    required String date,
    required String guideId,
  }) async {
    if (!_initialized || _firestore == null) return null;
    
    try {
      final docId = '${date}_$guideId';
      final doc = await _firestore!
          .collection('end_of_shift_reports')
          .doc(docId)
          .get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ Failed to get end of shift report: $e');
      return null;
    }
  }

  /// Get all end of shift reports for a date
  static Future<List<Map<String, dynamic>>> getEndOfShiftReportsForDate(String date) async {
    if (!_initialized || _firestore == null) return [];
    
    try {
      final querySnapshot = await _firestore!
          .collection('end_of_shift_reports')
          .where('date', isEqualTo: date)
          .get();
      
      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Failed to get end of shift reports: $e');
      return [];
    }
  }

  /// Check if guide has already submitted end of shift report
  static Future<bool> hasSubmittedEndOfShiftReport({
    required String date,
    required String guideId,
  }) async {
    if (!_initialized || _firestore == null) return false;
    
    try {
      final docId = '${date}_$guideId';
      final doc = await _firestore!
          .collection('end_of_shift_reports')
          .doc(docId)
          .get();
      
      return doc.exists;
    } catch (e) {
      print('❌ Failed to check end of shift report: $e');
      return false;
    }
  }
} 