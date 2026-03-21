import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/platform_channel.dart';
import '../../models/call_result.dart' show CallResult;
import '../../models/scam_alert.dart';
import 'live/live_caption_transcript_gateway.dart';
import 'live/simulated_call_scenario.dart';
import 'scam_call_controller.dart';

typedef LiveCallControllerFactory = ScamCallController Function();
typedef SimulationControllerFactory =
    ScamCallController Function(SimulatedCallScenario scenario);
typedef SpeakTextCallback =
    Future<void> Function(String text, {bool preferSpeaker});
typedef StopSpeakingCallback = Future<void> Function();
typedef SessionFinalizedCallback = Future<void> Function(CallResult result);

enum ScamCallSessionKind { idle, liveCall, simulation }

class ScamCallSessionManager extends ChangeNotifier {
  ScamCallSessionManager({
    LiveCallControllerFactory? liveCallControllerFactory,
    SimulationControllerFactory? simulationControllerFactory,
    SpeakTextCallback? speakText,
    StopSpeakingCallback? stopSpeaking,
    this.onSessionFinalized,
  }) : _liveCallControllerFactory =
           liveCallControllerFactory ?? _buildLiveCallController,
       _simulationControllerFactory =
           simulationControllerFactory ?? _buildSimulationController,
       _speakText = speakText ?? PlatformChannel.speakText,
       _stopSpeaking = stopSpeaking ?? PlatformChannel.stopSpeaking;

  final LiveCallControllerFactory _liveCallControllerFactory;
  final SimulationControllerFactory _simulationControllerFactory;
  final SpeakTextCallback _speakText;
  final StopSpeakingCallback _stopSpeaking;
  final SessionFinalizedCallback? onSessionFinalized;

  DateTime? _callStartTime;
  String? _callerNumber;

  ScamCallController? _controller;
  ScamCallSessionKind _sessionKind = ScamCallSessionKind.idle;

  ScamCallController? get controller => _controller;
  ScamCallSessionKind get sessionKind => _sessionKind;
  bool get hasActiveSession => _controller != null;

  /// Removes the controller from management without stopping or disposing it.
  /// The caller takes ownership and is responsible for disposal.
  ScamCallController? detachController() {
    final controller = _controller;
    _controller = null;
    _sessionKind = ScamCallSessionKind.idle;
    notifyListeners();
    return controller;
  }

  static const _finalizationGrace = Duration(milliseconds: 1500);

  void setCallTiming({required DateTime callStartTime, String? callerNumber}) {
    _callStartTime = callStartTime;
    _callerNumber = callerNumber;
  }

  String? get modeLabel => switch (_sessionKind) {
    ScamCallSessionKind.liveCall => 'Live Call Debug',
    ScamCallSessionKind.simulation => 'Simulation Mode',
    ScamCallSessionKind.idle => null,
  };

  Future<void> startLiveCallSession() async {
    if (_sessionKind == ScamCallSessionKind.liveCall && _controller != null) {
      return;
    }

    final controller = _liveCallControllerFactory();
    await _replaceSession(
      controller: controller,
      sessionKind: ScamCallSessionKind.liveCall,
    );
  }

  Future<void> startSimulationSession(SimulatedCallScenario scenario) async {
    final controller = _simulationControllerFactory(scenario);
    await _replaceSession(
      controller: controller,
      sessionKind: ScamCallSessionKind.simulation,
    );
    if (controller.isListening) {
      unawaited(_speakText(scenario.spokenScript, preferSpeaker: true));
    }
  }

  Future<void> stopSession() async {
    final controller = _controller;
    _controller = null;
    _sessionKind = ScamCallSessionKind.idle;
    notifyListeners();

    if (controller == null) {
      await _stopSpeaking();
      _resetCallTiming();
      return;
    }

    await _stopSpeaking();

    // Grace period: wait for in-flight analysis to finish.
    if (controller.analysisInFlight) {
      await Future.any([
        _waitForAnalysis(controller),
        Future.delayed(_finalizationGrace),
      ]);
    }

    // Extract final state before disposing.
    final callEndTime = DateTime.now();
    final callResult = controller.extractCallResult(
      callStartTime: _callStartTime ?? callEndTime,
      callEndTime: callEndTime,
      callerNumber: _callerNumber,
    );

    await controller.stopListening();
    controller.dispose();

    // Finalize: save to history + notify.
    await onSessionFinalized?.call(callResult);
    _resetCallTiming();
  }

  Future<void> _waitForAnalysis(ScamCallController controller) async {
    while (controller.analysisInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _resetCallTiming() {
    _callStartTime = null;
    _callerNumber = null;
  }

  Future<void> _replaceSession({
    required ScamCallController controller,
    required ScamCallSessionKind sessionKind,
  }) async {
    if (_controller != null) {
      await stopSession();
    }

    _controller = controller;
    _sessionKind = sessionKind;
    notifyListeners();
    await controller.startListening();
  }

  static ScamCallController _buildLiveCallController() {
    return ScamCallController(
      onOverlayShow: PlatformChannel.showOverlayBubble,
      onOverlayHide: PlatformChannel.hideOverlayBubble,
      onOverlayStatusUpdate: _updateOverlayStatus,
    );
  }

  static ScamCallController _buildSimulationController(
    SimulatedCallScenario scenario,
  ) {
    return ScamCallController(
      transcriptGateway: buildSimulationTranscriptGateway(),
      onOverlayShow: PlatformChannel.showOverlayBubble,
      onOverlayHide: PlatformChannel.hideOverlayBubble,
      onOverlayStatusUpdate: _updateOverlayStatus,
    );
  }

  @visibleForTesting
  static LiveCaptionTranscriptGateway buildSimulationTranscriptGateway() {
    return LiveCaptionTranscriptGateway();
  }

  static Future<void> _updateOverlayStatus(
    ThreatLevel threatLevel,
    ScamCallSessionStatus sessionStatus,
    double confidence,
  ) {
    return PlatformChannel.updateOverlayStatus(
      threatLevel: threatLevel.name,
      sessionStatus: sessionStatus.name,
      confidence: (confidence * 100).round(),
    );
  }

  @override
  void dispose() {
    unawaited(stopSession());
    super.dispose();
  }
}
