import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/gemini_scam_text_api.dart';
import '../../core/api/local_scam_classifier.dart';
import '../../core/platform_channel.dart';
import '../../models/call_result.dart' as call_result;
import '../../models/scam_alert.dart';
import 'live/scam_call_transcript_gateway.dart';
import 'live/live_caption_transcript_gateway.dart';
import 'live/live_transcript_models.dart';

typedef OverlayVisibilityCallback = Future<void> Function();
typedef OverlayTranscriptCallback = Future<void> Function(String text);
typedef OverlayStatusCallback =
    Future<void> Function(
      ThreatLevel threatLevel,
      ScamCallSessionStatus sessionStatus,
      double confidence,
    );

enum ScamCallSessionStatus {
  idle,
  connecting,
  listening,
  reconnecting,
  analyzing,
  error,
}

class ScamCallController extends ChangeNotifier {
  ScamCallController({
    ScamCallTranscriptGateway? transcriptGateway,
    ScamTextClassifier? classifier,
    this.onOverlayShow,
    this.onOverlayHide,
    this.onOverlayTranscriptUpdate,
    this.onOverlayStatusUpdate,
    this.analysisDebounce = const Duration(milliseconds: 1500),
    this.analysisMaxWait = const Duration(seconds: 5),
    this.sessionRefreshInterval = const Duration(minutes: 13),
  }) : _transcriptGateway =
           transcriptGateway ?? _buildDefaultTranscriptGateway(),
       _classifier = classifier ?? LocalScamClassifier();

  static ScamCallTranscriptGateway _buildDefaultTranscriptGateway() {
    return LiveCaptionTranscriptGateway();
  }

  final ScamCallTranscriptGateway _transcriptGateway;
  final ScamTextClassifier _classifier;
  final OverlayVisibilityCallback? onOverlayShow;
  final OverlayVisibilityCallback? onOverlayHide;
  final OverlayTranscriptCallback? onOverlayTranscriptUpdate;
  final OverlayStatusCallback? onOverlayStatusUpdate;
  final Duration analysisDebounce;

  /// Maximum time to wait before forcing analysis even if speech is continuous.
  final Duration analysisMaxWait;
  final Duration sessionRefreshInterval;

  final List<TranscriptLine> _transcript = [];

  /// Latest partial transcript text (not yet finalized by STT).
  String _pendingPartial = '';

  StreamSubscription<LiveTranscriptEvent>? _transcriptSub;
  Timer? _analysisTimer;

  /// Fires when speech has been continuous for [analysisMaxWait] without
  /// any analysis running — forces analysis even during non-stop speech.
  Timer? _maxWaitTimer;
  Timer? _sessionRefreshTimer;

  ThreatLevel _threatLevel = ThreatLevel.safe;
  List<String> _patterns = [];
  String _summary = '';
  String _advice = '';
  double _confidence = 0;

  // ── EMA smoothing state ──────────────────────────────────────────
  static const _emaAlpha = 0.35;

  /// Exponential moving average of raw scam probability.  Initialized to
  /// -1 (sentinel) so the first analysis seeds the value directly.
  double _emaScamProb = -1.0;

  /// Consecutive analyses where the classifier returned non-safe.
  /// Decrements by 1 on safe (instead of resetting) to avoid flicker.
  int _consecutiveNonSafe = 0;

  bool _isListening = false;
  bool _analysisInFlight = false;
  String? _errorMessage;
  String? _sessionWarning;
  DateTime? _lastTranscriptAt;
  DateTime? _lastAnalysisAt;
  ScamCallSessionStatus _sessionStatus = ScamCallSessionStatus.idle;

