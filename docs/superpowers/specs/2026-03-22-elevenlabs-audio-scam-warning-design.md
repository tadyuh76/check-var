# ElevenLabs Audio Scam Warning — Design Spec

## Summary

Integrate ElevenLabs TTS API to provide audio warnings during phone calls when scam is detected. Uses a hybrid approach: pre-generated alert sounds for immediate response, real-time ElevenLabs TTS for scam-type-specific advice. Audio is routed through the earpiece so only the user hears it.

## Trigger Logic

- **Threat level**: Only triggers on `ThreatLevel.scam` (not suspicious)
- **Minimum call duration**: Warning won't fire before 10 seconds into the call
- **Confidence gate**: Requires 3 consecutive scam analyses (stricter than the existing 2-consecutive non-safe gate)
- **Cooldown**: 30 seconds between warnings
- **One-shot**: Phase 1 alert plays once per session. Phase 2 advice replays only if a different scam type is detected.

## Warning Sequence

### Phase 1 — Non-skippable (~2-3s)
Pre-generated alert audio bundled as app assets:
- `assets/audio/scam_warning_vi.mp3` — "Cảnh báo: Cuộc gọi này có dấu hiệu lừa đảo"
- `assets/audio/scam_warning_en.mp3` — "Warning: This call shows signs of a scam"

Generated via ElevenLabs API at build time. Static files, never change at runtime.

### Phase 2 — Skippable
Scam-type-specific advice via real-time ElevenLabs TTS. Example: "Công an không bao giờ yêu cầu chuyển tiền" for police impersonation scam.

User can dismiss by tapping the overlay bubble. Falls back to Android native TTS if ElevenLabs is unavailable.

**Advice text source**: The 41 scam types already have Vietnamese `advice` strings defined in the `ScamType` enum (`local_scam_classifier.dart`). English translations will be added to `assets/scam_advice.json` with schema: `{ "scamTypeId": { "vi": "...", "en": "..." } }`. This file serves as the single source of truth for Phase 2 TTS text in both languages.

### Latency Optimization
Begin fetching Phase 2 TTS audio speculatively during Phase 1 playback to hide network latency. By the time Phase 1 finishes (~2-3s), Phase 2 audio is likely cached and ready.

## ElevenLabs Integration

### API
- Endpoint: `POST /v1/text-to-speech/{voice_id}`
- Returns MP3 audio bytes
- Timeout: 3 seconds (mid-call, latency matters)

### Voice Selection
Auto-matched by locale:
- Vietnamese → Vietnamese-capable ElevenLabs voice
- English → Default English ElevenLabs voice

Voice IDs stored as constants in `ElevenLabsTtsService`.

### Caching
- Key: `(scamType, locale)` → cached MP3 in app's temp directory (`elevenlabs_cache/`)
- Max 82 files (41 scam types × 2 languages)
- Persists across sessions, cleared on app update
- **Validation**: On cache read, verify MP3 header bytes (0xFF 0xFB or ID3 tag) and minimum file size (1KB) to guard against corrupted partial writes

### API Key Storage
- `.env` file (gitignored), loaded via `flutter_dotenv`
- Key name: `ELEVENLABS_API_KEY`
- Never hardcoded in source
- **Security note**: The `.env` file is bundled into the APK and can be extracted. This is acceptable for this app's threat model (personal-use app, not distributed on Play Store). If the app is ever published, migrate to a backend proxy or Firebase Remote Config to keep the key server-side.

### Fallback Chain
```
Cache → ElevenLabs API → Android native TTS
```

## Native Audio Playback (Android)

### New Platform Channel Methods

| Method | Purpose |
|--------|---------|
| `playWarningAudio(bytes, isSkippable)` | Play MP3 bytes into earpiece |
| `playWarningAsset(assetPath, isSkippable)` | Play bundled asset into earpiece |
| `stopWarningAudio()` | Stop current warning (no-op if non-skippable) |
| `isWarningPlaying()` | Check playback state |

