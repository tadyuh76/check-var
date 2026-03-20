import 'dart:async';

import 'package:check_var/features/scam_call/speaker_test/phrase_accuracy.dart';
import 'package:check_var/features/scam_call/speaker_test/speaker_test_gateway.dart';
import 'package:check_var/features/scam_call/speaker_test/speaker_transcript_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeakerTestGateway implements SpeakerTestGateway {
  FakeSpeakerTestGateway({
    required this.readiness,
    this.readyDelays = const [],
    this.autoRespondWithSpokenPhrase = false,
  });

  final SpeakerTestReadiness readiness;
  final List<Duration> readyDelays;
  final bool autoRespondWithSpokenPhrase;
  final _controller = StreamController<SpeakerTranscriptEvent>();
  int startCallCount = 0;
  int stopCallCount = 0;
  final List<String> spokenPhrases = [];
  bool stopSpeakingCalled = false;
  int _remainingSessionFinals = 0;
  Completer<void>? _readyCompleter;

  bool get startCalled => startCallCount > 0;
  bool get stopCalled => stopCallCount > 0;

  @override
  Future<SpeakerTestReadiness> getReadiness() async => readiness;

  @override
  Stream<SpeakerTranscriptEvent> transcriptEvents() => _controller.stream;

  @override
  Future<void> startListening() async {
    startCallCount++;
    _remainingSessionFinals++;
    final completer = Completer<void>();
    _readyCompleter = completer;
    final sessionIndex = startCallCount - 1;
    final delay = sessionIndex < readyDelays.length
        ? readyDelays[sessionIndex]
        : Duration.zero;
    if (delay == Duration.zero) {
      completer.complete();
    } else {
      Future<void>.delayed(delay, () {
        if (identical(_readyCompleter, completer) && !completer.isCompleted) {
          completer.complete();
        }
      });
    }
  }

  @override
  Future<void> stopListening() async {
    stopCallCount++;
  }

  @override
  Future<void> refreshListeningSession() async {
    await stopListening();
    await startListening();
  }

  @override
  Future<void> waitUntilListeningReady() async {
    await (_readyCompleter?.future ?? Future<void>.value());
  }

  @override
  Future<void> speakPhrase(String text) async {
    spokenPhrases.add(text);
    if (autoRespondWithSpokenPhrase) {
      final recognized = (_readyCompleter?.isCompleted ?? true)
          ? text
          : _clipLeadingWords(text);
      Future<void>.microtask(() => emitSessionFinal(recognized));
    }
  }

  @override
  Future<void> stopSpeaking() async {
    stopSpeakingCalled = true;
  }

  void emitPartial(String text) {
    _controller.add(SpeakerTranscriptEvent(text: text, isFinal: false));
  }

  void emitFinal(String text) {
    _controller.add(SpeakerTranscriptEvent(text: text, isFinal: true));
  }

  void emitSessionFinal(String text) {
    if (_remainingSessionFinals <= 0) return;
    _remainingSessionFinals--;
    emitFinal(text);
  }

  void dispose() {
    _controller.close();
  }

  String _clipLeadingWords(String text) {
    final words = text.split(' ');
    if (words.length <= 2) return '';
    return words.sublist(2).join(' ');
  }
}

