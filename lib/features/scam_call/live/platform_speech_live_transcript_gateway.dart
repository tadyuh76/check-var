import 'dart:async';

import '../speaker_test/platform_speaker_test_gateway.dart';
import '../speaker_test/speaker_test_gateway.dart';
import 'agora_live_transcript_gateway.dart';
import 'live_transcript_models.dart';

class PlatformSpeechLiveTranscriptGateway implements ScamCallTranscriptGateway {
  PlatformSpeechLiveTranscriptGateway({SpeakerTestGateway? speakerGateway})
      : _speakerGateway = speakerGateway ?? PlatformSpeakerTestGateway();

  final SpeakerTestGateway _speakerGateway;
  final StreamController<LiveTranscriptEvent> _transcripts =
      StreamController<LiveTranscriptEvent>.broadcast();

  StreamSubscription<SpeakerTranscriptEvent>? _transcriptSub;
  bool _started = false;

  @override
  Stream<LiveTranscriptEvent> get transcripts => _transcripts.stream;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    _transcriptSub = _speakerGateway.transcriptEvents().listen((event) {
      if (event.text.trim().isEmpty) {
        return;
      }

      // Forward both partial and final transcripts so the controller
      // can analyze during continuous speech (not just after silences).
      _transcripts.add(
        LiveTranscriptEvent(
          kind: LiveTranscriptEventKind.inputTranscript,
          text: event.text,
          isFinal: event.isFinal,
        ),
      );
    });

    await _speakerGateway.startListening();
    await _speakerGateway.waitUntilListeningReady();
    _started = true;
    _transcripts.add(
      const LiveTranscriptEvent(kind: LiveTranscriptEventKind.setupComplete),
    );
  }

  @override
  Future<void> restartLiveSession() async {
    if (!_started) {
      return;
    }

    await _speakerGateway.stopListening();
    await _speakerGateway.startListening();
    await _speakerGateway.waitUntilListeningReady();
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _speakerGateway.stopListening();
    await _transcriptSub?.cancel();
    _transcriptSub = null;
  }
}
