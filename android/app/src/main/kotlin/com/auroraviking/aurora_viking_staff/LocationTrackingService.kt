package com.auroraviking.aurora_viking_staff

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.*
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class LocationTrackingService : Service() {
    private val binder = LocationBinder()
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var busId: String? = null
    private var userId: String? = null
    private var updateIntervalMs: Long = 10000
    private var distanceFilterMeters: Float = 5f
    
    private var lastLocation: Location? = null
    private var locationUpdateCount = 0
    
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val CHANNEL_NAME = "Location Tracking"
        private const val CHANNEL_DESCRIPTION = "Tracks bus location for Aurora Viking staff"
        
        private const val METHOD_CHANNEL = "com.auroraviking.aurora_viking_staff/location"
        private const val EVENT_CHANNEL = "com.auroraviking.aurora_viking_staff/location_updates"
        
        // Static references for Flutter communication
        private var methodChannel: MethodChannel? = null
        private var eventSink: EventChannel.EventSink? = null
        private var instance: LocationTrackingService? = null
        
        // Service running state - moved to companion object for persistence
        @Volatile
        var isRunning: Boolean = false
            private set
        
        @JvmStatic
        fun setupChannels(flutterEngine: FlutterEngine, context: Context) {
            // Set up method channel
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            methodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLocationService" -> {
                        val busId = call.argument<String>("busId")
                        val userId = call.argument<String>("userId")
                        val updateIntervalMs = call.argument<Int>("updateIntervalMs")?.toLong() ?: 10000L
                        val distanceFilterMeters = call.argument<Int>("distanceFilterMeters")?.toFloat() ?: 5f
                        
                        if (busId != null && userId != null) {
                            startService(context, busId, userId, updateIntervalMs, distanceFilterMeters)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "busId and userId are required", null)
                        }
                    }
                    "stopLocationService" -> {
                        stopService(context)
                        result.success(true)
                    }
                    "isServiceRunning" -> {
                        result.success(isRunning)
                    }
                    "heartbeat" -> {
                        instance?.onHeartbeat()
                        result.success(true)
                    }
                    "getLastLocation" -> {
                        val location = instance?.lastLocation
                        if (location != null) {
                            result.success(mapOf(
                                "latitude" to location.latitude,
                                "longitude" to location.longitude,
                                "accuracy" to location.accuracy,
                                "altitude" to location.altitude,
                                "speed" to location.speed,
                                "heading" to location.bearing
                            ))
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
            
            // Set up event channel for location updates
            val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
        
        private fun startService(
            context: Context,
            busId: String,
            userId: String,
            updateIntervalMs: Long,
            distanceFilterMeters: Float
        ) {
            val intent = Intent(context, LocationTrackingService::class.java).apply {
                putExtra("busId", busId)
                putExtra("userId", userId)
                putExtra("updateIntervalMs", updateIntervalMs)
                putExtra("distanceFilterMeters", distanceFilterMeters)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        private fun stopService(context: Context) {
            val intent = Intent(context, LocationTrackingService::class.java)
            context.stopService(intent)
        }
        
        // Send location to Flutter
        fun sendLocationToFlutter(location: Location) {
            val locationData = mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
                "altitude" to location.altitude,
                "speed" to location.speed.toDouble(),
                "heading" to location.bearing.toDouble(),
                "timestamp" to System.currentTimeMillis()
            )
            
            // Send via event channel
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(locationData)
            }
            
            // Also send via method channel as backup
            Handler(Looper.getMainLooper()).post {
                methodChannel?.invokeMethod("onLocationUpdate", locationData)
            }
        }
        
        // Notify Flutter that service stopped
        fun notifyServiceStopped() {
            Handler(Looper.getMainLooper()).post {
                methodChannel?.invokeMethod("onServiceStopped", null)
            }
        }
        
        // Notify Flutter of errors
        fun notifyError(error: String) {
            Handler(Looper.getMainLooper()).post {
                methodChannel?.invokeMethod("onServiceError", error)
            }
        }
    }
    
    inner class LocationBinder : Binder() {
        fun getService(): LocationTrackingService = this@LocationTrackingService
    }
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }
    
    override fun onBind(intent: Intent): IBinder {
        return binder
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Extract parameters from intent
        busId = intent?.getStringExtra("busId")
        userId = intent?.getStringExtra("userId")
        updateIntervalMs = intent?.getLongExtra("updateIntervalMs", 10000) ?: 10000
        distanceFilterMeters = intent?.getFloatExtra("distanceFilterMeters", 5f) ?: 5f
        
        // Start as foreground service with proper type for Android 10+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, 
                createNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }
        
        // Acquire wake lock
        acquireWakeLock()
        
        // Start location updates
        startLocationUpdates()
        
        LocationTrackingService.isRunning = true
        android.util.Log.d("LocationService", "Service started for bus: $busId")
        
        // Return START_STICKY to restart service if killed
        return START_STICKY
    }
    
    override fun onDestroy() {
        super.onDestroy()
        LocationTrackingService.isRunning = false
        stopLocationUpdates()
        releaseWakeLock()
        instance = null
        notifyServiceStopped()
        android.util.Log.d("LocationService", "Service destroyed")
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Restart service if app is killed from recents
        android.util.Log.d("LocationService", "Task removed, service will continue running")
    }
    
    private fun onHeartbeat() {
        android.util.Log.d("LocationService", "Heartbeat received, location updates: $locationUpdateCount")
        // Force a location update on heartbeat
        requestSingleLocation()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = CHANNEL_DESCRIPTION
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Create a stop action
        val stopIntent = Intent(this, LocationTrackingService::class.java).apply {
            action = "STOP_TRACKING"
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Aurora Viking Staff")
            .setContentText("Tracking bus location • ${locationUpdateCount} updates")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(R.mipmap.ic_launcher, "Stop", stopPendingIntent)
            .build()
    }
    
    private fun updateNotification() {
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, createNotification())
    }
    
    private fun startLocationUpdates() {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            updateIntervalMs
        ).apply {
            setMinUpdateIntervalMillis(updateIntervalMs / 2)
            setMaxUpdateDelayMillis(updateIntervalMs * 2)
            setMinUpdateDistanceMeters(distanceFilterMeters)
            setWaitForAccurateLocation(false)
        }.build()
        
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    handleLocationUpdate(location)
                }
            }
            
            override fun onLocationAvailability(availability: LocationAvailability) {
                if (!availability.isLocationAvailable) {
                    android.util.Log.w("LocationService", "Location not available")
                    notifyError("Location not available")
                }
            }
        }
        
        try {
            fusedLocationClient?.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                Looper.getMainLooper()
            )
            android.util.Log.d("LocationService", "Location updates started")
        } catch (e: SecurityException) {
            android.util.Log.e("LocationService", "Security exception: ${e.message}")
            notifyError("Location permission denied")
        } catch (e: Exception) {
            android.util.Log.e("LocationService", "Error starting location updates: ${e.message}")
            notifyError("Error starting location updates: ${e.message}")
        }
        
        // Also request a single location immediately
        requestSingleLocation()
    }
    
    private fun requestSingleLocation() {
        try {
            fusedLocationClient?.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                null
            )?.addOnSuccessListener { location ->
                location?.let { handleLocationUpdate(it) }
            }?.addOnFailureListener { e ->
                android.util.Log.e("LocationService", "Error getting single location: ${e.message}")
            }
        } catch (e: SecurityException) {
            android.util.Log.e("LocationService", "Security exception getting single location: ${e.message}")
        }
    }
    
    private fun handleLocationUpdate(location: Location) {
        lastLocation = location
        locationUpdateCount++
        
        // Send to Flutter
        sendLocationToFlutter(location)
        
        // Update notification periodically
        if (locationUpdateCount % 10 == 0) {
            updateNotification()
        }
        
        android.util.Log.d("LocationService", 
            "Location update #$locationUpdateCount: ${location.latitude}, ${location.longitude} " +
            "(accuracy: ${location.accuracy}m, speed: ${location.speed}m/s)")
    }
    
    private fun stopLocationUpdates() {
        locationCallback?.let { callback ->
            fusedLocationClient?.removeLocationUpdates(callback)
        }
        locationCallback = null
        android.util.Log.d("LocationService", "Location updates stopped")
    }
    
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "AuroraViking::LocationTrackingWakeLock"
            ).apply {
                // Acquire with timeout to avoid ANR, will be re-acquired periodically
                acquire(10 * 60 * 1000L) // 10 minutes
            }
            
            // Set up a handler to periodically re-acquire the wake lock
            val handler = Handler(Looper.getMainLooper())
            val reacquireRunnable = object : Runnable {
                override fun run() {
                    if (isRunning && wakeLock != null) {
                        try {
                            if (!wakeLock!!.isHeld) {
                                wakeLock!!.acquire(10 * 60 * 1000L)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("LocationService", "Error re-acquiring wake lock: ${e.message}")
                        }
                        handler.postDelayed(this, 5 * 60 * 1000L) // Re-check every 5 minutes
                    }
                }
            }
            handler.postDelayed(reacquireRunnable, 5 * 60 * 1000L)
            
            android.util.Log.d("LocationService", "Wake lock acquired")
        } catch (e: Exception) {
            android.util.Log.e("LocationService", "Error acquiring wake lock: ${e.message}")
        }
    }
    
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            wakeLock = null
            android.util.Log.d("LocationService", "Wake lock released")
        } catch (e: Exception) {
            android.util.Log.e("LocationService", "Error releasing wake lock: ${e.message}")
        }
    }
}