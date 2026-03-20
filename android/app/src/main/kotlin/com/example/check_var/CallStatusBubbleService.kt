package com.example.check_var

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.IBinder
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * Compact Messenger-style overlay for real call detection.
 *
 * The bubble stays small and status-only while the user remains on the phone
 * UI. Tapping it foregrounds the app and requests the transcript debug screen.
 */
class CallStatusBubbleService : Service() {

    companion object {
        private var instance: CallStatusBubbleService? = null

        fun updateStatus(sessionStatus: String, threatLevel: String) {
            instance?.setStatus(sessionStatus, threatLevel)
        }
    }

    private var windowManager: WindowManager? = null
    private var bubbleView: TextView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var sessionStatus: String = "idle"
    private var threatLevel: String = "safe"

    override fun onCreate() {
        super.onCreate()
        instance = this

        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createBubbleView()
    }

    override fun onDestroy() {
        bubbleView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
        bubbleView = null
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createBubbleView() {
        val density = resources.displayMetrics.density
        val size = (62 * density).toInt()

        val bubble = TextView(this).apply {
            text = "CV"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(null, Typeface.BOLD)
        }

        layoutParams = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = (16 * density).toInt()
            y = (132 * density).toInt()
        }

        setupTouchBehavior(bubble)
        bubbleView = bubble
        setStatus(sessionStatus, threatLevel)

        try {
            windowManager?.addView(bubble, layoutParams)
        } catch (_: Exception) {
            bubbleView = null
            stopSelf()
        }
    }

    private fun setupTouchBehavior(view: View) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false
        val density = resources.displayMetrics.density
        val dragThreshold = 6 * density

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams?.x ?: 0
                    initialY = layoutParams?.y ?: 0
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!moved) {
                        val deltaX = kotlin.math.abs(event.rawX - touchX)
                        val deltaY = kotlin.math.abs(event.rawY - touchY)
                        moved = deltaX > dragThreshold || deltaY > dragThreshold
                    }

                    if (moved) {
                        layoutParams?.x = initialX - (event.rawX - touchX).toInt()
                        layoutParams?.y = initialY + (event.rawY - touchY).toInt()
                        windowManager?.updateViewLayout(bubbleView, layoutParams)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        launchDebugScreen()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun setStatus(sessionStatus: String, threatLevel: String) {
        this.sessionStatus = sessionStatus
        this.threatLevel = threatLevel

        bubbleView?.post {
            val bubble = bubbleView ?: return@post
            bubble.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(resolveBubbleColor(sessionStatus, threatLevel))
            }
            bubble.text = resolveBubbleLabel(sessionStatus, threatLevel)
        }
    }

    private fun resolveBubbleColor(sessionStatus: String, threatLevel: String): Int {
        return when {
            threatLevel == "scam" -> Color.parseColor("#D32F2F")
            threatLevel == "suspicious" -> Color.parseColor("#F9A825")
            sessionStatus == "error" -> Color.parseColor("#6A1B9A")
            sessionStatus == "reconnecting" -> Color.parseColor("#455A64")
            sessionStatus == "analyzing" -> Color.parseColor("#1976D2")
            else -> Color.parseColor("#00897B")
        }
    }

    private fun resolveBubbleLabel(sessionStatus: String, threatLevel: String): String {
        return when {
            threatLevel == "scam" -> "!!"
            threatLevel == "suspicious" -> "!?"
            sessionStatus == "error" -> "X"
            sessionStatus == "reconnecting" -> "..."
            sessionStatus == "analyzing" -> "..."
            else -> "CV"
        }
    }

    private fun launchDebugScreen() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launchIntent.putExtra(MainActivity.EXTRA_APP_ACTION, MainActivity.ACTION_OPEN_CALL_DEBUG)
        startActivity(launchIntent)
    }
}
