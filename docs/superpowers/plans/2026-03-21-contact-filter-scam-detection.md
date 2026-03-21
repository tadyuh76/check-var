# Contact-Based Scam Detection Filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Filter scam call detection so it only activates for unknown callers, using the existing accessibility service to read the dialer screen during RINGING.

**Architecture:** New `CallerIdentityResolver` classifies dialer text as known-contact/unknown/undetermined. `CheckVarAccessibilityService` gets a new method to read the dialer window. `CallMonitorService` gates both event emission and overlay launch based on the cached caller type. All changes are in the Kotlin native layer — zero Flutter/Dart changes.

**Tech Stack:** Kotlin, Android Accessibility API, Android TelephonyManager

**Spec:** `docs/superpowers/specs/2026-03-21-contact-filter-scam-detection-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `android/app/src/main/kotlin/com/example/check_var/CallerIdentityResolver.kt` | Pure classification logic: phone regex, private patterns, resolve() |
| Modify | `android/app/src/main/kotlin/com/example/check_var/CheckVarAccessibilityService.kt` | Add `readDialerCallerInfo()` + `extractDialerTextFromNode()` |
| Modify | `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt` | Add `lastCallerType` cache + `cacheCallerType()` / `resetCallerType()` |
| Modify | `android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt` | RINGING handler + OFFHOOK gating + IDLE reset |
| Create | `android/app/src/test/kotlin/com/example/check_var/CallerIdentityResolverTest.kt` | Unit tests for all classification paths |

---

### Task 1: Create CallerIdentityResolver

**Files:**
- Create: `android/app/src/main/kotlin/com/example/check_var/CallerIdentityResolver.kt`
- Create: `android/app/src/test/kotlin/com/example/check_var/CallerIdentityResolverTest.kt`

- [ ] **Step 1: Create the test file with all classification test cases**

Create `android/app/src/test/kotlin/com/example/check_var/CallerIdentityResolverTest.kt`:

```kotlin
package com.example.check_var

import com.example.check_var.CallerIdentityResolver.CallerType
import org.junit.Assert.assertEquals
import org.junit.Test

class CallerIdentityResolverTest {

    // ── Null / blank → UNDETERMINED ──────────────────────────────
    @Test fun `null input returns UNDETERMINED`() {
        assertEquals(CallerType.UNDETERMINED, CallerIdentityResolver.resolve(null))
    }

    @Test fun `empty string returns UNDETERMINED`() {
        assertEquals(CallerType.UNDETERMINED, CallerIdentityResolver.resolve(""))
    }

    @Test fun `whitespace-only returns UNDETERMINED`() {
        assertEquals(CallerType.UNDETERMINED, CallerIdentityResolver.resolve("   "))
    }

    // ── Private caller patterns → UNKNOWN ────────────────────────
    @Test fun `english Private returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Private"))
    }

    @Test fun `english Unknown returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Unknown"))
    }

    @Test fun `english No Caller ID returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("No Caller ID"))
    }

    @Test fun `english Blocked returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Blocked"))
    }

    @Test fun `english Restricted returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Restricted"))
    }

    @Test fun `english Unavailable returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Unavailable"))
    }

    @Test fun `vietnamese Khong xac dinh returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Không xác định"))
    }

    @Test fun `vietnamese Rieng tu returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Riêng tư"))
    }

    @Test fun `case insensitive matching`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("PRIVATE"))
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("unknown"))
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("không xác định"))
    }

    @Test fun `substring matching catches OEM variants`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Người gọi không xác định"))
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Số riêng tư"))
    }

    // ── Phone number patterns → UNKNOWN ──────────────────────────
    @Test fun `international number returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("+62 812 345 6789"))
    }

    @Test fun `local number with dashes returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("0812-345-6789"))
    }

    @Test fun `number with parens returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("(021) 345-6789"))
    }

    @Test fun `short emergency number returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("113"))
    }

    @Test fun `digits only returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("08123456789"))
    }

    // ── Contact names → KNOWN_CONTACT ────────────────────────────
    @Test fun `english name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Mom"))
    }

    @Test fun `full name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("John Smith"))
    }

    @Test fun `vietnamese name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Nguyễn Văn A"))
    }

    @Test fun `name with emoji returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Mom ❤️"))
    }

    @Test fun `business name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Pizza Hut Delivery"))
    }
}
```

- [ ] **Step 2: Verify test directory exists, create if needed**

Run: `ls android/app/src/test/kotlin/com/example/check_var/ 2>/dev/null || mkdir -p android/app/src/test/kotlin/com/example/check_var/`

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd android && ./gradlew test --tests "com.example.check_var.CallerIdentityResolverTest" 2>&1 | tail -20`
Expected: Compilation error — `CallerIdentityResolver` does not exist yet.

