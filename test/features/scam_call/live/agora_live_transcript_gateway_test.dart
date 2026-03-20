import 'dart:async';
import 'dart:typed_data';

import 'package:check_var/core/api/live_transcript_source.dart';
import 'package:check_var/features/scam_call/live/agora_live_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/live_audio_frame.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'forwards agora pcm frames to the live client and exposes transcript events',
    () async {
      final audioSource = FakeAgoraAudioSource();
      final liveSource = FakeLiveTranscriptSource();
      final gateway = AgoraLiveTranscriptGateway(
        audioSource: audioSource,
        liveSource: liveSource,
      );

      await gateway.start();
      audioSource.emitPcm(Uint8List.fromList(List.filled(3200, 1)));

      expect(liveSource.sentAudioChunks, hasLength(1));

      final transcriptFuture = gateway.transcripts.first;
      liveSource.emitTranscript('your account is blocked');
      final transcript = await transcriptFuture;
      expect(transcript.text, 'your account is blocked');
    },
  );

  test(
    'drops audio frames when the live client disconnects mid-stream',
    () async {
      final audioSource = FakeAgoraAudioSource();
      final liveSource = FakeLiveTranscriptSource();
      final gateway = AgoraLiveTranscriptGateway(
        audioSource: audioSource,
        liveSource: liveSource,
      );
      Object? uncaughtError;

      await runZonedGuarded(() async {
        await gateway.start();
        await liveSource.disconnect();

        audioSource.emitPcm(Uint8List.fromList(List.filled(3200, 1)));
        await Future<void>.delayed(Duration.zero);
      }, (error, stackTrace) {
        uncaughtError = error;
      });

      expect(uncaughtError, isNull);
      expect(liveSource.sentAudioChunks, isEmpty);
    },
  );
}

class FakeAgoraAudioSource implements LiveAudioSource {
  final _controller = StreamController<LiveAudioFrame>.broadcast(sync: true);

  bool initialized = false;
  bool listening = false;

  @override
  Stream<LiveAudioFrame> get audioFrames => _controller.stream;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> startListening() async {
    listening = true;
  }

  @override
  Future<void> stopListening() async {
    listening = false;
  }

  void emitPcm(Uint8List bytes) {
    _controller.add(
      LiveAudioFrame(
        pcmBytes: bytes,
        sampleRate: 16000,
        channels: 1,
        bytesPerSample: 2,
        timestamp: DateTime.now(),
      ),
    );
  }
}

class FakeLiveTranscriptSource implements LiveTranscriptSource {
  final _controller = StreamController<LiveTranscriptEvent>.broadcast(
    sync: true,
  );
  final List<Uint8List> sentAudioChunks = [];

  bool connected = false;

  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

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
  Stream<LiveTranscriptEvent> get events => _controller.stream;

  @override
  Future<void> sendAudioPcm(
    Uint8List pcmBytes, {
    required int sampleRate,
  }) async {
    if (!connected) {
      throw StateError('Gemini Live API socket is not connected.');
    }
    sentAudioChunks.add(pcmBytes);
  }
}
