import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/models/call_result.dart';
import 'package:check_var/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime(2026, 3, 21, 10, 0, 0);
  final endTime = DateTime(2026, 3, 21, 10, 5, 0);

  CallResult makeResult({
    required ThreatLevel threatLevel,
    required double confidence,
    List<String> patterns = const [],
    String? summary,
  }) {
    return CallResult(
      threatLevel: threatLevel,
      confidence: confidence,
      transcript: '',
      patterns: patterns,
      duration: const Duration(seconds: 300),
      callStartTime: baseTime,
      callEndTime: endTime,
      wasAnalyzed: true,
      summary: summary,
    );
  }

  group('NotificationService.buildScamCallTitle', () {
    test('formats scam verdict with confidence', () {
      final result = makeResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.87,
      );
      final title = NotificationService.buildScamCallTitle(result);
      expect(title, contains('CheckVar'));
      expect(title, contains('87%'));
    });

    test('formats safe verdict with confidence', () {
      final result = makeResult(
        threatLevel: ThreatLevel.safe,
        confidence: 0.12,
      );
      final title = NotificationService.buildScamCallTitle(result);
      expect(title, contains('CheckVar'));
      expect(title, contains('12%'));
    });

    test('formats suspicious verdict with confidence', () {
      final result = makeResult(
        threatLevel: ThreatLevel.suspicious,
        confidence: 0.63,
      );
      final title = NotificationService.buildScamCallTitle(result);
      expect(title, contains('CheckVar'));
      expect(title, contains('63%'));
    });
  });

  group('NotificationService.buildScamCallBody', () {
    test('returns first pattern when patterns exist', () {
      final result = makeResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.9,
        patterns: ['khan cap', 'mac danh'],
        summary: 'Some summary',
      );
      expect(
        NotificationService.buildScamCallBody(result),
        'khan cap',
      );
    });

    test('falls back to summary when no patterns', () {
      final result = makeResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.9,
        patterns: [],
        summary: 'Nguoi goi gia mao ngan hang',
      );
      expect(
        NotificationService.buildScamCallBody(result),
        'Nguoi goi gia mao ngan hang',
      );
    });
  });
}