void main() {
  late FakeSpeakerTestGateway gateway;

  SpeakerTestReadiness allReady() => const SpeakerTestReadiness(
    hasActiveCall: true,
    hasOverlayPermission: true,
    hasMicrophonePermission: true,
    recognizerAvailable: true,
    isSpeakerphoneOn: true,
  );

  setUp(() {
    gateway = FakeSpeakerTestGateway(readiness: allReady());
  });

  tearDown(() {
    gateway.dispose();
  });

  group('loadReadiness', () {
    test('populates readiness from gateway', () async {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const ['xin chao'],
      );

      await controller.loadReadiness();

      expect(controller.readiness.hasMicrophonePermission, isTrue);
      expect(controller.readiness.recognizerAvailable, isTrue);
      expect(controller.readiness.isReadyToListen, isTrue);
      expect(controller.blockingMessage, isNull);

      controller.dispose();
    });

    test('reports blocking message when recognizer unavailable', () async {
      gateway = FakeSpeakerTestGateway(
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

      await controller.loadReadiness();

      expect(controller.readiness.isReadyToListen, isFalse);
      expect(controller.blockingMessage, isNotNull);

      controller.dispose();
    });
  });

  group('runTest', () {
    test('plays each phrase via TTS and scores mic output', () async {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const [
          'vui long xac nhan so tai khoan',
          'chuyen tien ngay lap tuc',
        ],
      );

      await controller.loadReadiness();
      final testFuture = controller.runTest();

      await Future.delayed(Duration.zero);
      gateway.emitFinal('vui long xac nhan so tai khoan');
      await Future.delayed(Duration.zero);

      await Future.delayed(const Duration(milliseconds: 900));
      gateway.emitFinal('chuyen tien ngay lap tuc');
      await Future.delayed(Duration.zero);

      await testFuture;

      expect(gateway.spokenPhrases, [
        'vui long xac nhan so tai khoan',
        'chuyen tien ngay lap tuc',
      ]);
      expect(controller.phraseScores, hasLength(2));
      expect(controller.phraseScores[0].accuracy, 1.0);
      expect(controller.phraseScores[1].accuracy, 1.0);
      expect(controller.isRunning, isFalse);
      expect(gateway.startCalled, isTrue);
      expect(gateway.stopCalled, isTrue);

      controller.dispose();
    });

    test('scores partial match when mic hears differently', () async {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const ['chuyen tien ngay lap tuc'],
      );

      await controller.loadReadiness();
      final testFuture = controller.runTest();

      await Future.delayed(Duration.zero);
      gateway.emitFinal('chuyen tien ngay');
      await Future.delayed(Duration.zero);

      await testFuture;

      expect(controller.phraseScores, hasLength(1));
      expect(controller.phraseScores[0].accuracy, 0.6);

      controller.dispose();
    });

    test(
      'refreshes listening between phrases so later phrases still transcribe',
      () async {
        final controller = SpeakerTranscriptController(
          gateway: gateway,
          expectedPhrases: const [
            'vui long xac nhan so tai khoan',
            'chuyen tien ngay lap tuc',
          ],
        );

        await controller.loadReadiness();
        final testFuture = controller.runTest();

        await Future.delayed(Duration.zero);
        gateway.emitSessionFinal('vui long xac nhan so tai khoan');
        await Future.delayed(const Duration(milliseconds: 900));

        expect(
          gateway.startCallCount,
          2,
          reason: 'Each scripted phrase needs a fresh recognition session.',
        );

        gateway.emitSessionFinal('chuyen tien ngay lap tuc');
        await Future.delayed(Duration.zero);
        await testFuture;

        expect(controller.phraseScores, hasLength(2));
        expect(controller.phraseScores[0].accuracy, 1.0);
        expect(controller.phraseScores[1].accuracy, 1.0);

        controller.dispose();
      },
    );

    test(
      'waits for recognizer readiness before longer later phrases',
      () async {
        gateway = FakeSpeakerTestGateway(
          readiness: allReady(),
          readyDelays: const [
            Duration.zero,
            Duration(milliseconds: 300),
            Duration(milliseconds: 1500),
            Duration(milliseconds: 1500),
          ],
          autoRespondWithSpokenPhrase: true,
        );
        final controller = SpeakerTranscriptController(
          gateway: gateway,
          expectedPhrases: const [
            'Vui long xac nhan so tai khoan cua ban',
            'Chuyen tien ngay lap tuc',
            'Chung toi can so can cuoc cong dan cua ban',
            'Ban da trung thuong mot giai thuong lon',
          ],
        );

        await controller.loadReadiness();
        await controller.runTest();

        expect(controller.phraseScores, hasLength(4));
        expect(
          controller.phraseScores.map((score) => score.accuracy),
          everyElement(1.0),
        );

        controller.dispose();
      },
    );

    test(
      'handles timeout when mic hears nothing',
      () async {
        final controller = SpeakerTranscriptController(
          gateway: gateway,
          expectedPhrases: const ['vui long xac nhan so tai khoan'],
        );

        await controller.loadReadiness();
        final testFuture = controller.runTest();
        await testFuture;

        expect(controller.phraseScores, hasLength(1));
        expect(controller.phraseScores[0].accuracy, 0.0);
        expect(controller.phraseScores[0].recognized, '');

        controller.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  group('stopTest', () {
    test('cancels running test', () async {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const ['cau thu nhat', 'cau thu hai', 'cau thu ba'],
      );

      await controller.loadReadiness();
      final testFuture = controller.runTest();

      await Future.delayed(Duration.zero);
      gateway.emitFinal('cau thu nhat');
      await Future.delayed(Duration.zero);

      await controller.stopTest();
      await testFuture;

      expect(controller.isRunning, isFalse);
      expect(gateway.stopSpeakingCalled, isTrue);
      expect(controller.phraseScores.length, lessThan(3));

      controller.dispose();
    });
  });

  group('transcript handling', () {
    test('stores partial transcript separately', () async {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const ['vui long xac nhan so tai khoan'],
      );

      await controller.loadReadiness();
      await controller.startListening();
      gateway.emitPartial('xin');

      await Future.delayed(Duration.zero);

      expect(controller.partialTranscript, 'xin');
      expect(controller.transcriptHistory, isEmpty);

      controller.dispose();
    });
  });

  group('pre-set test mode', () {
    test('expectedPhrases are exposed for display', () {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const ['cau thu nhat', 'cau thu hai'],
      );

      expect(controller.expectedPhrases, hasLength(2));
      expect(controller.expectedPhrases.first, 'cau thu nhat');

      controller.dispose();
    });

    test('summaryVerdict reflects overall accuracy', () async {
      final controller = SpeakerTranscriptController(
        gateway: gateway,
        expectedPhrases: const ['vui long xac nhan so tai khoan'],
      );

      await controller.loadReadiness();
      final testFuture = controller.runTest();

      await Future.delayed(Duration.zero);
      gateway.emitFinal('vui long xac nhan so tai khoan');
      await Future.delayed(Duration.zero);

      await testFuture;

      expect(controller.summaryVerdict, SpeakerTestVerdict.usable);

      controller.dispose();
    });
  });
}
