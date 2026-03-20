import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:check_var/features/scam_call/live/simulated_call_scenario.dart';
import 'package:check_var/features/scam_call/live/simulated_transcript_gateway.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emits setupComplete then all scenario lines on a timer', () {
    fakeAsync((async) {
      final scenario = SimulatedCallScenario.customScript(
        'First line. Second line. Third line.',
      );
      final gateway = SimulatedTranscriptGateway(
        scenario: scenario,
        lineInterval: const Duration(seconds: 2),
      );

      final events = <LiveTranscriptEvent>[];
      gateway.transcripts.listen(events.add);
      gateway.start();

      // setupComplete + first line emitted immediately.
      async.flushMicrotasks();
      expect(events, hasLength(2));
      expect(events[0].kind, LiveTranscriptEventKind.setupComplete);
      expect(events[1].kind, LiveTranscriptEventKind.inputTranscript);
      expect(events[1].text, contains('First line'));
      expect(events[1].isFinal, isTrue);

      // After 2s → second line.
      async.elapse(const Duration(seconds: 2));
      expect(events, hasLength(3));
      expect(events[2].text, contains('Second line'));

      // After another 2s → third line.
      async.elapse(const Duration(seconds: 2));
      expect(events, hasLength(4));
      expect(events[3].text, contains('Third line'));

      // No more events after all lines emitted.
      async.elapse(const Duration(seconds: 10));
      expect(events, hasLength(4));

      gateway.stop();
    });
  });

  test('start is idempotent', () {
    fakeAsync((async) {
      final scenario = SimulatedCallScenario.customScript('Hello.');
      final gateway = SimulatedTranscriptGateway(
        scenario: scenario,
        lineInterval: const Duration(seconds: 1),
      );

      final events = <LiveTranscriptEvent>[];
      gateway.transcripts.listen(events.add);
      gateway.start();
      gateway.start(); // second call should be ignored
      async.flushMicrotasks();

      // Only one setupComplete + one line.
      expect(events, hasLength(2));
      gateway.stop();
    });
  });

  test('stop cancels pending line emissions', () {
    fakeAsync((async) {
      final scenario = SimulatedCallScenario.customScript(
        'Line one. Line two. Line three.',
      );
      final gateway = SimulatedTranscriptGateway(
        scenario: scenario,
        lineInterval: const Duration(seconds: 2),
      );

      final events = <LiveTranscriptEvent>[];
      gateway.transcripts.listen(events.add);
      gateway.start();
      async.flushMicrotasks();

      // setupComplete + first line.
      expect(events, hasLength(2));

      // Stop before second line fires.
      gateway.stop();
      async.elapse(const Duration(seconds: 10));

      // No new events after stop.
      expect(events, hasLength(2));
    });
  });

  test('handles empty scenario gracefully', () {
    fakeAsync((async) {
      final scenario = SimulatedCallScenario.customScript('');
      final gateway = SimulatedTranscriptGateway(
        scenario: scenario,
        lineInterval: const Duration(seconds: 1),
      );

      final events = <LiveTranscriptEvent>[];
      gateway.transcripts.listen(events.add);
      gateway.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));

      // Only setupComplete, no transcript lines.
      expect(events, hasLength(1));
      expect(events[0].kind, LiveTranscriptEventKind.setupComplete);
      gateway.stop();
    });
  });

  test('works with preset bank scam scenario', () {
    fakeAsync((async) {
      final gateway = SimulatedTranscriptGateway(
        scenario: SimulatedCallScenario.bankScam,
        lineInterval: const Duration(seconds: 1),
      );

      final transcriptTexts = <String>[];
      gateway.transcripts
          .where((e) => e.kind == LiveTranscriptEventKind.inputTranscript)
          .listen((e) => transcriptTexts.add(e.text));

      gateway.start();
      async.elapse(const Duration(seconds: 10));

      expect(transcriptTexts, hasLength(3));
      expect(transcriptTexts.join(' '), contains('ngân hàng'));
      expect(transcriptTexts.join(' '), contains('chuyển tiền'));
      gateway.stop();
    });
  });
}
