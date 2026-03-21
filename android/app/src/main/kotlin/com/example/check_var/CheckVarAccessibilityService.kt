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

        /** Known dialer packages across major OEMs. */
        private val DIALER_PACKAGES = setOf(
            "com.google.android.dialer",     // Pixel, stock Android
            "com.samsung.android.dialer",    // Samsung
            "com.android.phone",             // AOSP fallback
            "com.miui.phone",                // Xiaomi
            "com.oneplus.dialer",            // OnePlus
        )

        /** Max retries when dialer window isn't rendered yet. */
        private const val DIALER_READ_MAX_RETRIES = 3
        private const val DIALER_READ_RETRY_DELAY_MS = 200L
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

    /** Pending delayed collapse — reset on each "no … speech recognized" event. */
    private val dismissRunnable = Runnable { collapseLiveCaptionOverlay() }

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

        // Minimize the Live Caption overlay after real text has been flowing
        // for a few seconds.  We delay so the user can still change language
        // if Live Caption initially mis-detects and emits stray words before
        // showing the "No … speech recognized" notice.
        if (!overlayDismissed) {
            if (noSpeechPattern.containsMatchIn(text)) {
                // Wrong language — cancel any pending collapse, keep overlay open.
                mainHandler.removeCallbacks(dismissRunnable)
            } else {
                // Real text — schedule collapse after 3s (resets on each event,
                // so it fires 3s after the LAST text update with no wrong-language
                // interruption).
                mainHandler.removeCallbacks(dismissRunnable)
                mainHandler.postDelayed(dismissRunnable, 3000)
            }
        }

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

    /**
     * Extract text from a dialer window's node tree.
     *
     * Unlike [extractTextFromNode] (used for Live Caption), this does NOT skip
     * Button/ImageButton nodes — OEM dialers sometimes render the caller name
     * inside button-like widgets.  Only ImageView is skipped.
     */
    private fun extractDialerTextFromNode(node: AccessibilityNodeInfo): String {
        val builder = StringBuilder()

        val className = node.className?.toString() ?: ""
        if (className == "android.widget.ImageView") {
            return ""
        }

        val nodeText = node.text?.toString()
        if (!nodeText.isNullOrBlank()) {
            builder.append(nodeText)
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val childText = extractDialerTextFromNode(child)
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
     * Read the caller identity text from the dialer screen.
     *
     * Searches accessibility windows for a known dialer package, then falls
     * back to any TYPE_PHONE window.  Retries up to [DIALER_READ_MAX_RETRIES]
     * times with [DIALER_READ_RETRY_DELAY_MS] delays to handle the case where
     * the dialer UI hasn't rendered yet when RINGING fires.
     *
     * **WARNING:** This method uses Thread.sleep() for retries and must NOT be
     * called from the main thread.  It is designed to run on CallMonitorService's
     * background executor thread.
     *
     * @return The caller text shown on the dialer, or null if not found.
     */
    fun readDialerCallerInfo(): String? {
        require(Looper.myLooper() != Looper.getMainLooper()) {
            "readDialerCallerInfo() must not be called on the main thread"
        }

        repeat(DIALER_READ_MAX_RETRIES) { attempt ->
            val text = tryReadDialerWindow()
            if (!text.isNullOrBlank()) {
                Log.d(TAG, "readDialerCallerInfo: found '${text.take(40)}' on attempt $attempt")
                return text
            }
            if (attempt < DIALER_READ_MAX_RETRIES - 1) {
                Thread.sleep(DIALER_READ_RETRY_DELAY_MS)
            }
        }
        Log.d(TAG, "readDialerCallerInfo: no dialer text found after $DIALER_READ_MAX_RETRIES attempts")
        return null
    }

    /**
     * Single attempt to find and read the dialer window.
     */
    private fun tryReadDialerWindow(): String? {
        val allWindows = try {
            windows
        } catch (e: Exception) {
            Log.w(TAG, "tryReadDialerWindow: getWindows() failed", e)
            return null
        }
        if (allWindows == null) return null

        // Tier 1: known dialer packages
        for (window in allWindows) {
            val root = window.root ?: continue
            val pkg = root.packageName?.toString() ?: ""
            if (pkg in DIALER_PACKAGES) {
                val text = extractDialerTextFromNode(root)
                root.recycle()
                if (text.isNotBlank()) return text
            } else {
                root.recycle()
            }
        }

        // Tier 2: any non-system application window we haven't checked yet.
        // The dialer is a TYPE_APPLICATION window; on unknown OEMs its package
        // won't be in DIALER_PACKAGES, but it will still be the foreground app.
        for (window in allWindows) {
            if (window.type != android.view.accessibility.AccessibilityWindowInfo.TYPE_APPLICATION) continue
            val root = window.root ?: continue
            val pkg = root.packageName?.toString() ?: ""
            // Skip packages we already checked or that we know aren't dialers.
            if (pkg in DIALER_PACKAGES || pkg in IGNORED_PACKAGES || pkg in LIVE_CAPTION_PACKAGES) {
                root.recycle()
                continue
            }
            val text = extractDialerTextFromNode(root)
            root.recycle()
            if (text.isNotBlank()) return text
        }

        return null
    }

    /**
     * Minimize the Live Caption overlay without stopping captioning.
     *
     * Tries, in order:
     *  1. ACTION_COLLAPSE on the window root node
     *  2. ACTION_DISMISS on the window root node
     *  3. Swipe-down gesture on the overlay (triggers the built-in minimize)
     *
     * All attempts are best-effort.  If none succeed the overlay simply stays
     * expanded — captioning and event flow are unaffected.
     */
    private fun collapseLiveCaptionOverlay() {
        if (overlayDismissed) return
        overlayDismissed = true

        try {
            val allWindows = windows ?: run {
                Log.d(TAG, "collapseLiveCaptionOverlay: getWindows() returned null")
                return
            }

            for (window in allWindows) {
                val root = window.root ?: continue
                val pkg = root.packageName?.toString() ?: ""
                if (pkg !in LIVE_CAPTION_PACKAGES) {
                    root.recycle()
                    continue
                }

                Log.d(TAG, "collapseLiveCaptionOverlay: found Live Caption window (pkg=$pkg)")

                // Try ACTION_COLLAPSE first — cleanly minimizes to a pill.
                val collapsed = root.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_COLLAPSE.id)
                if (collapsed) {
                    Log.d(TAG, "collapseLiveCaptionOverlay: ACTION_COLLAPSE succeeded")
                    root.recycle()
                    return
                }

                // Try ACTION_DISMISS — some implementations use this to minimize.
                val dismissed = root.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_DISMISS.id)
                if (dismissed) {
                    Log.d(TAG, "collapseLiveCaptionOverlay: ACTION_DISMISS succeeded")
                    root.recycle()
                    return
                }

                // Fallback: swipe down gesture on the overlay bounds.
                val rect = android.graphics.Rect()
                root.getBoundsInScreen(rect)
                root.recycle()

                if (rect.width() > 0 && rect.height() > 0) {
                    val path = android.graphics.Path()
                    path.moveTo(rect.centerX().toFloat(), rect.top.toFloat())
                    path.lineTo(rect.centerX().toFloat(), rect.bottom.toFloat() + 100f)

                    val gesture = android.accessibilityservice.GestureDescription.Builder()
                        .addStroke(
                            android.accessibilityservice.GestureDescription.StrokeDescription(
                                path, 0, 200
                            )
                        )
                        .build()
                    dispatchGesture(gesture, null, null)
                    Log.d(TAG, "collapseLiveCaptionOverlay: dispatched swipe-down gesture")
                }
                return
            }
            Log.d(TAG, "collapseLiveCaptionOverlay: no Live Caption window found")
        } catch (e: Exception) {
            Log.w(TAG, "collapseLiveCaptionOverlay: failed (non-fatal)", e)
        }
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
