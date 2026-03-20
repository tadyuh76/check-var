package com.example.check_var

import android.content.Context
import android.content.Intent

/**
 * Builds launch intents and event payloads for the speaker test flow.
 * Kept free of service state for unit testability.
 */
object SpeakerTestLaunch {

    const val REASON_KEY = "launch_reason"
    const val REASON_SPEAKER_TEST = "speaker_test_launch"

    /**
     * Builds an intent to bring MainActivity to the foreground
     * with the speaker_test_launch reason.
     */
    fun buildLaunchIntent(context: Context): Intent {
        val intent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra(REASON_KEY, REASON_SPEAKER_TEST)
        return intent
    }

    /**
     * Builds the event map sent to Flutter when a call state change
     * indicates the user can shake to activate scam detection.
     */
    fun buildCallActiveEvent(isActive: Boolean): Map<String, Any> {
        return mapOf(
            "type" to "call_state",
            "isActive" to isActive,
        )
    }

    /**
     * Builds a transcript event map for the Flutter event channel.
     */
    fun buildTranscriptEvent(text: String, isFinal: Boolean): Map<String, Any> {
        return mapOf(
            "type" to if (isFinal) "transcript_final" else "transcript_partial",
            "text" to text,
        )
    }

    /**
     * Builds an event map indicating the speech recognizer is ready
     * to capture the next utterance.
     */
    fun buildRecognizerReadyEvent(): Map<String, Any> {
        return mapOf("type" to "recognizer_ready")
    }
}
