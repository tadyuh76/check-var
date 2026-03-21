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

        /** Known Live Caption provider packages across device manufacturers. */
        private val LIVE_CAPTION_PACKAGES = setOf(
            "com.google.android.as",           // Google Android System Intelligence (Pixel, most OEMs)
            "com.google.android.tts",          // Fallback on some devices
        )

        /** Packages that produce noisy TYPE_WINDOW_CONTENT_CHANGED events
         *  but never contain caption text. Skipped to reduce overhead. */
        private val IGNORED_PACKAGES = setOf(
            "com.example.check_var",           // Our own app
            "com.android.systemui",            // System UI (status bar, notifications)
        )
    }

    private val executor: Executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Last emitted caption text — used for word-level deduplication. */
    private var lastEmittedCaption: String = ""

    /** Whether we have already dismissed the Live Caption overlay this session. */
    private var overlayDismissed: Boolean = false

    /** Unique packages seen since last diagnostic dump — helps discover Live Caption's package. */
    private val recentPackages = mutableSetOf<String>()
    private var lastDiagnosticDump = 0L

    /** Unique event types seen since capture started — reveals if service is alive. */
    private val seenEventTypes = mutableSetOf<Int>()
    private var totalEventCount = 0

    /** Pending delayed dismiss — reset on each "no … speech recognized" event. */
    private val dismissRunnable = Runnable { dismissLiveCaptionOverlay() }

    /**
     * Matches Live Caption's wrong-language notice, e.g.
     * "No English speech recognized", "No Japanese speech recognized", etc.
     */
    private val noSpeechPattern = Regex(
        "no\\s+\\w+\\s+speech\\s+recognized", RegexOption.IGNORE_CASE
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // ── Top-level diagnostic: is the service receiving ANY events? ──
        val bridge = ServiceBridge.instance
        if (bridge.captionCaptureActive) {
            totalEventCount++
            if (seenEventTypes.add(event.eventType)) {
                Log.w(TAG, "DIAG-EVENT: eventType=${event.eventType} " +
                        "pkg=${event.packageName} " +
                        "(totalEvents=$totalEventCount, " +
                        "uniqueTypes=${seenEventTypes.toList()})")
            }
        }

        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return

        val pkg = event.packageName?.toString() ?: ""

        if (!bridge.captionCaptureActive) {
            // Not capturing — only log events from known Live Caption packages.
            if (pkg in LIVE_CAPTION_PACKAGES) {
                Log.d(TAG, "captionCaptureActive=false, ignoring Live Caption event from pkg=$pkg")
            }
            return
        }

        // Skip packages that never contain caption text.
        if (pkg in IGNORED_PACKAGES) return

        // ── Diagnostic: log all unique packages seen while capturing ──
        if (recentPackages.add(pkg)) {
            Log.d(TAG, "DIAG: new package while capturing: $pkg")
        }

        // When actively capturing, accept text from ANY package.
        // During phone calls, Live Caption may render through the dialer,
        // a carrier captioning service, or other system components — not
        // necessarily com.google.android.as.

        val source = event.source
        if (source == null) {
            Log.w(TAG, "event.source is null for pkg=$pkg — cannot extract text (missing flagRetrieveInteractiveWindows?)")
            return
        }
        val text = extractTextFromNode(source)
        source.recycle()

        if (text.isBlank()) {
            Log.d(TAG, "Extracted text is blank for pkg=$pkg")
            return
        }
        Log.d(TAG, "Caption text extracted: '${text.take(80)}'")

        // NOTE: We intentionally leave the Live Caption overlay visible.
        // Clicking its close/collapse button turns off captioning entirely
        // on most devices, killing the accessibility event pipeline.

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
        overlayDismissed = false
        recentPackages.clear()
        seenEventTypes.clear()
        totalEventCount = 0
        lastDiagnosticDump = 0L
        mainHandler.removeCallbacks(dismissRunnable)
        Log.d(TAG, "resetCaptionState: ready to capture Live Caption events")
    }

    /**
     * Attempt to dismiss the Live Caption overlay by finding and clicking its
     * close / collapse button.  The captioning service keeps running internally
     * so accessibility events should continue to flow.
     *
     * This is best-effort: if the window or button is not found, it is a no-op.
     */
    fun dismissLiveCaptionOverlay() {
        if (overlayDismissed) return
        overlayDismissed = true

        try {
            val windows = windows ?: run {
                Log.d(TAG, "dismissLiveCaptionOverlay: getWindows() returned null")
                return
            }

            for (window in windows) {
                val root = window.root ?: continue
                val pkg = root.packageName?.toString() ?: ""
                if (pkg !in LIVE_CAPTION_PACKAGES) {
                    root.recycle()
                    continue
                }

                Log.d(TAG, "dismissLiveCaptionOverlay: found Live Caption window (pkg=$pkg)")
                val dismissed = findAndClickClose(root)
                root.recycle()
                if (dismissed) {
                    Log.d(TAG, "dismissLiveCaptionOverlay: clicked close/collapse button")
                    return
                }
            }
            Log.d(TAG, "dismissLiveCaptionOverlay: no Live Caption close button found")
        } catch (e: Exception) {
            Log.w(TAG, "dismissLiveCaptionOverlay: failed", e)
        }
    }

    /**
     * Recursively search for a clickable Button / ImageButton and click it.
     * Returns true if a click was performed.
     */
    private fun findAndClickClose(node: AccessibilityNodeInfo): Boolean {
        val className = node.className?.toString() ?: ""
        if ((className == "android.widget.ImageButton" || className == "android.widget.Button")
            && node.isClickable
        ) {
            val result = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            Log.d(TAG, "findAndClickClose: clicked $className, result=$result")
            return result
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findAndClickClose(child)
            child.recycle()
            if (found) return true
        }
        return false
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
