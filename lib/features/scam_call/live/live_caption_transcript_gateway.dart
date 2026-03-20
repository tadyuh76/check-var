import 'dart:async';

import '../../../core/platform_channel.dart';
import 'scam_call_transcript_gateway.dart';
import 'live_transcript_models.dart';

/// [ScamCallTranscriptGateway] backed by Android's Live Caption feature.
///
/// Listens for `caption_text` events from the native [CheckVarAccessibilityService]
/// via the shared EventChannel and converts them to [LiveTranscriptEvent]s.
///
/// Live Caption transcribes the caller's voice on-device — no microphone needed.
class LiveCaptionTranscriptGateway implements ScamCallTranscriptGateway {
  final StreamController<LiveTranscriptEvent> _transcripts =
      StreamController<LiveTranscriptEvent>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  bool _started = false;

  /// Last emitted text — used for Dart-side deduplication.
  String _lastEmittedText = '';

  @override
  Stream<LiveTranscriptEvent> get transcripts => _transcripts.stream;

  @override
  Future<void> start() async {
    if (_started) return;

    _lastEmittedText = '';

    _eventSub = PlatformChannel.shakeEvents.listen((event) {
      final type = event['type'] as String?;
      if (type != 'caption_text') return;

      final text = (event['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) return;

      // Dart-side dedup — skip if identical to last emission.
      if (text == _lastEmittedText) return;
      _lastEmittedText = text;

      _transcripts.add(
        LiveTranscriptEvent(
          kind: LiveTranscriptEventKind.inputTranscript,
          text: text,
          isFinal: true,
        ),
      );
    });

    await PlatformChannel.startCaptionCapture();
    _started = true;
    _transcripts.add(
      const LiveTranscriptEvent(kind: LiveTranscriptEventKind.setupComplete),
    );
  }

  @override
  Future<void> restartLiveSession() async {
    // Live Caption is passive — no session to restart.
    // Just reset dedup state so new text is emitted.
    _lastEmittedText = '';
  }

  @override
  Future<void> stop() async {
    _started = false;
    await PlatformChannel.stopCaptionCapture();
    await _eventSub?.cancel();
    _eventSub = null;
  }
}
