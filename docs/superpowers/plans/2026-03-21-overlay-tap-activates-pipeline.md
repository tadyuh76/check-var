# Overlay Tap Activates Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the overlay bubble so tapping it starts the scam detection pipeline (when idle) or toggles the threat card (when running), removing the navigate-to-app behavior entirely.

**Architecture:** Native Android (`OverlayBubbleService`) routes taps locally based on `sessionStatus` — emit `overlay_activate` event to Dart when idle, or expand/collapse the card when running. Dart (`AppShell`) handles the new event identically to shake-to-activate. All dead code from the old `overlay_tap` → navigate path is removed across 5 files.

**Tech Stack:** Kotlin (Android native overlay), Dart/Flutter (event handling)

**Spec:** `docs/superpowers/specs/2026-03-21-overlay-tap-activates-pipeline-design.md`

---

### Task 1: Add `emitOverlayActivate()` to ServiceBridge

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt:261-272`

This is the foundation — the new event emission method. Must land before the tap handler can use it.

- [ ] **Step 1: Add the `emitOverlayActivate` method**

Add this method right after `emitCaptionText()` (after line 272), following the same pattern:

```kotlin
/** Called by OverlayBubbleService when user taps idle overlay to start detection. */
fun emitOverlayActivate() {
    Log.d(TAG, "emitOverlayActivate: eventSink=${eventSink != null}")
    mainHandler.post {
        eventSink?.success(
            mapOf("type" to "overlay_activate")
        )
    }
}
```

- [ ] **Step 2: Verify the project still compiles**

Run: `cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt
git commit -m "feat: add emitOverlayActivate() to ServiceBridge"
```

---

### Task 2: Rewrite tap handler in OverlayBubbleService

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/OverlayBubbleService.kt:644-660`

- [ ] **Step 1: Replace the tap handler and remove `launchApp()`**

In `setupTouch()`, replace line 646:
```kotlin
if (isExpanded) collapse() else launchApp()
```
with:
```kotlin
when {
    isExpanded -> collapse()
    sessionStatus == "idle" || sessionStatus == "connecting" -> {
        ServiceBridge.instance.emitOverlayActivate()
    }
    else -> expand()  // collapsed + pipeline running → show card
}
```

Then delete the entire `launchApp()` method (lines 655-660):
```kotlin
private fun launchApp() {
    val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    intent.putExtra(MainActivity.EXTRA_APP_ACTION, MainActivity.ACTION_OPEN_CALL_DEBUG)
    startActivity(intent)
}
```

Also update the class-level KDoc comment (line 34) — change:
```
 * The bubble is draggable.  Tap collapsed → open app.  Tap expanded → dismiss.
```
to:
```
 * The bubble is draggable.  Tap collapsed → activate detection / expand card.
 * Tap expanded → dismiss.
```

- [ ] **Step 2: Verify the project still compiles**

Run: `cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/OverlayBubbleService.kt
git commit -m "feat: rewrite overlay tap handler — activate pipeline or toggle card"
```

---

### Task 3: Handle `overlay_activate` in AppShell and remove old `overlay_tap` path

**Files:**
- Modify: `lib/app_shell.dart:55-190`

- [ ] **Step 1: Extract shared guard logic into `_tryStartScamSession()`**

Add this private method (e.g. after `_handleCallShake`, around line 143):

```dart
/// Shared guard: checks preconditions and starts a live-call session.
/// Returns true if a session was started, false if guards blocked it.
Future<bool> _tryStartScamSession() async {
  final homeState = context.read<HomeStateProvider>();
  if (!homeState.scamCallEnabled) return false;
  if (_sessionManager.hasActiveSession) return false;

  debugPrint('AppShell: starting background scam call session');
  await _sessionManager.startLiveCallSession();
  debugPrint(
    'AppShell: session started, '
    'isListening=${_sessionManager.controller?.isListening}',
  );
  return true;
}
```

- [ ] **Step 2: Refactor `_handleCallShake()` to use the shared helper**

Replace `_handleCallShake()` (lines 129-143) with:

```dart
Future<void> _handleCallShake() async {
  debugPrint(
    'AppShell._handleCallShake: '
    'scamCallEnabled=${context.read<HomeStateProvider>().scamCallEnabled}, '
    'hasActiveSession=${_sessionManager.hasActiveSession}',
  );
  HapticFeedback.heavyImpact();
  await _tryStartScamSession();
}
```

Note: Haptic fires immediately on shake (before the async session start) to preserve perceived responsiveness — matching the original behavior.

- [ ] **Step 3: Add `overlay_activate` case and `_handleOverlayActivate()`**

In `_handlePlatformEvent()`, replace the `overlay_tap` case (lines 66-68):
```dart
case 'overlay_tap':
    debugPrint('AppShell: overlay_tap received');
    _handleOverlayTap();
```
with:
```dart
case 'overlay_activate':
    debugPrint('AppShell: overlay_activate received');
    _handleOverlayActivate();
```

Add `_handleOverlayActivate()` (replaces the old `_handleOverlayTap` at lines 175-190):

```dart
Future<void> _handleOverlayActivate() async {
  debugPrint(
    'AppShell._handleOverlayActivate: '
    'scamCallEnabled=${context.read<HomeStateProvider>().scamCallEnabled}, '
    'hasActiveSession=${_sessionManager.hasActiveSession}',
  );
  await _tryStartScamSession();
  // No haptic — tap already provides tactile feedback via the OS.
}
```

- [ ] **Step 4: Delete `_handleOverlayTap()`** (lines 175-190)

