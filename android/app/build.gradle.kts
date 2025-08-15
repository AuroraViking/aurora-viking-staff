plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

android {
    namespace = "com.auroraviking.aurora_viking_staff"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // Load MAPS_API_KEY from multiple sources (project -P, local.properties, env)
    val localPropsFile = rootProject.file("local.properties")
    val localProps = Properties()
    if (localPropsFile.exists()) {
        localProps.load(localPropsFile.inputStream())
    }
    val mapsKey: String = (project.findProperty("MAPS_API_KEY") as String?)
        ?: (project.findProperty("GOOGLE_MAPS_API_KEY") as String?)
        ?: (localProps.getProperty("MAPS_API_KEY") ?: localProps.getProperty("GOOGLE_MAPS_API_KEY"))
        ?: (System.getenv("MAPS_API_KEY") ?: System.getenv("GOOGLE_MAPS_API_KEY") ?: "")

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.auroraviking.aurora_viking_staff"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23  // Updated from flutter.minSdkVersion to 23 for Firebase compatibility
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = mapsKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-location:20.0.0")
    implementation("androidx.core:core:1.10.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
}
