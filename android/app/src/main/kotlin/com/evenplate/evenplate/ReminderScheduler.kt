package com.evenplate.evenplate

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

object ReminderScheduler {
    private const val prefsName = "evenplate_reminders"
    const val channelId = "evenplate_reminders"

    fun replace(context: Context, arguments: Any?) {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val alarm = context.getSystemService(AlarmManager::class.java)
        val previous = JSONArray(prefs.getString("rows", "[]"))
        val manager = context.getSystemService(NotificationManager::class.java)
        for (i in 0 until previous.length()) {
            val id = previous.getJSONObject(i).getInt("id")
            alarm.cancel(pending(context, id, null))
            manager.cancel(id)
        }
        // Cancel alarms left by an earlier app version.
        for (raw in prefs.getStringSet("ids", emptySet()) ?: emptySet()) {
            raw.toIntOrNull()?.let { alarm.cancel(pending(context, it, null)); manager.cancel(it) }
        }
        val rows = JSONArray()
        for (raw in arguments as? List<*> ?: emptyList<Any>()) {
            val map = raw as? Map<*, *> ?: continue
            rows.put(JSONObject(map))
        }
        prefs.edit().putString("rows", rows.toString()).remove("ids").apply()
        restore(context)
    }

    fun restore(context: Context) {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val rows = JSONArray(prefs.getString("rows", "[]"))
        for (i in 0 until rows.length()) schedule(context, rows.getJSONObject(i))
    }

    private fun schedule(context: Context, row: JSONObject) {
        var whenMs = row.optLong("when")
        val repeatKind = row.optString("repeat")
        if (whenMs <= System.currentTimeMillis() && repeatKind.isNotEmpty()) {
            val calendar = Calendar.getInstance().apply { timeInMillis = whenMs }
            while (calendar.timeInMillis <= System.currentTimeMillis()) calendar.add(Calendar.DAY_OF_YEAR, if (repeatKind == "weekly") 7 else 1)
            whenMs = calendar.timeInMillis
        }
        if (whenMs <= System.currentTimeMillis()) return
        val id = row.getInt("id")
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", row.getString("title"))
            putExtra("body", row.getString("body"))
            putExtra("payload", row.optString("payload", "{}"))
            putExtra("repeat", repeatKind)
        }
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMs, pending(context, id, intent))
    }

    private fun pending(context: Context, id: Int, intent: Intent?): PendingIntent = PendingIntent.getBroadcast(
        context, id, intent ?: Intent(context, ReminderReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { ReminderScheduler.restore(context) }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: return
        val id = intent.getIntExtra("id", 0)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) manager.createNotificationChannel(NotificationChannel(ReminderScheduler.channelId, "Meal reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, ReminderScheduler.channelId) else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        fun open(action: String, request: Int): PendingIntent {
            val launch = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("reminder_payload", intent.getStringExtra("payload"))
                putExtra("reminder_action", action)
            }
            return PendingIntent.getActivity(context, request, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        builder.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText(body)
            .setContentIntent(open("open", id)).setAutoCancel(true)
        if (id >= 100000) {
            builder.addAction(Notification.Action.Builder(null, "Steady", open("action_steady", id + 1000000)).build())
            builder.addAction(Notification.Action.Builder(null, "Feeling a dip", open("action_dip", id + 2000000)).build())
        }
        try { manager.notify(id, builder.build()) } catch (_: SecurityException) { }
        if (!intent.getStringExtra("repeat").isNullOrEmpty()) ReminderScheduler.restore(context)
    }
}
