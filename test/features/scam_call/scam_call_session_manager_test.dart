import 'dart:async';

import 'package:check_var/core/api/gemini_scam_text_api.dart';
import 'package:check_var/features/scam_call/live/scam_call_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:check_var/features/scam_call/live/live_caption_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/simulated_call_scenario.dart';
import 'package:check_var/features/scam_call/scam_call_controller.dart';
import 'package:check_var/features/scam_call/scam_call_session_manager.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      null,
    );
  });

  test('startLiveCallSession creates one shared live controller', () async {
    final liveGateway = _FakeTranscriptGateway();
    var liveFactoryCalls = 0;
    final manager = ScamCallSessionManager(
      liveCallControllerFactory: () {
        liveFactoryCalls++;
        return _buildController(liveGateway);
      },
      simulationControllerFactory: (_) => _buildController(
        _FakeTranscriptGateway(),
      ),
      speakText: (_, {preferSpeaker = false}) async {},
      stopSpeaking: () async {},
    );
    addTearDown(() async => manager.stopSession());

    await manager.startLiveCallSession();
    final firstController = manager.controller;
    await manager.startLiveCallSession();

    expect(liveFactoryCalls, 1);
    expect(identical(manager.controller, firstController), isTrue);
    expect(manager.sessionKind, ScamCallSessionKind.liveCall);
    expect(liveGateway.startCount, 1);
  });

  test('startSimulationSession speaks the selected script and replaces live mode', () async {
    final liveGateway = _FakeTranscriptGateway();
    final simulationGateway = _FakeTranscriptGateway();
    final spokenScripts = <String>[];
    final speakerPreferences = <bool>[];

    final manager = ScamCallSessionManager(
      liveCallControllerFactory: () => _buildController(liveGateway),
      simulationControllerFactory: (_) => _buildController(simulationGateway),
      speakText: (text, {preferSpeaker = false}) async {
        spokenScripts.add(text);
        speakerPreferences.add(preferSpeaker);
      },
      stopSpeaking: () async {},
    );
    addTearDown(() async => manager.stopSession());

    await manager.startLiveCallSession();
    await manager.startSimulationSession(
      SimulatedCallScenario.customScript(
        'Đây là ngân hàng của bạn. Hãy chuyển tiền ngay.',
      ),
    );

    expect(manager.sessionKind, ScamCallSessionKind.simulation);
    expect(manager.modeLabel, 'Simulation Mode');
    expect(spokenScripts, ['Đây là ngân hàng của bạn. Hãy chuyển tiền ngay.']);
    expect(speakerPreferences, [isTrue]);
    expect(liveGateway.stopCount, 1);
    expect(simulationGateway.startCount, 1);
  });

  test('simulation mode uses the live caption transcript gateway', () {
    expect(
      ScamCallSessionManager.buildSimulationTranscriptGateway(),
      isA<LiveCaptionTranscriptGateway>(),
    );
  });
}

ScamCallController _buildController(ScamCallTranscriptGateway gateway) {
  return ScamCallController(
    transcriptGateway: gateway,
    classifier: _FakeScamTextClassifier(),
    analysisDebounce: const Duration(milliseconds: 10),
  );
}

class _FakeTranscriptGateway implements ScamCallTranscriptGateway {
  final _controller = StreamController<LiveTranscriptEvent>.broadcast();

  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<LiveTranscriptEvent> get transcripts => _controller.stream;

  @override
  Future<void> restartLiveSession() async {}

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class _FakeScamTextClassifier implements ScamTextClassifier {
  @override
  Future<ScamAnalysisResult> classifyTranscriptWindow(String transcript) async {
    return const ScamAnalysisResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0.1,
      patterns: [],
      summary: 'No issues.',
      advice: 'No action needed.',
    );
  }
}
