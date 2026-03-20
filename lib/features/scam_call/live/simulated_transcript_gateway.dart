import 'dart:async';

import 'scam_call_transcript_gateway.dart';
import 'live_transcript_models.dart';
import 'simulated_call_scenario.dart';

/// [ScamCallTranscriptGateway] that feeds scenario lines directly as
/// transcript events on a timer — no microphone, Live Caption, or TTS needed.
///
/// Each [SimulatedCallScenario.spokenLines] entry is emitted as a final
/// [LiveTranscriptEvent] at [lineInterval] intervals, giving the classifier
/// time to analyse between lines just like a real conversation.
class SimulatedTranscriptGateway implements ScamCallTranscriptGateway {
  SimulatedTranscriptGateway({
    required this.scenario,
    this.lineInterval = const Duration(seconds: 2),
  });

  final SimulatedCallScenario scenario;
  final Duration lineInterval;

  final StreamController<LiveTranscriptEvent> _transcripts =
      StreamController<LiveTranscriptEvent>.broadcast();

  Timer? _timer;
  int _lineIndex = 0;
  bool _started = false;

  @override
  Stream<LiveTranscriptEvent> get transcripts => _transcripts.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _lineIndex = 0;

    _transcripts.add(
      const LiveTranscriptEvent(kind: LiveTranscriptEventKind.setupComplete),
    );

    final lines = scenario.spokenLines;
    if (lines.isEmpty) return;

    // Emit the first line immediately, then schedule the rest.
    _emitLine(lines[_lineIndex]);
    _lineIndex++;

    if (_lineIndex < lines.length) {
      _timer = Timer.periodic(lineInterval, (_) {
        if (_lineIndex >= lines.length) {
          _timer?.cancel();
          _timer = null;
          return;
        }
        _emitLine(lines[_lineIndex]);
        _lineIndex++;
      });
    }
  }

  void _emitLine(String text) {
    _transcripts.add(
      LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.inputTranscript,
        text: text,
        isFinal: true,
      ),
    );
  }

  @override
  Future<void> restartLiveSession() async {
    // Simulation is self-contained — nothing to restart.
  }

  @override
  Future<void> stop() async {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }
}
