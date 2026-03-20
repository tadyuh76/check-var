package com.example.check_var

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator

class GlowOverlayService : Service() {

    companion object {
        fun show(context: Context) {
            if (!Settings.canDrawOverlays(context)) return
            context.startService(Intent(context, GlowOverlayService::class.java))
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, GlowOverlayService::class.java))
        }

        fun playSound(context: Context) {
            try {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                am.playSoundEffect(AudioManager.FX_KEY_CLICK, 1.0f)
            } catch (_: Exception) {}
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: GlowOverlayView? = null
    private val animators = mutableListOf<ValueAnimator>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        overlayView = GlowOverlayView(this)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            params.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        windowManager?.addView(overlayView, params)
        startAnimation()
    }

    private fun startAnimation() {
        val waveAnim = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 500
            interpolator = DecelerateInterpolator(1.5f)
            addUpdateListener {
                overlayView?.waveProgress = it.animatedValue as Float
                overlayView?.invalidate()
            }
        }

        val rotateAnim = ValueAnimator.ofFloat(0f, 0.5f).apply {
            duration = 4000
            interpolator = LinearInterpolator()
            addUpdateListener {
                overlayView?.gradientRotation = it.animatedValue as Float
                overlayView?.invalidate()
            }
        }

        val fadeAnim = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = 800
            startDelay = 2700
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                overlayView?.opacity = it.animatedValue as Float
                overlayView?.invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    stopSelf()
                }
            })
        }

        animators.addAll(listOf(waveAnim, rotateAnim, fadeAnim))
        animators.forEach { it.start() }
    }

    override fun onDestroy() {
        animators.forEach { it.cancel() }
        animators.clear()
        overlayView?.let { windowManager?.removeView(it) }
        overlayView = null
        super.onDestroy()
    }
}

class GlowOverlayView(context: Context) : View(context) {
    var waveProgress = 0f
    var opacity = 1f
    var gradientRotation = 0f

    private val colorsBlue = intArrayOf(
        Color.parseColor("#00D4FF"),
        Color.parseColor("#0088FF"),
        Color.parseColor("#6C5CE7"),
        Color.parseColor("#A855F7"),
        Color.parseColor("#3B82F6"),
        Color.parseColor("#00D4FF"),
    )

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (waveProgress <= 0f || opacity <= 0f) return

        val w = width.toFloat()
        val h = height.toFloat()

        canvas.saveLayerAlpha(0f, 0f, w, h, (opacity * 255).toInt())

        val path = buildWavePath(w, h, waveProgress)
        drawGlow(canvas, path, w, h)

        canvas.restore()
    }

    private fun buildWavePath(w: Float, h: Float, progress: Float): Path {
        val path = Path()

        val topProgress = (progress / 0.15f).coerceIn(0f, 1f)
        val sideProgress = ((progress - 0.1f) / 0.65f).coerceIn(0f, 1f)
        val bottomProgress = ((progress - 0.7f) / 0.3f).coerceIn(0f, 1f)

        if (topProgress > 0f) {
            val halfW = w / 2
            val topLeft = halfW - halfW * topProgress
            val topRight = halfW + halfW * topProgress
            path.moveTo(topLeft, 0f)
            path.lineTo(topRight, 0f)
        }

        if (sideProgress > 0f) {
            path.moveTo(w, 0f)
            path.lineTo(w, h * sideProgress)
        }

        if (sideProgress > 0f) {
            path.moveTo(0f, 0f)
            path.lineTo(0f, h * sideProgress)
        }

        if (bottomProgress > 0f) {
            val halfW = w / 2
            path.moveTo(0f, h)
            path.lineTo(halfW * bottomProgress, h)
            path.moveTo(w, h)
            path.lineTo(w - halfW * bottomProgress, h)
        }

        return path
    }

    private fun drawGlow(canvas: Canvas, path: Path, w: Float, h: Float) {
        val cx = w / 2
        val cy = h / 2

        val matrix = Matrix().apply { setRotate(gradientRotation * 360f, cx, cy) }
        val gradient = SweepGradient(cx, cy, colorsBlue, null)
        gradient.setLocalMatrix(matrix)

        // Layer 1: Atmospheric glow
        canvas.drawPath(path, Paint().apply {
            shader = gradient
            style = Paint.Style.STROKE
            strokeWidth = 200f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            alpha = 40
            maskFilter = BlurMaskFilter(90f, BlurMaskFilter.Blur.NORMAL)
            isAntiAlias = true
        })

        // Layer 2: Wide glow
        canvas.drawPath(path, Paint().apply {
            shader = gradient
            style = Paint.Style.STROKE
            strokeWidth = 120f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            alpha = 80
            maskFilter = BlurMaskFilter(45f, BlurMaskFilter.Blur.NORMAL)
            isAntiAlias = true
        })

        // Layer 3: Medium glow
        canvas.drawPath(path, Paint().apply {
            shader = gradient
            style = Paint.Style.STROKE
            strokeWidth = 70f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            alpha = 140
            maskFilter = BlurMaskFilter(20f, BlurMaskFilter.Blur.NORMAL)
            isAntiAlias = true
        })

        // Layer 4: Solid border
        canvas.drawPath(path, Paint().apply {
            shader = gradient
            style = Paint.Style.STROKE
            strokeWidth = 36f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            isAntiAlias = true
        })

        // Layer 5: Bright inner core
        val coreGradient = SweepGradient(cx, cy, intArrayOf(
            Color.parseColor("#B0E0FF"),
            Color.parseColor("#FFFFFF"),
            Color.parseColor("#D0B0FF"),
            Color.parseColor("#FFFFFF"),
            Color.parseColor("#B0E0FF"),
        ), null)
        coreGradient.setLocalMatrix(matrix)

        canvas.drawPath(path, Paint().apply {
            shader = coreGradient
            style = Paint.Style.STROKE
            strokeWidth = 10f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            alpha = 200
            isAntiAlias = true
        })
    }
}
