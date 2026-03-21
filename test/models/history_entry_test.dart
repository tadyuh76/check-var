import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/models/call_result.dart';
import 'package:check_var/models/history_entry.dart';

void main() {
  final now = DateTime(2026, 3, 21, 10, 0, 0);
  final later = DateTime(2026, 3, 21, 10, 5, 30);

  CallResult _makeAnalyzedResult() => CallResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.92,
        transcript: 'Hello, this is your bank calling.',
        patterns: ['urgency', 'impersonation'],
        duration: const Duration(seconds: 330),
        callerNumber: '+60123456789',
        callStartTime: now,
        callEndTime: later,
        wasAnalyzed: true,
        summary: 'Caller impersonated a bank and requested OTP.',
        advice: 'Do not share OTPs with anyone.',
        scamProbability: 0.95,
      );

  CallResult _makeUnanalyzedResult() => CallResult(
        threatLevel: ThreatLevel.safe,
        confidence: 0.0,
        transcript: '',
        patterns: [],
        duration: const Duration(seconds: 90),
        callerNumber: null,
        callStartTime: now,
        callEndTime: later,
        wasAnalyzed: false,
        summary: null,
        advice: null,
        scamProbability: null,
      );

  group('HistoryEntry.fromCallResult', () {
    test('includes new fields in data map for analyzed call', () {
      final result = _makeAnalyzedResult();
      final entry = HistoryEntry.fromCallResult(result);

      expect(entry.type, HistoryType.call);
      expect(entry.data['callerNumber'], '+60123456789');
      expect(entry.data['wasAnalyzed'], isTrue);
      expect(entry.data['summary'], 'Caller impersonated a bank and requested OTP.');
      expect(entry.data['advice'], 'Do not share OTPs with anyone.');
      expect(entry.data['scamProbability'], 0.95);
    });

    test('existing fields are still in data map', () {
      final result = _makeAnalyzedResult();
      final entry = HistoryEntry.fromCallResult(result);

      expect(entry.data['threatLevel'], 'scam');
      expect(entry.data['confidence'], 0.92);
      expect(entry.data['transcript'], 'Hello, this is your bank calling.');
      expect(entry.data['patterns'], ['urgency', 'impersonation']);
      expect(entry.data['duration'], 330);
    });

    test('handles unanalyzed call — wasAnalyzed=false, null optional fields', () {
      final result = _makeUnanalyzedResult();
      final entry = HistoryEntry.fromCallResult(result);

      expect(entry.data['wasAnalyzed'], isFalse);
      expect(entry.data['callerNumber'], isNull);
      expect(entry.data['summary'], isNull);
      expect(entry.data['advice'], isNull);
      expect(entry.data['scamProbability'], isNull);
    });
  });

  group('HistoryEntry call-specific getters', () {
    test('callerNumber returns correct value', () {
      final entry = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      expect(entry.callerNumber, '+60123456789');
    });

    test('callerNumber returns null when not set', () {
      final entry = HistoryEntry.fromCallResult(_makeUnanalyzedResult());
      expect(entry.callerNumber, isNull);
    });

    test('wasAnalyzed returns true for analyzed call', () {
      final entry = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      expect(entry.wasAnalyzed, isTrue);
    });

    test('wasAnalyzed returns false for unanalyzed call', () {
      final entry = HistoryEntry.fromCallResult(_makeUnanalyzedResult());
      expect(entry.wasAnalyzed, isFalse);
    });

    test('wasAnalyzed defaults to true when key is missing', () {
      final entry = HistoryEntry(
        id: 1,
        type: HistoryType.call,
        timestamp: now,
        data: {'threatLevel': 'safe'},
      );
      expect(entry.wasAnalyzed, isTrue);
    });

    test('callSummary returns correct value', () {
      final entry = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      expect(entry.callSummary, 'Caller impersonated a bank and requested OTP.');
    });

    test('callSummary returns null for unanalyzed call', () {
      final entry = HistoryEntry.fromCallResult(_makeUnanalyzedResult());
      expect(entry.callSummary, isNull);
    });

    test('callAdvice returns correct value', () {
      final entry = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      expect(entry.callAdvice, 'Do not share OTPs with anyone.');
    });

    test('callAdvice returns null for unanalyzed call', () {
      final entry = HistoryEntry.fromCallResult(_makeUnanalyzedResult());
      expect(entry.callAdvice, isNull);
    });

    test('scamProbability returns correct value', () {
      final entry = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      expect(entry.scamProbability, 0.95);
    });

    test('scamProbability returns null for unanalyzed call', () {
      final entry = HistoryEntry.fromCallResult(_makeUnanalyzedResult());
      expect(entry.scamProbability, isNull);
    });
  });

  group('HistoryEntry JSON round-trip for call type', () {
    test('preserves new call fields through toJson/fromJson', () {
      final original = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      final restored = HistoryEntry.fromJson(original.toJson());

      expect(restored.type, HistoryType.call);
      expect(restored.data['callerNumber'], '+60123456789');
      expect(restored.data['wasAnalyzed'], isTrue);
      expect(restored.data['summary'], 'Caller impersonated a bank and requested OTP.');
      expect(restored.data['advice'], 'Do not share OTPs with anyone.');
      expect(restored.data['scamProbability'], 0.95);
      expect(restored.data['threatLevel'], 'scam');
      expect(restored.data['confidence'], 0.92);
      expect(restored.data['duration'], 330);
    });

    test('preserves null optional fields through toJson/fromJson for unanalyzed call', () {
      final original = HistoryEntry.fromCallResult(_makeUnanalyzedResult());
      final restored = HistoryEntry.fromJson(original.toJson());

      expect(restored.data['wasAnalyzed'], isFalse);
      expect(restored.data['callerNumber'], isNull);
      expect(restored.data['summary'], isNull);
      expect(restored.data['advice'], isNull);
      expect(restored.data['scamProbability'], isNull);
    });

    test('getters work correctly after round-trip', () {
      final original = HistoryEntry.fromCallResult(_makeAnalyzedResult());
      final restored = HistoryEntry.fromJson(original.toJson());

      expect(restored.callerNumber, '+60123456789');
      expect(restored.wasAnalyzed, isTrue);
      expect(restored.callSummary, 'Caller impersonated a bank and requested OTP.');
      expect(restored.callAdvice, 'Do not share OTPs with anyone.');
      expect(restored.scamProbability, 0.95);
    });
  });
}
