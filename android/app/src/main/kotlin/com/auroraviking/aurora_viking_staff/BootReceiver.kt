package com.auroraviking.aurora_viking_staff

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * BootReceiver - Automatically restarts location tracking after device reboot
 *
 * This is optional - if you don't want auto-restart after reboot, you can:
 * 1. Remove the <receiver> entry from AndroidManifest.xml
 * 2. Delete this file
 *
 * The tracking state is saved in SharedPreferences when tracking starts/stops.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val PREFS_NAME = "aurora_viking_location_prefs"
        private const val KEY_WAS_TRACKING = "was_tracking"
        private const val KEY_BUS_ID = "bus_id"
        private const val KEY_USER_ID = "user_id"

        /**
         * Save tracking state to SharedPreferences
         * Called by MainActivity when tracking starts/stops
         */
        fun saveTrackingState(context: Context, isTracking: Boolean, busId: String?, userId: String?) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putBoolean(KEY_WAS_TRACKING, isTracking)
                    if (isTracking && busId != null && userId != null) {
                        putString(KEY_BUS_ID, busId)
                        putString(KEY_USER_ID, userId)
                    } else {
                        remove(KEY_BUS_ID)
                        remove(KEY_USER_ID)
                    }
                    apply()
                }
                android.util.Log.d("BootReceiver", "Saved tracking state: isTracking=$isTracking, busId=$busId")
            } catch (e: Exception) {
                android.util.Log.e("BootReceiver", "Error saving tracking state: ${e.message}")
            }
        }

        /**
         * Get saved tracking state from SharedPreferences
         */
        fun getTrackingState(context: Context): Triple<Boolean, String?, String?> {
            return try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val wasTracking = prefs.getBoolean(KEY_WAS_TRACKING, false)
                val busId = prefs.getString(KEY_BUS_ID, null)
                val userId = prefs.getString(KEY_USER_ID, null)
                Triple(wasTracking, busId, userId)
            } catch (e: Exception) {
                android.util.Log.e("BootReceiver", "Error getting tracking state: ${e.message}")
                Triple(false, null, null)
            }
        }

        /**
         * Clear tracking state
         */
        fun clearTrackingState(context: Context) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().clear().apply()
                android.util.Log.d("BootReceiver", "Cleared tracking state")
            } catch (e: Exception) {
                android.util.Log.e("BootReceiver", "Error clearing tracking state: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON") {

            android.util.Log.d("BootReceiver", "Device booted, checking if tracking should restart")

            val (wasTracking, busId, userId) = getTrackingState(context)

            if (wasTracking && busId != null && userId != null) {
                android.util.Log.d("BootReceiver", "Restarting location tracking for bus: $busId")

                // Start the location service
                val serviceIntent = Intent(context, LocationTrackingService::class.java).apply {
                    putExtra("busId", busId)
                    putExtra("userId", userId)
                    putExtra("updateIntervalMs", 10000L)
                    putExtra("distanceFilterMeters", 5f)
                }

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    android.util.Log.d("BootReceiver", "Location service restarted successfully after boot")
                } catch (e: Exception) {
                    android.util.Log.e("BootReceiver", "Error starting location service after boot: ${e.message}")
                }
            } else {
                android.util.Log.d("BootReceiver", "Tracking was not active before reboot (wasTracking=$wasTracking, busId=$busId)")
            }
        }
    }
}