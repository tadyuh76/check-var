package com.example.check_var

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Unified bridge that handles both:
 *  - News-check shake detection (accessibility OCR)
 *  - Scam-call platform methods (call monitor, TTS, overlays, Live Caption capture)
 */
class ServiceBridge private constructor() {

    companion object {
        val instance: ServiceBridge by lazy { ServiceBridge() }
        private const val TAG = "ServiceBridge"
    }

    private lateinit var context: Context

    // ── Shared state ────────────────────────────────────────────────────────
    var mode: String = "news"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    // ── Scam-call state ─────────────────────────────────────────────────────
    private var newsDetectionEnabled: Boolean = false
    private var callDetectionEnabled: Boolean = false
    private var isCallActive: Boolean = false

    /** Cached caller identity from the most recent RINGING event. */
    var lastCallerType: CallerIdentityResolver.CallerType = CallerIdentityResolver.CallerType.UNDETERMINED
        private set
    var lastCallerDisplayText: String? = null
        private set
    private var tts: TextToSpeech? = null
    private var speakerRoutingActive: Boolean = false
    private var previousSpeakerphoneState: Boolean? = null
    private var previousAudioMode: Int? = null

    // ── Live Caption capture state ──────────────────────────────────────────
    /** When true, the AccessibilityService forwards caption events. */
    var captionCaptureActive: Boolean = false
        private set

    fun initialize(ctx: Context) {
        context = ctx
    }

    // ── Event sink management ───────────────────────────────────────────────

    fun attachEventSink(events: EventChannel.EventSink?) {
        eventSink = events
    }

    fun detachEventSink() {
        eventSink = null
    }