  List<TranscriptLine> get transcript => List.unmodifiable(_transcript);
  ThreatLevel get threatLevel => _threatLevel;
  List<String> get patterns => List.unmodifiable(_patterns);
  String get summary => _summary;
  String get advice => _advice;
  double get confidence => _confidence;
  bool get isListening => _isListening;
  bool get analysisInFlight => _analysisInFlight;
  String? get errorMessage => _errorMessage;
  String? get sessionWarning => _sessionWarning;
  DateTime? get lastTranscriptAt => _lastTranscriptAt;
  DateTime? get lastAnalysisAt => _lastAnalysisAt;
  ScamCallSessionStatus get sessionStatus => _sessionStatus;

  String get sessionStatusLabel => switch (_sessionStatus) {
    ScamCallSessionStatus.idle => 'Chờ',
    ScamCallSessionStatus.connecting => 'Đang kết nối',
    ScamCallSessionStatus.listening => 'Đang nghe',
    ScamCallSessionStatus.reconnecting => 'Đang kết nối lại',
    ScamCallSessionStatus.analyzing => 'Đang phân tích',
    ScamCallSessionStatus.error => 'Lỗi',
  };

  /// The raw EMA-smoothed scam probability. Returns null if no analysis has run.
  double? get emaScamProbability => _emaScamProb < 0 ? null : _emaScamProb;

  /// Extracts the controller's current analysis state as a [call_result.CallResult].
  /// Call this before disposing the controller to capture the final state.
  call_result.CallResult extractCallResult({
    required DateTime callStartTime,
    required DateTime callEndTime,
    String? callerNumber,
  }) {
    // Both ThreatLevel enums (scam_alert.dart and call_result.dart) have
    // identical value names, so we convert via name lookup.
    final threat = call_result.ThreatLevel.values.firstWhere(
      (v) => v.name == _threatLevel.name,
    );
    return call_result.CallResult(
      threatLevel: threat,
      confidence: _confidence,
      transcript: _transcript.map((l) => l.text).join(' '),
      patterns: List.unmodifiable(_patterns),
      duration: callEndTime.difference(callStartTime),
      callerNumber: callerNumber,
      callStartTime: callStartTime,
      callEndTime: callEndTime,
      wasAnalyzed: true,
      summary: _summary.isNotEmpty ? _summary : null,
      advice: _advice.isNotEmpty ? _advice : null,
      scamProbability: _emaScamProb < 0 ? null : _emaScamProb,
    );
  }

  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    _resetState();
    _sessionStatus = ScamCallSessionStatus.connecting;
    notifyListeners();

    try {
      // Ensure overlay permission is granted before starting.
      await PlatformChannel.requestOverlayPermission();

      await _transcriptSub?.cancel();
      _transcriptSub = _transcriptGateway.transcripts.listen(_handleLiveEvent);
      await _transcriptGateway.start();
      _isListening = true;
      _sessionStatus = ScamCallSessionStatus.listening;
      _scheduleSessionRefresh();
      await onOverlayShow?.call();
      await _publishOverlayStatus();
      notifyListeners();
    } catch (e) {
      _isListening = false;
      _errorMessage = e.toString();
      _sessionStatus = ScamCallSessionStatus.error;
      await _publishOverlayStatus();
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;
    await _transcriptSub?.cancel();
    _transcriptSub = null;
    await _transcriptGateway.stop();
    _isListening = false;
    _analysisInFlight = false;
    _sessionStatus = ScamCallSessionStatus.idle;
    await onOverlayHide?.call();
    if (!_disposed) {
      await _publishOverlayStatus();
      notifyListeners();
    }
  }

  Future<void> _handleLiveEvent(LiveTranscriptEvent event) async {
    switch (event.kind) {
      case LiveTranscriptEventKind.inputTranscript:
        await _handleTranscriptEvent(event);
      case LiveTranscriptEventKind.goAway:
        await _restartLiveSession(
          event.detail ?? 'Refreshing live session before the session limit.',
        );
      case LiveTranscriptEventKind.error:
        await _restartLiveSession(
          event.detail ?? 'Live session disconnected. Reconnecting.',
        );
      case LiveTranscriptEventKind.setupComplete:
        _sessionStatus = ScamCallSessionStatus.listening;
        await _publishOverlayStatus();
        notifyListeners();
      case LiveTranscriptEventKind.modelText:
        // The scam detector uses input transcription events as the source of
        // truth, so model-text turns are ignored in the controller.
        break;
    }
  }

