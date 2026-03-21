package com.example.check_var

import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
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
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class AnalysisOverlayService : Service() {

    companion object {
        private var instance: AnalysisOverlayService? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun show(context: Context) {
            if (!Settings.canDrawOverlays(context)) return
            context.startService(Intent(context, AnalysisOverlayService::class.java))
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, AnalysisOverlayService::class.java))
        }

        fun updateStatus(statusText: String) {
            mainHandler.post { instance?.setStatus(statusText) }
        }

        fun showResult(verdict: String, confidence: String, summary: String) {
            mainHandler.post { instance?.setResult(verdict, confidence, summary) }
        }

        fun showError(message: String) {
            mainHandler.post { instance?.setError(message) }
        }
    }

    private var windowManager: WindowManager? = null

    // Card window (bottom sheet, OPAQUE)
    private var cardView: FrameLayout? = null
    private var cardWmParams: WindowManager.LayoutParams? = null

    // Scrim window (fullscreen dim, only shown on result)
    private var scrimView: View? = null

    private var statusText: TextView? = null
    private var dotViews: List<View>? = null
    private var loadingContainer: LinearLayout? = null
    private var scrollView: ScrollView? = null
    private var resultContainer: LinearLayout? = null
    private var verdictIcon: TextView? = null
    private var verdictLabel: TextView? = null
    private var confidenceText: TextView? = null
    private var summaryText: TextView? = null
    private var closeButton: TextView? = null
    private var dotAnimator: ValueAnimator? = null
    private var autoDismissRunnable: Runnable? = null
    private var safetyTimeoutRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createCardWindow()
        startDotAnimation()

        // Safety timeout: auto-dismiss after 60s if no result/error arrives
        safetyTimeoutRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(safetyTimeoutRunnable!!, 60_000)
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics
        ).toInt()
    }

    private fun screenHeight(): Int = resources.displayMetrics.heightPixels

    // ── Card window (pinned to bottom) ─────────────────────────────────

    private fun createCardWindow() {
        val wrapper = FrameLayout(this).apply {
            // Solid white background with rounded top corners
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadii = floatArrayOf(
                    dp(20).toFloat(), dp(20).toFloat(),   // top-left
                    dp(20).toFloat(), dp(20).toFloat(),   // top-right
                    0f, 0f, 0f, 0f                        // bottom corners
                )
            }
            // Ensure no hardware layer blending issues
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(16), dp(24), dp(24))
        }
        wrapper.addView(card, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Handle bar
        card.addView(View(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#CCCCCC"))
                cornerRadius = dp(2).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(12)
            }
        })

        // Loading container
        loadingContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(16), 0, dp(16))
        }

        // Logo
        loadingContainer!!.addView(TextView(this).apply {
            text = "✓"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2196F3"))
            }
            val s = dp(56)
            layoutParams = LinearLayout.LayoutParams(s, s).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        })

        // App name
        loadingContainer!!.addView(TextView(this).apply {
            text = "CheckVar"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTextColor(Color.parseColor("#1A1A1A"))
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(12); gravity = Gravity.CENTER_HORIZONTAL }
        })

        // Dots row
        val dotsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(20); gravity = Gravity.CENTER_HORIZONTAL }
        }
        val dots = mutableListOf<View>()
        for (i in 0 until 5) {
            val dot = View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(4).toFloat()
                    setColor(Color.parseColor("#2196F3"))
                }
                layoutParams = LinearLayout.LayoutParams(dp(6), dp(8)).apply {
                    marginStart = if (i > 0) dp(4) else 0
                }
            }
            dots.add(dot)
            dotsRow.addView(dot)
        }
        dotViews = dots
        loadingContainer!!.addView(dotsRow)

        // Status text
        statusText = TextView(this).apply {
            text = "Đang chuẩn bị..."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.parseColor("#666666"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(12); gravity = Gravity.CENTER_HORIZONTAL }
        }
        loadingContainer!!.addView(statusText)
        card.addView(loadingContainer)

        // ScrollView for result (hidden)
        scrollView = ScrollView(this).apply {
            visibility = View.GONE
            isFillViewport = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }

        resultContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(8), 0, dp(8))
        }

        verdictIcon = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
        }
        resultContainer!!.addView(verdictIcon)

        verdictLabel = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8); gravity = Gravity.CENTER_HORIZONTAL }
        }
        resultContainer!!.addView(verdictLabel)

        confidenceText = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4); gravity = Gravity.CENTER_HORIZONTAL }
        }
        resultContainer!!.addView(confidenceText)

        // Divider
        resultContainer!!.addView(View(this).apply {
            setBackgroundColor(Color.parseColor("#E0E0E0"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1)
            ).apply { topMargin = dp(16); bottomMargin = dp(16) }
        })

        summaryText = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.parseColor("#333333"))
            gravity = Gravity.START
            setLineSpacing(dp(4).toFloat(), 1f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        resultContainer!!.addView(summaryText)

        scrollView!!.addView(resultContainer)
        card.addView(scrollView)

        // Close button (hidden until result)
        closeButton = TextView(this).apply {
            text = "Đóng"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#2196F3"))
                cornerRadius = dp(12).toFloat()
            }
            setPadding(dp(24), dp(14), dp(24), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(12) }
            visibility = View.GONE
            setOnClickListener { stopSelf() }
        }
        card.addView(closeButton)

        // Window: fixed height at bottom 40%, TRANSLUCENT pixel format for ColorOS compat
        cardWmParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            (screenHeight() * 0.4).toInt(),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM
        }

        windowManager?.addView(wrapper, cardWmParams)
        cardView = wrapper

        // Slide in
        wrapper.translationY = dp(300).toFloat()
        wrapper.animate()
            .translationY(0f)
            .setDuration(400)
            .setInterpolator(DecelerateInterpolator())
            .start()
    }

    // ── Scrim window (added on result) ──────────────────────────────────

    private fun showScrim() {
        if (scrimView != null) return
        scrimView = View(this).apply {
            setBackgroundColor(Color.parseColor("#99000000"))
            alpha = 0f
        }
        val scrimParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        )
        windowManager?.addView(scrimView, scrimParams)
        scrimView?.animate()?.alpha(1f)?.setDuration(300)?.start()

        // Re-add card on top of scrim by updating its z-order
        cardView?.let {
            windowManager?.removeView(it)
            cardWmParams?.let { p ->
                // Switch to touchable for scrolling
                p.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                p.height = (screenHeight() * 0.7).toInt()
                windowManager?.addView(it, p)
            }
        }
    }

    // ── Dot animation ───────────────────────────────────────────────────

    private fun startDotAnimation() {
        dotAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1500
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animator ->
                val progress = animator.animatedValue as Float
                dotViews?.forEachIndexed { index, dot ->
                    val offset = index.toFloat() / 5f
                    val wave = Math.sin(((progress + offset) * 2 * Math.PI)).toFloat()
                    val absWave = Math.abs(wave)
                    val params = dot.layoutParams as LinearLayout.LayoutParams
                    params.height = dp(8 + (absWave * 16).toInt())
                    dot.layoutParams = params
                    dot.alpha = 0.3f + (absWave * 0.7f)
                }
            }
            start()
        }
    }

    // ── Status updates ──────────────────────────────────────────────────

    private fun setStatus(text: String) {
        statusText?.text = text
    }

    private fun setResult(verdict: String, confidence: String, summary: String) {
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        dotAnimator?.cancel()
        loadingContainer?.visibility = View.GONE
        scrollView?.visibility = View.VISIBLE
        resultContainer?.visibility = View.VISIBLE

        when (verdict) {
            "real" -> {
                verdictIcon?.text = "✅"
                verdictLabel?.text = "Tin thật"
                verdictLabel?.setTextColor(Color.parseColor("#4CAF50"))
                confidenceText?.setTextColor(Color.parseColor("#4CAF50"))
            }
            "fake" -> {
                verdictIcon?.text = "❌"
                verdictLabel?.text = "Tin giả"
                verdictLabel?.setTextColor(Color.parseColor("#F44336"))
                confidenceText?.setTextColor(Color.parseColor("#F44336"))
            }
            else -> {
                verdictIcon?.text = "❓"
                verdictLabel?.text = "Chưa xác định"
                verdictLabel?.setTextColor(Color.parseColor("#FF9800"))
                confidenceText?.setTextColor(Color.parseColor("#FF9800"))
            }
        }

        confidenceText?.text = confidence
        summaryText?.text = summary
        closeButton?.visibility = View.VISIBLE

        showScrim()

        autoDismissRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(autoDismissRunnable!!, 15000)
    }

    private fun setError(message: String) {
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        dotAnimator?.cancel()
        loadingContainer?.visibility = View.GONE
        scrollView?.visibility = View.VISIBLE
        resultContainer?.visibility = View.VISIBLE

        verdictIcon?.text = "⚠️"
        verdictLabel?.text = "Lỗi"
        verdictLabel?.setTextColor(Color.parseColor("#F44336"))
        confidenceText?.visibility = View.GONE
        summaryText?.text = message
        closeButton?.visibility = View.VISIBLE

        showScrim()

        autoDismissRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(autoDismissRunnable!!, 8000)
    }

    override fun onDestroy() {
        instance = null
        dotAnimator?.cancel()
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
        scrimView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        cardView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        scrimView = null
        cardView = null
        super.onDestroy()
    }
}
