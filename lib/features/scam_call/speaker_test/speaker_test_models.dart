enum SpeakerTestVerdict { usable, borderline, notUsable }

class PhraseAccuracyResult {
  const PhraseAccuracyResult({
    required this.expected,
    required this.recognized,
    required this.matchedWords,
    required this.expectedWords,
    required this.accuracy,
    required this.verdict,
  });

  final String expected;
  final String recognized;
  final int matchedWords;
  final int expectedWords;
  final double accuracy;
  final SpeakerTestVerdict verdict;
}

class SpeakerTestReadiness {
  const SpeakerTestReadiness({
    required this.hasActiveCall,
    required this.hasOverlayPermission,
    required this.hasMicrophonePermission,
    required this.recognizerAvailable,
    required this.isSpeakerphoneOn,
  });

  const SpeakerTestReadiness.empty()
    : hasActiveCall = false,
      hasOverlayPermission = false,
      hasMicrophonePermission = false,
      recognizerAvailable = false,
      isSpeakerphoneOn = false;

  final bool hasActiveCall;
  final bool hasOverlayPermission;
  final bool hasMicrophonePermission;
  final bool recognizerAvailable;
  final bool isSpeakerphoneOn;

  bool get isReadyToListen =>
      hasActiveCall &&
      hasOverlayPermission &&
      hasMicrophonePermission &&
      recognizerAvailable;
}

enum SpeakerTranscriptEventType { partial, finalTranscript, error }

class SpeakerTranscriptEvent {
  const SpeakerTranscriptEvent._({required this.type, this.text, this.message});

  const SpeakerTranscriptEvent.partial(String text)
    : this._(type: SpeakerTranscriptEventType.partial, text: text);

  const SpeakerTranscriptEvent.finalTranscript(String text)
    : this._(type: SpeakerTranscriptEventType.finalTranscript, text: text);

  const SpeakerTranscriptEvent.error(String message)
    : this._(type: SpeakerTranscriptEventType.error, message: message);

  final SpeakerTranscriptEventType type;
  final String? text;
  final String? message;
}
