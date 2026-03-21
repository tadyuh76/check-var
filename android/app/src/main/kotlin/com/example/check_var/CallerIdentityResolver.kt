package com.example.check_var

/**
 * Classifies dialer-screen text to determine whether the caller
 * is a known contact, an unknown number, or undetermined.
 *
 * Used to gate scam-call detection: known contacts are suppressed.
 */
object CallerIdentityResolver {

    enum class CallerType { KNOWN_CONTACT, UNKNOWN, UNDETERMINED }

    /**
     * Private/hidden caller labels — matched as case-insensitive substrings
     * to catch OEM variations (e.g. "Người gọi không xác định").
     *
     * Sources:
     *  EN: standard Android Telecom strings
     *  VI: AOSP packages/services/Telecomm/res/values-vi/strings.xml
     *      and frameworks/base/core/res/res/values-vi/strings.xml
     */
    private val PRIVATE_CALLER_PATTERNS = listOf(
        // English
        "private",
        "unknown",
        "no caller id",
        "blocked",
        "restricted",
        "unavailable",
        // Vietnamese (AOSP-verified)
        "không xác định",
        "riêng tư",
    )

    /**
     * Matches strings that are primarily digits with common phone separators.
     * Minimum 3 chars to cover short-codes and emergency numbers (113, 114, 115).
     */
    private val PHONE_NUMBER_REGEX = Regex(
        "^\\s*[+]?[\\d\\s\\-().]{3,}\\s*$"
    )

    /**
     * Classify dialer text as known contact, unknown caller, or undetermined.
     *
     * Logic:
     *  1. null / blank → UNDETERMINED (fail open)
     *  2. matches private caller pattern → UNKNOWN
     *  3. matches phone number regex → UNKNOWN
     *  4. otherwise → KNOWN_CONTACT (dialer shows a name)
     */
    fun resolve(dialerText: String?): CallerType {
        if (dialerText.isNullOrBlank()) return CallerType.UNDETERMINED

        val lower = dialerText.lowercase()

        for (pattern in PRIVATE_CALLER_PATTERNS) {
            if (lower.contains(pattern)) return CallerType.UNKNOWN
        }

        if (PHONE_NUMBER_REGEX.matches(dialerText)) return CallerType.UNKNOWN

        return CallerType.KNOWN_CONTACT
    }
}
