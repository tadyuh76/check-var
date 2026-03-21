# Contact-Based Scam Detection Filter

**Date:** 2026-03-21
**Branch:** feature/live-caption-scam-transcription
**Status:** Draft

## Problem

The scam call detection overlay currently activates for every incoming call, including calls from contacts already in the user's phone book. This is unnecessary and potentially annoying — users don't need scam protection when their mom calls.

## Solution

Use the existing Accessibility Service to read the dialer screen during the `RINGING` phase. If the dialer shows a contact name (known caller), suppress scam detection entirely. If it shows a raw phone number or a private/unknown label, proceed with scam detection as normal.

**Key principle:** Zero new permissions. The accessibility service already has `flagRetrieveInteractiveWindows` and `typeAllMask`, giving it full access to read the dialer's UI.

## Design Decisions

1. **Gate at the native level, not Flutter.** When the caller is known, the `call_state` event is never emitted to the Dart side. No overlay, no shake listener, no session — zero overhead.

2. **Read during RINGING, act on OFFHOOK.** The dialer shows caller info during `RINGING`. We read it then and cache the result. When `OFFHOOK` fires (user answered), we check the cached result to decide whether to activate scam detection.

3. **Fail open.** If the accessibility service can't read the dialer (timing issue, unfamiliar OEM dialer, empty text), treat the caller as unknown and activate scam detection. Better a false overlay than a missed scam.

4. **Private/hidden callers are treated as unknown.** "Không xác định", "Riêng tư", "Private", "Unknown", "Restricted", etc. all trigger scam detection.

## Architecture

### New File: `CallerIdentityResolver.kt`

Single-responsibility utility class with:

```kotlin
object CallerIdentityResolver {
    enum class CallerType { KNOWN_CONTACT, UNKNOWN, UNDETERMINED }

    fun resolve(dialerText: String?): CallerType
}
```

**Classification logic in `resolve()`:**

1. If `dialerText` is null or blank → `UNDETERMINED`
2. If text matches a private caller pattern (case-insensitive, substring) → `UNKNOWN`
3. If text matches a phone number regex → `UNKNOWN`
4. Otherwise → `KNOWN_CONTACT`

**Private caller patterns (multi-locale):**

| Language | Patterns |
|----------|----------|
| English  | "Private", "Unknown", "No Caller ID", "Blocked", "Restricted", "Unavailable" |
| Vietnamese | "Không xác định", "Riêng tư" |

Matched as case-insensitive substrings to catch OEM variations like "Người gọi không xác định" or "Số riêng tư".

Source: Verified against AOSP `packages/services/Telecomm/res/values-vi/strings.xml` and `frameworks/base/core/res/res/values-vi/strings.xml`.

**Phone number regex:**

```regex
^[\s]*[+]?[\d\s\-().]{6,}[\s]*$
```

Matches strings primarily composed of digits with common separators (`+`, `-`, `()`, spaces). Minimum 6 characters to avoid false matches.

### Modified: `CheckVarAccessibilityService.kt`

New public method:

```kotlin
fun readDialerCallerInfo(): String?
```

**Dialer window discovery — two tiers:**

1. **Known packages** (fast path):
   - `com.google.android.dialer` (Pixel, stock Android)
   - `com.samsung.android.dialer` (Samsung)
   - `com.android.phone` (AOSP fallback)
   - `com.miui.phone` (Xiaomi)
   - `com.oneplus.dialer` (OnePlus)

2. **Heuristic fallback**: If no known package found, look for any window with type `TYPE_PHONE`.

Once the dialer window is found, extract text from its node tree using the existing `extractTextFromNode()` method (reused from Live Caption extraction). Returns the extracted text or null if nothing found.

### Modified: `CallMonitorService.kt`

```
handleCallState(state):
  if RINGING:
    → ask CheckVarAccessibilityService.readDialerCallerInfo()
    → pass result to CallerIdentityResolver.resolve()
    → cache result via ServiceBridge.cacheCallerType()

  if OFFHOOK:
    → check ServiceBridge.lastCallerType
    → if KNOWN_CONTACT: skip (don't emit event, don't show overlay)
    → if UNKNOWN or UNDETERMINED: proceed with current behavior

  if IDLE:
    → ServiceBridge.resetCallerType()
    → proceed with current behavior (hide overlay)
```

### Modified: `ServiceBridge.kt`

New fields and methods:

```kotlin
var lastCallerType: CallerIdentityResolver.CallerType = UNDETERMINED
    private set

fun cacheCallerType(type: CallerIdentityResolver.CallerType)
fun resetCallerType()  // called on IDLE
```

The `startCallMonitor()` callback is updated: when it receives an `isActive=true` event and `lastCallerType == KNOWN_CONTACT`, it does NOT emit the event to Flutter and does NOT start the overlay.

### Unchanged Files

- **All Flutter/Dart files** — zero changes. The gate is entirely in the native layer.
- **`accessibility_service_config.xml`** — already configured with `typeAllMask` and `flagRetrieveInteractiveWindows`.
- **`AndroidManifest.xml`** — no new permissions required.
- **`EventPayloadBuilder.kt`** — no changes; we simply don't call it for known contacts.

## Event Flow

```
RINGING fires
    ↓
CallMonitorService.handleCallState(RINGING)
    ↓
CheckVarAccessibilityService.readDialerCallerInfo() → "Mom" / "+62 812..." / "Không xác định" / null
    ↓
CallerIdentityResolver.resolve(text) → KNOWN_CONTACT / UNKNOWN / UNDETERMINED
    ↓
ServiceBridge.cacheCallerType(result)
    ↓
(user answers phone)
    ↓
OFFHOOK fires
    ↓
CallMonitorService.handleCallState(OFFHOOK)
    ↓
ServiceBridge checks lastCallerType
    ├── KNOWN_CONTACT → suppress: no overlay, no event to Flutter
    └── UNKNOWN / UNDETERMINED → current behavior: emit event, show overlay
    ↓
(call ends)
    ↓
IDLE fires → ServiceBridge.resetCallerType()
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No RINGING before OFFHOOK (VoIP, some carriers) | `lastCallerType` is `UNDETERMINED` → fail open → scam detection activates |
| Private/hidden number ("Không xác định", "Private") | Matches private pattern → `UNKNOWN` → scam detection activates |
| Dialer window not found (unfamiliar OEM) | `readDialerCallerInfo()` returns null → `UNDETERMINED` → fail open |
| Contact named with digits ("08123456") | Matches phone regex → classified as `UNKNOWN` → false positive (acceptable, degenerate case) |
| Multiple RINGING events | Subsequent reads overwrite cache — last read wins (correct, captures most up-to-date info) |
| User rejects call | `IDLE` fires → `resetCallerType()` → clean state for next call |

## Testing Strategy

**Unit tests:**
- `CallerIdentityResolver.resolve()` — pure function, test all classification paths:
  - Phone numbers (international, local, with various separators)
  - Contact names (English, Vietnamese, mixed)
  - Private caller patterns (all English + Vietnamese variants, substring matching)
  - Edge cases: empty, null, whitespace-only, very long strings

**Manual device testing:**
- Known contact calling → overlay does NOT appear
- Unknown number calling → overlay appears as before
- Private/hidden number → overlay appears
- Different dialer apps (stock, Samsung, Xiaomi) → verify window discovery
- Call without RINGING phase → verify fail-open behavior
