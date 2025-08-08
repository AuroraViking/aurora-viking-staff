// Script to initialize default buses in the database
// Run: dart scripts/initialize_buses.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  print('🚌 Initializing Default Buses');
  print('==============================\n');

  try {
    // Load environment variables
    await dotenv.load(fileName: '.env');
    
    // Initialize Firebase (you'll need to set up Firebase credentials)
    // This is just a template - you'll need to configure Firebase properly
    
    final firestore = FirebaseFirestore.instance;
    
    // Default buses data
    final defaultBuses = [
      {
        'name': 'Lúxusinn - AYX70',
        'licensePlate': 'AYX70',
        'color': 'blue',
        'description': 'Main luxury bus for premium tours',
        'isActive': true,
      },
      {
        'name': 'Afi Stjáni - MAF43',
        'licensePlate': 'MAF43',
        'color': 'green',
        'description': 'Reliable bus for standard tours',
        'isActive': true,
      },
      {
        'name': 'Meistarinn - TZE50',
        'licensePlate': 'TZE50',
        'color': 'red',
        'description': 'Master bus for large groups',
        'isActive': true,
      },
    ];

    print('📝 Adding default buses to database...');
    
    for (final bus in defaultBuses) {
      try {
        await firestore.collection('buses').add({
          ...bus,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ Added: ${bus['name']}');
      } catch (e) {
        print('❌ Failed to add ${bus['name']}: $e');
      }
    }

    print('\n🎉 Bus initialization completed!');
    print('You can now use the Bus Management screen to manage these buses.');
    
  } catch (e) {
    print('❌ Error initializing buses: $e');
    print('\nMake sure you have:');
    print('1. Firebase properly configured');
    print('2. .env file with Firebase credentials');
    print('3. Firestore rules allowing write access to buses collection');
  }
} 