// Build script to inject environment variables into Android manifest
// Run this script before building: dart scripts/build_with_env.dart

import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main(List<String> args) async {
  print('🔧 Environment Injection Script');
  print('==============================\n');

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
    
    // Read the Android manifest
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    if (!await manifestFile.exists()) {
      print('❌ AndroidManifest.xml not found');
      exit(1);
    }

    String manifestContent = await manifestFile.readAsString();
    
    // Replace the placeholder with the actual API key
    final originalContent = manifestContent;
    manifestContent = manifestContent.replaceAll(
      'android:value="\${GOOGLE_MAPS_API_KEY}"',
      'android:value="$apiKey"'
    );

    if (manifestContent != originalContent) {
      // Write the updated manifest
      await manifestFile.writeAsString(manifestContent);
      print('✅ Updated AndroidManifest.xml with API key');
    } else {
      print('ℹ️  AndroidManifest.xml already has the correct API key');
    }

    print('\n🚀 Ready to build! Run:');
    print('flutter clean');
    print('flutter pub get');
    print('flutter run');

  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
} 