  Future<void> _handleTranscriptEvent(LiveTranscriptEvent event) async {
    final text = event.text.trim();
    if (text.isEmpty) {
      return;
    }
    debugPrint(
      'ScamCallController: transcript event '
      'isFinal=${event.isFinal}, '
      'len=${text.length}, '
      'text="${text.length > 60 ? text.substring(0, 60) : text}"',
    );

    if (event.isFinal) {
      // Final transcript — commit it and clear the pending partial.
      _pendingPartial = '';
      _transcript.add(TranscriptLine(text: text, timestamp: DateTime.now()));
    } else {
      // Partial transcript — store it but don't commit yet.
      // It will be included in the analysis window via _buildAnalysisText().
      _pendingPartial = text;
    }

    _lastTranscriptAt = DateTime.now();
    _sessionWarning = null;
    _sessionStatus = ScamCallSessionStatus.listening;
    unawaited(onOverlayTranscriptUpdate?.call(_buildOverlayText()));
    unawaited(_publishOverlayStatus());
    _scheduleAnalysis();
    notifyListeners();
  }

  void _scheduleAnalysis() {
    // Debounce: wait for a pause in speech before analyzing.
    _analysisTimer?.cancel();
    _analysisTimer = Timer(analysisDebounce, () => unawaited(_runAnalysis()));

    // Max-wait: if speech is continuous without pauses, force analysis
    // periodically so the user isn't left waiting.
    _maxWaitTimer ??= Timer(analysisMaxWait, () {
      _maxWaitTimer = null;
      if (!_analysisInFlight) {
        unawaited(_runAnalysis());
      }
    });
  }

  Future<void> _runAnalysis() async {
    if (_analysisInFlight || (_transcript.isEmpty && _pendingPartial.isEmpty)) {
      return;
    }

    _analysisInFlight = true;
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    _sessionStatus = ScamCallSessionStatus.analyzing;
    await _publishOverlayStatus();
    notifyListeners();

    try {
      // Include both committed finals and the current partial in the window.
      final transcriptWindow = _buildAnalysisText();
      debugPrint(
        'ScamCallController: running analysis, '
        'transcript=${_transcript.length} lines, '
        'window=${transcriptWindow.length} chars',
      );
      final result = await _classifier.classifyTranscriptWindow(
        transcriptWindow,
      );
      _lastAnalysisAt = DateTime.now();
      debugPrint(
        'ScamCallController: analysis result '
        'threat=${result.threatLevel.name}, '
        'confidence=${result.confidence.toStringAsFixed(2)}, '
        'patterns=${result.patterns}',
      );
      _applyAnalysis(result);
    } catch (e, st) {
      debugPrint('ScamCallController: analysis FAILED: $e\n$st');
      _errorMessage = 'Analysis error: $e';
    } finally {
      _analysisInFlight = false;
      if (_isListening) {
        _sessionStatus = ScamCallSessionStatus.listening;
      }
      await _publishOverlayStatus();
      notifyListeners();
    }
  }

