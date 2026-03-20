import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/gemini_scam_text_api.dart';
import '../../core/api/local_scam_classifier.dart';
import '../../core/platform_channel.dart';
import '../../models/scam_alert.dart';
import 'live/agora_live_transcript_gateway.dart';
import 'live/live_transcript_models.dart';
import 'live/platform_speech_live_transcript_gateway.dart';

typedef OverlayVisibilityCallback = Future<void> Function();
typedef OverlayTranscriptCallback = Future<void> Function(String text);
typedef OverlayStatusCallback =
    Future<void> Function(
      ThreatLevel threatLevel,
      ScamCallSessionStatus sessionStatus,
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
    return PlatformSpeechLiveTranscriptGateway();
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

  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    _resetState();
    _sessionStatus = ScamCallSessionStatus.connecting;
    notifyListeners();

    try {
      // Ensure microphone and overlay permissions are granted before starting.
      await PlatformChannel.requestSpeakerTestPermissions();
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
    await _publishOverlayStatus();
    notifyListeners();
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
      final result = await _classifier.classifyTranscriptWindow(
        transcriptWindow,
      );
      _lastAnalysisAt = DateTime.now();
      _applyAnalysis(result);
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
    if (result.threatLevel.index >= _threatLevel.index) {
      _threatLevel = result.threatLevel;
      _confidence = result.confidence;
      if (result.summary.trim().isNotEmpty) {
        _summary = result.summary;
      }
      if (result.advice.trim().isNotEmpty) {
        _advice = result.advice;
      }
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
    _errorMessage = null;
    _sessionWarning = null;
    _analysisInFlight = false;
    _lastTranscriptAt = null;
    _lastAnalysisAt = null;
  }

  Future<void> _publishOverlayStatus() async {
    await onOverlayStatusUpdate?.call(_threatLevel, _sessionStatus);
  }

  @override
  void dispose() {
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
