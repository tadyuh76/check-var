import 'dart:async';

import 'package:check_var/core/api/gemini_scam_text_api.dart';
import 'package:check_var/features/scam_call/live/scam_call_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:check_var/features/scam_call/scam_call_controller.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      null,
    );
  });
  test('appends live transcript events and throttles scam analysis', () async {
    final gateway = FakeAgoraLiveTranscriptGateway();
    final classifier = FakeScamTextClassifier(
      queuedResults: [
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.suspicious,
          confidence: 0.81,
          patterns: ['khan cap'],
          summary: 'Nguoi goi dang gay ap luc phai hanh dong ngay',
          advice: 'Binh tinh va tu xac minh qua kenh khac',
        ),
      ],
    );
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );

    await controller.startListening();
    gateway.emitTranscript('ban phai lam ngay');
    gateway.emitTranscript('ban phai chuyen tien ngay bay gio');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.transcript, hasLength(2));
    expect(controller.transcript.last.text, 'ban phai chuyen tien ngay bay gio');
    expect(classifier.callCount, 1);
    expect(controller.threatLevel, ThreatLevel.suspicious);
    expect(controller.summary, contains('gay ap luc'));
  });

  test('escalates threat level monotonically within a session', () async {
    final gateway = FakeAgoraLiveTranscriptGateway();
    final classifier = FakeScamTextClassifier(
      queuedResults: [
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.scam,
          confidence: 0.95,
          patterns: ['the qua tang'],
          summary: 'Nguoi goi yeu cau mua the qua tang',
          advice: 'Tat may ngay lap tuc',
        ),
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.safe,
          confidence: 0.2,
          patterns: [],
          summary: 'Model became unsure later',
          advice: 'No action needed',
        ),
      ],
    );
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );

    await controller.startListening();
    gateway.emitTranscript('mua the qua tang ngay');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gateway.emitTranscript('thoi bo qua di');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.threatLevel, ThreatLevel.scam);
    expect(controller.summary, contains('the qua tang'));
  });

  test('restarts the live session when a go-away event arrives', () async {
    final gateway = FakeAgoraLiveTranscriptGateway();
    final classifier = FakeScamTextClassifier(queuedResults: const []);
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );

    await controller.startListening();
    gateway.emitGoAway();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(gateway.restartCallCount, 1);
    expect(controller.sessionStatus, ScamCallSessionStatus.listening);
  });

  test('publishes overlay status updates for session and threat changes', () async {
    final gateway = FakeAgoraLiveTranscriptGateway();
    final classifier = FakeScamTextClassifier(
      queuedResults: [
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.suspicious,
          confidence: 0.82,
          patterns: ['khan cap'],
          summary: 'Nguoi goi dang thuc ep hanh dong ngay.',
          advice: 'Tu xac minh truoc khi lam theo.',
        ),
      ],
    );
    final updates = <(ThreatLevel, ScamCallSessionStatus)>[];
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
      onOverlayStatusUpdate: (threatLevel, sessionStatus) async {
        updates.add((threatLevel, sessionStatus));
      },
    );

    await controller.startListening();
    gateway.emitTranscript('gui tien ngay bay gio');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(
      updates,
      contains((ThreatLevel.safe, ScamCallSessionStatus.listening)),
    );
    expect(
      updates,
      contains((ThreatLevel.suspicious, ScamCallSessionStatus.listening)),
    );
  });
}

class FakeAgoraLiveTranscriptGateway implements ScamCallTranscriptGateway {
  final _controller = StreamController<LiveTranscriptEvent>.broadcast(
    sync: true,
  );

  bool started = false;
  int restartCallCount = 0;

  @override
  Future<void> restartLiveSession() async {
    restartCallCount++;
  }

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  void emitGoAway() {
    _controller.add(
      const LiveTranscriptEvent(kind: LiveTranscriptEventKind.goAway),
    );
  }

  void emitTranscript(String text) {
    _controller.add(
      LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.inputTranscript,
        text: text,
        isFinal: true,
      ),
    );
  }

  @override
  Stream<LiveTranscriptEvent> get transcripts => _controller.stream;
}

class FakeScamTextClassifier implements ScamTextClassifier {
  FakeScamTextClassifier({required List<ScamAnalysisResult> queuedResults})
    : _queuedResults = List.of(queuedResults);

  final List<ScamAnalysisResult> _queuedResults;
  int callCount = 0;

  @override
  Future<ScamAnalysisResult> classifyTranscriptWindow(String transcript) async {
    callCount++;
    if (_queuedResults.isEmpty) {
      return const ScamAnalysisResult(
        threatLevel: ThreatLevel.safe,
        confidence: 0,
        patterns: [],
        summary: 'No classifier result queued.',
        advice: 'No action needed.',
      );
    }
    return _queuedResults.removeAt(0);
  }
}
