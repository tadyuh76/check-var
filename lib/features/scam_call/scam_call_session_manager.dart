import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/platform_channel.dart';
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

enum ScamCallSessionKind { idle, liveCall, simulation }

class ScamCallSessionManager extends ChangeNotifier {
  ScamCallSessionManager({
    LiveCallControllerFactory? liveCallControllerFactory,
    SimulationControllerFactory? simulationControllerFactory,
    SpeakTextCallback? speakText,
    StopSpeakingCallback? stopSpeaking,
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

  ScamCallController? _controller;
  ScamCallSessionKind _sessionKind = ScamCallSessionKind.idle;

  ScamCallController? get controller => _controller;
  ScamCallSessionKind get sessionKind => _sessionKind;
  bool get hasActiveSession => _controller != null;
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
      return;
    }

    await _stopSpeaking();
    await controller.stopListening();
    controller.dispose();
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
  ) {
    return PlatformChannel.updateOverlayStatus(
      threatLevel: threatLevel.name,
      sessionStatus: sessionStatus.name,
    );
  }

  @override
  void dispose() {
    unawaited(stopSession());
    super.dispose();
  }
}
