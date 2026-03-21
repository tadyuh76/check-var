import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/models/call_result.dart';
import 'package:check_var/services/notification_service.dart';

void main() {
  final _baseTime = DateTime(2026, 3, 21, 10, 0, 0);
  final _endTime = DateTime(2026, 3, 21, 10, 5, 0);

  CallResult _makeResult({
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
      callStartTime: _baseTime,
      callEndTime: _endTime,
      wasAnalyzed: true,
      summary: summary,
    );
  }

  group('NotificationService.buildScamCallTitle', () {
    test('formats "CheckVar: Lừa đảo (87%)" for scam verdict', () {
      final result = _makeResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.87,
      );
      expect(
        NotificationService.buildScamCallTitle(result),
        'CheckVar: Lừa đảo (87%)',
      );
    });

    test('formats "CheckVar: An toàn (12%)" for safe verdict', () {
      final result = _makeResult(
        threatLevel: ThreatLevel.safe,
        confidence: 0.12,
      );
      expect(
        NotificationService.buildScamCallTitle(result),
        'CheckVar: An toàn (12%)',
      );
    });

    test('formats "CheckVar: Đáng ngờ (63%)" for suspicious verdict', () {
      final result = _makeResult(
        threatLevel: ThreatLevel.suspicious,
        confidence: 0.63,
      );
      expect(
        NotificationService.buildScamCallTitle(result),
        'CheckVar: Đáng ngờ (63%)',
      );
    });
  });

  group('NotificationService.buildScamCallBody', () {
    test('returns first pattern when patterns exist', () {
      final result = _makeResult(
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
      final result = _makeResult(
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
