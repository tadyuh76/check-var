/// Readiness state for the speaker transcription test.
class SpeakerTestReadiness {
  const SpeakerTestReadiness({
    required this.hasActiveCall,
    required this.hasOverlayPermission,
    required this.hasMicrophonePermission,
    required this.recognizerAvailable,
    required this.isSpeakerphoneOn,
  });

  factory SpeakerTestReadiness.empty() => const SpeakerTestReadiness(
    hasActiveCall: false,
    hasOverlayPermission: false,
    hasMicrophonePermission: false,
    recognizerAvailable: false,
    isSpeakerphoneOn: false,
  );

  final bool hasActiveCall;
  final bool hasOverlayPermission;
  final bool hasMicrophonePermission;
  final bool recognizerAvailable;
  final bool isSpeakerphoneOn;

  /// Ready to listen if mic + recognizer are available.
  /// Active call and speakerphone are required for real call mode,
  /// but not for the pre-set script test.
  bool get isReadyToListen => hasMicrophonePermission && recognizerAvailable;
}

/// A transcript chunk from the speech recognizer.
class SpeakerTranscriptEvent {
  const SpeakerTranscriptEvent({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

/// Abstracts platform interactions for testability.
abstract class SpeakerTestGateway {
  Future<SpeakerTestReadiness> getReadiness();
  Stream<SpeakerTranscriptEvent> transcriptEvents();
  Future<void> startListening();
  Future<void> stopListening();

  /// Wait until the active listening session is ready to capture speech.
  Future<void> waitUntilListeningReady() async {}

  /// Refresh the recognizer between scripted phrases so the next phrase
  /// starts with a fresh listening session.
  Future<void> refreshListeningSession() async {
    await stopListening();
    await startListening();
  }

  /// Play [text] aloud via TTS. Completes when the utterance finishes.
  Future<void> speakPhrase(String text);

  /// Cancel any in-progress TTS playback.
  Future<void> stopSpeaking();
}
