package io.github.waywhywhy.waydlp

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps waydlp alive while downloads run, showing a
 * progress notification. It stops itself when no job is queued or running.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannels(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        ServiceCompat.startForeground(this, ONGOING_ID, buildOngoing(this), type)
        if (DownloadEngine.activeCount() == 0) stopSelfSafely()
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ limits dataSync services; stop gracefully (downloads can be resumed).
        stopSelfSafely()
    }

    private fun stopSelfSafely() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        private const val CHANNEL_PROGRESS = "downloads"
        private const val CHANNEL_DONE = "completed"
        private const val ONGOING_ID = 1
        @Volatile private var lastRefresh = 0L
        @Volatile private var running = false

        fun intent(ctx: Context) = Intent(ctx, DownloadService::class.java)

        fun start(ctx: Context) {
            running = true
            ContextCompat.startForegroundService(ctx, intent(ctx))
        }

        fun ensureChannels(ctx: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_PROGRESS, "Download progress", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) },
            )
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_DONE, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }

        private fun openApp(ctx: Context): PendingIntent = PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun buildOngoing(ctx: Context): Notification {
            val (text, fraction) = DownloadEngine.summary()
            return NotificationCompat.Builder(ctx, CHANNEL_PROGRESS)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("waydlp is downloading")
                .setContentText(text)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setContentIntent(openApp(ctx))
                .setProgress(100, if (fraction >= 0) (fraction * 100).toInt() else 0, fraction < 0)
                .build()
        }

        private fun canNotify(ctx: Context): Boolean =
            Build.VERSION.SDK_INT < 33 ||
                ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

        /** Update the ongoing notification (throttled) or stop when idle. */
        @SuppressLint("MissingPermission") // checked by canNotify()
        fun refresh(ctx: Context) {
            if (DownloadEngine.activeCount() == 0) {
                if (running) {
                    running = false
                    ctx.stopService(intent(ctx))
                }
                return
            }
            val now = SystemClock.elapsedRealtime()
            if (now - lastRefresh < 1000) return
            lastRefresh = now
            if (canNotify(ctx)) NotificationManagerCompat.from(ctx).notify(ONGOING_ID, buildOngoing(ctx))
        }

        @SuppressLint("MissingPermission") // checked by canNotify()
        fun notifyDone(ctx: Context, title: String, ok: Boolean) {
            if (!canNotify(ctx)) return
            ensureChannels(ctx)
            val n = NotificationCompat.Builder(ctx, CHANNEL_DONE)
                .setSmallIcon(if (ok) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
                .setContentTitle(if (ok) "Download complete" else "Download failed")
                .setContentText(title)
                .setAutoCancel(true)
                .setContentIntent(openApp(ctx))
                .build()
            NotificationManagerCompat.from(ctx).notify(title.hashCode() and 0x7fffffff or 0x10000, n)
        }
    }
}
