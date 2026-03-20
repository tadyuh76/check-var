# Live Caption Scam Call Transcription

**Date**: 2026-03-21
**Status**: Approved
**Replaces**: SpeechRecognizer-based microphone transcription for scam call detection

## Problem

The current scam call transcription uses Android's `SpeechRecognizer` API to capture audio from the device microphone during a call. This primarily picks up the user's own voice; the scam caller's voice is only captured through unreliable speaker bleed. This limits detection accuracy since the scam patterns exist in what the *caller* says, not the user.

## Solution

Replace `SpeechRecognizer` with Android's built-in **Live Caption** feature, reading its output via the existing `AccessibilityService`. Live Caption transcribes all audio playing through the device's audio output — including the caller's voice — using Google's on-device ML model. Vietnamese is supported on Pixel 6+ and Android 14+.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Replacement strategy | Full replacement of SpeechRecognizer | Simplicity; Live Caption captures what we actually need (caller's voice) |
| Accessibility service | Extend existing `CheckVarAccessibilityService` | Android limits one AccessibilityService per app; features are naturally mutually exclusive |
| OEM support | Google-only (`com.google.android.as`), extensible for OEMs later | Ship fast, expand later |
| Setup flow | Instructions + deep-link to Live Caption & Accessibility settings | Ensure both prerequisites are met before session start |
| Live Caption detection | Best-effort `Settings.Secure` check (`oda_enabled` key, undocumented) + timeout hint as primary mechanism | The Settings.Secure key is not a public API and may vary across devices; the 10s timeout fallback is the reliable detection path |
| Overlay UI | Single bubble showing scam/safe verdict only | No transcript display, no confidence level |
| `RECORD_AUDIO` permission | Remove runtime request from scam call flow; remove from `AndroidManifest.xml` since speaker test is also being removed | No longer needed anywhere; Live Caption handles transcription |
| Speaker test feature | Remove entirely | Will be replaced by simulation mode using Live Caption in a future iteration |

## Architecture

### Data Flow

```
Active Call
  -> Android Live Caption transcribes caller's voice (on-device)
  -> CheckVarAccessibilityService captures caption text from Live Caption UI
     (TYPE_WINDOW_CONTENT_CHANGED from com.google.android.as)
  -> ServiceBridge forwards via EventChannel {"type": "caption_text", "text": "..."}
  -> LiveCaptionTranscriptGateway converts to LiveTranscriptEvent stream
  -> ScamCallController collects text, debounces (1.5s pause / 5s max wait)
  -> LocalScamClassifier runs TF-IDF classification
  -> Result: scam or safe
  -> Overlay bubble shows verdict
```

### Native Android Layer

#### `CheckVarAccessibilityService.kt` — New caption capture path

In `onAccessibilityEvent()`:
1. **Filter**: `TYPE_WINDOW_CONTENT_CHANGED` from package `com.google.android.as`
2. **Extract**: Traverse `AccessibilityNodeInfo` tree, collect text nodes
3. **Deduplicate (word-level)**: Live Caption updates character-by-character, producing high-frequency events. Buffer text and only emit when a new complete word or sentence boundary is detected (whitespace/punctuation delta). This prevents flooding the Dart layer with per-character updates and avoids constantly resetting the controller's debounce timer.
4. **Null safety**: Guard against `event.source` being null (common with accessibility events). Skip events with null source or empty node text. Filter out UI chrome text (e.g., "Live Caption" label) by checking node class types.
5. **Emit**: Forward to `ServiceBridge` which sends through EventChannel as `{"type": "caption_text", "text": "..."}`

#### `ServiceBridge.kt` — New methods

| Method | Purpose |
|--------|---------|
| `startCaptionCapture()` | Set flag so accessibility service forwards caption events |
| `stopCaptionCapture()` | Clear flag, stop forwarding |
| `checkLiveCaptionEnabled()` | Read `Settings.Secure` to verify Live Caption is toggled on |

#### `accessibility_service_config.xml`

**Critical changes**:
- Set `android:canRetrieveWindowContent="true"` (currently `false`) — required to traverse `AccessibilityNodeInfo` trees from Live Caption's UI
- Add `com.google.android.as` to the `packageNames` filter
- Review `notificationTimeout` (currently 100ms) — may need tuning for caption event frequency

#### Removed

- `SpeechRecognizerManager.kt` — deleted entirely
- `startSpeakerRecognition()`, `stopSpeakerRecognition()`, `getSpeakerTestReadiness()` from ServiceBridge
- `RECORD_AUDIO` permission requests in scam call flow

### Dart Layer

#### New: `LiveCaptionTranscriptGateway`

Replaces `PlatformSpeechLiveTranscriptGateway`. Implements the same stream interface.

- Listens to EventChannel for `caption_text` events
- Converts to `LiveTranscriptEvent` (kind: `inputTranscript`, `isFinal: true`)
- Deduplicates on Dart side as well
- Same `Stream<LiveTranscriptEvent>` interface — `ScamCallController` needs minimal changes

#### `ScamCallController` changes

- Swap gateway dependency from speech-based to caption-based
- Remove microphone permission checks
- Add Live Caption enabled check at session start
- Keep existing debounced analysis flow unchanged

#### `PlatformChannel` updates

- **Add**: `startCaptionCapture()`, `stopCaptionCapture()`, `checkLiveCaptionEnabled()`
- **Remove**: `startSpeakerRecognition()`, `stopSpeakerRecognition()`, `getSpeakerTestReadiness()`

### Setup & Permission Flow

New setup check before first scam call session:

1. Call `checkLiveCaptionEnabled()` — verify Live Caption is on
2. Check if Accessibility Service is enabled
3. If either is missing, show dialog with:
   - Explanation of why these are needed
   - "Open Live Caption Settings" button -> deep-link via `Settings.ACTION_SOUND_SETTINGS` (no dedicated Live Caption intent exists; user navigates to Live Caption from Sound settings). On failure, fall back to `Settings.ACTION_SETTINGS`.
   - "Open Accessibility Settings" button -> deep-link to `Settings.ACTION_ACCESSIBILITY_SETTINGS`
4. Block session start until both are confirmed

**Timeout hint**: If no caption events arrive within ~10 seconds during an active call, show "No captions detected — is Live Caption enabled?"

### Overlay Simplification

**Merge into single overlay bubble**:
- Delete `CallStatusBubbleService.kt` entirely; adapt `OverlayBubbleService.kt` to show verdict only
- `OverlayBubbleService` shows verdict only:
  - Green/Teal = safe
  - Red = scam
  - Blue = analyzing/listening
  - Gray = no captions yet
- No transcript text displayed
- Keep draggable behavior

### Cleanup

#### Files to delete

**Kotlin (native)**:
- `SpeechRecognizerManager.kt` — native speech recognizer wrapper
- `SpeechRecognizerConfigTest.kt` — its tests
- `SpeakerTestLaunchTest.kt` — tests for speaker test launch utilities
- `SpeakerTranscriptEventPayload.kt` — dead code, only used by old `SpeechRecognizerManager` flow
- `CallStatusBubbleService.kt` — merged into simplified `OverlayBubbleService`

**Dart (lib)**:
- `lib/features/scam_call/live/platform_speech_live_transcript_gateway.dart` — old Dart gateway
- `lib/features/scam_call/live/platform_speaker_test_gateway.dart` — speaker test gateway
- `lib/features/scam_call/speaker_test/` — entire directory (includes `speaker_transcript_controller.dart`, `speaker_transcript_test_screen.dart`, `speaker_test_gateway.dart`, `speaker_test_models.dart`, `phrase_accuracy.dart`)

**Tests**:
- `test/features/scam_call/speaker_test/` — all speaker test tests
- `test/features/scam_call/live/platform_speech_live_transcript_gateway_test.dart` — old gateway test

#### Files to update

**Kotlin (native)**:
- `AndroidManifest.xml` — remove `RECORD_AUDIO` permission declaration entirely
- `accessibility_service_config.xml` — set `canRetrieveWindowContent="true"`, add `com.google.android.as` to package filter, keep `notificationTimeout` at 100ms (word-level dedup in code handles event throttling)
- `ServiceBridge.kt` — remove speaker recognition methods (`startSpeakerRecognition`, `stopSpeakerRecognition`, `getSpeakerTestReadiness`), remove `CallStatusBubbleService` methods (`showCallStatusBubble`, `hideCallStatusBubble`, `updateOverlayStatus`), add caption capture methods (`startCaptionCapture`, `stopCaptionCapture`, `checkLiveCaptionEnabled`)
- `MainActivity.kt` — remove `requestSpeakerTestPermissions()` method and `RECORD_AUDIO` permission handling
- `CallMonitorService.kt` — remove `CallStatusBubbleService` stop reference on call end
- `SpeakerTestLaunch.kt` — rename to `EventPayloadBuilder.kt` (or similar), keep `buildCallActiveEvent()` used by `CallMonitorService`, remove dead `buildTranscriptEvent()` and `buildRecognizerReadyEvent()` methods

**Dart (lib)**:
- `PlatformChannel` — add `startCaptionCapture()`, `stopCaptionCapture()`, `checkLiveCaptionEnabled()`; remove `startSpeakerRecognition()`, `stopSpeakerRecognition()`, `getSpeakerTestReadiness()`, `requestSpeakerTestPermissions()` (or refactor to only request `READ_PHONE_STATE`); remove `showCallStatusBubble()`, `hideCallStatusBubble()`, `updateOverlayStatus()`
- `ScamCallController` — replace `requestSpeakerTestPermissions()` call in `startListening()` with Live Caption + Accessibility prerequisite check; swap gateway dependency to `LiveCaptionTranscriptGateway`
- `ScamCallScreen` — update UI to reflect simplified overlay, remove speaker test references
- `ScamCallSessionManager` — update session lifecycle for caption-based flow
- `home_screen.dart` — remove speaker test imports and speaker test button (`home_speaker_test_button`)
- `OverlayBubbleService.kt` — simplify to verdict-only display

#### New files
- `lib/features/scam_call/live/live_caption_transcript_gateway.dart` — new gateway
- `test/features/scam_call/live/live_caption_transcript_gateway_test.dart` — its tests

#### New `LiveCaptionTranscriptGateway` behavior notes
- `restartLiveSession()` — no-op (or resets dedup state). Live Caption is passive; there is no session to restart.
- All events emitted as `isFinal: true` since Live Caption provides finalized (word-boundary) text after our dedup logic.

## Device Requirements

- Android 14+ (Android U) or Pixel 6+ for Vietnamese Live Caption support
- Accessibility Service permission granted
- Live Caption enabled in device settings

## Out of Scope

- OEM-specific caption implementations (Samsung, Xiaomi, etc.) — designed for extensibility but not implemented in v1
- Simulation mode — will be added later, also using Live Caption
- Two-sided transcript (user + caller) — only capturing caller's voice via Live Caption
