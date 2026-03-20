package com.example.check_var

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import java.util.concurrent.Executors

class CallMonitorService : Service() {

    companion object {
        private const val CHANNEL_ID = "call_monitor_channel"
        private const val NOTIFICATION_ID = 3001

        var onCallStateChanged: ((Map<String, Any>) -> Unit)? = null
    }

    private var telephonyManager: TelephonyManager? = null
    private var telephonyCallback: TelephonyCallback? = null
    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        registerCallStateListener()
    }

    override fun onDestroy() {
        unregisterCallStateListener()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    private fun registerCallStateListener() {
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleCallState(state)
                }
            }
            telephonyCallback = callback
            telephonyManager?.registerTelephonyCallback(executor, callback)
        }
    }

    private fun unregisterCallStateListener() {
        telephonyCallback?.let { callback ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyManager?.unregisterTelephonyCallback(callback)
            }
        }
        telephonyCallback = null
    }

    private fun handleCallState(state: Int) {
        val isActive = CallMonitorPolicy.isCallActive(state)

        val event = SpeakerTestLaunch.buildCallActiveEvent(isActive)
        onCallStateChanged?.invoke(event)

        if (CallMonitorPolicy.shouldHideOverlay(state)) {
            val overlayIntent = Intent(this, OverlayBubbleService::class.java)
            stopService(overlayIntent)
            val statusBubbleIntent = Intent(this, CallStatusBubbleService::class.java)
            stopService(statusBubbleIntent)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Call Monitor",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Monitors call state for scam detection"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("CheckVar")
            .setContentText("Monitoring calls — shake during a call to detect scams")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .build()
    }
}
