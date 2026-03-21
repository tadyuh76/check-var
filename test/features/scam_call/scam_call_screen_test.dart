import 'dart:async';

import 'package:check_var/core/api/gemini_scam_text_api.dart';
import 'package:check_var/features/scam_call/live/scam_call_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:check_var/features/scam_call/scam_call_controller.dart';
import 'package:check_var/features/scam_call/scam_call_screen.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  testWidgets(
    'renders live transcript status, threat banner, and advice from an injected controller',
    (tester) async {
      final gateway = FakeScamCallTranscriptGateway();
      final classifier = FakeScamTextClassifier(
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.suspicious,
          confidence: 0.81,
          scamProbability: 0.81,
          patterns: ['urgency'],
          summary: 'Caller pressures the target to act immediately',
          advice: 'Slow down and verify independently',
        ),
      );
      final controller = ScamCallController(
        transcriptGateway: gateway,
        classifier: classifier,
        analysisDebounce: const Duration(milliseconds: 10),
      );

      await tester.pumpWidget(
        MaterialApp(home: ScamCallScreen(controller: controller)),
      );

      // Two analyses needed for the consecutive gate to pass.
      gateway.emitTranscript('you must act right now');
      await tester.pump(const Duration(milliseconds: 30));
      gateway.emitTranscript('send money immediately');
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.text('Đang nghe'), findsOneWidget);
      // EMA of 0.81 is above 0.55 with 2 consecutive → scam
      expect(find.text('LỪA ĐẢO'), findsOneWidget);
      expect(find.text('you must act right now'), findsOneWidget);
      expect(find.text('Slow down and verify independently'), findsOneWidget);
    },
  );

  testWidgets('renders simulation mode label when provided', (tester) async {
    final gateway = FakeScamCallTranscriptGateway();
    final classifier = FakeScamTextClassifier(
      const ScamAnalysisResult(
        threatLevel: ThreatLevel.safe,
        confidence: 0.2,
        patterns: [],
        summary: 'Looks routine.',
        advice: 'No action needed.',
      ),
    );
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScamCallScreen(
          controller: controller,
          modeLabel: 'Simulation Mode',
        ),
      ),
    );

    expect(find.text('Simulation Mode'), findsOneWidget);
  });

  testWidgets('bottom control padding accounts for the Android nav bar', (
    tester,
  ) async {
    final gateway = FakeScamCallTranscriptGateway();
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: FakeScamTextClassifier(
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.safe,
          confidence: 0.2,
          patterns: [],
          summary: 'Looks routine.',
          advice: 'No action needed.',
        ),
      ),
      analysisDebounce: const Duration(milliseconds: 10),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: 28),
        ),
        child: MaterialApp(home: ScamCallScreen(controller: controller)),
      ),
    );

    final button = tester.widget<SizedBox>(
      find.byKey(const Key('scam_call_controls_button')),
    );
    final padding = tester.widget<Container>(
      find.ancestor(
        of: find.byKey(const Key('scam_call_controls_button')),
        matching: find.byType(Container),
      ).first,
    ).padding as EdgeInsets;

    expect(button.width, double.infinity);
    expect(padding, const EdgeInsets.fromLTRB(16, 16, 16, 44));
  });

  testWidgets(
    'does not start or stop an attached shared controller when lifecycle management is disabled',
    (tester) async {
      final gateway = CountingScamCallTranscriptGateway();
      final controller = ScamCallController(
        transcriptGateway: gateway,
        classifier: FakeScamTextClassifier(
          const ScamAnalysisResult(
            threatLevel: ThreatLevel.safe,
            confidence: 0.2,
            patterns: [],
            summary: 'Looks routine.',
            advice: 'No action needed.',
          ),
        ),
        analysisDebounce: const Duration(milliseconds: 10),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ScamCallScreen(
            controller: controller,
            manageSessionLifecycle: false,
          ),
        ),
      );

      await tester.pump();
      expect(gateway.startCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(gateway.stopCount, 0);
    },
  );
}

class FakeScamCallTranscriptGateway implements ScamCallTranscriptGateway {
  final _controller = StreamController<LiveTranscriptEvent>.broadcast(
    sync: true,
  );

  @override
  Future<void> restartLiveSession() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void emitTranscript(String text) {
    _controller.add(
      LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.inputTranscript,
        text: text,
        isFinal: true,
      ),
    );
  }

  @override
  Stream<LiveTranscriptEvent> get transcripts => _controller.stream;
}

class CountingScamCallTranscriptGateway implements ScamCallTranscriptGateway {
  final _controller = StreamController<LiveTranscriptEvent>.broadcast();

  int startCount = 0;
  int stopCount = 0;

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

  @override
  Stream<LiveTranscriptEvent> get transcripts => _controller.stream;
}

class FakeScamTextClassifier implements ScamTextClassifier {
  FakeScamTextClassifier(this.result);

  final ScamAnalysisResult result;

  @override
  Future<ScamAnalysisResult> classifyTranscriptWindow(String transcript) async {
    return result;
  }
}
