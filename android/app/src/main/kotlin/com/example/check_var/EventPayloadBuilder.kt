package com.example.check_var

/**
 * Builds event payloads sent to Flutter via the shared EventChannel.
 */
object EventPayloadBuilder {

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
}
