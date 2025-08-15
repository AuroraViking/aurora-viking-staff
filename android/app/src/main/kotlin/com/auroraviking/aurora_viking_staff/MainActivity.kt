package com.auroraviking.aurora_viking_staff

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "aurora_viking_location"
    private var locationServiceIntent: Intent? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocationService" -> {
                    startLocationService()
                    result.success(true)
                }
                "stopLocationService" -> {
                    stopLocationService()
                    result.success(true)
                }
                "isLocationServiceRunning" -> {
                    result.success(isLocationServiceRunning())
                }
                "requestBatteryOptimizationBypass" -> {
                    requestBatteryOptimizationBypass()
                    result.success(true)
                }
                "requestPreciseLocationPermission" -> {
                    requestPreciseLocationPermission()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun startLocationService() {
        try {
            locationServiceIntent = Intent(this, LocationTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(locationServiceIntent!!)
            } else {
                startService(locationServiceIntent!!)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun stopLocationService() {
        try {
            locationServiceIntent?.let {
                stopService(it)
                locationServiceIntent = null
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun isLocationServiceRunning(): Boolean {
        return locationServiceIntent != null
    }
    
    private fun requestBatteryOptimizationBypass() {
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun requestPreciseLocationPermission() {
        try {
            // This will trigger the permission dialog
            // The actual permission request is handled by the Flutter permission_handler plugin
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
