package com.example.check_var

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ServiceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private var newsDetectionEnabled: Boolean = false
    private var callDetectionEnabled: Boolean = false
    private var isCallActive: Boolean = false
    private var eventSink: EventChannel.EventSink? = null
    private var pendingAppAction: String? = null

    private var speechRecognizerManager: SpeechRecognizerManager? = null
    private var tts: TextToSpeech? = null
    private var speakerRoutingActive: Boolean = false
    private var previousSpeakerphoneState: Boolean? = null
    private var previousAudioMode: Int? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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
                // Legacy no-op retained for compatibility with older Flutter builds.
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

            // Speaker test methods
            "startCallMonitorService" -> {
                startCallMonitor()
                result.success(true)
            }
            "stopCallMonitorService" -> {
                stopCallMonitor()
                result.success(true)
            }
            "getSpeakerTestReadiness" -> {
                result.success(getSpeakerTestReadiness())
            }
            "startSpeakerRecognition" -> {
                val language = call.argument<String>("language") ?: "vi-VN"
                startSpeakerRecognition(language)
                result.success(true)
            }
            "stopSpeakerRecognition" -> {
                stopSpeakerRecognition()
                result.success(true)
            }
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
            "updateOverlayTranscript" -> {
                val text = call.argument<String>("text") ?: ""
                OverlayBubbleService.updateTranscript(text)
                result.success(true)
            }
            "showCallStatusBubble" -> {
                val intent = Intent(context, CallStatusBubbleService::class.java)
                context.startService(intent)
                result.success(true)
            }
            "hideCallStatusBubble" -> {
                val intent = Intent(context, CallStatusBubbleService::class.java)
                context.stopService(intent)
                result.success(true)
            }
            "updateOverlayStatus" -> {
                val threatLevel = call.argument<String>("threatLevel") ?: "safe"
                val sessionStatus = call.argument<String>("sessionStatus") ?: "idle"
                CallStatusBubbleService.updateStatus(sessionStatus, threatLevel)
                result.success(true)
            }
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
                }
                newsDetectionEnabled && MainActivity.projectionReady -> {
                    Handler(Looper.getMainLooper()).post {
                        MainActivity.instance?.captureScreenNow { bytes ->
                            MainActivity.instance?.pendingScreenshotBytes = bytes
                            emitShake("news")
                            bringAppToForeground()
                        }
                    }
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

    fun attachEventSink(events: EventChannel.EventSink?) {
        eventSink = events
        flushPendingAppAction()
    }

    fun detachEventSink() {
        eventSink = null
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
            Handler(Looper.getMainLooper()).post {
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

    private fun getSpeakerTestReadiness(): Map<String, Any> {
        val hasPhoneStatePermission = androidx.core.content.ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.READ_PHONE_STATE
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED

        val hasActiveCall = if (hasPhoneStatePermission) {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            @Suppress("DEPRECATION")
            CallMonitorPolicy.isCallActive(tm.callState)
        } else {
            false
        }

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager

        val hasMicPermission = androidx.core.content.ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED

        return mapOf(
            "hasActiveCall" to hasActiveCall,
            "hasOverlayPermission" to Settings.canDrawOverlays(context),
            "hasMicrophonePermission" to hasMicPermission,
            "recognizerAvailable" to SpeechRecognizer.isRecognitionAvailable(context),
            "isSpeakerphoneOn" to audioManager.isSpeakerphoneOn,
        )
    }

    private fun startSpeakerRecognition(language: String = "vi-VN") {
        val hasMic = androidx.core.content.ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!hasMic) return

        if (speechRecognizerManager == null) {
            speechRecognizerManager = SpeechRecognizerManager(context, language) { event ->
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success(event)
                }
            }
        }
        speechRecognizerManager?.start()
    }

    private fun stopSpeakerRecognition() {
        speechRecognizerManager?.stop()
        speechRecognizerManager = null
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
                    Handler(Looper.getMainLooper()).post {
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
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success(mapOf("type" to "tts_done"))
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                restoreAudioRouting()
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success(mapOf("type" to "tts_done"))
                }
            }
        }
    }

    private fun routeTtsToSpeaker() {
        if (speakerRoutingActive) {
            return
        }

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        previousSpeakerphoneState = audioManager.isSpeakerphoneOn
        previousAudioMode = audioManager.mode
        audioManager.mode = AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = true
        speakerRoutingActive = true
    }

    private fun restoreAudioRouting() {
        if (!speakerRoutingActive) {
            return
        }

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
