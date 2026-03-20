package com.example.check_var

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.IBinder
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Floating overlay that shows live transcript while the user is on their
 * phone app during a call. The overlay is draggable and can be collapsed
 * to a small indicator bubble or expanded to show full transcript text.
 */
class OverlayBubbleService : Service() {

    companion object {
        fun updateTranscript(text: String) {
            instance?.setTranscriptText(text)
        }

        private var instance: OverlayBubbleService? = null
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var transcriptTextView: TextView? = null
    private var scrollView: ScrollView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var isExpanded = true

    override fun onCreate() {
        super.onCreate()
        instance = this

        // SYSTEM_ALERT_WINDOW must be granted; silently skip if not.
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createOverlayView()
    }

    override fun onDestroy() {
        removeOverlayView()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createOverlayView() {
        val density = resources.displayMetrics.density

        // Root container
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#E6121212")) // Dark semi-transparent
            setPadding(
                (12 * density).toInt(),
                (8 * density).toInt(),
                (12 * density).toInt(),
                (8 * density).toInt(),
            )
        }

        // Header row: icon + title
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val title = TextView(this).apply {
            text = "CheckVar — Listening"
            setTextColor(Color.parseColor("#00BFA5")) // Teal accent matching app theme
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(null, Typeface.BOLD)
        }
        header.addView(title)
        container.addView(header)

        // Transcript text in a scrollable area
        scrollView = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (120 * density).toInt(), // Max height for transcript area
            )
        }

        transcriptTextView = TextView(this).apply {
            text = "Waiting for speech..."
            setTextColor(Color.parseColor("#B3FFFFFF")) // Light white
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, (4 * density).toInt(), 0, 0)
            maxLines = 8
        }
        scrollView!!.addView(transcriptTextView)
        container.addView(scrollView)

        // Layout params for the overlay window
        layoutParams = WindowManager.LayoutParams(
            (260 * density).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = (16 * density).toInt()
            y = (100 * density).toInt()
        }

        // Make draggable
        setupDragBehavior(container)

        overlayView = container
        try {
            windowManager?.addView(container, layoutParams)
        } catch (e: Exception) {
            // Overlay permission revoked or other WindowManager error — skip
            overlayView = null
            stopSelf()
        }
    }

    private fun setupDragBehavior(view: View) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams?.x ?: 0
                    initialY = layoutParams?.y ?: 0
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layoutParams?.x = initialX - (event.rawX - touchX).toInt()
                    layoutParams?.y = initialY + (event.rawY - touchY).toInt()
                    windowManager?.updateViewLayout(overlayView, layoutParams)
                    true
                }
                else -> false
            }
        }
    }

    private fun removeOverlayView() {
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
                // View may already be removed
            }
        }
        overlayView = null
        transcriptTextView = null
        scrollView = null
    }

    private fun setTranscriptText(text: String) {
        transcriptTextView?.post {
            transcriptTextView?.text = text
            // Auto-scroll to bottom
            scrollView?.post {
                scrollView?.fullScroll(View.FOCUS_DOWN)
            }
        }
    }
}
