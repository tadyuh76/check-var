import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/elevenlabs_tts_service.dart';
import '../core/api/gemini_scam_text_api.dart';
import '../core/api/local_scam_classifier.dart';
import '../core/platform_channel.dart';
import '../models/scam_alert.dart';

/// Orchestrates audio scam warnings during phone calls.
///
/// Trigger guards:
///  - Only fires on [ThreatLevel.scam] (not suspicious)
///  - Minimum 10 seconds into the call
///  - 3 consecutive scam analyses required
///  - 30-second cooldown between warnings
///  - Phase 1 alert plays once per session
///
/// Warning sequence:
///  - Phase 1 (non-skippable): pre-generated asset alert
///  - Phase 2 (skippable): ElevenLabs TTS for scam-type advice,
///    fallback to Android native TTS
class ScamAudioWarningService {
  ScamAudioWarningService({ElevenLabsTtsService? ttsService})
      : _ttsService = ttsService ?? ElevenLabsTtsService();

  static const settingsKey = 'scam_audio_warning_enabled';

  // ── Trigger thresholds ─────────────────────────────────────────────
  // DEMO MODE: fire 3s after the first scam popup appears
  static const _delayAfterScamPopup = Duration(seconds: 3);

  final ElevenLabsTtsService _ttsService;

  // ── Session state ──────────────────────────────────────────────────
  DateTime? _sessionStartTime;
  DateTime? _firstScamPopupTime;
  int _consecutiveScamCount = 0;
  bool _hasPlayedInitialAlert = false;
  ScamType? _lastWarnedScamType;
  DateTime? _lastWarningTime;
  bool _isPlaying = false;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  // ── Advice map (loaded once from assets) ───────────────────────────
  Map<String, Map<String, String>>? _adviceMap;

  // ── Telemetry ──────────────────────────────────────────────────────
  int _warningCount = 0;
  int _phase2DismissCount = 0;
  int _nativeTtsFallbackCount = 0;

  /// Call once when a session starts to listen for warning_audio_done events.
  void startSession() {
    _sessionStartTime = DateTime.now();
    _consecutiveScamCount = 0;
    _firstScamPopupTime = null;
    _hasPlayedInitialAlert = false;
    _lastWarnedScamType = null;
    _lastWarningTime = null;
    _isPlaying = false;
    _warningCount = 0;
    _phase2DismissCount = 0;
    _nativeTtsFallbackCount = 0;

    _eventSub?.cancel();
    try {
      _eventSub = PlatformChannel.shakeEvents.listen(_onNativeEvent);
    } catch (e) {
      debugPrint('[ScamAudioWarning] Could not subscribe to events: $e');
    }
  }

  /// Call when the session ends. Stops any playing audio and cleans up.
  void stopSession() {
    _eventSub?.cancel();
    _eventSub = null;
    if (_isPlaying) {
      PlatformChannel.stopWarningAudio();
      _isPlaying = false;
    }
    debugPrint('[ScamAudioWarning] Session ended — '
        'warnings=$_warningCount, '
        'phase2Dismissed=$_phase2DismissCount, '
        'nativeTtsFallbacks=$_nativeTtsFallbackCount');
  }