  void _applyAnalysis(ScamAnalysisResult result) {
    // ── Update EMA ───────────────────────────────────────────────────
    final prob = result.scamProbability;
    if (_emaScamProb < 0) {
      _emaScamProb = prob; // first analysis — seed directly
    } else {
      _emaScamProb = _emaAlpha * prob + (1 - _emaAlpha) * _emaScamProb;
    }

    // ── Update consecutive non-safe counter ──────────────────────────
    if (result.threatLevel == ThreatLevel.safe) {
      _consecutiveNonSafe = (_consecutiveNonSafe - 1).clamp(0, 999);
    } else {
      _consecutiveNonSafe++;
    }

    // ── Determine effective threat level from EMA + consecutive gate ─
    final ThreatLevel effectiveThreat;
    if (_emaScamProb < 0.50) {
      effectiveThreat = ThreatLevel.safe;
    } else if (_consecutiveNonSafe < 2) {
      effectiveThreat = ThreatLevel.safe; // still gathering signal
    } else if (_emaScamProb < 0.55) {
      effectiveThreat = ThreatLevel.suspicious;
    } else {
      effectiveThreat = ThreatLevel.scam;
    }

    _threatLevel = effectiveThreat;
    _confidence = _emaScamProb;

    // ── Update summary / advice / patterns ───────────────────────────
    if (effectiveThreat != ThreatLevel.safe) {
      if (result.summary.trim().isNotEmpty) {
        _summary = result.summary;
      }
      if (result.advice.trim().isNotEmpty) {
        _advice = result.advice;
      }
    } else {
      _summary = '';
      _advice = '';
    }

    _patterns = {
      ..._patterns,
      ...result.patterns.where((pattern) => pattern.trim().isNotEmpty),
    }.toList();

    unawaited(_publishOverlayStatus());
  }

  Future<void> _restartLiveSession(String warning) async {
    if (!_isListening) {
      return;
    }

    _sessionWarning = warning;
    _sessionStatus = ScamCallSessionStatus.reconnecting;
    await _publishOverlayStatus();
    notifyListeners();

    try {
      await _transcriptGateway.restartLiveSession();
      _scheduleSessionRefresh();
      _sessionStatus = ScamCallSessionStatus.listening;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      _sessionStatus = ScamCallSessionStatus.error;
      _isListening = false;
    }

    await _publishOverlayStatus();
    notifyListeners();
  }

  void _scheduleSessionRefresh() {
    _sessionRefreshTimer?.cancel();
    if (sessionRefreshInterval <= Duration.zero) {
      return;
    }
    _sessionRefreshTimer = Timer(
      sessionRefreshInterval,
      () => unawaited(
        _restartLiveSession(
          'Refreshing live session before the session limit.',
        ),
      ),
    );
  }

  /// Build the full text for classifier analysis, including pending partials.
  String _buildAnalysisText() {
    final parts = _transcript.map((line) => line.text).toList();
    if (_pendingPartial.isNotEmpty) {
      parts.add(_pendingPartial);
    }
    return parts.join(' ');
  }

  String _buildOverlayText() {
    if (_transcript.isEmpty && _pendingPartial.isEmpty) {
      return '';
    }

    final startIndex = _transcript.length > 3 ? _transcript.length - 3 : 0;
    final parts = _transcript
        .skip(startIndex)
        .map((line) => line.text)
        .toList();
    if (_pendingPartial.isNotEmpty) {
      parts.add(_pendingPartial);
    }
    final overlayText = parts.join(' ');
    if (overlayText.length <= 160) {
      return overlayText;
    }
    return overlayText.substring(overlayText.length - 160);
  }

  void _resetState() {
    _transcript.clear();
    _pendingPartial = '';
    _threatLevel = ThreatLevel.safe;
    _patterns = [];
    _summary = '';
    _advice = '';
    _confidence = 0;
    _emaScamProb = -1.0;
    _consecutiveNonSafe = 0;
    _errorMessage = null;
    _sessionWarning = null;
    _analysisInFlight = false;
    _lastTranscriptAt = null;
    _lastAnalysisAt = null;
  }

  Future<void> _publishOverlayStatus() async {
    await onOverlayStatusUpdate?.call(_threatLevel, _sessionStatus, _confidence);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _analysisTimer?.cancel();
    _maxWaitTimer?.cancel();
    _sessionRefreshTimer?.cancel();
    _transcriptSub?.cancel();
    if (_isListening || _transcriptSub != null) {
      unawaited(_transcriptGateway.stop());
    }
    super.dispose();
  }
}
