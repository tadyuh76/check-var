package com.example.check_var

import android.animation.ValueAnimator
import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Redesigned overlay bubble for scam call detection.
 *
 * Visual design matches the news-detection UI aesthetic:
 *   - Collapsed: gradient circle (purple→beige idle, blue→green listening)
 *     with pulsing outer ring and status caption
 *   - Expanded: frosted-glass pill card showing threat verdict, confidence %,
 *     and color-coded progress bar
 *
 * The bubble is draggable.  Tap collapsed → open app.  Tap expanded → dismiss.
 * Auto-collapses after a timeout (except scam, which stays until dismissed).
 */
class OverlayBubbleService : Service() {

    companion object {
        private var instance: OverlayBubbleService? = null

        fun updateStatus(sessionStatus: String, threatLevel: String, confidence: Int = -1) {
            instance?.applyStatus(sessionStatus, threatLevel, confidence)
        }
    }

    // ── State ────────────────────────────────────────────────────────────────

    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private var sessionStatus = "idle"
    private var threatLevel = "safe"
    private var confidence = -1
    private var isExpanded = false

    /** Tracks which threat level was last expanded for.
     *  Prevents re-expanding on every status update for the same threat. */
    private var expandedForThreat: String? = null

    private val handler = Handler(Looper.getMainLooper())
    private var pulseAnimator: ValueAnimator? = null
    private var collapseRunnable: Runnable? = null

    // ── Collapsed views ──────────────────────────────────────────────────────

    private var collapsedContainer: FrameLayout? = null
    private var pulseRing: View? = null
    private var bubbleCircle: FrameLayout? = null
    private var bubbleLabel: TextView? = null
    private var statusCaption: TextView? = null

    // ── Expanded views ───────────────────────────────────────────────────────

    private var expandedContainer: FrameLayout? = null
    private var expandedCard: LinearLayout? = null
    private var expandedIconBg: FrameLayout? = null
    private var expandedIconLabel: TextView? = null
    private var expandedTitle: TextView? = null
    private var expandedSubtitle: TextView? = null
    private var expandedPercent: TextView? = null
    private var progressFill: View? = null

    // ── Dimensions ───────────────────────────────────────────────────────────

    private val density by lazy { resources.displayMetrics.density }
    private fun dp(v: Int) = (v * density).toInt()
    private fun dpf(v: Float) = v * density

    // ── Design tokens ────────────────────────────────────────────────────────

    // Sizes (dp)
    private val BUBBLE_DP = 64
    private val EXPANDED_W = 252
    private val EXPANDED_H = 92
    private val ICON_DP = 38
    private val CORNER_RADIUS = 28f

    // Gradients matching home screen feature card backgrounds
    private val IDLE_COLORS = intArrayOf(0xFFE8D5F5.toInt(), 0xFFF5E6D0.toInt())
    private val LISTEN_COLORS = intArrayOf(0xFFD5E8F5.toInt(), 0xFFE8F5D5.toInt())

    // Threat palette
    private val C_SAFE = 0xFF4CAF50.toInt()
    private val C_SUSPICIOUS = 0xFFFF9800.toInt()
    private val C_SCAM = 0xFFF44336.toInt()
    private val C_ANALYZING = 0xFF6D5584.toInt()
    private val C_ERROR = 0xFF6A1B9A.toInt()
    private val C_RECONNECTING = 0xFF78909C.toInt()

    // Surface / text
    private val C_GLASS = 0xF5FFFFFF.toInt()
    private val C_TEXT_DIM = 0xFF5E5F5D.toInt()

    // Auto-collapse delays
    private val WARN_COLLAPSE_MS = 8000L

