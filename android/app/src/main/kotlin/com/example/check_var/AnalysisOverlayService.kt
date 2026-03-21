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
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class AnalysisOverlayService : Service() {

    companion object {
        private var instance: AnalysisOverlayService? = null
        private val mainHandler = Handler(Looper.getMainLooper())
        private var pendingInitialStatus: String? = null

        fun show(context: Context, initialStatus: String = "") {
            if (!Settings.canDrawOverlays(context)) return
            pendingInitialStatus = initialStatus.ifEmpty { null }
            context.startService(Intent(context, AnalysisOverlayService::class.java))
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, AnalysisOverlayService::class.java))
        }

        fun updateStatus(statusText: String) {
            mainHandler.post { instance?.setStatus(statusText) }
        }

        fun showResult(verdict: String, verdictLabel: String, confidence: String, summary: String, closeLabel: String) {
            mainHandler.post { instance?.setResult(verdict, verdictLabel, confidence, summary, closeLabel) }
        }

        fun showError(message: String, errorLabel: String = "Error", closeLabel: String = "Close") {
            mainHandler.post { instance?.setError(message, errorLabel, closeLabel) }
        }
    }

    private var windowManager: WindowManager? = null

    // Loading overlay (bottom-anchored: translucent header + white card)
    private var loadingOverlay: View? = null
    private var statusText: TextView? = null
    private var dotViews: List<View>? = null
    private var dotAnimator: ValueAnimator? = null

    // Result card (bottom sheet)
    private var cardView: FrameLayout? = null
    private var scrimView: View? = null
    private var verdictIcon: TextView? = null
    private var verdictLabel: TextView? = null
    private var confidenceText: TextView? = null
    private var summaryText: TextView? = null
    private var closeButton: TextView? = null

    private var autoDismissRunnable: Runnable? = null
    private var safetyTimeoutRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        // Use accessibility service's WindowManager when available — TYPE_ACCESSIBILITY_OVERLAY
        // bypasses ColorOS/OPPO forced transparency on TYPE_APPLICATION_OVERLAY
        val a11y = CheckVarAccessibilityService.instance
        windowManager = if (a11y != null) {
            a11y.getSystemService(WINDOW_SERVICE) as WindowManager
        } else {
            getSystemService(WINDOW_SERVICE) as WindowManager
        }
        createLoadingOverlay()
        startDotAnimation()

        safetyTimeoutRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(safetyTimeoutRunnable!!, 60_000)
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics
        ).toInt()
    }

    private fun screenHeight(): Int = resources.displayMetrics.heightPixels

    /** TYPE_ACCESSIBILITY_OVERLAY if a11y service is active, else TYPE_APPLICATION_OVERLAY */
    private fun overlayType(): Int {
        return if (CheckVarAccessibilityService.instance != null) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        }
    }

    // ── Loading overlay (translucent header + white card, bottom-anchored) ──

    private fun createLoadingOverlay() {
        // No slide animation — appears instantly to avoid ColorOS alpha blending
        // FrameLayout wrapper with hardware layer ensures opaque rendering on all ROMs
        val root = FrameLayout(this).apply {
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            // Opaque background — PixelFormat.OPAQUE requires every pixel filled
            setBackgroundColor(Color.parseColor("#F0F0F5"))
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.addView(content, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // ── Section 1: Header (icon + app name, fills top space) ──
        // Solid color #F0F0F5 instead of alpha transparency to avoid ROM bugs
        // Header has no rounded corners itself — the root FrameLayout handles that
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F0F0F5"))
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }

        // Logo (blue circle + checkmark)
        header.addView(TextView(this).apply {
            text = "✓"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
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
        header.addView(TextView(this).apply {
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

        // Header fills remaining space (weight=1)
        content.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))

        // ── Section 2: White card (handle + status + wave bars) ──
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.WHITE)
            setPadding(dp(24), dp(12), dp(24), dp(32))
        }

        // Handle bar
        card.addView(View(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#CCCCCC"))
                cornerRadius = dp(2).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(20)
            }
        })

        // Status text
        statusText = TextView(this).apply {
            text = pendingInitialStatus ?: ""
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.parseColor("#666666"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(16); gravity = Gravity.CENTER_HORIZONTAL }
        }
        card.addView(statusText)

        // Wave bars row
        val dotsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
        }
        val dots = mutableListOf<View>()
        for (i in 0 until 5) {
            val dot = View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(5).toFloat()
                    setColor(Color.parseColor("#2196F3"))
                }
                layoutParams = LinearLayout.LayoutParams(dp(10), dp(12)).apply {
                    marginStart = if (i > 0) dp(8) else 0
                }
            }
            dots.add(dot)
            dotsRow.addView(dot)
        }
        dotViews = dots
        card.addView(dotsRow)

        content.addView(card, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        // Window: bottom-anchored, 40% screen height
        // TYPE_ACCESSIBILITY_OVERLAY bypasses ColorOS forced transparency
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            (screenHeight() * 0.4).toInt(),
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.OPAQUE
        ).apply {
            gravity = Gravity.BOTTOM
        }
        windowManager?.addView(root, params)
        loadingOverlay = root
    }

    // ── Result card (bottom sheet, created on result) ────────────────────

    private fun createResultCard(verdict: String, verdictLabel: String, confidence: String, summary: String, closeLabel: String) {
        // Scrim (dim background)
        scrimView = View(this).apply {
            setBackgroundColor(Color.parseColor("#99000000"))
            alpha = 0f
        }
        val scrimParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        )
        windowManager?.addView(scrimView, scrimParams)
        scrimView?.animate()?.alpha(1f)?.setDuration(300)?.start()

        // Card wrapper with rounded top corners
        val wrapper = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadii = floatArrayOf(
                    dp(20).toFloat(), dp(20).toFloat(),
                    dp(20).toFloat(), dp(20).toFloat(),
                    0f, 0f, 0f, 0f
                )
            }
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

        // ScrollView for result
        val scrollView = ScrollView(this).apply {
            isFillViewport = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }

        val resultContainer = LinearLayout(this).apply {
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
        resultContainer.addView(verdictIcon)

        this.verdictLabel = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8); gravity = Gravity.CENTER_HORIZONTAL }
        }
        resultContainer.addView(this.verdictLabel)

        confidenceText = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4); gravity = Gravity.CENTER_HORIZONTAL }
        }
        resultContainer.addView(confidenceText)

        // Divider
        resultContainer.addView(View(this).apply {
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
        resultContainer.addView(summaryText)

        scrollView.addView(resultContainer)
        card.addView(scrollView)

        // Close button
        closeButton = TextView(this).apply {
            text = closeLabel
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
            setOnClickListener { stopSelf() }
        }
        card.addView(closeButton)

        // Set verdict data — labels come localized from Flutter
        when (verdict) {
            "real" -> {
                verdictIcon?.text = "✅"
                this.verdictLabel?.setTextColor(Color.parseColor("#4CAF50"))
                confidenceText?.setTextColor(Color.parseColor("#4CAF50"))
            }
            "fake" -> {
                verdictIcon?.text = "❌"
                this.verdictLabel?.setTextColor(Color.parseColor("#F44336"))
                confidenceText?.setTextColor(Color.parseColor("#F44336"))
            }
            "error" -> {
                verdictIcon?.text = "⚠️"
                this.verdictLabel?.setTextColor(Color.parseColor("#F44336"))
                confidenceText?.visibility = View.GONE
            }
            else -> {
                verdictIcon?.text = "❓"
                this.verdictLabel?.setTextColor(Color.parseColor("#FF9800"))
                confidenceText?.setTextColor(Color.parseColor("#FF9800"))
            }
        }
        this.verdictLabel?.text = verdictLabel
        confidenceText?.text = confidence
        summaryText?.text = summary

        // Add card window at bottom, 70% height, touchable for scrolling
        val cardParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            (screenHeight() * 0.7).toInt(),
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM
        }
        windowManager?.addView(wrapper, cardParams)
        cardView = wrapper
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
                    params.height = dp(12 + (absWave * 20).toInt())
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

    private fun setResult(verdict: String, verdictLabel: String, confidence: String, summary: String, closeLabel: String) {
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        dotAnimator?.cancel()

        loadingOverlay?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        loadingOverlay = null

        createResultCard(verdict, verdictLabel, confidence, summary, closeLabel)

        autoDismissRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(autoDismissRunnable!!, 15000)
    }

    private fun setError(message: String, errorLabel: String = "Error", closeLabel: String = "Close") {
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        dotAnimator?.cancel()

        loadingOverlay?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        loadingOverlay = null

        createResultCard("error", errorLabel, "", message, closeLabel)

        autoDismissRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(autoDismissRunnable!!, 8000)
    }

    override fun onDestroy() {
        instance = null
        dotAnimator?.cancel()
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
        loadingOverlay?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        scrimView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        cardView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        loadingOverlay = null
        scrimView = null
        cardView = null
        super.onDestroy()
    }
}
