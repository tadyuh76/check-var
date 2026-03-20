import 'package:check_var/core/platform_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  setUp(() {
    log = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.checkvar/service'), (
          call,
        ) async {
          log.add(call);
          if (call.method == 'checkLiveCaptionEnabled') return true;
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

  test('startCaptionCapture invokes the correct method', () async {
    await PlatformChannel.startCaptionCapture();

    expect(log.single.method, 'startCaptionCapture');
  });

  test('stopCaptionCapture invokes the correct method', () async {
    await PlatformChannel.stopCaptionCapture();

    expect(log.single.method, 'stopCaptionCapture');
  });

  test('checkLiveCaptionEnabled returns the native result', () async {
    final result = await PlatformChannel.checkLiveCaptionEnabled();

    expect(log.single.method, 'checkLiveCaptionEnabled');
    expect(result, isTrue);
  });

  test('updateOverlayStatus passes threatLevel and sessionStatus', () async {
    await PlatformChannel.updateOverlayStatus(
      threatLevel: 'scam',
      sessionStatus: 'analyzing',
    );

    expect(log.single.method, 'updateOverlayStatus');
    expect(log.single.arguments, {
      'threatLevel': 'scam',
      'sessionStatus': 'analyzing',
    });
  });
}
