import 'package:flutter_test/flutter_test.dart';
import 'package:check_var/models/call_result.dart';

void main() {
  group('CallResult', () {
    final now = DateTime(2026, 3, 21, 10, 0, 0);
    final later = DateTime(2026, 3, 21, 10, 5, 30);

    group('full analyzed call - stores all fields and round-trips toJson/fromJson', () {
      test('stores all new fields correctly', () {
        final result = CallResult(
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

        expect(result.callerNumber, '+60123456789');
        expect(result.callStartTime, now);
        expect(result.callEndTime, later);
        expect(result.wasAnalyzed, isTrue);
        expect(result.summary, 'Caller impersonated a bank and requested OTP.');
        expect(result.advice, 'Do not share OTPs with anyone.');
        expect(result.scamProbability, 0.95);
      });

      test('existing fields are still stored correctly', () {
        final result = CallResult(
          threatLevel: ThreatLevel.suspicious,
          confidence: 0.6,
          transcript: 'Some transcript',
          patterns: ['pattern1'],
          duration: const Duration(seconds: 60),
          callerNumber: null,
          callStartTime: now,
          callEndTime: later,
          wasAnalyzed: true,
          summary: null,
          advice: null,
          scamProbability: null,
        );

        expect(result.threatLevel, ThreatLevel.suspicious);
        expect(result.confidence, 0.6);
        expect(result.transcript, 'Some transcript');
        expect(result.patterns, ['pattern1']);
        expect(result.duration, const Duration(seconds: 60));
      });

      test('toJson serializes all fields correctly', () {
        final result = CallResult(
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

        final json = result.toJson();

        expect(json['threatLevel'], 'scam');
        expect(json['confidence'], 0.92);
        expect(json['transcript'], 'Hello, this is your bank calling.');
        expect(json['patterns'], ['urgency', 'impersonation']);
        expect(json['duration'], 330);
        expect(json['callerNumber'], '+60123456789');
        expect(json['callStartTime'], now.toIso8601String());
        expect(json['callEndTime'], later.toIso8601String());
        expect(json['wasAnalyzed'], isTrue);
        expect(json['summary'], 'Caller impersonated a bank and requested OTP.');
        expect(json['advice'], 'Do not share OTPs with anyone.');
        expect(json['scamProbability'], 0.95);
      });

      test('fromJson deserializes all fields correctly', () {
        final json = {
          'threatLevel': 'scam',
          'confidence': 0.92,
          'transcript': 'Hello, this is your bank calling.',
          'patterns': ['urgency', 'impersonation'],
          'duration': 330,
          'callerNumber': '+60123456789',
          'callStartTime': now.toIso8601String(),
          'callEndTime': later.toIso8601String(),
          'wasAnalyzed': true,
          'summary': 'Caller impersonated a bank and requested OTP.',
          'advice': 'Do not share OTPs with anyone.',
          'scamProbability': 0.95,
        };

        final result = CallResult.fromJson(json);

        expect(result.threatLevel, ThreatLevel.scam);
        expect(result.confidence, 0.92);
        expect(result.transcript, 'Hello, this is your bank calling.');
        expect(result.patterns, ['urgency', 'impersonation']);
        expect(result.duration, const Duration(seconds: 330));
        expect(result.callerNumber, '+60123456789');
        expect(result.callStartTime, now);
        expect(result.callEndTime, later);
        expect(result.wasAnalyzed, isTrue);
        expect(result.summary, 'Caller impersonated a bank and requested OTP.');
        expect(result.advice, 'Do not share OTPs with anyone.');
        expect(result.scamProbability, 0.95);
      });

      test('round-trip toJson then fromJson preserves all fields', () {
        final original = CallResult(
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

        final restored = CallResult.fromJson(original.toJson());

        expect(restored.threatLevel, original.threatLevel);
        expect(restored.confidence, original.confidence);
        expect(restored.transcript, original.transcript);
        expect(restored.patterns, original.patterns);
        expect(restored.duration, original.duration);
        expect(restored.callerNumber, original.callerNumber);
        expect(restored.callStartTime, original.callStartTime);
        expect(restored.callEndTime, original.callEndTime);
        expect(restored.wasAnalyzed, original.wasAnalyzed);
        expect(restored.summary, original.summary);
        expect(restored.advice, original.advice);
        expect(restored.scamProbability, original.scamProbability);
      });
    });

    group('unanalyzed call - wasAnalyzed=false, nullable fields null', () {
      test('unanalyzed call stores wasAnalyzed=false and nullable fields as null', () {
        final result = CallResult(
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

        expect(result.wasAnalyzed, isFalse);
        expect(result.callerNumber, isNull);
        expect(result.summary, isNull);
        expect(result.advice, isNull);
        expect(result.scamProbability, isNull);
      });

      test('unanalyzed call round-trips toJson/fromJson with null optional fields', () {
        final original = CallResult(
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

        final json = original.toJson();
        expect(json['wasAnalyzed'], isFalse);
        expect(json['callerNumber'], isNull);
        expect(json['summary'], isNull);
        expect(json['advice'], isNull);
        expect(json['scamProbability'], isNull);

        final restored = CallResult.fromJson(json);
        expect(restored.wasAnalyzed, isFalse);
        expect(restored.callerNumber, isNull);
        expect(restored.summary, isNull);
        expect(restored.advice, isNull);
        expect(restored.scamProbability, isNull);
      });

      test('fromJson handles missing optional fields gracefully (legacy data)', () {
        final json = {
          'threatLevel': 'safe',
          'confidence': 0.0,
          'transcript': '',
          'patterns': [],
          'duration': 90,
          'callStartTime': now.toIso8601String(),
          'callEndTime': later.toIso8601String(),
          'wasAnalyzed': false,
        };

        final result = CallResult.fromJson(json);
        expect(result.callerNumber, isNull);
        expect(result.summary, isNull);
        expect(result.advice, isNull);
        expect(result.scamProbability, isNull);
      });
    });
  });
}
