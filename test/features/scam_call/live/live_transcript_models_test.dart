import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a live input transcription event', () {
    final event = LiveTranscriptEvent.fromServerMessage({
      'serverContent': {
        'inputTranscription': {'text': 'vui long mua the qua tang ngay'},
      },
    });

    expect(event, isNotNull);
    expect(event!.text, 'vui long mua the qua tang ngay');
    expect(event.kind, LiveTranscriptEventKind.inputTranscript);
    expect(event.isFinal, isTrue);
  });

  test('parses a go-away event for forced reconnect handling', () {
    final event = LiveTranscriptEvent.fromServerMessage({
      'goAway': {'timeLeft': '30s'},
    });

    expect(event, isNotNull);
    expect(event!.kind, LiveTranscriptEventKind.goAway);
  });
}
