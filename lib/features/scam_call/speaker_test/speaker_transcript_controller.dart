import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/scam_alert.dart';
import 'phrase_accuracy.dart';
import 'speaker_test_gateway.dart';

/// Optional callbacks for overlay lifecycle, injected by the screen
/// to keep the controller platform-agnostic.
typedef OverlayCallback = Future<void> Function();
typedef OverlayTranscriptCallback = Future<void> Function(String text);

class SpeakerTranscriptController extends ChangeNotifier {
  SpeakerTranscriptController({
    required SpeakerTestGateway gateway,
    required List<String> expectedPhrases,
    this.onOverlayShow,
    this.onOverlayHide,
    this.onOverlayTranscriptUpdate,
  }) : _gateway = gateway,
       _expectedPhrases = List.unmodifiable(expectedPhrases);

  final SpeakerTestGateway _gateway;
  final List<String> _expectedPhrases;

  /// Called when listening starts — show the overlay bubble.
  final OverlayCallback? onOverlayShow;

  /// Called when listening stops — hide the overlay bubble.
  final OverlayCallback? onOverlayHide;

  /// Called with transcript text to update the overlay display.
  final OverlayTranscriptCallback? onOverlayTranscriptUpdate;

  // ── State ─────────────────────────────────────────────────────────────────

  SpeakerTestReadiness _readiness = SpeakerTestReadiness.empty();
  bool _isListening = false;
  bool _isRunning = false;
  bool _isPlayingPhrase = false;
  int _currentPhraseIndex = -1;
  String _partialTranscript = '';
  String? _errorMessage;
  String? _blockingMessage;

  final List<TranscriptLine> _transcriptHistory = [];
  final List<PhraseAccuracyResult> _phraseScores = [];

  StreamSubscription<SpeakerTranscriptEvent>? _transcriptSub;

  /// Completer resolved when the next final transcript arrives.
  Completer<String>? _awaitingFinal;

  // ── Getters ───────────────────────────────────────────────────────────────

  SpeakerTestReadiness get readiness => _readiness;
  bool get isListening => _isListening;
  bool get isRunning => _isRunning;
  bool get isPlayingPhrase => _isPlayingPhrase;
  int get currentPhraseIndex => _currentPhraseIndex;
  String get partialTranscript => _partialTranscript;
  String? get errorMessage => _errorMessage;
  String? get blockingMessage => _blockingMessage;
  List<TranscriptLine> get transcriptHistory =>
      List.unmodifiable(_transcriptHistory);
  List<PhraseAccuracyResult> get phraseScores =>
      List.unmodifiable(_phraseScores);
  List<String> get expectedPhrases => _expectedPhrases;

  double get averageAccuracy {
    if (_phraseScores.isEmpty) return 0.0;
    final sum = _phraseScores.fold<double>(0, (s, r) => s + r.accuracy);
    return sum / _phraseScores.length;
  }