- [ ] **Step 4: Create CallerIdentityResolver.kt**

Create `android/app/src/main/kotlin/com/example/check_var/CallerIdentityResolver.kt`:

```kotlin
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd android && ./gradlew test --tests "com.example.check_var.CallerIdentityResolverTest" 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/CallerIdentityResolver.kt \
       android/app/src/test/kotlin/com/example/check_var/CallerIdentityResolverTest.kt
git commit -m "feat: add CallerIdentityResolver with unit tests

Classifies dialer text as known-contact/unknown/undetermined.
Supports EN + VI private caller patterns and phone number regex."
```

---

### Task 2: Add readDialerCallerInfo() to CheckVarAccessibilityService

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/CheckVarAccessibilityService.kt`

- [ ] **Step 1: Add known dialer packages constant**

Add to the `companion object` block (after `IGNORED_PACKAGES`):

```kotlin
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
```

- [ ] **Step 2: Add extractDialerTextFromNode() method**

Add after the existing `extractTextFromNode()` method. This variant does NOT skip buttons (OEM dialers may render caller name in button widgets). Only skips `ImageView`.

```kotlin
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
```

- [ ] **Step 3: Add readDialerCallerInfo() method**

Add as a public method after `resetCaptionState()`:

```kotlin
/**
 * Read the caller identity text from the dialer screen.
 *
 * Searches accessibility windows for a known dialer package, then falls
 * back to any TYPE_PHONE window.  Retries up to [DIALER_READ_MAX_RETRIES]
 * times with [DIALER_READ_RETRY_DELAY_MS] delays to handle the case where
 * the dialer UI hasn't rendered yet when RINGING fires.
 *
 * **WARNING:** This method uses Thread.sleep() for retries and must NOT be called
 * from the main thread. It is designed to run on CallMonitorService's background
 * executor thread.
 *
 * @return The caller text shown on the dialer, or null if not found.
 */
