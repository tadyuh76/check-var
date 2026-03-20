@Tags(['integration'])
import 'dart:convert';
import 'dart:io';

import 'package:check_var/core/api/local_scam_classifier.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration test that loads the REAL model assets to verify Dart matches
/// Python's predictions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalScamClassifier classifier;

  setUp(() {
    // Load real model assets from disk instead of mocking.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());

      // Strip the leading path prefix to get the relative asset path.
      String assetPath;
      if (key.contains('assets/models/')) {
        final idx = key.indexOf('assets/models/');
        assetPath = key.substring(idx);
      } else {
        return null;
      }

      final file = File(assetPath);
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      return bytes.buffer.asByteData();
    });

    classifier = LocalScamClassifier();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('bank scam scenario (exact screenshot text) classifies as scam', () async {
    final text =
        'đây là bộ phận chống gian lận của ngân hàng tài khoản của bạn '
        'sẽ bị khóa hôm nay nếu bạn không hành động ngay hãy chuyển tiền '
        'ngay lập tức để bảo vệ tài khoản';

    final result = await classifier.classifyTranscriptWindow(text);
    print('Bank scam: ${result.threatLevel} ${result.confidence} ${result.summary}');
    expect(result.threatLevel, isNot(ThreatLevel.safe));
    expect(result.confidence, greaterThan(0.4));
  });

  test('delivery scam scenario classifies as scam', () async {
    final text =
        'gói hàng của bạn đang bị giữ tại hải quan '
        'bạn cần trả phí thông quan ngay bây giờ '
        'hãy gửi khoản thanh toán và đọc cho tôi mã xác nhận';

    final result = await classifier.classifyTranscriptWindow(text);
    print('Delivery scam: ${result.threatLevel} ${result.confidence} ${result.summary}');
    expect(result.threatLevel, isNot(ThreatLevel.safe));
  });

  test('safe call scenario classifies as safe', () async {
    final text =
        'chào bạn tôi muốn xác nhận bữa tối lúc bảy giờ tối nay '
        'nghe ổn đó tôi sẽ mang tài liệu vào ngày mai '
        'tuyệt hẹn gặp bạn nhé';

    final result = await classifier.classifyTranscriptWindow(text);
    print('Safe: ${result.threatLevel} ${result.confidence} ${result.summary}');
    expect(result.threatLevel, ThreatLevel.safe);
  });
}
