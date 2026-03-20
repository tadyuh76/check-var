import 'live_transcript_models.dart';

abstract interface class ScamCallTranscriptGateway {
  Stream<LiveTranscriptEvent> get transcripts;

  Future<void> start();

  Future<void> restartLiveSession();

  Future<void> stop();
}