fun readDialerCallerInfo(): String? {
    require(android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) {
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

    // Tier 2: any TYPE_PHONE window
    for (window in allWindows) {
        if (window.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_PHONE) {
            val root = window.root ?: continue
            val text = extractDialerTextFromNode(root)
            root.recycle()
            if (text.isNotBlank()) return text
        }
    }

    return null
}
```

- [ ] **Step 4: Add required import**

Verify the file already imports `android.view.accessibility.AccessibilityNodeInfo`. No new imports needed — `AccessibilityWindowInfo` is accessed via fully qualified name inline.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/CheckVarAccessibilityService.kt
git commit -m "feat: add readDialerCallerInfo() to accessibility service

Two-tier dialer window discovery (known packages + TYPE_PHONE fallback).
Separate extractDialerTextFromNode() that doesn't skip buttons.
Retry up to 3x with 200ms delays for dialer rendering race."
```

---

### Task 3: Add caller type cache to ServiceBridge

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt`

- [ ] **Step 1: Add lastCallerType field**

Add to the `// ── Scam-call state ──` section (after `private var isCallActive: Boolean = false`):

```kotlin
/** Cached caller identity from the most recent RINGING event. */
var lastCallerType: CallerIdentityResolver.CallerType = CallerIdentityResolver.CallerType.UNDETERMINED
    private set
```

- [ ] **Step 2: Add cacheCallerType() and resetCallerType() methods**

Add after the `emitCaptionText()` method, before `// ── Scam-call service orchestration ──`:

```kotlin
// ── Caller identity cache ────────────────────────────────────────

fun cacheCallerType(type: CallerIdentityResolver.CallerType) {
    lastCallerType = type
    Log.d(TAG, "cacheCallerType: $type")
}

fun resetCallerType() {
    lastCallerType = CallerIdentityResolver.CallerType.UNDETERMINED
    Log.d(TAG, "resetCallerType: reset to UNDETERMINED")
}
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt
git commit -m "feat: add caller type cache to ServiceBridge

Exposes lastCallerType, cacheCallerType(), resetCallerType()
for use by CallMonitorService gating logic."
```

---

### Task 4: Wire up gating in CallMonitorService

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt`

- [ ] **Step 1: Add RINGING handler to handleCallState()**

Replace the current `handleCallState()` method (lines 75-92) with the gated version:

```kotlin
private fun handleCallState(state: Int) {
    val isActive = CallMonitorPolicy.isCallActive(state)
    android.util.Log.d("CallMonitor", "handleCallState: state=$state, isActive=$isActive")

    // ── RINGING: read dialer to identify caller ──────────────
    if (state == android.telephony.TelephonyManager.CALL_STATE_RINGING) {
        val a11y = CheckVarAccessibilityService.instance
        val dialerText = a11y?.readDialerCallerInfo()
        val callerType = CallerIdentityResolver.resolve(dialerText)
        ServiceBridge.instance.cacheCallerType(callerType)
        android.util.Log.d("CallMonitor", "RINGING: dialerText='${dialerText?.take(40)}', callerType=$callerType")
    }

    // ── OFFHOOK: gate on caller type ─────────────────────────
    if (isActive) {
        val callerType = ServiceBridge.instance.lastCallerType
        if (callerType == CallerIdentityResolver.CallerType.KNOWN_CONTACT) {
            android.util.Log.d("CallMonitor", "OFFHOOK: known contact — suppressing scam detection")
            return
        }

        val event = EventPayloadBuilder.buildCallActiveEvent(isActive)
        onCallStateChanged?.invoke(event)

        val overlayIntent = Intent(this, OverlayBubbleService::class.java)
        startService(overlayIntent)
    } else {
        val event = EventPayloadBuilder.buildCallActiveEvent(isActive)
        onCallStateChanged?.invoke(event)
    }

    // ── IDLE: reset caller type cache + hide overlay ────────
    // IMPORTANT: Only reset caller type on IDLE, not RINGING.
    // shouldHideOverlay() returns true for BOTH IDLE and RINGING,
    // but resetting on RINGING would wipe the cache we just set above,
    // making the feature silently never work.
    if (state == android.telephony.TelephonyManager.CALL_STATE_IDLE) {
        ServiceBridge.instance.resetCallerType()
    }
    if (CallMonitorPolicy.shouldHideOverlay(state)) {
        val overlayIntent = Intent(this, OverlayBubbleService::class.java)
        stopService(overlayIntent)
    }
}
```

Key changes from original:
- RINGING: calls `readDialerCallerInfo()` → `CallerIdentityResolver.resolve()` → caches result
- OFFHOOK (`isActive`): checks `lastCallerType` — if `KNOWN_CONTACT`, returns early (no event, no overlay, `isCallActive` stays false in ServiceBridge)
- Non-active states: still emit event (e.g., `isActive=false` on IDLE needs to reach Flutter for cleanup)
- IDLE: resets caller type cache (separated from `shouldHideOverlay` — see comment above)
- RINGING/IDLE: still hides overlay via `shouldHideOverlay` (unchanged)

**Note on spec deviation:** The spec says to also update the `ServiceBridge.startCallMonitor()` callback lambda to gate on `lastCallerType`. This plan gates solely in `CallMonitorService.handleCallState()` instead — since it returns early before calling `onCallStateChanged?.invoke(event)`, the ServiceBridge callback never fires for known contacts. This is an intentional simplification: a single gate point is cleaner and less error-prone than redundant checks in two places.

- [ ] **Step 2: Verify the app compiles**

Run: `cd android && ./gradlew compileDebugKotlin 2>&1 | tail -20`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Run all existing tests to check for regressions**

Run: `cd android && ./gradlew test 2>&1 | tail -30`
Expected: All tests pass (including the new CallerIdentityResolverTest).

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt
git commit -m "feat: gate scam detection on caller identity

RINGING reads dialer via a11y service, classifies caller.
OFFHOOK suppresses overlay + event for known contacts.
IDLE resets caller type cache."
```

---

### Task 5: Final verification

- [ ] **Step 1: Full build check**

Run: `cd android && ./gradlew assembleDebug 2>&1 | tail -20`
Expected: BUILD SUCCESSFUL

- [ ] **Step 2: Run all tests**

Run: `cd android && ./gradlew test 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 3: Review all changes**

Run: `git diff HEAD~4 --stat` to verify only the expected files were touched:
- 1 new: `CallerIdentityResolver.kt`
- 1 new: `CallerIdentityResolverTest.kt`
- 3 modified: `CheckVarAccessibilityService.kt`, `ServiceBridge.kt`, `CallMonitorService.kt`

- [ ] **Step 4: Done — ready for manual device testing**

The feature is complete at the code level. Manual testing on a real device is required to verify:
- Known contact → overlay does NOT appear
- Unknown number → overlay appears
- Private/hidden number → overlay appears
- Different OEM dialers → window discovery works