    // ═════════════════════════════════════════════════════════════════════════
    //  Lifecycle
    // ═════════════════════════════════════════════════════════════════════════

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (!Settings.canDrawOverlays(this)) { stopSelf(); return }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        buildOverlay()
    }

    override fun onDestroy() {
        pulseAnimator?.cancel()
        collapseRunnable?.let { handler.removeCallbacks(it) }
        rootView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        rootView = null
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ═════════════════════════════════════════════════════════════════════════
    //  View construction
    // ═════════════════════════════════════════════════════════════════════════

    private fun buildOverlay() {
        rootView = FrameLayout(this)

        collapsedContainer = buildCollapsed()
        expandedContainer = buildExpanded().also { it.visibility = View.GONE }

        rootView!!.addView(collapsedContainer)
        rootView!!.addView(expandedContainer)

        layoutParams = WindowManager.LayoutParams(
            dp(BUBBLE_DP + 16),
            dp(BUBBLE_DP + 30),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dp(16)
            y = dp(120)
        }

        setupTouch(rootView!!)
        applyStatus(sessionStatus, threatLevel, confidence)

        try {
            windowManager?.addView(rootView, layoutParams)
        } catch (_: Exception) {
            rootView = null
            stopSelf()
        }
    }

    // ── Collapsed bubble ─────────────────────────────────────────────────────

    private fun buildCollapsed(): FrameLayout {
        val w = dp(BUBBLE_DP + 16)
        val h = dp(BUBBLE_DP + 30)
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(w, h)
        }

        // Pulse ring (behind the circle)
        val ringSize = dp(BUBBLE_DP + 12)
        pulseRing = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(ringSize, ringSize).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(2)
            }
            alpha = 0f
        }
        container.addView(pulseRing)

        // Main circle
        val bSize = dp(BUBBLE_DP)
        bubbleCircle = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(bSize, bSize).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(8)
            }
            elevation = dpf(8f)
        }
        bubbleLabel = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setTypeface(null, Typeface.BOLD)
            setShadowLayer(dpf(2f), 0f, dpf(1f), 0x40000000)
        }
        bubbleCircle!!.addView(bubbleLabel)
        container.addView(bubbleCircle)

        // Status caption below bubble
        statusCaption = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            }
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
            setTextColor(Color.WHITE)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.05f
            visibility = View.GONE
            background = GradientDrawable().apply {
                setColor(0xAA000000.toInt())
                cornerRadius = dpf(10f)
            }
            setPadding(dp(8), dp(2), dp(8), dp(3))
        }
        container.addView(statusCaption)

        return container
    }

    // ── Expanded pill card ───────────────────────────────────────────────────

    private fun buildExpanded(): FrameLayout {
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(EXPANDED_W), dp(EXPANDED_H))
        }

        expandedCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            elevation = dpf(12f)
            setPadding(dp(14), dp(12), dp(14), dp(8))
        }

        // ── Content row: [icon] [title/subtitle] [percent] ──
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f,
            )
        }

        // Icon circle
        val iconSize = dp(ICON_DP)
        expandedIconBg = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize).apply {
                marginEnd = dp(12)
            }
        }
        expandedIconLabel = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTypeface(null, Typeface.BOLD)
        }
        expandedIconBg!!.addView(expandedIconLabel)
        row.addView(expandedIconBg)

        // Text column
        val textCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            ).apply {
                marginEnd = dp(8)
            }
            gravity = Gravity.CENTER_VERTICAL
        }
        expandedTitle = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(null, Typeface.BOLD)
        }
        expandedSubtitle = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(1) }
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(C_TEXT_DIM)
        }
        textCol.addView(expandedTitle)
        textCol.addView(expandedSubtitle)
        row.addView(textCol)

        // Percentage
        expandedPercent = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        row.addView(expandedPercent)
        expandedCard!!.addView(row)

        // ── Progress bar ──
        val progressContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(4),
            ).apply { topMargin = dp(6) }
        }
        val progressTrack = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            background = GradientDrawable().apply {
                setColor(0x1A000000)
                cornerRadius = dpf(3f)
            }
        }
        progressFill = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(0, FrameLayout.LayoutParams.MATCH_PARENT)
            background = GradientDrawable().apply { cornerRadius = dpf(3f) }
        }
        progressContainer.addView(progressTrack)
        progressContainer.addView(progressFill)
        expandedCard!!.addView(progressContainer)

        container.addView(expandedCard)
        return container
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Status management
    // ═════════════════════════════════════════════════════════════════════════

    private fun applyStatus(newStatus: String, newThreat: String, newConfidence: Int) {
        this.sessionStatus = newStatus
        this.threatLevel = newThreat
        if (newConfidence >= 0) this.confidence = newConfidence

        // Reset expansion tracking when threat drops back to safe.
        if (newThreat == "safe") expandedForThreat = null

        rootView?.post {
            val isThreat = newThreat in listOf("suspicious", "scam")
            val shouldExpand = isThreat && newThreat != expandedForThreat

            if (shouldExpand) {
                expandedForThreat = newThreat
                expand()
                styleExpanded()
                scheduleAutoCollapse()
            } else if (isExpanded) {
                // Already showing the card — just update its content.
                styleExpanded()
            } else {
                styleCollapsed()
            }
        }
    }

    // ── Collapsed styling ────────────────────────────────────────────────────

    private fun styleCollapsed() {
        val circle = bubbleCircle ?: return

        when {
            threatLevel == "scam" -> {
                circle.background = ovalFill(C_SCAM)
                bubbleLabel?.text = "!!"
                showCaption("LỪA ĐẢO")
                startPulse(C_SCAM)
            }
            threatLevel == "suspicious" -> {
                circle.background = ovalFill(C_SUSPICIOUS)
                bubbleLabel?.text = "!?"
                showCaption("Đáng ngờ")
                startPulse(C_SUSPICIOUS)
            }
            sessionStatus == "error" -> {
                circle.background = ovalFill(C_ERROR)
                bubbleLabel?.text = "✕"
                showCaption("Lỗi")
                stopPulse()
            }
            sessionStatus == "reconnecting" -> {
                circle.background = ovalFill(C_RECONNECTING)
                bubbleLabel?.text = "···"
                hideCaption()
                stopPulse()
            }
            sessionStatus == "analyzing" -> {
                circle.background = ovalFill(C_ANALYZING)
                bubbleLabel?.text = "···"
                hideCaption()
                startPulse(C_ANALYZING)
            }
            sessionStatus == "listening" -> {
                circle.background = ovalGradient(LISTEN_COLORS)
                bubbleLabel?.text = "🎧"
                showCaption("Đang nghe")
                startPulse(0xFF00897B.toInt())
            }
            else -> { // idle / connecting
                circle.background = ovalGradient(IDLE_COLORS)
                bubbleLabel?.text = "🛡"
                hideCaption()
                stopPulse()
            }
        }
    }

    private fun showCaption(text: String) {
        statusCaption?.apply { this.text = text; visibility = View.VISIBLE }
    }

    private fun hideCaption() {
        statusCaption?.visibility = View.GONE
    }

    // ── Expanded styling ─────────────────────────────────────────────────────

    private fun styleExpanded() {
        val color = when (threatLevel) {
            "scam" -> C_SCAM
            "suspicious" -> C_SUSPICIOUS
            else -> C_SAFE
        }

        // Card background — frosted glass with threat color tint
        val tintRatio = if (threatLevel == "scam") 0.12f else 0.08f
        val borderAlpha = if (threatLevel == "scam") 0x4D else 0x40
        expandedCard?.background = GradientDrawable().apply {
            setColor(blendColor(C_GLASS, color, tintRatio))
            cornerRadius = dpf(CORNER_RADIUS)
            setStroke(
                dp(1),
                Color.argb(borderAlpha, Color.red(color), Color.green(color), Color.blue(color)),
            )
        }

        // Icon circle background
        expandedIconBg?.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.argb(0x26, Color.red(color), Color.green(color), Color.blue(color)))
        }

        when (threatLevel) {
            "scam" -> {
                expandedIconLabel?.apply { text = "✕"; setTextColor(color) }
                expandedTitle?.apply {
                    text = "LỪA ĐẢO!"
                    setTextColor(color)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                }
                expandedSubtitle?.text = "Hãy cúp máy ngay"
            }
            "suspicious" -> {
                expandedIconLabel?.apply { text = "⚠"; setTextColor(color) }
                expandedTitle?.apply {
                    text = "Đáng ngờ"
                    setTextColor(color)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                }
                expandedSubtitle?.text = "Có dấu hiệu lừa đảo"
            }
            else -> {
                expandedIconLabel?.apply { text = "✓"; setTextColor(color) }
                expandedTitle?.apply {
                    text = "An toàn"
                    setTextColor(color)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                }
                expandedSubtitle?.text = "Cuộc gọi bình thường"
            }
        }

        // Confidence %
        val pct = if (confidence >= 0) confidence else 0
        expandedPercent?.apply {
            text = "${pct}%"
            setTextColor(color)
        }

        // Progress bar fill
        (progressFill?.background as? GradientDrawable)?.setColor(color)
        val totalWidth = dp(EXPANDED_W - 28) // account for padding
        val fillW = ((pct / 100f) * totalWidth).toInt().coerceAtLeast(0)
        progressFill?.layoutParams = FrameLayout.LayoutParams(
            fillW, FrameLayout.LayoutParams.MATCH_PARENT,
        )
        progressFill?.requestLayout()
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Expand / Collapse
    // ═════════════════════════════════════════════════════════════════════════

    private fun expand() {
        if (isExpanded) return
        isExpanded = true
        stopPulse()

        collapsedContainer?.visibility = View.GONE
        expandedContainer?.visibility = View.VISIBLE

        layoutParams?.width = dp(EXPANDED_W)
        layoutParams?.height = dp(EXPANDED_H)
        try { windowManager?.updateViewLayout(rootView, layoutParams) } catch (_: Exception) {}

        // Animate: scale in from the right edge (where the bubble was)
        expandedContainer?.apply {
            pivotX = dp(EXPANDED_W).toFloat()
            pivotY = dp(EXPANDED_H).toFloat() / 2f
            scaleX = 0.3f; scaleY = 0.3f; alpha = 0f
            animate()
                .scaleX(1f).scaleY(1f).alpha(1f)
                .setDuration(300)
                .setInterpolator(DecelerateInterpolator(1.5f))
                .start()
        }
    }

    private fun collapse() {
        if (!isExpanded) return
        isExpanded = false

        expandedContainer?.animate()
            ?.scaleX(0.3f)?.scaleY(0.3f)?.alpha(0f)
            ?.setDuration(200)
            ?.setInterpolator(AccelerateInterpolator())
            ?.withEndAction {
                expandedContainer?.visibility = View.GONE
                collapsedContainer?.visibility = View.VISIBLE
                layoutParams?.width = dp(BUBBLE_DP + 16)
                layoutParams?.height = dp(BUBBLE_DP + 30)
                try { windowManager?.updateViewLayout(rootView, layoutParams) } catch (_: Exception) {}
                styleCollapsed()
            }
            ?.start()
    }

    private fun scheduleAutoCollapse() {
        collapseRunnable?.let { handler.removeCallbacks(it) }
        if (threatLevel == "scam") return // scam stays until manually dismissed
        collapseRunnable = Runnable { collapse() }
        handler.postDelayed(collapseRunnable!!, WARN_COLLAPSE_MS)
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Pulse animation
    // ═════════════════════════════════════════════════════════════════════════

    private fun startPulse(color: Int) {
        pulseAnimator?.cancel()
        val ring = pulseRing ?: return
        ring.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.TRANSPARENT)
            setStroke(
                dp(2),
                Color.argb(0x40, Color.red(color), Color.green(color), Color.blue(color)),
            )
        }
        pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1500
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                val v = it.animatedValue as Float
                ring.alpha = 1f - v
                ring.scaleX = 1f + v * 0.35f
                ring.scaleY = 1f + v * 0.35f
            }
            start()
        }
    }

    private fun stopPulse() {
        pulseAnimator?.cancel()
        pulseRing?.apply { alpha = 0f; scaleX = 1f; scaleY = 1f }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Touch handling (drag + tap)
    // ═════════════════════════════════════════════════════════════════════════

    private fun setupTouch(view: View) {
        var initX = 0; var initY = 0
        var tX = 0f; var tY = 0f
        var moved = false
        val threshold = 6 * density

        view.setOnTouchListener { _, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    initX = layoutParams?.x ?: 0
                    initY = layoutParams?.y ?: 0
                    tX = ev.rawX; tY = ev.rawY
                    moved = false; true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!moved) {
                        moved = kotlin.math.abs(ev.rawX - tX) > threshold ||
                                kotlin.math.abs(ev.rawY - tY) > threshold
                    }
                    if (moved) {
                        layoutParams?.x = initX - (ev.rawX - tX).toInt()
                        layoutParams?.y = initY + (ev.rawY - tY).toInt()
                        windowManager?.updateViewLayout(rootView, layoutParams)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        if (isExpanded) collapse() else launchApp()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun launchApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra(MainActivity.EXTRA_APP_ACTION, MainActivity.ACTION_OPEN_CALL_DEBUG)
        startActivity(intent)
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Drawable helpers
    // ═════════════════════════════════════════════════════════════════════════

    private fun ovalFill(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(dp(1), Color.argb(0x40, 255, 255, 255))
        }
    }

    private fun ovalGradient(colors: IntArray): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            this.colors = colors
            orientation = GradientDrawable.Orientation.TL_BR
            setStroke(dp(1), Color.argb(0x40, 255, 255, 255))
        }
    }

    private fun blendColor(base: Int, tint: Int, ratio: Float): Int {
        val r = ((1 - ratio) * Color.red(base) + ratio * Color.red(tint)).toInt()
        val g = ((1 - ratio) * Color.green(base) + ratio * Color.green(tint)).toInt()
        val b = ((1 - ratio) * Color.blue(base) + ratio * Color.blue(tint)).toInt()
        return Color.argb(
            Color.alpha(base),
            r.coerceIn(0, 255),
            g.coerceIn(0, 255),
            b.coerceIn(0, 255),
        )
    }
}
