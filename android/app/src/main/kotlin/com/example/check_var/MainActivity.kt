package com.example.check_var

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val METHOD_CHANNEL = "com.checkvar/methods"
        const val EVENT_CHANNEL = "com.checkvar/events"
        var pendingScreenText: String? = null
        var eventSink: EventChannel.EventSink? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startShakeService" -> {
                        val intent = Intent(this, ShakeDetectorService::class.java)
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
                        ServiceBridge.instance.mode = mode
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
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        ServiceBridge.instance.initialize()
    }
}
