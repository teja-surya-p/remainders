package com.suryatejap24.snooze

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        setShowOverLockScreen(isAlarmLaunch(intent))
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Only switch on here; the alarm screen switches it off when it closes.
        if (isAlarmLaunch(intent)) setShowOverLockScreen(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snooze/lockscreen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "release" -> {
                        setShowOverLockScreen(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Only a ringing alarm may appear over the lock screen; the rest of the app
     * stays behind it. flutter_local_notifications launches the activity with
     * action SELECT_NOTIFICATION and the notification payload as an extra.
     */
    private fun isAlarmLaunch(intent: Intent?): Boolean {
        if (intent?.action != "SELECT_NOTIFICATION") return false
        return intent.getStringExtra("payload")?.startsWith("alarm:") == true
    }

    private fun setShowOverLockScreen(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
}
