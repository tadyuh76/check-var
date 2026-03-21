# Overlay Bubble Call Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the overlay bubble automatically when a call starts (standby indicator), start scam analysis on shake without leaving the call, and auto-cleanup when the call ends.

**Architecture:** Native `CallMonitorService` shows/hides the overlay bubble based on call state. On shake, Dart-side `ScamCallSessionManager` starts a background analysis session (no navigation). The `overlay_tap` event triggers navigation to `ScamCallScreen` with the existing controller. Call end triggers full cleanup: stop caption capture, stop analysis, hide bubble, dispose controller.

**Tech Stack:** Kotlin (Android native services), Dart/Flutter (state management, navigation)

---

### Task 1: Native — Auto-show overlay on call start, don't foreground on shake

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt:75-86`
- Modify: `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt:286-290`

- [ ] **Step 1: Show overlay bubble when call becomes active**

In `CallMonitorService.handleCallState()`, add overlay show logic before the existing hide logic:

```kotlin
private fun handleCallState(state: Int) {
    val isActive = CallMonitorPolicy.isCallActive(state)
    android.util.Log.d("CallMonitor", "handleCallState: state=$state, isActive=$isActive")

    val event = EventPayloadBuilder.buildCallActiveEvent(isActive)
    onCallStateChanged?.invoke(event)

    // Show standby overlay as soon as call is active.
    if (isActive) {
        val overlayIntent = Intent(this, OverlayBubbleService::class.java)
        startService(overlayIntent)
    }

    if (CallMonitorPolicy.shouldHideOverlay(state)) {
        val overlayIntent = Intent(this, OverlayBubbleService::class.java)
        stopService(overlayIntent)
    }
}
```

- [ ] **Step 2: Remove `bringAppToForeground()` from call shake branch**

In `ServiceBridge.kt`, the shake callback for call mode currently brings the app to foreground. Remove that — we want the user to stay on the call screen:

```kotlin
callDetectionEnabled && isCallActive -> {
    Log.d(TAG, "SHAKE CALLBACK → emitting CALL shake")
    emitShake("call")
    // Do NOT call bringAppToForeground() — user stays on call screen.
    // The overlay bubble is already visible; Dart side starts analysis in background.
}
```

- [ ] **Step 3: Build and verify no compilation errors**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt \
        android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt
git commit -m "feat: auto-show overlay on call start, remove foreground on shake"
```

---

### Task 2: Dart — Add `detachController()` to ScamCallSessionManager

**Files:**
- Modify: `lib/features/scam_call/scam_call_session_manager.dart`

When the user taps the overlay bubble, we navigate to `ScamCallScreen` and hand it the running controller. The session manager must release ownership without stopping/disposing so the screen can manage the controller's remaining lifecycle.

- [ ] **Step 1: Add `detachController()` method**

Add after the `hasActiveSession` getter (around line 43):

```dart
/// Removes the controller from management without stopping or disposing it.
/// The caller takes ownership and is responsible for disposal.
ScamCallController? detachController() {
  final controller = _controller;
  _controller = null;
  _sessionKind = ScamCallSessionKind.idle;
  notifyListeners();
  return controller;
}
```

- [ ] **Step 2: Verify compilation**

