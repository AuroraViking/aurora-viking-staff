// Simple script to update Google Maps API key in Android manifest
// Run: dart scripts/update_google_maps_key.dart

import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  print('🗺️  Updating Google Maps API Key');
  print('===============================\n');

  try {
    // Load environment variables
    await dotenv.load(fileName: '.env');
    
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_google_maps_api_key_here') {
      print('❌ Google Maps API key not found in .env file');
      print('Please add GOOGLE_MAPS_API_KEY=your_actual_key to your .env file');
      exit(1);
    }

    print('✅ Found Google Maps API key in .env file');
    print('🔑 API Key: ${apiKey.substring(0, 10)}...');
    
    // Read the Android manifest
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    if (!await manifestFile.exists()) {
      print('❌ AndroidManifest.xml not found');
      exit(1);
    }

    String manifestContent = await manifestFile.readAsString();
    
    // Check if the API key is already set correctly
    if (manifestContent.contains(apiKey)) {
      print('✅ AndroidManifest.xml already has the correct API key');
      return;
    }
    
    // Find and replace the API key
    final regex = RegExp(r'android:value="[^"]*"');
    final newContent = manifestContent.replaceFirst(
      regex,
      'android:value="$apiKey"'
    );

    if (newContent != manifestContent) {
      // Write the updated manifest
      await manifestFile.writeAsString(newContent);
      print('✅ Updated AndroidManifest.xml with API key');
      print('\n🚀 Next steps:');
      print('flutter clean');
      print('flutter pub get');
      print('flutter run');
    } else {
      print('❌ Could not find API key placeholder in AndroidManifest.xml');
    }

  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
} 