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
} 