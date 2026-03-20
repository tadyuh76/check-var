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

  test('startSpeakerRecognition uses Vietnamese by default', () async {
    await PlatformChannel.startSpeakerRecognition();

    expect(log.single.method, 'startSpeakerRecognition');
    expect(log.single.arguments, {'language': 'vi-VN'});
  });
}