  SpeakerTestVerdict? get summaryVerdict {
    if (_phraseScores.isEmpty) return null;
    return overallVerdict(averageAccuracy);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> loadReadiness() async {
    try {
      _readiness = await _gateway.getReadiness();
      _blockingMessage = _computeBlockingMessage();
    } catch (e) {
      _errorMessage = 'Failed to check readiness: $e';
    }
    notifyListeners();
  }

  /// Run the automated speaker test: for each phrase, play it via TTS,
  /// then listen for the mic to pick it up, and score accuracy.
  Future<void> runTest() async {
    if (_isRunning) return;

    _isRunning = true;
    _phraseScores.clear();
    _transcriptHistory.clear();
    _partialTranscript = '';
    _currentPhraseIndex = 0;
    _errorMessage = null;
    notifyListeners();

    try {
      _transcriptSub = _gateway.transcriptEvents().listen(_onTranscriptEvent);
      await _gateway.startListening();
      _isListening = true;
      await onOverlayShow?.call();
      notifyListeners();

      for (var i = 0; i < _expectedPhrases.length; i++) {
        if (!_isRunning) break;
        _currentPhraseIndex = i;
        await _gateway.waitUntilListeningReady();
        if (!_isRunning) break;
        _isPlayingPhrase = true;
        _awaitingFinal = Completer<String>();
        notifyListeners();

        // Play phrase through the speaker via TTS
        await _gateway.speakPhrase(_expectedPhrases[i]);
        _isPlayingPhrase = false;
        notifyListeners();

        // Wait for recognizer to produce a final result
        String recognized;
        try {
          recognized = await _awaitingFinal!.future.timeout(
            const Duration(seconds: 8),
            onTimeout: () => '',
          );
        } catch (_) {
          recognized = '';
        }

        // Score what the mic heard vs what was played
        _phraseScores.add(
          scorePhraseAccuracy(
            expected: _expectedPhrases[i],
            recognized: recognized,
          ),
        );
        notifyListeners();

        // Brief pause between phrases
        if (i < _expectedPhrases.length - 1 && _isRunning) {
          try {
            _partialTranscript = '';
            await _gateway.refreshListeningSession();
            notifyListeners();
          } catch (e) {
            _errorMessage = 'Failed to refresh listening: $e';
            _isRunning = false;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    } catch (e) {
      _errorMessage = 'Test failed: $e';
    }

    await _stopAll();
    notifyListeners();
  }

  /// Cancel a running test.
  Future<void> stopTest() async {
    _isRunning = false;
    _isPlayingPhrase = false;
    if (_awaitingFinal != null && !_awaitingFinal!.isCompleted) {
      _awaitingFinal!.complete('');
    }
    try {
      await _gateway.stopSpeaking();
    } catch (_) {}
    await _stopAll();
    notifyListeners();
  }

  /// Start listening without TTS playback (for live call mode).
  Future<void> startListening() async {
    if (_isListening) return;

    try {
      _transcriptSub = _gateway.transcriptEvents().listen(_onTranscriptEvent);
      await _gateway.startListening();
      _isListening = true;
      _errorMessage = null;
      await onOverlayShow?.call();
    } catch (e) {
      _errorMessage = 'Failed to start listening: $e';
    }
    notifyListeners();
  }

  /// Stop listening (for live call mode).
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _stopAll();
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _onTranscriptEvent(SpeakerTranscriptEvent event) {
    if (event.isFinal) {
      _partialTranscript = '';
      _transcriptHistory.add(
        TranscriptLine(text: event.text, timestamp: DateTime.now()),
      );

      // Resolve the awaiting completer if we're in automated test mode
      if (_awaitingFinal != null && !_awaitingFinal!.isCompleted) {
        _awaitingFinal!.complete(event.text);
      }
    } else {
      _partialTranscript = event.text;
    }

    // Update overlay with latest transcript text
    final overlayText = _buildOverlayText();
    onOverlayTranscriptUpdate?.call(overlayText);

    notifyListeners();
  }

  String _buildOverlayText() {
    final lines = <String>[];
    for (final line in _transcriptHistory) {
      lines.add(line.text);
    }
    if (_partialTranscript.isNotEmpty) {
      lines.add('...$_partialTranscript');
    }
    // Show last 4 lines to keep overlay compact
    final recent = lines.length > 4 ? lines.sublist(lines.length - 4) : lines;
    return recent.join('\n');
  }

  Future<void> _stopAll() async {
    try {
      await _gateway.stopListening();
      await _transcriptSub?.cancel();
      _transcriptSub = null;
      _isListening = false;
      _isRunning = false;
      await onOverlayHide?.call();
    } catch (e) {
      _errorMessage = 'Failed to stop: $e';
    }
  }

  String? _computeBlockingMessage() {
    if (!_readiness.hasMicrophonePermission) {
      return 'Microphone permission is required.';
    }
    if (!_readiness.recognizerAvailable) {
      return 'On-device speech recognition is unavailable on this device.';
    }
    return null;
  }

  @override
  void dispose() {
    _transcriptSub?.cancel();
    super.dispose();
  }
}
