package com.hero.blockatie

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Native, session-scoped backup for service-status monitoring. It only checks
 * whether Android Location Services are enabled; it never requests or reads a
 * coordinate. A foreground service is used because a Flutter stream cannot be
 * relied on after the app is backgrounded.
 */
class LocationReadinessMonitorService : Service() {
    companion object {
        private const val EXTRA_IS_ARABIC = "is_arabic"
        private const val POLL_INTERVAL_MS = 8_000L

        fun start(context: Context, isArabic: Boolean): Boolean {
            if (!hasLocationPermission(context)) return false
            val intent = Intent(context, LocationReadinessMonitorService::class.java)
                .putExtra(EXTRA_IS_ARABIC, isArabic)
            return try {
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (_: SecurityException) {
                false
            } catch (_: IllegalStateException) {
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationReadinessMonitorService::class.java))
            // Logout must clear both the location warning and the foreground
            // monitor notification immediately; do not wait for onDestroy.
            DriverReadinessNotifications.hideAll(context)
        }

        private fun hasLocationPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isArabic = false
    private var receiverRegistered = false
    private var previousServiceEnabled: Boolean? = null

    private val providerChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = evaluate()
    }

    private val poll = object : Runnable {
        override fun run() {
            evaluate()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isArabic = intent?.getBooleanExtra(EXTRA_IS_ARABIC, false) == true
        try {
            startAsForeground()
        } catch (_: SecurityException) {
            stopSelf()
            return START_NOT_STICKY
        }
        registerProviderChangedReceiver()
        evaluate()
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, POLL_INTERVAL_MS)
        // Never restart after the process is killed: an old driver session must
        // not recreate a monitor after logout or process death.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (receiverRegistered) {
            try {
                unregisterReceiver(providerChangedReceiver)
            } catch (_: IllegalArgumentException) {
                // Already unregistered by Android during teardown.
            }
            receiverRegistered = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        DriverReadinessNotifications.hideAll(this)
        super.onDestroy()
    }

    private fun startAsForeground() {
        val notification = DriverReadinessNotifications.monitorNotification(this, isArabic)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                DriverReadinessNotifications.MONITOR_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            startForeground(DriverReadinessNotifications.MONITOR_NOTIFICATION_ID, notification)
        }
    }

    private fun registerProviderChangedReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION).apply {
            addAction(LocationManager.MODE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(providerChangedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(providerChangedReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun evaluate() {
        val enabled = try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.isLocationEnabled
            } else {
                manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            }
        } catch (_: SecurityException) {
            false
        }

        if (previousServiceEnabled == enabled) return
        previousServiceEnabled = enabled
        if (enabled) {
            DriverReadinessNotifications.hideLocationOff(this)
        } else {
            DriverReadinessNotifications.showLocationOff(this, isArabic)
        }
    }
}

/** Shared notification contract for both Flutter and the native monitor. */
object DriverReadinessNotifications {
    const val LOCATION_OFF_NOTIFICATION_ID = 7201
    const val MONITOR_NOTIFICATION_ID = 7202
    private const val LOCATION_WARNING_CHANNEL_ID = "driver_location_readiness"
    private const val MONITOR_CHANNEL_ID = "driver_location_monitor"
    private const val READINESS_LAUNCH_EXTRA = "open_driver_readiness"

    fun showLocationOff(context: Context, isArabic: Boolean): String {
        if (!notificationsAllowed(context)) {
            hideLocationOff(context)
            return "PERMISSION_DENIED"
        }
        return try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureWarningChannel(manager, isArabic)
            manager.notify(LOCATION_OFF_NOTIFICATION_ID, locationOffNotification(context, isArabic))
            "POSTED"
        } catch (_: SecurityException) {
            "PERMISSION_DENIED"
        } catch (_: RuntimeException) {
            "FAILED"
        }
    }

    fun hideLocationOff(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(LOCATION_OFF_NOTIFICATION_ID)
    }

    fun hideAll(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(LOCATION_OFF_NOTIFICATION_ID)
        manager.cancel(MONITOR_NOTIFICATION_ID)
    }

    fun monitorNotification(context: Context, isArabic: Boolean): Notification {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureMonitorChannel(manager, isArabic)
        return NotificationCompat.Builder(context, MONITOR_CHANNEL_ID)
            .setSmallIcon(R.mipmap.notification_logo)
            .setContentTitle(if (isArabic) "مراقبة جاهزية الموقع" else "Location readiness monitoring")
            .setContentText(
                if (isArabic) "يتم التحقق من تشغيل خدمة الموقع."
                else "Checking whether location service is enabled."
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openAppIntent(context))
            .build()
    }

    private fun locationOffNotification(context: Context, isArabic: Boolean): Notification =
        NotificationCompat.Builder(context, LOCATION_WARNING_CHANNEL_ID)
            .setSmallIcon(R.mipmap.notification_logo)
            .setContentTitle(if (isArabic) "خدمة الموقع متوقفة" else "Location service is off")
            .setContentText(
                if (isArabic) "افتح التطبيق وشغّل الموقع للاستمرار باستقبال الطلبات."
                else "Open the app and enable location to continue receiving orders."
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent(context))
            .build()

    private fun openAppIntent(context: Context): PendingIntent {
        val launch = (context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(READINESS_LAUNCH_EXTRA, true)
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationsAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun ensureWarningChannel(manager: NotificationManager, isArabic: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(
                LOCATION_WARNING_CHANNEL_ID,
                if (isArabic) "جاهزية موقع السائق" else "Driver location readiness",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = if (isArabic) "تنبيهات توقف خدمة الموقع" else "Location service warnings"
                setShowBadge(false)
            },
        )
    }

    private fun ensureMonitorChannel(manager: NotificationManager, isArabic: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(
                MONITOR_CHANNEL_ID,
                if (isArabic) "مراقبة الموقع" else "Location monitoring",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = if (isArabic) "مراقبة حالة خدمة الموقع" else "Location service state monitoring"
                setShowBadge(false)
            },
        )
    }
}
