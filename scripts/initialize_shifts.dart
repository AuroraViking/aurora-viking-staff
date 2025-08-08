// Script to initialize sample shifts in the database
// Run: dart scripts/initialize_shifts.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize Firebase
  await Firebase.initializeApp();
  
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  // Sign in anonymously for testing
  await auth.signInAnonymously();
  print('✅ Signed in anonymously');

  // Create sample shifts for the next 30 days
  final now = DateTime.now();
  final shifts = <Map<String, dynamic>>[];

  for (int i = 0; i < 30; i++) {
    final date = now.add(Duration(days: i));
    
    // Day Tour shifts (every day)
    shifts.add({
      'type': 'dayTour',
      'date': date.toIso8601String(),
      'startTime': '09:00',
      'endTime': '17:00',
      'status': 'available',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Northern Lights shifts (every other day)
    if (i % 2 == 0) {
      shifts.add({
        'type': 'northernLights',
        'date': date.toIso8601String(),
        'startTime': '20:00',
        'endTime': '23:00',
        'status': 'available',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Add shifts to Firestore
  print('📅 Creating ${shifts.length} sample shifts...');
  
  for (final shift in shifts) {
    await firestore.collection('shifts').add(shift);
  }

  print('✅ Successfully created ${shifts.length} sample shifts');
  print('📊 Shifts created for the next 30 days');
  print('🌞 Day Tours: Every day at 09:00-17:00');
  print('🌌 Northern Lights: Every other day at 20:00-23:00');
  print('📱 Guides can now apply for these shifts in the app');
  
  // Sign out
  await auth.signOut();
  print('👋 Signed out');
} 