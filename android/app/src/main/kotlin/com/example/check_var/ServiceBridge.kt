package com.example.check_var

import android.os.Handler
import android.os.Looper
import android.util.Log

class ServiceBridge private constructor() {
    companion object {
        val instance: ServiceBridge by lazy { ServiceBridge() }
        private const val TAG = "ServiceBridge"
    }

    var mode: String = "news"
    private val mainHandler = Handler(Looper.getMainLooper())

    fun initialize() {
        // Called from MainActivity to ensure bridge is ready
    }

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
                sendEventToFlutter(text)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onShakeDetected", e)
        }
    }

    private fun sendEventToFlutter(text: String?) {
        mainHandler.post {
            try {
                MainActivity.pendingScreenText = text
                MainActivity.eventSink?.success(
                    mapOf("type" to "shake", "mode" to mode)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error sending event to Flutter", e)
            }
        }
    }
}
