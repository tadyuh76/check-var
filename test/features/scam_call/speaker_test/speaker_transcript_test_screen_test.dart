import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/features/scam_call/speaker_test/speaker_test_gateway.dart';
import 'package:check_var/features/scam_call/speaker_test/speaker_transcript_controller.dart';
import 'package:check_var/features/scam_call/speaker_test/speaker_transcript_test_screen.dart';

class FakeSpeakerTestGateway implements SpeakerTestGateway {
  FakeSpeakerTestGateway({required this.readiness});

  final SpeakerTestReadiness readiness;
  final _controller = StreamController<SpeakerTranscriptEvent>.broadcast();

  @override
  Future<SpeakerTestReadiness> getReadiness() async => readiness;

  @override
  Stream<SpeakerTranscriptEvent> transcriptEvents() => _controller.stream;

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> waitUntilListeningReady() async {}

  @override
  Future<void> refreshListeningSession() async {}

  @override
  Future<void> speakPhrase(String text) async {}

  @override
  Future<void> stopSpeaking() async {}

  void emitFinal(String text) {
    _controller.add(SpeakerTranscriptEvent(text: text, isFinal: true));
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  test('default speaker test phrases are Vietnamese', () {
    expect(kDefaultTestPhrases.first, 'Vui lòng xác nhận số tài khoản của bạn');
    expect(kDefaultTestPhrases, contains('Thanh toán bằng thẻ quà tặng'));
  });

  testWidgets('shows app bar title and test phrases', (tester) async {
    final gateway = FakeSpeakerTestGateway(
      readiness: const SpeakerTestReadiness(
        hasActiveCall: false,
        hasOverlayPermission: false,
        hasMicrophonePermission: true,
        recognizerAvailable: true,
        isSpeakerphoneOn: false,
      ),
    );
    final controller = SpeakerTranscriptController(
      gateway: gateway,
      expectedPhrases: const ['cau thu thu nhat'],
    );

    await tester.pumpWidget(
      MaterialApp(home: SpeakerTranscriptTestScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Speaker Call Test'), findsOneWidget);
    expect(find.text('1. "cau thu thu nhat"'), findsOneWidget);
    expect(find.text('Run Speaker Test'), findsOneWidget);

    controller.dispose();
    gateway.dispose();
  });

  testWidgets('shows blocking message when recognizer unavailable', (
    tester,
  ) async {
    final gateway = FakeSpeakerTestGateway(
      readiness: const SpeakerTestReadiness(
        hasActiveCall: true,
        hasOverlayPermission: true,
        hasMicrophonePermission: true,
        recognizerAvailable: false,
        isSpeakerphoneOn: true,
      ),
    );
    final controller = SpeakerTranscriptController(
      gateway: gateway,
      expectedPhrases: const ['xin chao'],
    );

    await tester.pumpWidget(
      MaterialApp(home: SpeakerTranscriptTestScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('On-device speech recognition is unavailable on this device.'),
      findsOneWidget,
    );

    controller.dispose();
    gateway.dispose();
  });

  testWidgets('readiness card shows check marks', (tester) async {
    final gateway = FakeSpeakerTestGateway(
      readiness: const SpeakerTestReadiness(
        hasActiveCall: true,
        hasOverlayPermission: true,
        hasMicrophonePermission: true,
        recognizerAvailable: true,
        isSpeakerphoneOn: false,
      ),
    );
    final controller = SpeakerTranscriptController(
      gateway: gateway,
      expectedPhrases: const ['xin chao'],
    );

    await tester.pumpWidget(
      MaterialApp(home: SpeakerTranscriptTestScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Speech Recognizer'), findsOneWidget);

    controller.dispose();
    gateway.dispose();
  });

  testWidgets('bottom action padding accounts for the Android nav bar', (
    tester,
  ) async {
    final gateway = FakeSpeakerTestGateway(
      readiness: const SpeakerTestReadiness(
        hasActiveCall: true,
        hasOverlayPermission: true,
        hasMicrophonePermission: true,
        recognizerAvailable: true,
        isSpeakerphoneOn: false,
      ),
    );
    final controller = SpeakerTranscriptController(
      gateway: gateway,
      expectedPhrases: const ['xin chao'],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 24)),
        child: MaterialApp(
          home: SpeakerTranscriptTestScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final padding = tester.widget<Padding>(
      find.ancestor(
        of: find.byKey(const Key('speaker_test_run_button')),
        matching: find.byType(Padding),
      ).first,
    );

    expect(padding.padding, const EdgeInsets.fromLTRB(16, 16, 16, 40));

    controller.dispose();
    gateway.dispose();
  });
}
