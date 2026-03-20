package com.example.check_var

object SpeakerTranscriptEventPayload {
    fun partial(text: String): Map<String, String> {
        return mapOf(
            "type" to "speaker_test_partial",
            "text" to text,
        )
    }

    fun finalTranscript(text: String): Map<String, String> {
        return mapOf(
            "type" to "speaker_test_final",
            "text" to text,
        )
    }

    fun error(message: String): Map<String, String> {
        return mapOf(
            "type" to "speaker_test_error",
            "message" to message,
        )
    }
}
