# Overlay Tap Activates Pipeline & Toggle Card

**Date:** 2026-03-21
**Branch:** `feature/live-caption-scam-transcription`

## Problem

Currently, tapping the collapsed overlay bubble launches the app and navigates to `ScamCallScreen`. This is a wasted interaction — the user should be able to start the scam detection pipeline directly from the overlay without leaving their call screen. Once the pipeline is running, tapping the bubble should toggle the inner threat card instead of navigating away.

## Design

### Tap Behavior Matrix

| Pipeline State | Tap Target | Action |
|---|---|---|
| Not running (`idle` or `connecting`) | Collapsed bubble | Emit `overlay_activate` → Dart starts pipeline (guarded by session manager — no-op if already starting) |
| Running (`listening`, `analyzing`, `error`, `reconnecting`) | Collapsed bubble | Native toggles expanded card (no Dart round-trip) |
| Any | Expanded card | Native collapses card (unchanged) |

- No tap ever navigates to `ScamCallScreen`. That navigation path is removed.
- `connecting` is grouped with `idle` because the card has no useful content yet during connection setup. The Dart-side guard (`_sessionManager.hasActiveSession`) prevents duplicate pipeline starts.
- `error` and `reconnecting` are grouped with running states — tapping expands the card to show the current (possibly stale) status. This is intentional: the user can see the error/reconnecting state rather than being left with no feedback.

### Approach: Native-Only Tap Routing

Native already tracks `sessionStatus` via `OverlayBubbleService.applyStatus()`. The collapsed bubble's tap handler branches on this value locally — no Dart round-trip needed for the expand/collapse toggle.

## Changes

### 1. `OverlayBubbleService.kt` — Tap handler rewrite

**File:** `android/app/src/main/kotlin/com/example/check_var/OverlayBubbleService.kt`

**Current behavior (line 646):**
```kotlin
if (!moved) {
    if (isExpanded) collapse() else launchApp()
}
```

**New behavior:**
```kotlin
if (!moved) {
    when {
        isExpanded -> collapse()
        sessionStatus == "idle" || sessionStatus == "connecting" -> emitOverlayActivate()
        else -> expand()  // collapsed + pipeline running → show card
    }
}
```

Three clean branches matching the three rows of the tap matrix:
- Expanded → collapse
- Idle/connecting → emit activation event to Dart
- Otherwise (collapsed, pipeline running) → expand card

**New method `emitOverlayActivate()`:** Calls `ServiceBridge.instance.emitOverlayActivate()` to send the event through the existing EventChannel. Requires adding an import of `ServiceBridge` in `OverlayBubbleService.kt`.

**Remove `launchApp()` method** (lines 655-660) — no longer needed.

### 2. `ServiceBridge.kt` — New event type

**File:** `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt`

Add public method:
```kotlin
fun emitOverlayActivate() {
    Log.d(TAG, "emitOverlayActivate: eventSink=${eventSink != null}")
    mainHandler.post {
        eventSink?.success(
            mapOf("type" to "overlay_activate")
        )
    }
}
```

Follows the same pattern as `emitCaptionText()` (line 262) — post to main handler, emit through event sink, with debug logging.

**Dead code cleanup:** With `launchApp()` removed, the following become dead code and should be removed:
- `emitAppAction()` (line 371-378)
- `handleAppAction()` (line 345-351)
- `flushPendingAppAction()` (line 380-384)
- `pendingAppAction` field (line 35)

### 3. `AppShell` — Handle new event, remove old navigation

**File:** `lib/app_shell.dart`

**In `_handlePlatformEvent()` (line 55):** Add case for `overlay_activate`:
```dart
case 'overlay_activate':
    debugPrint('AppShell: overlay_activate received');
    _handleOverlayActivate();
```

**New method `_handleOverlayActivate()`:** Same logic as `_handleCallShake()` (lines 129-143) — check `scamCallEnabled`, check no active session, then `_sessionManager.startLiveCallSession()`. No haptic feedback (tap already provides tactile response via the OS). Consider extracting the shared guard logic (`scamCallEnabled` + `hasActiveSession` checks) into a private helper shared with `_handleCallShake()` to avoid duplication.

**Remove `_handleOverlayTap()`** (lines 175-190) and its `case 'overlay_tap'` in the switch (line 69).

### 4. No changes needed

- **`PlatformChannel`** — uses existing shared EventChannel, no new channels needed.
- **`ScamCallScreen`** — untouched; still reachable from within the app, just not from overlay tap.
- **Shake flow** — unchanged, remains as alternative activation method.
- **Icons** — deferred to a separate design.

### 5. Note on superseded behavior

This spec supersedes Task 3 Step 6 of the `overlay-bubble-call-lifecycle` plan (`docs/superpowers/plans/2026-03-21-overlay-bubble-call-lifecycle.md`), which described `overlay_tap` navigating to `ScamCallScreen`.

## Race Conditions

**Double-tap before status update:** User taps idle bubble, then taps again before native receives the `connecting` status update from Dart. Native emits a second `overlay_activate`. This is safe — Dart's `_sessionManager.hasActiveSession` guard prevents a duplicate `startLiveCallSession()` call. No native-side mitigation needed.

## Testing

- **Tap idle bubble** → pipeline starts (verify `sessionStatus` transitions from idle → connecting → listening)
- **Tap collapsed bubble while listening** → card expands showing current threat level
- **Tap expanded card** → collapses back to circle
- **Tap idle bubble when `scamCallEnabled == false`** → no-op (same as shake guard)
- **Shake still works** → existing shake-to-activate unchanged
- **Call end** → overlay hides, session disposes (unchanged)
- **Double-tap idle bubble rapidly** → only one session starts (Dart guard)
- **Tap during `connecting`** → no-op (grouped with idle, session already starting)
- **Tap during `error`/`reconnecting`** → expands card showing current degraded status
- **`overlay_activate` when `eventSink` is null** → no-op (null-safe `eventSink?.success()`)
- **Verify `launchApp()` removal** — grep for references to ensure no other caller
