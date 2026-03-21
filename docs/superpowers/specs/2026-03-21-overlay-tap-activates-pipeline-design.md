# Overlay Tap Activates Pipeline & Toggle Card

**Date:** 2026-03-21
**Branch:** `feature/live-caption-scam-transcription`

## Problem

Currently, tapping the collapsed overlay bubble launches the app and navigates to `ScamCallScreen`. This is a wasted interaction — the user should be able to start the scam detection pipeline directly from the overlay without leaving their call screen. Once the pipeline is running, tapping the bubble should toggle the inner threat card instead of navigating away.

## Design

### Tap Behavior Matrix

| Pipeline State | Tap Target | Action |
|---|---|---|
| Not running (`sessionStatus == "idle"`) | Collapsed bubble | Emit `overlay_activate` → Dart starts pipeline |
| Running (`sessionStatus != "idle"`) | Collapsed bubble | Native toggles expanded card (no Dart round-trip) |
| Running | Expanded card | Native collapses card (unchanged) |

No tap ever navigates to `ScamCallScreen`. That navigation path is removed.

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
        sessionStatus == "idle" -> emitOverlayActivate()
        else -> if (isExpanded) collapse() else expand()
    }
}
```

When collapsed and idle → emit `overlay_activate` event to Dart.
When collapsed and pipeline running → toggle to expanded card.
When expanded → collapse (unchanged).

**New method `emitOverlayActivate()`:** Calls `ServiceBridge.instance.emitOverlayActivate()` to send the event through the existing EventChannel.

**Remove `launchApp()` method** (lines 655-660) — no longer needed.

### 2. `ServiceBridge.kt` — New event type

**File:** `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt`

Add public method:
```kotlin
fun emitOverlayActivate() {
    mainHandler.post {
        eventSink?.success(
            mapOf("type" to "overlay_activate")
        )
    }
}
```

This follows the same pattern as `emitCaptionText()` (line 262) and `emitShake()` (line 335) — post to main handler, emit through event sink.

### 3. `AppShell` — Handle new event, remove old navigation

**File:** `lib/app_shell.dart`

**In `_handlePlatformEvent()` (line 55):** Add case for `overlay_activate`:
```dart
case 'overlay_activate':
    debugPrint('AppShell: overlay_activate received');
    _handleOverlayActivate();
```

**New method `_handleOverlayActivate()`:** Same logic as `_handleCallShake()` (lines 129-143) — check `scamCallEnabled`, check no active session, then `_sessionManager.startLiveCallSession()`. No haptic feedback (tap already provides tactile response via the OS).

**Remove `_handleOverlayTap()`** (lines 175-190) and its `case 'overlay_tap'` in the switch (line 69).

### 4. No changes needed

- **`PlatformChannel`** — uses existing shared EventChannel, no new channels needed.
- **`ScamCallScreen`** — untouched; still reachable from within the app, just not from overlay tap.
- **Shake flow** — unchanged, remains as alternative activation method.
- **Icons** — deferred to a separate design.

## Testing

- **Tap idle bubble** → pipeline starts (verify `sessionStatus` transitions from idle → connecting → listening)
- **Tap collapsed bubble while listening** → card expands showing current threat level
- **Tap expanded card** → collapses back to circle
- **Tap idle bubble when `scamCallEnabled == false`** → no-op (same as shake guard)
- **Shake still works** → existing shake-to-activate unchanged
- **Call end** → overlay hides, session disposes (unchanged)
