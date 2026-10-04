package dev.pixelforge.pixelforge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// Keeps the process alive while a batch runs. The work itself stays in Dart;
/// this service exists only so Android does not kill it mid-batch, and so the
/// user sees live progress with a way to cancel.
///
/// The cancel action reopens MainActivity with a cancel extra rather than
/// talking to Dart from a receiver, because a receiver cannot reach the
/// Flutter engine cleanly.
class BatchService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.getStringExtra(EXTRA_COMMAND)) {
            COMMAND_PROGRESS -> {
                val done = intent.getIntExtra(EXTRA_DONE, 0)
                val total = intent.getIntExtra(EXTRA_TOTAL, 1)
                startForegroundService(done, total)
            }
            COMMAND_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundService(done: Int, total: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Batch processing",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val cancelIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(MainActivity.EXTRA_CANCEL_BATCH, true)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val cancel = PendingIntent.getActivity(
            this, 0, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PixelForge")
            .setContentText("Processing $done of $total images")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(total.coerceAtLeast(1), done.coerceIn(0, total.coerceAtLeast(1)), false)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Cancel",
                cancel,
            )
            .setContentIntent(cancel)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val CHANNEL_ID = "pixelforge_batch"
        const val NOTIFICATION_ID = 41
        const val EXTRA_COMMAND = "pixelforge_command"
        const val COMMAND_PROGRESS = "progress"
        const val COMMAND_STOP = "stop"
        const val EXTRA_DONE = "done"
        const val EXTRA_TOTAL = "total"
    }
}
