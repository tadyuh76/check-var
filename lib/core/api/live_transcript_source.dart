import 'dart:typed_data';

import '../../features/scam_call/live/live_transcript_models.dart';

abstract interface class LiveTranscriptSource {
  Stream<LiveTranscriptEvent> get events;

  Future<void> connect();

  Future<void> sendAudioPcm(Uint8List pcmBytes, {required int sampleRate});

  Future<void> disconnect();
}
