package com.suryatejap24.snooze

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
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
        // What the reliability check needs: device facts and settings pages.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snooze/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER.lowercase(),
                            "sdk" to Build.VERSION.SDK_INT,
                            "batteryUnrestricted" to isIgnoringBatteryOptimizations(),
                            "fullScreenAllowed" to canUseFullScreenIntent(),
                        ),
                    )
                    "open" -> result.success(openSettings(call.argument<String>("page")))
                    else -> result.notImplemented()
                }
            }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val notifications =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return notifications.canUseFullScreenIntent()
    }

    /** Opens a settings page for this app; falls back to the app's info page. */
    private fun openSettings(page: String?): Boolean {
        val pkg = Uri.parse("package:$packageName")
        val intent = when {
            page == "notifications" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            page == "exactAlarms" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, pkg)
            page == "fullScreen" &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg)
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            } catch (e: ActivityNotFoundException) {
                false
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