### Implementation (ServiceBridge.kt)
- `MediaPlayer` with `AudioAttributes`: `USAGE_VOICE_COMMUNICATION` + `CONTENT_TYPE_SPEECH`
- Routes through earpiece (caller can't hear)
- Audio focus: `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` — ducks call audio briefly
- Sends `warning_audio_done` event to Dart on completion
- **OEM risk**: Earpiece routing via `USAGE_VOICE_COMMUNICATION` during active calls is not guaranteed on all Android OEMs (telephony stack owns the audio stream). If `MediaPlayer` fails to route correctly, fall back to `AudioTrack` with `MODE_STREAM` on `STREAM_VOICE_CALL`. Test on Samsung, Xiaomi, and Pixel at minimum.
- **Skip policy**: `isSkippable` enforcement stays in Dart — Dart simply doesn't call `stopWarningAudio` during Phase 1, rather than splitting policy across layers.

## Dart Architecture

### New Files

| File | Purpose |
|------|---------|
| `lib/core/services/scam_audio_warning_service.dart` | Orchestrator — trigger logic, sequencing, cooldown |
| `lib/core/api/elevenlabs_tts_service.dart` | ElevenLabs HTTP client + caching |

### ScamAudioWarningService
- Injected into `ScamCallController`
- Guards: `_callStartTime` (10s min), `_consecutiveScamCount` (3 required), `_lastWarningTime` (30s cooldown), `_hasPlayedInitialAlert` (one-shot), `_lastWarnedScamType` (type change detection)
- Sequence: Phase 1 asset → `warning_audio_done` event → ElevenLabs Phase 2 → play result
- Respects `scam_audio_warning_enabled` setting

### ElevenLabsTtsService
- `Future<Uint8List?> synthesize(String text, Locale locale)`
- Cache-first, then API call, returns null on failure
- Caller falls back to Android native TTS on null

### Integration Point
- `ScamCallController` calls `scamAudioWarningService.onAnalysisResult(result, elapsedTime)` after EMA smoothing
- Service internally decides whether to trigger

## Overlay & User Control

### Dismiss
- Tapping overlay bubble during Phase 2 → `stopWarningAudio()`
- "Tap to dismiss" hint shown on overlay during skippable playback
- Hanging up stops all audio

### Settings
- Toggle: "Voice scam warning" (default: ON)
- Key: `scam_audio_warning_enabled` in SharedPreferences
- When OFF, all audio warnings skipped (visual-only mode)

### Localization Additions

| Key | Vietnamese | English |
|-----|-----------|---------|
| `scam_audio.tap_dismiss` | Chạm để tắt | Tap to dismiss |
| `scam_audio.setting_title` | Cảnh báo bằng giọng nói | Voice scam warning |
| `scam_audio.setting_desc` | Phát cảnh báo bằng giọng nói khi phát hiện cuộc gọi lừa đảo | Play voice warnings when scam calls are detected |

## Telemetry

Log the following via `debugPrint` (upgrade to analytics if app is published):
- ElevenLabs API latency per call
- Cache hit/miss ratio
- Fallback to native TTS frequency
- Warning trigger count per session
- Phase 2 dismiss rate (user tapped to skip)

## Audio Routing

```
┌─────────────────────────────────────┐
│         ScamCallController          │
│  onAnalysisResult(result, elapsed)  │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│     ScamAudioWarningService         │
│  Trigger guards → Phase sequencing  │
└──────┬───────────────┬──────────────┘
       ▼               ▼
  Phase 1 asset    Phase 2 TTS
  (bundled MP3)    ┌─────────────┐
       │           │ ElevenLabs  │──fail──▶ Android TTS
       │           │  + Cache    │
       │           └──────┬──────┘
       ▼                  ▼
┌─────────────────────────────────────┐
│  PlatformChannel (playWarningAudio) │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│  ServiceBridge.kt → MediaPlayer     │
│  Earpiece routing + audio ducking   │
└─────────────────────────────────────┘
```
