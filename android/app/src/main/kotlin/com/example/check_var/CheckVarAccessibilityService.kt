package com.example.check_var

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.Executor
import java.util.concurrent.Executors

class CheckVarAccessibilityService : AccessibilityService() {
    companion object {
        var instance: CheckVarAccessibilityService? = null
        private const val TAG = "CheckVarA11y"
        private const val LIVE_CAPTION_PACKAGE = "com.google.android.as"
    }

    private val executor: Executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Last emitted caption text — used for word-level deduplication. */
    private var lastEmittedCaption: String = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return
        if (event.packageName?.toString() != LIVE_CAPTION_PACKAGE) return

        val bridge = ServiceBridge.instance
        if (!bridge.captionCaptureActive) return

        val source = event.source ?: return
        val text = extractTextFromNode(source)
        source.recycle()

        if (text.isBlank()) return

        // Word-level deduplication: only emit when new word(s) appear.
        if (text == lastEmittedCaption) return
        if (text.length < lastEmittedCaption.length) {
            // Live Caption may clear and start a new sentence.
            lastEmittedCaption = ""
        }
        // Check if the new text starts with the old text (character-by-character update)
        // and only emit if at least one new word boundary appeared.
        if (text.startsWith(lastEmittedCaption)) {
            val delta = text.substring(lastEmittedCaption.length)
            if (!delta.contains(' ') && !delta.contains('.') &&
                !delta.contains(',') && !delta.contains('!') &&
                !delta.contains('?')
            ) {
                // No new word boundary yet — skip this event.
                return
            }
        }

        lastEmittedCaption = text
        bridge.emitCaptionText(text)
    }

    /** Recursively extract all text from an AccessibilityNodeInfo tree. */
    private fun extractTextFromNode(node: AccessibilityNodeInfo): String {
        val builder = StringBuilder()

        // Skip UI chrome like labels ("Live Caption", button text, etc.)
        val className = node.className?.toString() ?: ""
        if (className == "android.widget.Button" ||
            className == "android.widget.ImageButton" ||
            className == "android.widget.ImageView"
        ) {
            return ""
        }

        val nodeText = node.text?.toString()
        if (!nodeText.isNullOrBlank() && nodeText != "Live Caption") {
            builder.append(nodeText)
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val childText = extractTextFromNode(child)
            child.recycle()
            if (childText.isNotBlank()) {
                if (builder.isNotEmpty()) builder.append(" ")
                builder.append(childText)
            }
        }

        return builder.toString().trim()
    }

    fun resetCaptionState() {
        lastEmittedCaption = ""
    }

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
