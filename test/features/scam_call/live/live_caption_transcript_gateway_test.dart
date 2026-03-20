import 'package:check_var/features/scam_call/live/live_caption_transcript_gateway.dart';
import 'package:check_var/features/scam_call/live/live_transcript_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> methodLog;
  late LiveCaptionTranscriptGateway gateway;

  setUp(() {
    methodLog = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      (call) async {
        methodLog.add(call);
        return null;
      },
    );

    // We can't easily mock the EventChannel broadcast stream from the
    // gateway's perspective since it uses PlatformChannel.shakeEvents
    // internally. Instead, we test the gateway's contract using the
    // public interface and verify method calls.

    gateway = LiveCaptionTranscriptGateway();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.checkvar/service'),
      null,
    );
  });

  test('start calls startCaptionCapture on the platform channel', () async {
    await gateway.start();

    expect(
      methodLog.any((call) => call.method == 'startCaptionCapture'),
      isTrue,
    );
  });

  test('stop calls stopCaptionCapture on the platform channel', () async {
    await gateway.start();
    await gateway.stop();

    expect(
      methodLog.any((call) => call.method == 'stopCaptionCapture'),
      isTrue,
    );
  });

  test('start is idempotent — calling twice does not start capture twice', () async {
    await gateway.start();
    await gateway.start();

    final captureStarts =
        methodLog.where((call) => call.method == 'startCaptionCapture');
    expect(captureStarts, hasLength(1));
  });

  test('restartLiveSession is a no-op (Live Caption is passive)', () async {
    await gateway.start();
    await gateway.restartLiveSession();

    // Should not call any platform methods for restart
    final captureStarts =
        methodLog.where((call) => call.method == 'startCaptionCapture');
    expect(captureStarts, hasLength(1));
  });

  test('emits setupComplete event after start', () async {
    final events = <LiveTranscriptEvent>[];
    gateway.transcripts.listen(events.add);

    await gateway.start();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.first.kind, LiveTranscriptEventKind.setupComplete);
  });
}
