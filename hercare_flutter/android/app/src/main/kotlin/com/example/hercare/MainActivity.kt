package com.hercare.app

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val channelName = "com.hercare/telemetry"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    "hercare_urgent_alerts",
                    "Urgent wellbeing alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Time-sensitive HerCare support notifications"
                    enableVibration(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                },
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "platform" -> result.success("android")
                    "hasNotificationAccess" -> result.success(hasNotificationAccess())
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "setMonitoringEnabled" -> {
                        TelemetryStore.setMonitoringEnabled(
                            this,
                            call.argument<Boolean>("enabled") == true,
                        )
                        result.success(null)
                    }
                    "collectTelemetry" -> result.success(collectTelemetry())
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasNotificationAccess(): Boolean {
        val component = ComponentName(this, NotificationRiskService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it) == component
        }
    }

    private fun hasUsageAccess(): Boolean {
        val manager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = manager.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun collectTelemetry(): Map<String, Any> {
        val notification = TelemetryStore.snapshot(this)
        val usage = if (hasUsageAccess()) collectUsage() else UsageAggregate()
        val timezoneOffset = -Calendar.getInstance().timeZone.getOffset(System.currentTimeMillis()) / 60000
        return mapOf(
            "local_date" to SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()),
            "timezone_offset_minutes" to timezoneOffset,
            "notifications_seen" to notification.notificationsSeen,
            "message_notifications" to notification.messageNotifications,
            "negative_notifications" to notification.negativeNotifications,
            "distress_notifications" to notification.distressNotifications,
            "abuse_notifications" to notification.abuseNotifications,
            "screen_time_minutes" to usage.screenMinutes,
            "social_minutes" to usage.socialMinutes,
            "late_night_minutes" to usage.lateNightMinutes,
            "app_switches" to usage.appSwitches,
            "notification_access" to hasNotificationAccess(),
            "usage_access" to hasUsageAccess(),
            "analysis_version" to TelemetryStore.analysisVersion,
        )
    }

    private fun collectUsage(): UsageAggregate {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val socialPackages = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "org.telegram.messenger",
            "com.facebook.orca",
            "com.instagram.android",
            "com.snapchat.android",
        )
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, now)
        val screenMs = stats.sumOf { max(0L, it.totalTimeInForeground) }
        val socialMs = stats
            .filter { socialPackages.contains(it.packageName) }
            .sumOf { max(0L, it.totalTimeInForeground) }

        var switches = 0
        var lateNightMs = 0L
        val activeSince = mutableMapOf<String, Long>()
        val events = manager.queryEvents(start, now)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    switches += 1
                    activeSince[event.packageName] = event.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    val resumed = activeSince.remove(event.packageName) ?: continue
                    lateNightMs += lateNightOverlap(resumed, event.timeStamp)
                }
            }
        }
        activeSince.values.forEach { lateNightMs += lateNightOverlap(it, now) }
        return UsageAggregate(
            screenMinutes = (screenMs / 60000).toInt().coerceIn(0, 1440),
            socialMinutes = (socialMs / 60000).toInt().coerceIn(0, 1440),
            lateNightMinutes = (lateNightMs / 60000).toInt().coerceIn(0, 480),
            appSwitches = switches.coerceIn(0, 20000),
        )
    }

    private fun lateNightOverlap(start: Long, end: Long): Long {
        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val fiveAm = midnight + (5 * 60 * 60 * 1000L)
        return max(0L, minOf(end, fiveAm) - maxOf(start, midnight))
    }
}

private data class UsageAggregate(
    val screenMinutes: Int = 0,
    val socialMinutes: Int = 0,
    val lateNightMinutes: Int = 0,
    val appSwitches: Int = 0,
)
