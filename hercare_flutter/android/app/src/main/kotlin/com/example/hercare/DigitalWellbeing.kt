package com.hercare.app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import java.util.Calendar

/** On-device aggregation only. No notification text or browsing history is read. */
object DigitalWellbeing {
    fun collect(context: Context): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val today = midnight.timeInMillis
        val nightStart = (midnight.clone() as Calendar).apply {
            add(Calendar.DATE, -1); set(Calendar.HOUR_OF_DAY, 18)
        }.timeInMillis
        val nightEnd = minOf(now, (midnight.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 12)
        }.timeInMillis)
        val lateEnd = (midnight.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 5)
        }.timeInMillis
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(nightStart, now)
            ?: return mapOf("available" to false)
        val totals = mutableMapOf<String, Long>()
        var active: String? = null
        var activeSince = nightStart
        var screenOff: Long? = null
        var bestStart: Long? = null
        var bestEnd: Long? = null
        var lateMs = 0L
        var switches = 0
        fun close(at: Long) {
            val pkg = active ?: return
            val from = maxOf(today, activeSince)
            val duration = (at - from).coerceAtLeast(0)
            totals[pkg] = (totals[pkg] ?: 0) + duration
            lateMs += (minOf(at, lateEnd) - from).coerceAtLeast(0)
            active = null
        }
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    close(event.timeStamp)
                    active = event.packageName
                    activeSince = event.timeStamp
                    if (event.timeStamp >= today) switches++
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (active == event.packageName) close(event.timeStamp)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    close(event.timeStamp)
                    if (screenOff == null) screenOff = event.timeStamp
                }
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    val start = screenOff
                    // Only completed intervals; never infer sleep while the screen is still off.
                    if (start != null && event.timeStamp <= nightEnd &&
                        event.timeStamp - start >= 2 * 60 * 60 * 1000L &&
                        event.timeStamp - start > (bestEnd ?: 0) - (bestStart ?: 0)) {
                        bestStart = start; bestEnd = event.timeStamp
                    }
                    screenOff = null
                }
                UsageEvents.Event.DEVICE_SHUTDOWN -> { close(event.timeStamp); screenOff = null }
            }
        }
        close(now)
        val social = setOf("com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger",
            "com.facebook.orca", "com.facebook.katana", "com.instagram.android", "com.snapchat.android",
            "com.zhiliaoapp.musically", "com.twitter.android")
        val apps = totals.entries.filter { it.value >= 60000 }.sortedByDescending { it.value }.take(50).map {
            val label = try {
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(it.key, 0)).toString()
            } catch (_: Exception) { it.key }
            mapOf("name" to label, "package" to it.key, "minutes" to it.value / 60000)
        }
        return mapOf(
            "available" to true, "collected_at" to now,
            "screen_minutes" to totals.values.sum() / 60000,
            "social_minutes" to totals.filterKeys { social.contains(it) }.values.sum() / 60000,
            "late_night_minutes" to lateMs / 60000, "app_switches" to switches,
            "apps" to apps, "estimated_bedtime" to bestStart, "estimated_wake" to bestEnd,
        )
    }
}
