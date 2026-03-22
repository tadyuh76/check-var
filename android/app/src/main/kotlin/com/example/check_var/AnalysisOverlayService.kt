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
import android.view.MotionEvent
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

        fun showResult(verdict: String, verdictLabel: String, confidence: String, summary: String, detailLabel: String, disclaimerLabel: String) {
            mainHandler.post { instance?.setResult(verdict, verdictLabel, confidence, summary, detailLabel, disclaimerLabel) }
        }

        fun showError(message: String, errorLabel: String = "Error", closeLabel: String = "Close") {
            mainHandler.post { instance?.setError(message, errorLabel, closeLabel) }
        }
    }

    private var windowManager: WindowManager? = null

    // Loading
    private var loadingOverlay: View? = null
    private var statusText: TextView? = null
    private var dotViews: List<View>? = null
    private var dotAnimator: ValueAnimator? = null

    // Result
    private var resultOverlay: View? = null

    private var autoDismissRunnable: Runnable? = null
    private var safetyTimeoutRunnable: Runnable? = null
    private var isDismissing = false
    private var screenReceiver: android.content.BroadcastReceiver? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()

        // Don't show overlay on lock screen
        val km = getSystemService(KEYGUARD_SERVICE) as android.app.KeyguardManager
        if (km.isKeyguardLocked) {
            stopSelf()
            return
        }

        instance = this
        val a11y = CheckVarAccessibilityService.instance
        windowManager = if (a11y != null) {
            a11y.getSystemService(WINDOW_SERVICE) as WindowManager
        } else {
            getSystemService(WINDOW_SERVICE) as WindowManager
        }
        showLoading()

        safetyTimeoutRunnable = Runnable { stopSelf() }
        mainHandler.postDelayed(safetyTimeoutRunnable!!, 60_000)

        // Dismiss when screen locks
        screenReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_SCREEN_OFF) stopSelf()
            }
        }
        registerReceiver(screenReceiver, android.content.IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    private fun screenHeight(): Int = resources.displayMetrics.heightPixels

    private fun isDarkMode(): Boolean {
        val uiMode = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
        return uiMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
    }

    private fun overlayType(): Int =
        if (CheckVarAccessibilityService.instance != null)
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        else
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY

    // ── Loading ──────────────────────────────────────────────────────────

    private fun showLoading() {
        val dark = isDarkMode()
        val cardBg = if (dark) Color.parseColor("#1A1A1A") else Color.WHITE
        val titleColor = if (dark) Color.parseColor("#EEEEEE") else Color.parseColor("#111111")
        val subtitleColor = if (dark) Color.parseColor("#888888") else Color.parseColor("#999999")

        val root = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
            setPadding(0, dp(24), 0, 0)
        }

        // Floating card
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = GradientDrawable().apply {
                setColor(cardBg)
                cornerRadius = dp(28).toFloat()
            }
            elevation = dp(8).toFloat()
            setPadding(dp(28), dp(28), dp(28), dp(32))
        }
        root.addView(card, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(dp(16), 0, dp(16), dp(16))
            gravity = Gravity.BOTTOM
        })

        // Blue circle logo
        card.addView(TextView(this).apply {
            text = "✓"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2196F3"))
            }
            val s = dp(44)
            layoutParams = LinearLayout.LayoutParams(s, s).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        })

        // App name
        card.addView(TextView(this).apply {
            text = "CheckVar"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(titleColor)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(10); gravity = Gravity.CENTER_HORIZONTAL }
        })

        // Status text
        statusText = TextView(this).apply {
            text = pendingInitialStatus ?: ""
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(subtitleColor)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(20); gravity = Gravity.CENTER_HORIZONTAL }
        }
        card.addView(statusText)

        // Wave bars
        val barsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)
            ).apply { topMargin = dp(14); gravity = Gravity.CENTER_HORIZONTAL }
        }
        val bars = mutableListOf<View>()
        for (i in 0 until 5) {
            val bar = View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(3).toFloat()
                    setColor(Color.parseColor("#2196F3"))
                }
                layoutParams = LinearLayout.LayoutParams(dp(6), dp(12)).apply {
                    marginStart = if (i > 0) dp(5) else 0
                    gravity = Gravity.CENTER_VERTICAL
                }
            }
            bars.add(bar)
            barsRow.addView(bar)
        }
        dotViews = bars
        card.addView(barsRow)

        // Window
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.BOTTOM }

        windowManager?.addView(root, params)
        loadingOverlay = root

        // Slide up
        root.translationY = dp(400).toFloat()
        root.animate()
            .translationY(0f)
            .setDuration(500)
            .setInterpolator(DecelerateInterpolator(2.5f))
            .start()

        startDotAnimation()
    }

    // ── Dot animation ────────────────────────────────────────────────────

    private fun startDotAnimation() {
        dotAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1200
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animator ->
                val progress = animator.animatedValue as Float
                dotViews?.forEachIndexed { index, dot ->
                    val offset = index.toFloat() / 5f
                    val wave = Math.sin(((progress + offset) * 2 * Math.PI)).toFloat()
                    val absWave = Math.abs(wave)
                    val p = dot.layoutParams as LinearLayout.LayoutParams
                    p.height = dp(8 + (absWave * 24).toInt())
                    dot.layoutParams = p
                    dot.alpha = 0.3f + (absWave * 0.7f)
                }
            }
            start()
        }
    }

    // ── Status ────────────────────────────────────────────────────────────

    private fun setStatus(text: String) {
        statusText?.text = text
    }

    // ── Result / Error ────────────────────────────────────────────────────

    private fun setResult(verdict: String, vLabel: String, confidence: String, summary: String, detailLabel: String, disclaimerLabel: String) {
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        dotAnimator?.cancel()

        loadingOverlay?.animate()
            ?.translationY(dp(400).toFloat())
            ?.alpha(0f)
            ?.setDuration(300)
            ?.setInterpolator(DecelerateInterpolator())
            ?.withEndAction {
                loadingOverlay?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
                loadingOverlay = null
            }
            ?.start()

        mainHandler.postDelayed({
            showResultCard(verdict, vLabel, confidence, summary, detailLabel, disclaimerLabel)
        }, 200)

        autoDismissRunnable = Runnable { dismissWithAnimation() }
        mainHandler.postDelayed(autoDismissRunnable!!, 15_000)
    }

    private fun setError(message: String, errorLabel: String, closeLabel: String) {
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        dotAnimator?.cancel()

        loadingOverlay?.animate()
            ?.translationY(dp(400).toFloat())
            ?.alpha(0f)
            ?.setDuration(300)
            ?.setInterpolator(DecelerateInterpolator())
            ?.withEndAction {
                loadingOverlay?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
                loadingOverlay = null
            }
            ?.start()

        mainHandler.postDelayed({
            showResultCard("error", errorLabel, "", message, closeLabel, "")
        }, 200)

        autoDismissRunnable = Runnable { dismissWithAnimation() }
        mainHandler.postDelayed(autoDismissRunnable!!, 8_000)
    }

    // ── Result card ──────────────────────────────────────────────────────

    private fun showResultCard(verdict: String, vLabel: String, confidence: String, summary: String, detailLabel: String, disclaimerLabel: String) {
        val dark = isDarkMode()
        val cardBg = if (dark) Color.parseColor("#1A1A1A") else Color.WHITE
        val handleColor = if (dark) Color.parseColor("#444444") else Color.parseColor("#DDDDDD")
        val closeBtnColor = if (dark) Color.parseColor("#AAAAAA") else Color.parseColor("#999999")
        val dividerColor = if (dark) Color.parseColor("#333333") else Color.parseColor("#F0F0F0")
        val summaryColor = if (dark) Color.parseColor("#CCCCCC") else Color.parseColor("#444444")

        // Single full-screen window: scrim background + card at bottom.
        // Using one window ensures touch events are reliably delivered.
        val root = FrameLayout(this).apply {
            // Tap on scrim (outside card) dismisses
            setOnClickListener { dismissWithAnimation() }
        }

        // Card container at the bottom — 65% height
        val cardContainer = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
            setPadding(0, dp(24), 0, 0)
            // Prevent clicks on the card from propagating to the scrim
            isClickable = true
        }
        root.addView(cardContainer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            (screenHeight() * 0.65).toInt()
        ).apply { gravity = Gravity.BOTTOM })

        val wrapper = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(cardBg)
                cornerRadius = dp(28).toFloat()
            }
            elevation = dp(16).toFloat()
        }
        cardContainer.addView(wrapper, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ).apply {
            setMargins(dp(12), 0, dp(12), dp(12))
        })

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(10), dp(24), dp(24))
        }
        wrapper.addView(card, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // ── Top bar: handle (draggable) + X button ──
        val topBar = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(12) }
        }

        // Handle bar (centered)
        val handle = View(this).apply {
            background = GradientDrawable().apply {
                setColor(handleColor)
                cornerRadius = dp(3).toFloat()
            }
            layoutParams = FrameLayout.LayoutParams(dp(36), dp(5)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(8)
            }
        }
        topBar.addView(handle)

        // X close button (top-right)
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTextColor(closeBtnColor)
            gravity = Gravity.CENTER
            val s = dp(32)
            layoutParams = FrameLayout.LayoutParams(s, s).apply {
                gravity = Gravity.END or Gravity.TOP
            }
            setOnClickListener { dismissWithAnimation() }
        }
        topBar.addView(closeBtn)

        // Drag-to-dismiss on handle only (not topBar, so X button stays tappable)
        var startY = 0f
        var startTransY = 0f
        val dismissThreshold = (screenHeight() * 0.1f)
        handle.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startY = event.rawY
                    startTransY = cardContainer.translationY
                    autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = event.rawY - startY
                    if (dy > 0) cardContainer.translationY = startTransY + dy
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (cardContainer.translationY > dismissThreshold) {
                        dismissWithAnimation()
                    } else {
                        cardContainer.animate().translationY(0f).setDuration(200).start()
                        // Restore auto-dismiss
                        autoDismissRunnable = Runnable { dismissWithAnimation() }
                        mainHandler.postDelayed(autoDismissRunnable!!, 15_000)
                    }
                    true
                }
                else -> false
            }
        }
        card.addView(topBar)

        // Verdict emoji
        val icon = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 44f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
        }
        card.addView(icon)

        // Verdict label
        val label = TextView(this).apply {
            text = vLabel
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8); gravity = Gravity.CENTER_HORIZONTAL }
        }
        card.addView(label)

        // Confidence
        val conf = TextView(this).apply {
            text = confidence
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4); gravity = Gravity.CENTER_HORIZONTAL }
        }
        card.addView(conf)

        // Color by verdict
        when (verdict) {
            "real" -> {
                icon.text = "✅"
                label.setTextColor(Color.parseColor("#4CAF50"))
                conf.setTextColor(Color.parseColor("#4CAF50"))
            }
            "fake" -> {
                icon.text = "❌"
                label.setTextColor(Color.parseColor("#F44336"))
                conf.setTextColor(Color.parseColor("#F44336"))
            }
            "error" -> {
                icon.text = "⚠️"
                label.setTextColor(Color.parseColor("#F44336"))
                conf.visibility = View.GONE
            }
            else -> {
                icon.text = "❓"
                label.setTextColor(Color.parseColor("#FF9800"))
                conf.setTextColor(Color.parseColor("#FF9800"))
            }
        }

        // Divider
        card.addView(View(this).apply {
            setBackgroundColor(dividerColor)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1)
            ).apply { topMargin = dp(20); bottomMargin = dp(16) }
        })

        // Scrollable summary
        val scrollView = ScrollView(this).apply {
            isFillViewport = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }
        scrollView.addView(TextView(this).apply {
            text = summary
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(summaryColor)
            setLineSpacing(dp(4).toFloat(), 1f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        })
        card.addView(scrollView)

        // AI disclaimer
        card.addView(TextView(this).apply {
            text = disclaimerLabel
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(Color.parseColor("#9E9E9E"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8); gravity = Gravity.CENTER_HORIZONTAL }
        })

        // "View details" button — opens app
        if (verdict != "error") {
            card.addView(TextView(this).apply {
                text = detailLabel
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#2196F3"))
                    cornerRadius = dp(14).toFloat()
                }
                setPadding(dp(24), dp(14), dp(24), dp(14))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(16) }
                setOnClickListener {
                    // Send event to Flutter to open detail screen
                    ServiceBridge.instance.sendEvent(mapOf("type" to "open_detail"))
                    // Open the app
                    packageManager.getLaunchIntentForPackage(packageName)?.let { i ->
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        startActivity(i)
                    }
                    dismissWithAnimation()
                }
            })
        }

        // Full-screen window containing scrim + card
        windowManager?.addView(root, WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ))

        resultOverlay = root

        // Animate scrim fade in + card slide up
        cardContainer.translationY = (screenHeight() * 0.65f)

        // Scrim fade
        val scrimDrawable = android.graphics.drawable.ColorDrawable(Color.parseColor("#55000000"))
        scrimDrawable.alpha = 0
        root.background = scrimDrawable
        ValueAnimator.ofInt(0, 255).apply {
            duration = 350
            addUpdateListener { scrimDrawable.alpha = it.animatedValue as Int }
            start()
        }

        // Card slide up
        cardContainer.animate()
            .translationY(0f)
            .setDuration(500)
            .setInterpolator(DecelerateInterpolator(2f))
            .start()
    }

    // ── Dismiss with animation ───────────────────────────────────────────

    private fun dismissWithAnimation() {
        if (isDismissing) return
        isDismissing = true
        autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }

        // Safety: always stop the service even if animation fails
        mainHandler.postDelayed({ stopSelf() }, 600)

        // Fade out scrim
        resultOverlay?.let { overlay ->
            (overlay.background as? android.graphics.drawable.ColorDrawable)?.let { bg ->
                ValueAnimator.ofInt(bg.alpha, 0).apply {
                    duration = 300
                    addUpdateListener { bg.alpha = it.animatedValue as Int }
                    start()
                }
            }
            // Slide card down
            val cardView = (overlay as? FrameLayout)?.getChildAt(0)
            cardView?.animate()
                ?.translationY(dp(600).toFloat())
                ?.setDuration(400)
                ?.setInterpolator(DecelerateInterpolator())
                ?.withEndAction { stopSelf() }
                ?.start()
                ?: stopSelf()
        } ?: stopSelf()
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────

    override fun onDestroy() {
        instance = null
        dotAnimator?.cancel()
        screenReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        safetyTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
        loadingOverlay?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        resultOverlay?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        loadingOverlay = null
        resultOverlay = null
        super.onDestroy()
    }
}
