import 'package:check_var/features/scam_call/live/simulated_call_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preset simulated call scripts are written in Vietnamese', () {
    expect(
      SimulatedCallScenario.safeCall.spokenScript,
      'Chào bạn, tôi muốn xác nhận bữa tối lúc bảy giờ tối nay. '
      'Nghe ổn đó. Tôi sẽ mang tài liệu vào ngày mai. '
      'Tuyệt, hẹn gặp bạn nhé.',
    );
    expect(
      SimulatedCallScenario.bankScam.spokenScript,
      'Đây là bộ phận chống gian lận của ngân hàng. '
      'Tài khoản của bạn sẽ bị khóa hôm nay nếu bạn không hành động ngay. '
      'Hãy chuyển tiền ngay lập tức để bảo vệ tài khoản.',
    );
    expect(
      SimulatedCallScenario.deliveryScam.spokenScript,
      'Gói hàng của bạn đang bị giữ tại hải quan. '
      'Bạn cần trả phí thông quan ngay bây giờ. '
      'Hãy gửi khoản thanh toán và đọc cho tôi mã xác nhận.',
    );
  });

  test('all presets have non-empty title and script', () {
    for (final scenario in SimulatedCallScenario.presets) {
      expect(scenario.title, isNotEmpty, reason: 'title should not be empty');
      expect(
        scenario.spokenScript,
        isNotEmpty,
        reason: '${scenario.title} spokenScript should not be empty',
      );
    }
  });

  test('presets list contains all 13 scenario types', () {
    expect(SimulatedCallScenario.presets, hasLength(13));
    final titles = SimulatedCallScenario.presets.map((s) => s.title).toSet();
    expect(titles, contains('Safe Call'));
    expect(titles, contains('Bank Scam'));
    expect(titles, contains('Delivery Scam'));
    expect(titles, contains('An toàn: Rủ cafe'));
    expect(titles, contains('An toàn: Mẹ gọi'));
    expect(titles, contains('An toàn: Gọi bác sĩ'));
    expect(titles, contains('Lừa đảo: Giả công an'));
    expect(titles, contains('Lừa đảo: Trúng thưởng'));
    expect(titles, contains('Lừa đảo: Đầu tư crypto'));
    expect(titles, contains('Lừa đảo: Dọa bắt cóc'));
    expect(titles, contains('Lừa đảo: Cho vay giả'));
    expect(titles, contains('Lừa đảo: Hỗ trợ kỹ thuật'));
    expect(titles, contains('Lừa đảo: Lừa tình'));
  });

  group('spokenLines', () {
    test('splits script into sentences on period, exclamation, and question', () {
      final lines = SimulatedCallScenario.safeCall.spokenLines;
      expect(lines, hasLength(4));
      expect(lines[0], contains('xác nhận bữa tối'));
      expect(lines[1], contains('Nghe ổn đó'));
      expect(lines[2], contains('Tôi sẽ mang tài liệu'));
      expect(lines[3], contains('hẹn gặp bạn'));
    });

    test('handles question marks as sentence terminators', () {
      final lines = SimulatedCallScenario.safeDoctor.spokenLines;
      expect(lines, hasLength(2));
      expect(lines[1], endsWith('?'));
    });

    test('returns single-element list for text without punctuation', () {
      final scenario = SimulatedCallScenario.customScript('no punctuation here');
      expect(scenario.spokenLines, ['no punctuation here']);
    });

    test('returns empty list for empty script', () {
      final scenario = SimulatedCallScenario.customScript('');
      expect(scenario.spokenLines, isEmpty);
    });

    test('handles whitespace-only script as empty', () {
      final scenario = SimulatedCallScenario.customScript('   ');
      expect(scenario.spokenLines, isEmpty);
    });
  });

  group('customScript factory', () {
    test('creates scenario with Custom Transcript title', () {
      final scenario =
          SimulatedCallScenario.customScript('Đây là ngân hàng.');
      expect(scenario.title, 'Custom Transcript');
      expect(scenario.spokenScript, 'Đây là ngân hàng.');
    });

    test('trims leading and trailing whitespace', () {
      final scenario =
          SimulatedCallScenario.customScript('  hello world  ');
      expect(scenario.spokenScript, 'hello world');
    });
  });

  group('scenario categories', () {
    test('safe scenarios do not contain scam trigger words', () {
      final safeScenarios = [
        SimulatedCallScenario.safeCall,
        SimulatedCallScenario.safeCafe,
        SimulatedCallScenario.safeParent,
        SimulatedCallScenario.safeDoctor,
      ];
      final scamTriggers = [
        'chuyển tiền',
        'bị khóa',
        'bị bắt',
        'trúng thưởng',
        'bắt cóc',
      ];

      for (final scenario in safeScenarios) {
        for (final trigger in scamTriggers) {
          expect(
            scenario.spokenScript.toLowerCase().contains(trigger),
            isFalse,
            reason:
                '${scenario.title} should not contain scam trigger "$trigger"',
          );
        }
      }
    });

    test('scam scenarios contain urgency or financial pressure language', () {
      final scamScenarios = [
        SimulatedCallScenario.bankScam,
        SimulatedCallScenario.deliveryScam,
        SimulatedCallScenario.fakePolice,
        SimulatedCallScenario.fakePrize,
        SimulatedCallScenario.cryptoInvestment,
        SimulatedCallScenario.kidnapping,
        SimulatedCallScenario.fakeLoan,
        SimulatedCallScenario.fakeTechSupport,
        SimulatedCallScenario.romance,
      ];

      for (final scenario in scamScenarios) {
        final script = scenario.spokenScript.toLowerCase();
        final hasFinancialLanguage =
            script.contains('tiền') ||
            script.contains('triệu') ||
            script.contains('thanh toán') ||
            script.contains('phí') ||
            script.contains('nạp') ||
            script.contains('chuyển');
        expect(
          hasFinancialLanguage,
          isTrue,
          reason: '${scenario.title} should contain financial pressure language',
        );
      }
    });
  });
}
