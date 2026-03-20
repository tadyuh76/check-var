import 'dart:async';

import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:check_var/features/scam_call/live/platform_speech_live_transcript_gateway.dart';
import 'package:check_var/features/scam_call/speaker_test/speaker_test_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards both partial and final transcripts as live transcript events', () async {
    final speakerGateway = FakeSpeakerTestGateway();
    final gateway = PlatformSpeechLiveTranscriptGateway(
      speakerGateway: speakerGateway,
    );

    await gateway.start();

    final events = <LiveTranscriptEvent>[];
    gateway.transcripts.listen(events.add);

    speakerGateway.emitTranscript('xin chao', isFinal: false);
    speakerGateway.emitTranscript('xin chao tu cuoc goi', isFinal: true);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    // Partial is forwarded
    expect(events[0].text, 'xin chao');
    expect(events[0].isFinal, false);
    // Final is forwarded
    expect(events[1].text, 'xin chao tu cuoc goi');
    expect(events[1].isFinal, true);
    expect(speakerGateway.startCount, 1);
  });

  test('restartLiveSession restarts the platform recognizer', () async {
    final speakerGateway = FakeSpeakerTestGateway();
    final gateway = PlatformSpeechLiveTranscriptGateway(
      speakerGateway: speakerGateway,
    );

    await gateway.start();
    await gateway.restartLiveSession();

    expect(speakerGateway.stopCount, 1);
    expect(speakerGateway.startCount, 2);
  });

  test('start waits for recognizer readiness before setup completes', () async {
    final speakerGateway = FakeSpeakerTestGateway(startReady: false);
    final gateway = PlatformSpeechLiveTranscriptGateway(
      speakerGateway: speakerGateway,
    );
    final events = <LiveTranscriptEvent>[];
    final sub = gateway.transcripts.listen(events.add);

    final startFuture = gateway.start();
    await Future<void>.delayed(Duration.zero);

    expect(speakerGateway.startCount, 1);
    expect(events, isEmpty);

    speakerGateway.markReady();
    await startFuture;
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.kind, LiveTranscriptEventKind.setupComplete);
    await sub.cancel();
  });
}

class FakeSpeakerTestGateway implements SpeakerTestGateway {
  FakeSpeakerTestGateway({this.startReady = true});

  final bool startReady;
  final _controller = StreamController<SpeakerTranscriptEvent>.broadcast();
  Completer<void>? _readyCompleter;

  int startCount = 0;
  int stopCount = 0;

  void emitTranscript(String text, {required bool isFinal}) {
    _controller.add(SpeakerTranscriptEvent(text: text, isFinal: isFinal));
  }

  @override
  Future<SpeakerTestReadiness> getReadiness() async =>
      SpeakerTestReadiness.empty();

  @override
  Future<void> speakPhrase(String text) async {}

  @override
  Future<void> startListening() async {
    startCount++;
    _readyCompleter = Completer<void>();
    if (startReady) {
      _readyCompleter?.complete();
    }
  }

  @override
  Future<void> stopListening() async {
    stopCount++;
  }

  @override
  Future<void> waitUntilListeningReady() async {
    await (_readyCompleter?.future ?? Future<void>.value());
  }

  @override
  Future<void> refreshListeningSession() async {
    stopCount++;
    startCount++;
    _readyCompleter = Completer<void>();
    if (startReady) {
      _readyCompleter?.complete();
    }
  }

  @override
  Future<void> stopSpeaking() async {}

  @override
  Stream<SpeakerTranscriptEvent> transcriptEvents() => _controller.stream;

  void markReady() {
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.complete();
    }
  }
}
