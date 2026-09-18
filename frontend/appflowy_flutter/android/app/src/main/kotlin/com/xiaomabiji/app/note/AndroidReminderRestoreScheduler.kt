package com.xiaomabiji.app.note

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.ZoneId

object AndroidReminderRestoreScheduler {
    private const val TAG = "ReminderRestore"
    private const val SCHEDULED_NOTIFICATIONS = "scheduled_notifications"
    private const val NOTIFICATION_TYPE = "notificationType"
    private const val REMINDER_TYPE = "reminder"
    private const val CLEANUP_REQUEST_CODE = 42872
    private const val CLEANUP_GRACE_MILLIS = 2 * 60 * 1000L
    private const val RETRY_MILLIS = 60 * 60 * 1000L

    fun sync(context: Context) {
        if (!AndroidPrivacyConsent.hasAccepted(context)) {
            disable(context)
            return
        }

        val reminderTimes = loadReminderTimes(context)
        if (reminderTimes == null) {
            enableBootReceiver(context)
            scheduleCleanup(context, System.currentTimeMillis())
            return
        }
        if (reminderTimes.isEmpty()) {
            disable(context)
            return
        }

        enableBootReceiver(context)
        scheduleCleanup(context, reminderTimes.minOrNull() ?: return)
    }

    fun disable(context: Context) {
        AndroidPrivacyConsent.setComponentEnabled(
            context,
            ReminderBootReceiver::class.java.name,
            false,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(cleanupIntent(context))
    }

    private fun enableBootReceiver(context: Context) {
        AndroidPrivacyConsent.setComponentEnabled(
            context,
            ReminderBootReceiver::class.java.name,
            true,
        )
    }

    private fun loadReminderTimes(context: Context): List<Long>? {
        val raw = context.getSharedPreferences(
            SCHEDULED_NOTIFICATIONS,
            Context.MODE_PRIVATE,
        ).getString(SCHEDULED_NOTIFICATIONS, null) ?: return emptyList()

        return try {
            val notifications = JSONArray(raw)
            buildList {
                for (index in 0 until notifications.length()) {
                    val notification = notifications.optJSONObject(index) ?: continue
                    val payload = notification.optString("payload")
                    val notificationType = try {
                        JSONObject(payload).optString(NOTIFICATION_TYPE)
                    } catch (_: Exception) {
                        null
                    }
                    if (notificationType != REMINDER_TYPE) {
                        continue
                    }

                    val scheduledDateTime = notification.optString("scheduledDateTime")
                    val timeZoneName = notification.optString("timeZoneName")
                    if (scheduledDateTime.isEmpty() || timeZoneName.isEmpty()) return null
                    try {
                        add(
                            LocalDateTime.parse(scheduledDateTime)
                                .atZone(ZoneId.of(timeZoneName))
                                .toInstant()
                                .toEpochMilli(),
                        )
                    } catch (error: Exception) {
                        Log.w(TAG, "Unable to parse scheduled reminder time", error)
                        return null
                    }
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to inspect scheduled reminder cache", error)
            null
        }
    }

    private fun scheduleCleanup(context: Context, reminderTime: Long) {
        val now = System.currentTimeMillis()
        val triggerAt = if (reminderTime > now) {
            reminderTime + CLEANUP_GRACE_MILLIS
        } else {
            now + RETRY_MILLIS
        }
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC,
                triggerAt,
                cleanupIntent(context),
            )
        } else {
            alarmManager.set(AlarmManager.RTC, triggerAt, cleanupIntent(context))
        }
    }

    private fun cleanupIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            CLEANUP_REQUEST_CODE,
            Intent(context, ReminderRestoreCleanupReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

class ReminderBootReceiver : ScheduledNotificationBootReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        AndroidReminderRestoreScheduler.sync(context)
    }
}

class ReminderRestoreCleanupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AndroidReminderRestoreScheduler.sync(context)
    }
}
