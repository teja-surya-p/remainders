package com.suryatejap24.snooze

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * Re-arms every reminder after events that invalidate scheduled alarms: a
 * reboot (the OS clears alarms), an app update, a manual clock change, and a
 * time-zone change (reminders keep their local clock time). Hands off to the
 * Dart re-arm job (lib/background/rearm_job.dart) via the workmanager plugin.
 */
class RearmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val request = OneTimeWorkRequestBuilder<BackgroundWorker>()
            .setInputData(Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, TASK).build())
            .build()
        // Several events often arrive together (time + zone); run once.
        WorkManager.getInstance(context)
            .enqueueUniqueWork(TASK, ExistingWorkPolicy.REPLACE, request)
    }

    companion object {
        /** Must match kRearmNowTask in lib/background/rearm_job.dart. */
        const val TASK = "snooze.rearm.now"
    }
}
