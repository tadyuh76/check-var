package com.example.check_var

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
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
    private var pendingAppAction: String? = null

    // ── Scam-call state ─────────────────────────────────────────────────────
    private var newsDetectionEnabled: Boolean = false
    private var callDetectionEnabled: Boolean = false
    private var isCallActive: Boolean = false
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
        flushPendingAppAction()
    }

    fun detachEventSink() {
        eventSink = null
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
        captionCaptureActive = true
        CheckVarAccessibilityService.instance?.resetCaptionState()
    }

    private fun stopCaptionCapture() {
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
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "caption_text",
                    "text" to text,
                )
            )
        }
    }

    // ── Scam-call service orchestration ─────────────────────────────────────

    private fun syncServices() {
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
        ShakeDetectorService.onShakeDetected = {
            when {
                callDetectionEnabled && isCallActive -> {
                    emitShake("call")
                    bringAppToForeground()
                }
                newsDetectionEnabled -> {
                    emitShake("news")
                    bringAppToForeground()
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
        eventSink?.success(
            mapOf(
                "type" to "shake",
                "mode" to mode
            )
        )
    }

    fun handleAppAction(action: String) {
        if (eventSink == null) {
            pendingAppAction = action
            return
        }
        emitAppAction(action)
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

    private fun emitAppAction(action: String) {
        eventSink?.success(
            mapOf(
                "type" to "overlay_tap",
                "action" to action,
            )
        )
    }

    private fun flushPendingAppAction() {
        val action = pendingAppAction ?: return
        pendingAppAction = null
        emitAppAction(action)
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

    private fun bringAppToForeground() {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        context.startActivity(launchIntent)
    }
}
