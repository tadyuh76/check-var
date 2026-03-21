import 'dart:async';

import 'package:check_var/core/api/gemini_scam_text_api.dart';
import 'package:check_var/features/scam_call/live/scam_call_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:check_var/features/scam_call/scam_call_controller.dart';
import 'package:check_var/models/call_result.dart' hide ThreatLevel;
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('com.checkvar/events'),
      MockStreamHandler.inline(
        onListen: (args, sink) {},
        onCancel: (args) {},
      ),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('com.checkvar/events'),
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
          scamProbability: 0.81,
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
    // Single analysis: EMA is high but consecutive non-safe is only 1,
    // so the min-analyses gate keeps threat at safe.
    expect(controller.threatLevel, ThreatLevel.safe);
  });

  test('escalates after 2 consecutive scam analyses, then decays on safe', () async {
    final gateway = FakeAgoraLiveTranscriptGateway();
    final classifier = FakeScamTextClassifier(
      queuedResults: [
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.scam,
          confidence: 0.95,
          scamProbability: 0.95,
          patterns: ['the qua tang'],
          summary: 'Nguoi goi yeu cau mua the qua tang',
          advice: 'Tat may ngay lap tuc',
        ),
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.scam,
          confidence: 0.90,
          scamProbability: 0.90,
          patterns: ['the qua tang'],
          summary: 'Nguoi goi yeu cau mua the qua tang',
          advice: 'Tat may ngay lap tuc',
        ),
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.safe,
          confidence: 0.9,
          scamProbability: 0.10,
          patterns: [],
          summary: '',
          advice: '',
        ),
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.safe,
          confidence: 0.95,
          scamProbability: 0.05,
          patterns: [],
          summary: '',
          advice: '',
        ),
      ],
    );
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );

    await controller.startListening();

    // Analysis 1: EMA=0.95, consecutive=1 → safe (min-analyses gate)
    gateway.emitTranscript('mua the qua tang ngay');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.threatLevel, ThreatLevel.safe);

    // Analysis 2: EMA=0.93, consecutive=2 → scam
    gateway.emitTranscript('phai mua ngay bay gio');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.threatLevel, ThreatLevel.scam);
    expect(controller.summary, contains('the qua tang'));

    // Analysis 3: safe result → consecutive decrements to 1, EMA decays
    gateway.emitTranscript('thoi bo qua di');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Analysis 4: another safe → consecutive=0, EMA decays further below 0.50
    gateway.emitTranscript('ok bye');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.threatLevel, ThreatLevel.safe);
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
          scamProbability: 0.82,
          patterns: ['khan cap'],
          summary: 'Nguoi goi dang thuc ep hanh dong ngay.',
          advice: 'Tu xac minh truoc khi lam theo.',
        ),
        const ScamAnalysisResult(
          threatLevel: ThreatLevel.suspicious,
          confidence: 0.80,
          scamProbability: 0.80,
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
      onOverlayStatusUpdate: (threatLevel, sessionStatus, confidence) async {
        updates.add((threatLevel, sessionStatus));
      },
    );

    await controller.startListening();
    // Two analyses needed for the consecutive gate to pass.
    gateway.emitTranscript('gui tien ngay bay gio');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    gateway.emitTranscript('chuyen tien ngay');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(
      updates,
      contains((ThreatLevel.safe, ScamCallSessionStatus.listening)),
    );
    expect(
      updates,
      contains((ThreatLevel.scam, ScamCallSessionStatus.listening)),
    );
  });

  test('extractCallResult returns current analysis state', () async {
    final gateway = FakeAgoraLiveTranscriptGateway();
    final classifier = FakeScamTextClassifier(queuedResults: const []);
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    final now = DateTime.now();
    final result = controller.extractCallResult(
      callStartTime: now.subtract(const Duration(minutes: 5)),
      callEndTime: now,
      callerNumber: '+84123456789',
    );

    expect(result.threatLevel.name, ThreatLevel.safe.name);
    expect(result.wasAnalyzed, true);
    expect(result.callerNumber, '+84123456789');
    expect(result.callStartTime, now.subtract(const Duration(minutes: 5)));
    expect(result.callEndTime, now);
    expect(result.transcript, isEmpty);
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
