import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/features/scam_call/speaker_test/platform_speaker_test_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlatformSpeakerTestGateway gateway;
  late List<MethodCall> log;

  setUp(() {
    gateway = PlatformSpeakerTestGateway();
    log = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.checkvar/service'), (
          call,
        ) async {
          log.add(call);
          if (call.method == 'getSpeakerTestReadiness') {
            return <String, dynamic>{
              'hasActiveCall': true,
              'hasOverlayPermission': true,
              'hasMicrophonePermission': true,
              'recognizerAvailable': true,
              'isSpeakerphoneOn': false,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.checkvar/service'),
          null,
        );
  });

  test('getReadiness requests permissions then maps platform response', () async {
    final readiness = await gateway.getReadiness();

    expect(readiness.hasActiveCall, isTrue);
    expect(readiness.hasOverlayPermission, isTrue);
    expect(readiness.hasMicrophonePermission, isTrue);
    expect(readiness.recognizerAvailable, isTrue);
    expect(readiness.isSpeakerphoneOn, isFalse);
    expect(readiness.isReadyToListen, isTrue);
    // Should call requestSpeakerTestPermissions first, then getSpeakerTestReadiness
    expect(log.length, 2);
    expect(log[0].method, 'requestSpeakerTestPermissions');
    expect(log[1].method, 'getSpeakerTestReadiness');
  });

  test('startListening invokes startSpeakerRecognition', () async {
    await gateway.startListening();

    expect(log.single.method, 'startSpeakerRecognition');
  });

  test('stopListening invokes stopSpeakerRecognition', () async {
    // Need to start first to initialize stream subscription
    gateway.transcriptEvents();
    await gateway.startListening();
    log.clear();

    await gateway.stopListening();

    expect(log.single.method, 'stopSpeakerRecognition');
  });

  test(
    'refreshListeningSession restarts speaker recognition in place',
    () async {
      await gateway.refreshListeningSession();

      expect(log, hasLength(2));
      expect(log[0].method, 'stopSpeakerRecognition');
      expect(log[1].method, 'startSpeakerRecognition');
    },
  );

  test('speakPhrase invokes speakText', () async {
    // Initialize the event stream so tts_done events can be received
    gateway.transcriptEvents();

    // speakPhrase will timeout after 15s if no tts_done event,
    // but we just check the method call was made
    final future = gateway.speakPhrase('hello world');

    await Future.delayed(Duration.zero);
    expect(log.any((c) => c.method == 'speakText'), isTrue);
    final speakCall = log.firstWhere((c) => c.method == 'speakText');
    expect(speakCall.arguments, {
      'text': 'hello world',
      'preferSpeaker': false,
    });

    // Let it timeout rather than waiting 15s in test
    await future;
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('stopSpeaking invokes stopSpeaking', () async {
    await gateway.stopSpeaking();

    expect(log.single.method, 'stopSpeaking');
  });
}
