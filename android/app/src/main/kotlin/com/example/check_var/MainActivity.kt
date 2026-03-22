package com.example.check_var

import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Channel used by the scam-call Dart PlatformChannel class. */
        private const val SCAM_CALL_CHANNEL = "com.checkvar/service"
        /** Channel used by the news-check Dart layer. */
        private const val NEWS_CHANNEL = "com.checkvar/methods"
        /** Shared event channel (shake, call_state, caption_text, overlay_activate …). */
        private const val EVENT_CHANNEL = "com.checkvar/events"
        private const val PHONE_STATE_PERMISSION_REQUEST = 1003

        var instance: MainActivity? = null
        var pendingScreenText: String? = null
        var isInForeground = false
    }

    private var pendingPermissionsResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        val bridge = ServiceBridge.instance
        bridge.initialize(this)

        // ── Scam-call method channel (used by Dart PlatformChannel) ─────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCAM_CALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPhoneStatePermission" -> requestPhoneStatePermission(result)
                    else -> bridge.onScamCallMethod(call, result)
                }
            }

        // ── News method channel (used by Dart news-check layer) ─────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NEWS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startShakeService" -> {
                        val intent = Intent(this, ShakeDetectorService::class.java)
                        call.argument<String>("notificationTitle")?.let {
                            intent.putExtra("notificationTitle", it)
                        }
                        call.argument<String>("notificationBody")?.let {
                            intent.putExtra("notificationBody", it)
                        }
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "stopShakeService" -> {
                        val intent = Intent(this, ShakeDetectorService::class.java)
                        stopService(intent)
                        result.success(null)
                    }
                    "setMode" -> {
                        val mode = call.argument<String>("mode") ?: "news"
                        bridge.mode = mode
                        result.success(null)
                    }
                    "setDarkMode" -> {
                        val isDark = call.argument<Boolean>("isDark") ?: false
                        AnalysisOverlayService.appDarkMode = isDark
                        result.success(null)
                    }
                    "getPendingText" -> {
                        val text = pendingScreenText
                        if (text != null) pendingScreenText = null
                        result.success(text)
                    }
                    "checkAccessibilityPermission" -> {
                        result.success(CheckVarAccessibilityService.instance != null)
                    }
                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    "showGlowOverlay" -> {
                        GlowOverlayService.show(this)
                        GlowOverlayService.playSound(this)
                        result.success(null)
                    }
                    "hideGlowOverlay" -> {
                        GlowOverlayService.hide(this)
                        result.success(null)
                    }
                    "checkOverlayPermission" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "requestOverlayPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    // ── Analysis overlay ──────────────────────────────
                    "showAnalysisOverlay" -> {
                        val initialStatus = call.argument<String>("initialStatus") ?: ""
                        AnalysisOverlayService.show(this, initialStatus)
                        result.success(null)
                    }
                    "hideAnalysisOverlay" -> {
                        AnalysisOverlayService.hide(this)
                        result.success(null)
                    }
                    "updateAnalysisStatus" -> {
                        val status = call.argument<String>("status") ?: ""
                        AnalysisOverlayService.updateStatus(status)
                        result.success(null)
                    }
                    "showAnalysisResult" -> {
                        val verdict = call.argument<String>("verdict") ?: "uncertain"
                        val verdictLabel = call.argument<String>("verdictLabel") ?: ""
                        val confidence = call.argument<String>("confidence") ?: ""
                        val summary = call.argument<String>("summary") ?: ""
                        val detailLabel = call.argument<String>("detailLabel") ?: "View details"
                        val disclaimerLabel = call.argument<String>("disclaimerLabel") ?: "AI can make mistakes"
                        AnalysisOverlayService.showResult(verdict, verdictLabel, confidence, summary, detailLabel, disclaimerLabel)
                        result.success(null)
                    }
                    "showAnalysisError" -> {
                        val message = call.argument<String>("message") ?: ""
                        val errorLabel = call.argument<String>("errorLabel") ?: "Error"
                        val closeLabel = call.argument<String>("closeLabel") ?: "Close"
                        AnalysisOverlayService.showError(message, errorLabel, closeLabel)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Shared event channel ────────────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bridge.attachEventSink(events)
                }
                override fun onCancel(arguments: Any?) {
                    bridge.detachEventSink()
                }
            })
    }

    // ── Phone state runtime permission ──────────────────────────────────────

    private fun requestPhoneStatePermission(result: MethodChannel.Result) {
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingPermissionsResult = result
        androidx.core.app.ActivityCompat.requestPermissions(
            this,
            arrayOf(android.Manifest.permission.READ_PHONE_STATE),
            PHONE_STATE_PERMISSION_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PHONE_STATE_PERMISSION_REQUEST) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all {
                it == PackageManager.PERMISSION_GRANTED
            }
            pendingPermissionsResult?.success(allGranted)
            pendingPermissionsResult = null
        }
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────

    override fun onResume() {
        super.onResume()
        isInForeground = true
    }

    override fun onPause() {
        super.onPause()
        isInForeground = false
    }

    override fun onDestroy() {
        instance = null
        isInForeground = false
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
