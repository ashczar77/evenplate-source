package com.evenplate.evenplate

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reminders: MethodChannel? = null
    private var pending: Map<String, String>? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "evenplate/permissions").setMethodCallHandler { call, result ->
            if (call.method != "openSettings") {
                result.notImplemented()
            } else {
                try {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(true)
                } catch (error: Exception) {
                    result.success(false)
                }
            }
        }
        readReminder(intent)
        reminders = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "evenplate/reminders").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pending" -> { result.success(pending); pending = null }
                    "acknowledge" -> { pending = null; result.success(null) }
                    "replace" -> {
                        try { ReminderScheduler.replace(this@MainActivity, call.arguments); result.success(null) }
                        catch (error: Exception) { result.error("schedule_failed", error.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readReminder(intent)
        pending?.let { reminders?.invokeMethod("notification", it) }
    }
    private fun readReminder(intent: Intent) {
        val payload = intent.getStringExtra("reminder_payload") ?: return
        pending = mapOf("payload" to payload, "action" to (intent.getStringExtra("reminder_action") ?: "open"))
        intent.removeExtra("reminder_payload")
    }
}
