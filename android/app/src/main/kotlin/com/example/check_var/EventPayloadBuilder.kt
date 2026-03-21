package com.example.check_var

object EventPayloadBuilder {

    fun buildCallActiveEvent(
        isActive: Boolean,
        callerDisplayText: String? = null,
    ): Map<String, Any?> {
        return mapOf(
            "type" to "call_state",
            "isActive" to isActive,
            "callerDisplayText" to callerDisplayText,
        )
    }
}
