// Helper script to set up Google Maps API key
// Run this script to configure your Google Maps API key

import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  print('🗺️  Google Maps API Key Setup Helper');
  print('=====================================\n');

  // Load environment variables
  await dotenv.load(fileName: '.env');

  final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
  
  if (apiKey == null || apiKey.isEmpty || apiKey == 'your_google_maps_api_key_here') {
    print('❌ Google Maps API key not found in .env file');
    print('\n📝 To fix this:');
    print('1. Open your .env file');
    print('2. Find the line: GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here');
    print('3. Replace "your_google_maps_api_key_here" with your actual API key');
    print('4. Save the file');
    print('\n🔑 To get a Google Maps API key:');
    print('1. Go to https://console.cloud.google.com/');
    print('2. Create a new project or select existing one');
    print('3. Enable "Maps SDK for Android" API');
    print('4. Go to Credentials and create an API key');
    print('5. Copy the API key to your .env file');
  } else {
    print('✅ Google Maps API key found in .env file');
    print('🔑 API Key: ${apiKey.substring(0, 10)}...');
    
    // Check Android manifest
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    if (await manifestFile.exists()) {
      final manifestContent = await manifestFile.readAsString();
      
      if (manifestContent.contains('YOUR_ACTUAL_API_KEY')) {
        print('\n⚠️  Android manifest still has placeholder API key');
        print('📝 To fix this:');
        print('1. Open android/app/src/main/AndroidManifest.xml');
        print('2. Find: android:value="YOUR_ACTUAL_API_KEY"');
        print('3. Replace "YOUR_ACTUAL_API_KEY" with: $apiKey');
        print('4. Save the file');
        print('5. Run: flutter clean && flutter pub get');
      } else if (manifestContent.contains(apiKey)) {
        print('\n✅ Android manifest is configured correctly');
      } else {
        print('\n⚠️  Android manifest has a different API key');
        print('Please update android/app/src/main/AndroidManifest.xml with your API key');
      }
    }
  }

  print('\n🚀 Next steps:');
  print('1. Ensure your API key is set in both .env and AndroidManifest.xml');
  print('2. Run: flutter clean');
  print('3. Run: flutter pub get');
  print('4. Run: flutter run');
  print('5. Navigate to Admin > Map to test');
} 