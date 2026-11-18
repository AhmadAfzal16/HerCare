package com.hercare.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

/** Generic foreground counterpart to the OS-owned background FCM notification. */
class UrgentNotifications(private val context: Context) {
    companion object {
        const val CHANNEL_ID = "hercare_urgent_v1"
        private const val INTENT_KEY = "hercare_urgent_recipient"

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val sound = Uri.parse("android.resource://${context.packageName}/raw/hercare_urgent")
            val audio = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                CHANNEL_ID, "Urgent guardian support", NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Time-sensitive support alerts from an approved HerCare link"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                enableVibration(true)
                setSound(sound, audio)
                // Never bypass DND; channel sound/importance remains user-controlled.
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        fun takeOpened(intent: Intent?): Map<String, String>? {
            if (intent == null) return null
            val recipient = intent.getStringExtra(INTENT_KEY) ?: return null
            val alert = intent.getStringExtra("hercare_urgent_alert") ?: return null
            intent.removeExtra(INTENT_KEY)
            intent.removeExtra("hercare_urgent_alert")
            if (!validId(recipient) || !validId(alert)) return null
            return mapOf(
                "recipient_id" to recipient, "alert_id" to alert,
                "type" to "guardian_alert", "route" to "/notifications", "urgent" to "true",
            )
        }

        private fun validId(value: String): Boolean =
            Regex("^[A-Za-z0-9-]{1,100}$").matches(value)
    }

    private var accountId: String? = null
    private val shown = linkedSetOf<String>()
    private val manager get() = context.getSystemService(NotificationManager::class.java)

    fun bindAccount(value: String?) {
        val next = value?.takeIf { validId(it) }
        if (next == accountId) return
        // Clear prior app notices at account boundaries, including OS-posted FCM.
        manager.cancelAll()
        shown.clear()
        accountId = next
    }

    fun show(data: Map<*, *>): Boolean {
        val recipient = data["recipient_id"] as? String ?: return false
        val alert = data["alert_id"] as? String ?: return false
        if (recipient != accountId || !validId(recipient) || !validId(alert) ||
            data["urgent"] != "true" || data["type"] != "guardian_alert" ||
            data["route"] != "/notifications") return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID)?.importance ==
            NotificationManager.IMPORTANCE_NONE) return false
        val key = "$recipient:$alert"
        if (!shown.add(key)) return false
        if (shown.size > 100) shown.remove(shown.first())
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(INTENT_KEY, recipient)
            putExtra("hercare_urgent_alert", alert)
        }
        val notificationId = key.hashCode() and 0x7fffffff
        val pending = PendingIntent.getActivity(
            context, notificationId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("HerCare support alert")
            .setContentText("Please open HerCare and check in with your linked mother.")
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    setPriority(Notification.PRIORITY_HIGH)
                    setSound(Uri.parse("android.resource://${context.packageName}/raw/hercare_urgent"))
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    setTimeoutAfter(60 * 60 * 1000L)
                }
            }.build()
        return try {
            manager.notify("hercare_urgent:$alert", notificationId, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }
}
