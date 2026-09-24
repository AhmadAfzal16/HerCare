package com.example.hercare

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NotificationRiskService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        if (sbn.packageName == packageName || notification.category != Notification.CATEGORY_MESSAGE) {
            return
        }
        val title = notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val preview = "$title $body".take(100)
        TelemetryStore.record(applicationContext, preview)
    }
}

internal data class NotificationAggregate(
    val notificationsSeen: Int,
    val messageNotifications: Int,
    val negativeNotifications: Int,
    val distressNotifications: Int,
    val abuseNotifications: Int,
)

internal object TelemetryStore {
    const val analysisVersion = "on-device-lexicon-v1"
    private const val preferencesName = "hercare_aggregate_telemetry"
    private val negativeTerms = listOf(
        "sad", "alone", "hopeless", "cry", "hate", "upset", "bad",
        "اداس", "اکیلی", "ناامید", "رونا", "نفرت", "پریشان",
        "udas", "akeli", "akela", "naumeed", "rona", "pareshan",
    )
    private val distressTerms = listOf(
        "die", "dead", "suicide", "kill myself", "hurt myself", "no reason to live",
        "مرنا", "موت", "خودکشی", "خود کو نقصان", "جینا نہیں",
        "marna", "khudkushi", "jaan de", "zinda nahi", "khud ko nuqsan",
    )
    private val abuseTerms = listOf(
        "useless", "worthless", "stupid", "shut up", "leave you", "divorce",
        "بیکار", "فضول", "چپ کرو", "چھوڑ دوں", "طلاق",
        "bekar", "fazool", "chup karo", "chor dunga", "talaq",
    )

    @Synchronized
    fun record(context: Context, preview: String) {
        val prefs = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("monitoring_enabled", false)) return
        ensureToday(prefs)
        val normalized = preview.lowercase(Locale.ROOT)
        val negative = negativeTerms.any(normalized::contains)
        val distress = distressTerms.any(normalized::contains)
        val abuse = abuseTerms.any(normalized::contains)
        prefs.edit()
            .putInt("notifications_seen", prefs.getInt("notifications_seen", 0) + 1)
            .putInt("message_notifications", prefs.getInt("message_notifications", 0) + 1)
            .putInt(
                "negative_notifications",
                prefs.getInt("negative_notifications", 0) + if (negative) 1 else 0,
            )
            .putInt(
                "distress_notifications",
                prefs.getInt("distress_notifications", 0) + if (distress) 1 else 0,
            )
            .putInt(
                "abuse_notifications",
                prefs.getInt("abuse_notifications", 0) + if (abuse) 1 else 0,
            )
            .apply()
        // The preview is deliberately discarded here and is never persisted or sent to Flutter.
    }

    @Synchronized
    fun snapshot(context: Context): NotificationAggregate {
        val prefs = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        ensureToday(prefs)
        return NotificationAggregate(
            notificationsSeen = prefs.getInt("notifications_seen", 0),
            messageNotifications = prefs.getInt("message_notifications", 0),
            negativeNotifications = prefs.getInt("negative_notifications", 0),
            distressNotifications = prefs.getInt("distress_notifications", 0),
            abuseNotifications = prefs.getInt("abuse_notifications", 0),
        )
    }

    @Synchronized
    fun setMonitoringEnabled(context: Context, enabled: Boolean) {
        val prefs = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        if (!enabled) {
            prefs.edit().clear().putBoolean("monitoring_enabled", false).commit()
        } else {
            prefs.edit().putBoolean("monitoring_enabled", true).apply()
        }
    }

    private fun ensureToday(preferences: android.content.SharedPreferences) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        if (preferences.getString("local_date", null) == today) return
        val enabled = preferences.getBoolean("monitoring_enabled", false)
        preferences.edit().clear()
            .putBoolean("monitoring_enabled", enabled)
            .putString("local_date", today)
            .commit()
    }
}