Run: `flutter analyze --no-fatal-infos 2>&1 | grep -E "error|Error" | head -5`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/scam_call/scam_call_session_manager.dart
git commit -m "feat: add detachController to ScamCallSessionManager"
```

---

### Task 3: Dart — Rewire AppShell for background scam call sessions

**Files:**
- Modify: `lib/app_shell.dart`

This is the main wiring change. AppShell needs to:
1. Hold a `ScamCallSessionManager` instance
2. Listen for `call_state` and `overlay_tap` events from the platform channel
3. On shake during call: start background session (no navigation)
4. On overlay tap: navigate to ScamCallScreen with existing controller
5. On call end: stop session + stop caption capture

- [ ] **Step 1: Add imports and state**

Add imports at the top:

```dart
import 'core/platform_channel.dart' as core_channel;
import 'features/scam_call/scam_call_session_manager.dart';
```

Add to `_AppShellState` fields:

```dart
late final ScamCallSessionManager _sessionManager;
StreamSubscription<Map<String, dynamic>>? _eventSub;
```

- [ ] **Step 2: Initialize session manager and event subscription in initState**

Replace the current `initState`:

```dart
@override
void initState() {
  super.initState();
  _sessionManager = ScamCallSessionManager();
  ShakeService.instance.startListening();
  _shakeSub = ShakeService.instance.onShake.listen(_handleShake);
  _eventSub = core_channel.PlatformChannel.shakeEvents.listen(_handlePlatformEvent);
}
```

- [ ] **Step 3: Add dispose cleanup**

Replace the current `dispose`:

```dart
@override
void dispose() {
  _shakeSub?.cancel();
  _eventSub?.cancel();
  _sessionManager.dispose();
  super.dispose();
}
```

- [ ] **Step 4: Add `_handlePlatformEvent` method**

Add after `dispose()`:

```dart
void _handlePlatformEvent(Map<String, dynamic> event) {
  final type = event['type'] as String?;
  switch (type) {
    case 'call_state':
      final isActive = event['isActive'] as bool? ?? false;
      debugPrint('AppShell: call_state isActive=$isActive');
      if (!isActive) {
        _onCallEnded();
      }
    case 'overlay_tap':
      debugPrint('AppShell: overlay_tap received');
      _handleOverlayTap();
    default:
      break; // shake, caption_text, tts_done handled elsewhere
  }
}
```

- [ ] **Step 5: Add `_onCallEnded` method**

```dart
Future<void> _onCallEnded() async {
  // Stop caption capture immediately for optimization,
  // regardless of who owns the controller.
  try {
    await core_channel.PlatformChannel.stopCaptionCapture();
  } catch (_) {}

  // If the session manager still owns the controller, full cleanup.
  if (_sessionManager.hasActiveSession) {
    await _sessionManager.stopSession();
  }
}
```

- [ ] **Step 6: Add `_handleOverlayTap` method**

```dart
void _handleOverlayTap() {
  final controller = _sessionManager.detachController();
  if (controller == null) return;
  if (!mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ScamCallScreen(
        controller: controller,
        modeLabel: 'Live Caption',
        disposeController: true,
        manageSessionLifecycle: true,
      ),
    ),
  );
}
```

- [ ] **Step 7: Rewrite `_handleCallShake` to start background session**

Replace the current `_handleCallShake` method:

```dart
Future<void> _handleCallShake() async {
  final homeState = context.read<HomeStateProvider>();
  if (!homeState.scamCallEnabled) return;
  if (_sessionManager.hasActiveSession) return; // already running

  HapticFeedback.heavyImpact();
  debugPrint('AppShell: starting background scam call session');
  await _sessionManager.startLiveCallSession();
}
```

- [ ] **Step 8: Verify compilation**

Run: `flutter analyze --no-fatal-infos 2>&1 | grep -E "error|Error" | head -5`
Expected: No errors

- [ ] **Step 9: Commit**

```bash
git add lib/app_shell.dart
git commit -m "feat: rewire AppShell for background scam call sessions"
```

---

### Task 4: Integration verification

- [ ] **Step 1: Full build**

Run: `flutter build apk --debug`
Expected: Build succeeds

- [ ] **Step 2: Manual test checklist**

Deploy to device and verify:

1. Enable scam call detection on HomeScreen
2. Receive/make a phone call → **overlay bubble appears in standby (idle) mode**
3. Shake 3 times during call → **bubble transitions to "listening", no app foreground**
4. TTS or caller speaks → **Live Caption transcribes, bubble updates with threat level**
5. Tap the bubble → **app opens with ScamCallScreen showing transcript + analysis**
6. End the call → **caption capture stops, bubble hides, session cleaned up**
7. Verify news-check shake still works when not in a call

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: overlay bubble auto-shows on call, background analysis on shake"
```
