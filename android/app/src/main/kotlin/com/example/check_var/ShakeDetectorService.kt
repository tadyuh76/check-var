package com.example.check_var

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import kotlin.math.sqrt

class ShakeDetectorService : Service(), SensorEventListener {

    companion object {
        private const val TAG = "ShakeDetector"
        private const val CHANNEL_ID = "checkvar_shake"
        private const val NOTIFICATION_ID = 1
        private const val SHAKE_THRESHOLD = 15.0f
        private const val SHAKE_TIME_WINDOW = 2000L
        private const val MIN_SHAKE_INTERVAL = 3000L
        private const val SHAKE_DEBOUNCE = 300L

        /**
         * Optional callback set by the scam-call ServiceBridge to intercept
         * shake events for call-mode detection. When set, this fires INSTEAD
         * of the default ServiceBridge.instance.onShakeDetected() path.
         */
        var onShakeDetected: (() -> Unit)? = null
    }

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var lastShakeTime = 0L
    private var shakeCount = 0
    private var lastDetectionTime = 0L
    private var notifTitle = "CheckVar is active"
    private var notifBody = "Shake your phone 3 times to check news"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // Temporary notification — will be replaced in onStartCommand with localized strings.
        startForeground(NOTIFICATION_ID, buildNotification())

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelerometer?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }

        Log.d(TAG, "Service created, sensor registered, wakeLock acquired")
    }

    override fun onDestroy() {
        sensorManager?.unregisterListener(this)
        Log.d(TAG, "Service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra("notificationTitle")?.let { notifTitle = it }
        intent?.getStringExtra("notificationBody")?.let { notifBody = it }
        // Update the notification with localized strings.
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]

        val acceleration = sqrt((x * x + y * y + z * z).toDouble()).toFloat() - SensorManager.GRAVITY_EARTH

        if (acceleration > SHAKE_THRESHOLD) {
            val now = System.currentTimeMillis()

            if (now - lastDetectionTime < MIN_SHAKE_INTERVAL) return
            if (now - lastShakeTime < SHAKE_DEBOUNCE) return

            if (now - lastShakeTime < SHAKE_TIME_WINDOW) {
                shakeCount++
                Log.d(TAG, "Shake count: $shakeCount")
                if (shakeCount >= 3) {
                    Log.d(TAG, "Triple shake detected!")
                    shakeCount = 0
                    lastDetectionTime = now

                    if (!shouldHandleShake()) {
                        Log.d(TAG, "Ignoring shake: screen off, locked, or app in foreground")
                        return
                    }

                    // If the scam-call layer set a callback, use it;
                    // otherwise fall through to the news-check path.
                    val callback = onShakeDetected
                    if (callback != null) {
                        callback.invoke()
                    } else {
                        ServiceBridge.instance.onShakeDetected()
                    }
                }
            } else {
                shakeCount = 1
            }
            lastShakeTime = now
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** Only handle shake when screen is on, unlocked, and app is NOT in foreground */
    private fun shouldHandleShake(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isInteractive) return false

        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (km.isKeyguardLocked) return false

        // Use MainActivity lifecycle flag — getRunningTasks() is broken on Android 10+
        if (MainActivity.isInForeground) return false

        return true
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "CheckVar Shake Detection",
            NotificationManager.IMPORTANCE_LOW
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(notifTitle)
            .setContentText(notifBody)
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setOngoing(true)
            .build()
    }
}