Remove the entire method:
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

- [ ] **Step 5: Remove unused import if `ScamCallScreen` is no longer referenced**

Check if `ScamCallScreen` is still imported elsewhere in this file. Since `_handleOverlayTap` was the only place using it, remove line 7:
```dart
import 'features/scam_call/scam_call_screen.dart';
```

- [ ] **Step 6: Run Flutter analysis**

Run: `flutter analyze lib/ 2>&1`
Expected: No errors across the whole lib directory

- [ ] **Step 7: Commit**

```bash
git add lib/app_shell.dart
git commit -m "feat: handle overlay_activate event, remove overlay_tap navigation"
```

---

### Task 4: Dead code cleanup — ServiceBridge, MainActivity, ShakeService

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt:35,61-63,345-384`
- Modify: `android/app/src/main/kotlin/com/example/check_var/MainActivity.kt:19,23-24,116,158-168`
- Delete: `lib/core/shake_service.dart` (entirely dead — no importers)

- [ ] **Step 1: Clean up ServiceBridge.kt**

Remove these four items:

1. Remove the `pendingAppAction` field (line 35):
```kotlin
private var pendingAppAction: String? = null
```

2. Remove the `flushPendingAppAction()` call from `attachEventSink()` (line 63). Change:
```kotlin
fun attachEventSink(events: EventChannel.EventSink?) {
    eventSink = events
    flushPendingAppAction()
}
```
to:
```kotlin
fun attachEventSink(events: EventChannel.EventSink?) {
    eventSink = events
}
```

3. Remove `handleAppAction()` method (lines 345-351):
```kotlin
fun handleAppAction(action: String) {
    if (eventSink == null) {
        pendingAppAction = action
        return
    }
    emitAppAction(action)
}
```

4. Remove `emitAppAction()` method (lines 371-378):
```kotlin
private fun emitAppAction(action: String) {
    eventSink?.success(
        mapOf(
            "type" to "overlay_tap",
            "action" to action,
        )
    )
}
```

5. Remove `flushPendingAppAction()` method (lines 380-384):
```kotlin
private fun flushPendingAppAction() {
    val action = pendingAppAction ?: return
    pendingAppAction = null
    emitAppAction(action)
}
```

- [ ] **Step 2: Clean up MainActivity.kt**

1. Update the event channel comment (line 19). Change:
```kotlin
/** Shared event channel (shake, call_state, caption_text, overlay_tap …). */
```
to:
```kotlin
/** Shared event channel (shake, call_state, caption_text, overlay_activate …). */
```

2. Remove constants (lines 23-24):
```kotlin
const val EXTRA_APP_ACTION = "checkvar_app_action"
const val ACTION_OPEN_CALL_DEBUG = "open_call_debug"
```

3. Remove `handleAppActionIntent(intent)` call from `configureFlutterEngine()` (line 116). Delete the line entirely.

4. Remove the `handleAppActionIntent` call from `onNewIntent()` (line 161). The method becomes:
```kotlin
override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
}
```

5. Remove the `handleAppActionIntent()` method (lines 164-168):
```kotlin
private fun handleAppActionIntent(intent: Intent?) {
    val action = intent?.getStringExtra(EXTRA_APP_ACTION) ?: return
    intent.removeExtra(EXTRA_APP_ACTION)
    ServiceBridge.instance.handleAppAction(action)
}
```

- [ ] **Step 3: Delete `lib/core/shake_service.dart` entirely**

This file has zero importers in the codebase — it is entirely dead code. The actively used ShakeService lives at `lib/services/shake_service.dart` (singleton pattern). Delete the whole file:

```bash
git rm lib/core/shake_service.dart
```

- [ ] **Step 4: Verify everything compiles**

Run both:
```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
flutter analyze 2>&1 | tail -10
```
Expected: Both succeed with no errors.

- [ ] **Step 5: Verify no remaining references to removed code**

Run grep to check for any remaining references:
```bash
grep -r "overlay_tap\|launchApp\|EXTRA_APP_ACTION\|ACTION_OPEN_CALL_DEBUG\|handleAppAction\|emitAppAction\|flushPendingAppAction\|onOverlayTap\|OverlayTapCallback" --include="*.kt" --include="*.dart" lib/ android/app/src/main/kotlin/
```
Expected: No matches (or only in comments/docs, not in executable code).

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt \
        android/app/src/main/kotlin/com/example/check_var/MainActivity.kt
git rm lib/core/shake_service.dart
git commit -m "chore: remove dead overlay_tap code from ServiceBridge, MainActivity; delete dead shake_service"
```

---

### Task 5: Update existing tests

**Files:**
- Modify: `test/features/scam_call/scam_call_controller_test.dart`
- Modify: `test/features/scam_call/scam_call_screen_test.dart`

- [ ] **Step 1: Check for any test references to overlay_tap or handleOverlayTap**

Run:
```bash
grep -r "overlay_tap\|handleOverlayTap\|_handleOverlayTap\|launchApp" --include="*_test.dart" test/
```

If matches found, update them to use the new `overlay_activate` event name or remove tests for the deleted navigation path.

- [ ] **Step 2: Run all existing tests**

Run: `flutter test 2>&1 | tail -20`
Expected: All tests pass. If any fail due to the removed `overlay_tap` path, fix them by either removing the test (if it tested the old navigation) or updating the event name.

- [ ] **Step 3: Commit any test fixes**

```bash
git add test/
git commit -m "test: update tests for overlay_activate change"
```

(Skip this step if no test changes were needed.)