    fun sendEvent(data: Map<String, Any>) {
        mainHandler.post { eventSink?.success(data) }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  NEWS-CHECK: Accessibility OCR shake handler (remote's feature)
    // ═══════════════════════════════════════════════════════════════════════

    fun onShakeDetected() {
        try {
            Log.d(TAG, "onShakeDetected called, mode=$mode")
            if (mode != "news") return

            val service = CheckVarAccessibilityService.instance
            if (service == null) {
                Log.w(TAG, "AccessibilityService not available, skipping")
                return
            }

            Log.d(TAG, "Starting captureAndOcr...")
            service.captureAndOcr { text ->
                Log.d(TAG, "OCR result: length=${text.length}, preview=${text.take(100)}")
                sendNewsEventToFlutter(text)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onShakeDetected", e)
        }
    }

    private fun sendNewsEventToFlutter(text: String?) {
        mainHandler.post {
            try {
                MainActivity.pendingScreenText = text
                eventSink?.success(
                    mapOf("type" to "shake", "mode" to mode)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error sending event to Flutter", e)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SCAM-CALL: Method handler for com.checkvar/service channel
    // ═══════════════════════════════════════════════════════════════════════

    fun onScamCallMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startShakeService" -> {
                startShakeService()
                result.success(true)
            }
            "stopShakeService" -> {
                stopShakeService()
                result.success(true)
            }
            "setMode" -> {
                result.success(true)
            }
            "setNewsDetectionEnabled" -> {
                newsDetectionEnabled = call.argument<Boolean>("enabled") ?: false
                syncServices()
                result.success(true)
            }
            "setCallDetectionEnabled" -> {
                callDetectionEnabled = call.argument<Boolean>("enabled") ?: false
                syncServices()
                result.success(true)
            }
            "startCallMonitorService" -> {
                startCallMonitor()
                result.success(true)
            }
            "stopCallMonitorService" -> {
                stopCallMonitor()
                result.success(true)
            }
            // ── Live Caption capture ────────────────────────────────────
            "startCaptionCapture" -> {
                startCaptionCapture()
                result.success(true)
            }
            "stopCaptionCapture" -> {
                stopCaptionCapture()
                result.success(true)
            }
            "checkLiveCaptionEnabled" -> {
                result.success(checkLiveCaptionEnabled())
            }
            "openLiveCaptionSettings" -> {
                openLiveCaptionSettings()
                result.success(true)
            }
            // ── Overlay ─────────────────────────────────────────────────
            "requestOverlayPermission" -> {
                val granted = Settings.canDrawOverlays(context)
                if (!granted) {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        android.net.Uri.parse("package:${context.packageName}")
                    )
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                }
                result.success(granted)
            }
            "showOverlayBubble" -> {
                val intent = Intent(context, OverlayBubbleService::class.java)
                context.startService(intent)
                result.success(true)
            }
            "hideOverlayBubble" -> {
                val intent = Intent(context, OverlayBubbleService::class.java)
                context.stopService(intent)
                result.success(true)
            }
            "updateOverlayStatus" -> {
                val threatLevel = call.argument<String>("threatLevel") ?: "safe"
                val sessionStatus = call.argument<String>("sessionStatus") ?: "idle"
                val confidence = call.argument<Int>("confidence") ?: -1
                OverlayBubbleService.updateStatus(sessionStatus, threatLevel, confidence)
                result.success(true)
            }
            // ── TTS ─────────────────────────────────────────────────────
            "speakText" -> {
                val text = call.argument<String>("text") ?: ""
                val preferSpeaker = call.argument<Boolean>("preferSpeaker") ?: false
                speakText(text, preferSpeaker)
                result.success(true)
            }
            "stopSpeaking" -> {
                tts?.stop()
                restoreAudioRouting()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ── Live Caption capture methods ────────────────────────────────────────

    private fun startCaptionCapture() {
        val a11y = CheckVarAccessibilityService.instance
        Log.w(TAG, "startCaptionCapture: a11yService=${a11y != null}, " +
                "eventSink=${eventSink != null}")
        if (a11y == null) {
            Log.e(TAG, "startCaptionCapture: AccessibilityService NOT RUNNING — " +
                    "user must enable it in Settings > Accessibility")
        }
        captionCaptureActive = true
        a11y?.resetCaptionState()
    }

    private fun stopCaptionCapture() {
        Log.d(TAG, "stopCaptionCapture: setting captionCaptureActive=false")
        captionCaptureActive = false
    }

    /**
     * Best-effort check for Live Caption being enabled via Settings.Secure.
     * The key `oda_enabled` is undocumented and may vary across devices.
     * Returns true if the key is set to "1", false otherwise.
     */
    private fun checkLiveCaptionEnabled(): Boolean {
        return try {
            val value = Settings.Secure.getString(
                context.contentResolver, "oda_enabled"
            )
            value == "1"
        } catch (_: Exception) {
            false
        }
    }

    /** Open the device's Live Caption / captioning settings screen. */
    private fun openLiveCaptionSettings() {
        // Try intents from most specific to least specific.
        // ACTION_CAPTIONING_SETTINGS is a standard API that opens caption
        // preferences, which includes the Live Caption toggle on most devices.
        val intents = listOf(
            Intent("android.settings.CAPTIONING_SETTINGS"),
            Intent(Settings.ACTION_SOUND_SETTINGS),
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return
            } catch (_: Exception) {
                // Intent not available on this device, try next.
            }
        }
    }

    /** Called by CheckVarAccessibilityService to emit caption text to Flutter. */
    fun emitCaptionText(text: String) {
        Log.d(TAG, "emitCaptionText: '${text.take(60)}', eventSink=${eventSink != null}")
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "caption_text",
                    "text" to text,
                )
            )
        }
    }

    /** Called by OverlayBubbleService when user taps idle overlay to start detection. */
    fun emitOverlayActivate() {
        Log.d(TAG, "emitOverlayActivate: eventSink=${eventSink != null}")
        mainHandler.post {
            eventSink?.success(
                mapOf("type" to "overlay_activate")
            )
        }
    }

    // ── Caller identity cache ────────────────────────────────────────────────

    fun cacheCallerInfo(type: CallerIdentityResolver.CallerType, displayText: String?) {
        lastCallerType = type
        lastCallerDisplayText = displayText
        Log.d(TAG, "cacheCallerInfo: type=$type, displayText='${displayText?.take(40)}'")
    }

    fun resetCallerType() {
        lastCallerType = CallerIdentityResolver.CallerType.UNDETERMINED
        lastCallerDisplayText = null
        Log.d(TAG, "resetCallerType: reset to UNDETERMINED")
    }

    // ── Scam-call service orchestration ─────────────────────────────────────

    private fun syncServices() {
        Log.d(TAG, "syncServices: newsDetection=$newsDetectionEnabled, callDetection=$callDetectionEnabled, isCallActive=$isCallActive")
        if (newsDetectionEnabled || callDetectionEnabled) {
            startShakeService()
        } else {
            stopShakeService()
        }

        if (callDetectionEnabled) {
            startCallMonitor()
        } else {
            isCallActive = false
            stopCallMonitor()
        }
    }

    private fun startShakeService() {
        Log.d(TAG, "startShakeService: setting onShakeDetected callback")
        ShakeDetectorService.onShakeDetected = {
            Log.d(TAG, "SHAKE CALLBACK: callDetection=$callDetectionEnabled, isCallActive=$isCallActive, newsDetection=$newsDetectionEnabled, eventSink=${eventSink != null}")
            when {
                callDetectionEnabled && isCallActive -> {
                    Log.d(TAG, "SHAKE CALLBACK → emitting CALL shake")
                    emitShake("call")
                    // Do NOT call bringAppToForeground() — user stays on call screen.
                    // The overlay bubble is already visible; Dart side starts analysis in background.
                }
                newsDetectionEnabled -> {
                    Log.d(TAG, "SHAKE CALLBACK → routing to onShakeDetected (OCR)")
                    acquireTransientWakeLock()
                    onShakeDetected()
                }
                else -> {
                    Log.d(TAG, "SHAKE CALLBACK → NO BRANCH MATCHED, shake ignored")
                }
            }
        }
        val intent = Intent(context, ShakeDetectorService::class.java)
        context.startForegroundService(intent)
    }

    private fun stopShakeService() {
        ShakeDetectorService.onShakeDetected = null
        val intent = Intent(context, ShakeDetectorService::class.java)
        context.stopService(intent)
    }

    private fun emitShake(mode: String) {
        Log.d(TAG, "emitShake: mode=$mode, eventSink=${eventSink != null}")
        eventSink?.success(
            mapOf(
                "type" to "shake",
                "mode" to mode
            )
        )
    }

    private fun startCallMonitor() {
        CallMonitorService.onCallStateChanged = { event ->
            val active = event["isActive"] as? Boolean ?: false
            isCallActive = active
            mainHandler.post {
                eventSink?.success(event)
            }
        }
        val intent = Intent(context, CallMonitorService::class.java)
        context.startForegroundService(intent)
    }

    private fun stopCallMonitor() {
        CallMonitorService.onCallStateChanged = null
        val intent = Intent(context, CallMonitorService::class.java)
        context.stopService(intent)
    }

    // ── TTS ─────────────────────────────────────────────────────────────────

    private fun speakText(text: String, preferSpeaker: Boolean) {
        if (preferSpeaker) {
            routeTtsToSpeaker()
        } else {
            restoreAudioRouting()
        }

        if (tts == null) {
            tts = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    tts?.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    tts?.setOnUtteranceProgressListener(createTtsListener())
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "checkvar_tts")
                } else {
                    restoreAudioRouting()
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "tts_done"))
                    }
                }
            }
        } else {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "checkvar_tts")
        }
    }

    private fun createTtsListener(): UtteranceProgressListener {
        return object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onDone(utteranceId: String?) {
                restoreAudioRouting()
                mainHandler.post {
                    eventSink?.success(mapOf("type" to "tts_done"))
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                restoreAudioRouting()
                mainHandler.post {
                    eventSink?.success(mapOf("type" to "tts_done"))
                }
            }
        }
    }

    private fun routeTtsToSpeaker() {
        if (speakerRoutingActive) return

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        previousSpeakerphoneState = audioManager.isSpeakerphoneOn
        previousAudioMode = audioManager.mode
        audioManager.mode = AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = true
        speakerRoutingActive = true
    }

    private fun restoreAudioRouting() {
        if (!speakerRoutingActive) return

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        previousSpeakerphoneState?.let { audioManager.isSpeakerphoneOn = it }
        previousAudioMode?.let { audioManager.mode = it }
        previousSpeakerphoneState = null
        previousAudioMode = null
        speakerRoutingActive = false
    }

    /**
     * Acquire a short-lived partial wake lock to prevent doze/battery
     * optimization from throttling the network while Flutter runs the
     * fact-check API call.  Auto-releases after 90 seconds.
     */
    private fun acquireTransientWakeLock() {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "checkvar:factcheck")
            wl.acquire(90_000)
            Log.d(TAG, "acquireTransientWakeLock: acquired for 90s")
        } catch (e: Exception) {
            Log.w(TAG, "acquireTransientWakeLock: failed", e)
        }
    }

    private fun bringAppToForeground() {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        context.startActivity(launchIntent)
    }
}
