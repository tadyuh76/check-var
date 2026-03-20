package com.example.check_var

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/**
 * Wraps Android's on-device [SpeechRecognizer] and emits partial/final
 * transcript events via [onEvent] for bridging to Flutter.
 *
 * The recognizer automatically restarts after each final result to keep
 * listening continuously during the call, until [stop] is called.
 */
class SpeechRecognizerManager(
    private val context: Context,
    private val language: String = "vi-VN",
    private val onEvent: (Map<String, Any>) -> Unit,
) {
    companion object {
        private const val TAG = "SpeechRecMgr"
        /** Delay before restarting after an error to let the audio system settle. */
        private const val RESTART_DELAY_MS = 500L
    }

    private var recognizer: SpeechRecognizer? = null
    private var isRunning = false
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Token for the pending delayed restart so we can cancel duplicates. */
    private val restartRunnable = Runnable {
        if (isRunning) recreateAndStart()
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "onReadyForSpeech")
            onEvent(SpeakerTestLaunch.buildRecognizerReadyEvent())
        }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onPartialResults(partialResults: Bundle?) {
            val texts = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = texts?.firstOrNull() ?: return

            onEvent(SpeakerTestLaunch.buildTranscriptEvent(text, isFinal = false))
        }

        override fun onResults(results: Bundle?) {
            val texts = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = texts?.firstOrNull() ?: return

            Log.d(TAG, "onResults: $text")
            onEvent(SpeakerTestLaunch.buildTranscriptEvent(text, isFinal = true))

            // Restart immediately on the existing recognizer so there is no
            // gap in listening. Full recreate is only needed for error recovery.
            if (isRunning) {
                startRecognizing()
            }
        }

        override fun onError(error: Int) {
            Log.w(TAG, "onError: $error")
            // Schedule ONE restart. Cancel any previously pending restart first
            // so rapid-fire errors (e.g. 7 then 11) don't create competing
            // recognizer instances.
            if (isRunning) {
                scheduleRestart()
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    fun start() {
        if (isRunning) return
        isRunning = true
        recreateAndStart()
    }

    fun stop() {
        isRunning = false
        mainHandler.removeCallbacks(restartRunnable)
        destroyRecognizer()
    }

    /**
     * Cancel any pending restart and schedule exactly one new one.
     */
    private fun scheduleRestart() {
        mainHandler.removeCallbacks(restartRunnable)
        mainHandler.postDelayed(restartRunnable, RESTART_DELAY_MS)
    }

    /**
     * Destroys the current recognizer (if any), creates a fresh one with
     * the listener attached, and starts listening.
     */
    private fun recreateAndStart() {
        mainHandler.removeCallbacks(restartRunnable)
        destroyRecognizer()
        try {
            recognizer = SpeechRecognizer.createSpeechRecognizer(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create recognizer", e)
            return
        }
        if (recognizer == null) return

        recognizer?.setRecognitionListener(listener)
        startRecognizing()
    }

    private fun startRecognizing() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
        }
        try {
            recognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "startListening failed", e)
            if (isRunning) {
                scheduleRestart()
            }
        }
    }

    private fun destroyRecognizer() {
        try {
            recognizer?.stopListening()
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {
            // Ignore cleanup errors
        }
        recognizer = null
    }
}