  /// Called by [ScamCallController] after each analysis result.
  /// The service internally decides whether to trigger a warning.
  Future<void> onAnalysisResult(
    ScamAnalysisResult result,
    String locale, {
    ThreatLevel? effectiveThreat,
  }) async {
    final threat = effectiveThreat ?? result.threatLevel;

    // Check if audio warnings are enabled
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(settingsKey) ?? true)) return;

    // DEMO MODE: fire 3s after the scam popup first appears
    if (threat != ThreatLevel.scam) return;

    // Record when the scam popup first appeared
    _firstScamPopupTime ??= DateTime.now();

    final sincePopup = DateTime.now().difference(_firstScamPopupTime!);
    if (sincePopup < _delayAfterScamPopup) return;

    // Guard: don't interrupt a playing warning
    if (_isPlaying) return;

    // All guards passed — trigger warning
    _lastWarningTime = DateTime.now();
    _warningCount++;
    debugPrint('[ScamAudioWarning] Triggering warning #$_warningCount '
        '(sincePopup=${sincePopup.inSeconds}s, '
        'scamType=${result.scamType?.name})');

    await _playWarningSequence(result, locale);
  }

  /// Stop Phase 2 audio (user tapped dismiss). No-op during Phase 1.
  void dismissPhase2() {
    if (_isPlaying) {
      PlatformChannel.stopWarningAudio();
      _phase2DismissCount++;
      debugPrint('[ScamAudioWarning] Phase 2 dismissed by user');
    }
  }

  // ── Warning sequence ───────────────────────────────────────────────

  Future<void> _playWarningSequence(
    ScamAnalysisResult result,
    String locale,
  ) async {
    _isPlaying = true;

    // Phase 1: play initial alert asset (if not already played this session)
    if (!_hasPlayedInitialAlert) {
      _hasPlayedInitialAlert = true;

      final assetPath = locale == 'vi'
          ? 'assets/audio/scam_warning_vi.mp3'
          : 'assets/audio/scam_warning_en.mp3';

      debugPrint('[ScamAudioWarning] Phase 1: playing asset $assetPath');

      // Start Phase 2 TTS fetch speculatively during Phase 1 playback
      final phase2Future = _fetchPhase2Audio(result, locale);

      await PlatformChannel.playWarningAsset(assetPath);

      // Wait for Phase 1 to finish (the warning_audio_done event)
      await _waitForAudioDone();

      // Phase 2: play scam-type advice
      await _playPhase2(result, locale, phase2Future);
    } else if (result.scamType != null &&
        result.scamType != _lastWarnedScamType) {
      // Different scam type detected — replay Phase 2 only
      debugPrint('[ScamAudioWarning] Phase 2 replay: new type '
          '${result.scamType?.name} (was ${_lastWarnedScamType?.name})');
      final phase2Future = _fetchPhase2Audio(result, locale);
      await _playPhase2(result, locale, phase2Future);
    } else {
      _isPlaying = false;
    }

    _lastWarnedScamType = result.scamType;
  }

  Future<Uint8List?> _fetchPhase2Audio(
    ScamAnalysisResult result,
    String locale,
  ) async {
    if (result.scamType == null) return null;

    final adviceMap = await _loadAdviceMap();
    return _ttsService.synthesizeAdvice(result.scamType!, locale, adviceMap);
  }

  Future<void> _playPhase2(
    ScamAnalysisResult result,
    String locale,
    Future<Uint8List?> phase2AudioFuture,
  ) async {
    final audioBytes = await phase2AudioFuture;

    if (audioBytes != null) {
      debugPrint('[ScamAudioWarning] Phase 2: playing ElevenLabs TTS '
          '(${audioBytes.length} bytes)');
      await PlatformChannel.playWarningAudio(audioBytes);
      await _waitForAudioDone();
    } else {
      // Fallback: Android native TTS
      _nativeTtsFallbackCount++;
      final adviceText = await _getAdviceText(result, locale);
      debugPrint('[ScamAudioWarning] Phase 2: fallback to native TTS '
          '(fallbacks=$_nativeTtsFallbackCount)');
      await PlatformChannel.speakText(adviceText);
      await _waitForTtsDone();
    }

    _isPlaying = false;
  }

  Future<String> _getAdviceText(
    ScamAnalysisResult result,
    String locale,
  ) async {
    if (result.scamType != null) {
      final adviceMap = await _loadAdviceMap();
      final advice = adviceMap[result.scamType!.name]?[locale] ??
          adviceMap[result.scamType!.name]?['vi'] ??
          result.advice;
      return advice;
    }
    return result.advice;
  }

  // ── Advice map loading ─────────────────────────────────────────────

  Future<Map<String, Map<String, String>>> _loadAdviceMap() async {
    if (_adviceMap != null) return _adviceMap!;

    final jsonString = await rootBundle.loadString('assets/scam_advice.json');
    final raw = jsonDecode(jsonString) as Map<String, dynamic>;

    _adviceMap = raw.map((key, value) {
      final inner = (value as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
      return MapEntry(key, inner);
    });

    return _adviceMap!;
  }

  // ── Native event handling ──────────────────────────────────────────

  void _onNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'warning_audio_done') {
      _warningAudioDoneCompleter?.complete();
    } else if (type == 'tts_done') {
      _ttsDoneCompleter?.complete();
    }
  }

  Completer<void>? _warningAudioDoneCompleter;
  Completer<void>? _ttsDoneCompleter;

  Future<void> _waitForAudioDone() {
    _warningAudioDoneCompleter = Completer<void>();
    return _warningAudioDoneCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[ScamAudioWarning] warning_audio_done timeout');
      },
    );
  }

  Future<void> _waitForTtsDone() {
    _ttsDoneCompleter = Completer<void>();
    return _ttsDoneCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('[ScamAudioWarning] tts_done timeout');
      },
    );
  }
}
