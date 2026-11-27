package com.pyure.player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground-сервис с типом `dataSync`, удерживающий процесс и PARTIAL_WAKE_LOCK
 * во время индексации MP3-файлов, чтобы сканирование на Android не прерывалось
 * при сворачивании приложения или блокировке экрана.
 */
class ScanForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val folderArg = intent?.getStringExtra(EXTRA_FOLDER_NAME)?.trim()
        if (!folderArg.isNullOrEmpty()) {
            currentFolderName = folderArg
        }

        val appContext = applicationContext
        ensureNotificationChannel(appContext)
        val notification = buildNotification(
            context = appContext,
            folderName = currentFolderName,
            processed = currentProcessed,
            total = currentTotal,
            fileName = currentFileName,
        )

        try {
            val fgType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, fgType)
        } catch (_: Exception) {
            stopAndRelease()
            return START_NOT_STICKY
        }

        if (!shouldStayActive) {
            stopAndRelease()
            return START_NOT_STICKY
        }

        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopAndRelease()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopAndRelease()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        shouldStayActive = false
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Pyure:LibraryScanWakeLock",
        ).apply {
            setReferenceCounted(false)
            acquire(MAX_WAKE_LOCK_MS)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun stopAndRelease() {
        shouldStayActive = false
        releaseWakeLock()
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        stopSelf()
    }

    companion object {
        private const val CHANNEL_ID = "pyure_library_scan"
        private const val CHANNEL_NAME = "Сканирование медиатеки"
        private const val NOTIFICATION_ID = 2026
        private const val EXTRA_FOLDER_NAME = "folder_name"
        private const val MAX_WAKE_LOCK_MS = 2L * 60L * 60L * 1000L

        @Volatile
        private var shouldStayActive = false

        @Volatile
        private var currentFolderName = "медиатека"

        @Volatile
        private var currentProcessed = 0

        @Volatile
        private var currentTotal = 0

        @Volatile
        private var currentFileName = ""

        fun start(context: Context, folderName: String?) {
            val appContext = context.applicationContext
            shouldStayActive = true
            currentFolderName = folderName?.trim()?.takeIf { it.isNotEmpty() } ?: "медиатека"
            currentProcessed = 0
            currentTotal = 0
            currentFileName = ""

            ensureNotificationChannel(appContext)
            val intent = Intent(appContext, ScanForegroundService::class.java).apply {
                putExtra(EXTRA_FOLDER_NAME, currentFolderName)
            }
            try {
                ContextCompat.startForegroundService(appContext, intent)
            } catch (_: Exception) {
            }
        }

        fun updateProgress(
            context: Context,
            processed: Int,
            total: Int,
            fileName: String?,
        ) {
            if (!shouldStayActive) return
            val appContext = context.applicationContext
            currentProcessed = processed.coerceAtLeast(0)
            currentTotal = total.coerceAtLeast(0)
            currentFileName = fileName?.trim() ?: ""

            ensureNotificationChannel(appContext)
            val notification = buildNotification(
                context = appContext,
                folderName = currentFolderName,
                processed = currentProcessed,
                total = currentTotal,
                fileName = currentFileName,
            )
            val manager =
                appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    ?: return
            try {
                manager.notify(NOTIFICATION_ID, notification)
            } catch (_: Exception) {
            }
        }

        fun stop(context: Context) {
            val appContext = context.applicationContext
            shouldStayActive = false
            val manager =
                appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            try {
                manager?.cancel(NOTIFICATION_ID)
            } catch (_: Exception) {
            }
            try {
                appContext.stopService(Intent(appContext, ScanForegroundService::class.java))
            } catch (_: Exception) {
            }
        }

        private fun ensureNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Отображает прогресс фонового поиска и чтения треков Pyure"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        private fun buildNotification(
            context: Context,
            folderName: String,
            processed: Int,
            total: Int,
            fileName: String,
        ): Notification {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
            val contentIntent = PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val indeterminate = total <= 0
            val clampedProcessed = if (total > 0) processed.coerceIn(0, total) else 0
            val contentText = when {
                total <= 0 -> "Поиск MP3-файлов в папке «$folderName»…"
                fileName.isNotEmpty() -> "$clampedProcessed из $total • $fileName"
                else -> "Обработано $clampedProcessed из $total"
            }

            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_pyure)
                .setContentTitle("Сканирование медиатеки")
                .setContentText(contentText)
                .setSubText(folderName)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setProgress(if (indeterminate) 0 else total, clampedProcessed, indeterminate)
                .setContentIntent(contentIntent)
                .build()
        }
    }
}
