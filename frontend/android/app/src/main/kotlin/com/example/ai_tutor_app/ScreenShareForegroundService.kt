package com.example.ai_tutor_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Minimal foreground service required by Android 10+ (strictly enforced
 * on Android 14+) before MediaProjection.start() can be called - without
 * a running foregroundServiceType="mediaProjection" service, the OS
 * throws inside MediaProjectionManagerService and the whole app crashes
 * (this is exactly what was happening: the permission dialog appeared
 * and was accepted, but the app died immediately after because this
 * service didn't exist yet).
 *
 * flutter_webrtc's OrientationAwareScreenCapturer does NOT start this
 * service itself - starting it is the hosting app's responsibility.
 */
class ScreenShareForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "screen_share_channel"
        const val NOTIFICATION_ID = 4321
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Sharing",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("AI Tutor")
            .setContentText("Sharing your screen in the live class")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
