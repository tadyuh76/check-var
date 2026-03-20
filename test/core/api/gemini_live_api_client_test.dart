import 'dart:async';
import 'dart:convert';

import 'package:check_var/core/api/gemini_live_api_client.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'connect sends setup and emits parsed input transcript events',
    () async {
      final socket = FakeLiveSocket();
      final client = GeminiLiveApiClient(
        socketFactory: (_) async => socket,
        apiKey: 'hackathon-key',
        model: 'gemini-live-2.5-flash-preview',
      );

      await client.connect();

      final sentSetup =
          jsonDecode(socket.sentMessages.single) as Map<String, dynamic>;
      expect(
        sentSetup['setup']['model'],
        contains('gemini-live-2.5-flash-preview'),
      );
      expect(
        sentSetup['setup']['generationConfig']['responseModalities'],
        ['AUDIO'],
      );
      expect(sentSetup['setup']['inputAudioTranscription'], isA<Map>());

      final eventFuture = client.events.firstWhere(
        (event) => event.kind == LiveTranscriptEventKind.inputTranscript,
      );
      socket.pushServerMessage({
        'serverContent': {
          'inputTranscription': {'text': 'mua the qua tang ngay lap tuc'},
        },
      });

      final event = await eventFuture;
      expect(event.text, 'mua the qua tang ngay lap tuc');
    },
  );
}

class FakeLiveSocket implements LiveSocket {
  final _controller = StreamController<String>.broadcast();
  final List<String> sentMessages = [];

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> close([int? code, String? reason]) async {
    await _controller.close();
  }

  void pushServerMessage(Map<String, dynamic> message) {
    _controller.add(jsonEncode(message));
  }

  @override
  void send(String message) {
    sentMessages.add(message);
  }

  @override
  Stream<String> get stream => _controller.stream;
}
