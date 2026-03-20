import 'dart:async';

import '../../../core/platform_channel.dart';
import 'speaker_test_gateway.dart';

/// Concrete [SpeakerTestGateway] backed by platform channels.
///
/// Bridges Android native speech recognition, call-state APIs, and TTS
/// into the Flutter speaker test flow.
class PlatformSpeakerTestGateway implements SpeakerTestGateway {
  StreamController<SpeakerTranscriptEvent>? _eventController;
  StreamSubscription? _platformSub;
  Completer<void>? _recognizerReadyCompleter;

  /// Completer that resolves when the native TTS engine finishes an utterance.
  Completer<void>? _ttsCompleter;

  @override
  Future<SpeakerTestReadiness> getReadiness() async {
    // Request runtime permissions before querying readiness state.
    await PlatformChannel.requestSpeakerTestPermissions();
    final map = await PlatformChannel.getSpeakerTestReadiness();
    return SpeakerTestReadiness(
      hasActiveCall: map['hasActiveCall'] as bool? ?? false,
      hasOverlayPermission: map['hasOverlayPermission'] as bool? ?? false,
      hasMicrophonePermission: map['hasMicrophonePermission'] as bool? ?? false,
      recognizerAvailable: map['recognizerAvailable'] as bool? ?? false,
      isSpeakerphoneOn: map['isSpeakerphoneOn'] as bool? ?? false,
    );
  }

  @override
  Stream<SpeakerTranscriptEvent> transcriptEvents() {
    _eventController ??= StreamController<SpeakerTranscriptEvent>.broadcast();

    _platformSub ??= PlatformChannel.shakeEvents.listen((event) {
      final type = event['type'] as String?;
      if (type == 'transcript_partial' || type == 'transcript_final') {
        _eventController?.add(
          SpeakerTranscriptEvent(
            text: event['text'] as String? ?? '',
            isFinal: type == 'transcript_final',
          ),
        );
      } else if (type == 'tts_done') {
        if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
          _ttsCompleter!.complete();
        }
      } else if (type == 'recognizer_ready') {
        if (_recognizerReadyCompleter != null &&
            !_recognizerReadyCompleter!.isCompleted) {
          _recognizerReadyCompleter!.complete();
        }
      }
    });

    return _eventController!.stream;
  }

  @override
  Future<void> startListening() async {
    _recognizerReadyCompleter = Completer<void>();
    await PlatformChannel.startSpeakerRecognition();
  }

  @override
  Future<void> stopListening() async {
    await PlatformChannel.stopSpeakerRecognition();
    await _platformSub?.cancel();
    _platformSub = null;
    await _eventController?.close();
    _eventController = null;
    if (_recognizerReadyCompleter != null &&
        !_recognizerReadyCompleter!.isCompleted) {
      _recognizerReadyCompleter!.complete();
    }
    _recognizerReadyCompleter = null;
  }

  @override
  Future<void> refreshListeningSession() async {
    _recognizerReadyCompleter = Completer<void>();
    await PlatformChannel.stopSpeakerRecognition();
    await PlatformChannel.startSpeakerRecognition();
  }

  @override
  Future<void> waitUntilListeningReady() async {
    final completer = _recognizerReadyCompleter;
    if (completer == null) return;
    await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
  }

  @override
  Future<void> speakPhrase(String text) async {
    _ttsCompleter = Completer<void>();
    await PlatformChannel.speakText(text);
    // Wait for the native TTS engine to finish, with a generous timeout
    // so the test doesn't hang if TTS fails silently.
    await _ttsCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
    _ttsCompleter = null;
  }

  @override
  Future<void> stopSpeaking() async {
    await PlatformChannel.stopSpeaking();
    if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
      _ttsCompleter!.complete();
    }
    _ttsCompleter = null;
  }
}
