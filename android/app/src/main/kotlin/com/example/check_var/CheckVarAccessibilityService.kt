package com.example.check_var

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.Executor
import java.util.concurrent.Executors

class CheckVarAccessibilityService : AccessibilityService() {
    companion object {
        var instance: CheckVarAccessibilityService? = null
        private const val TAG = "CheckVarA11y"
    }

    private val executor: Executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "Accessibility service destroyed")
        super.onDestroy()
    }

    fun captureAndOcr(callback: (String) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            Log.w(TAG, "API level too low for takeScreenshot")
            callback("")
            return
        }

        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                executor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        try {
                            val hardwareBuffer = result.hardwareBuffer
                            val colorSpace = result.colorSpace

                            val hardwareBitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                            hardwareBuffer.close()

                            if (hardwareBitmap == null) {
                                Log.w(TAG, "wrapHardwareBuffer returned null")
                                callback("")
                                return
                            }

                            val softwareBitmap = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
                            hardwareBitmap.recycle()

                            if (softwareBitmap == null) {
                                Log.w(TAG, "bitmap copy returned null")
                                callback("")
                                return
                            }

                            val inputImage = InputImage.fromBitmap(softwareBitmap, 0)
                            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

                            recognizer.process(inputImage)
                                .addOnSuccessListener { visionText ->
                                    softwareBitmap.recycle()
                                    Log.d(TAG, "OCR success: ${visionText.text.take(100)}...")
                                    callback(visionText.text)
                                }
                                .addOnFailureListener { e ->
                                    softwareBitmap.recycle()
                                    Log.e(TAG, "ML Kit failed", e)
                                    callback("")
                                }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing screenshot", e)
                            callback("")
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "takeScreenshot failed with code: $errorCode")
                        callback("")
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error calling takeScreenshot", e)
            callback("")
        }
    }
}
