import 'dart:convert';

import 'package:check_var/core/api/local_scam_classifier.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal TF-IDF config with a tiny vocabulary for testing.
Map<String, dynamic> _tinyTfidfConfig() => {
  'analyzer': 'char_wb',
  'ngram_range': [2, 3],
  'sublinear_tf': true,
  'max_features': 6,
  'vocabulary': {
    ' n': 0, 'ng': 1, 'gâ': 2,  // "ngân" fragments
    ' a': 3, 'an': 4, ' t': 5,  // "an toàn" fragments
  },
  'idf': [1.5, 1.5, 2.0, 1.2, 1.0, 1.1],
};

/// Classifier weights: 2 classes (safe, bank_fraud), 6 features.
Map<String, dynamic> _tinyWeights() => {
  'classes': ['bank_fraud', 'safe'],
  'coef_shape': [2, 6],
  'coef': [
    [1.0, 1.0, 1.5, -0.5, -0.5, 0.0],   // bank_fraud weights
    [-0.5, -0.5, -1.0, 1.0, 1.5, 0.5],   // safe weights
  ],
  'intercept': [0.0, 0.0],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalScamClassifier classifier;

  setUp(() {
    // Intercept asset loading to provide tiny test model.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.contains('tfidf_config.json')) {
        return Uint8List.fromList(utf8.encode(jsonEncode(_tinyTfidfConfig())))
            .buffer
            .asByteData();
      }
      if (key.contains('classifier_weights.json')) {
        return Uint8List.fromList(utf8.encode(jsonEncode(_tinyWeights())))
            .buffer
            .asByteData();
      }
      return null;
    });

    classifier = LocalScamClassifier();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('classifies text using loaded model weights', () async {
    // "ngân hàng" contains n-grams that match bank_fraud weights
    final result = await classifier.classifyTranscriptWindow('ngân hàng ngân');

    expect(result.threatLevel, ThreatLevel.scam);
    expect(result.confidence, greaterThan(0.5));
    expect(result.patterns, isNotEmpty);
  });

  test('returns safe for benign text', () async {
    // "an toàn" contains n-grams that match safe weights
    final result = await classifier.classifyTranscriptWindow('an toàn an');

    expect(result.threatLevel, ThreatLevel.safe);
    expect(result.confidence, greaterThan(0.5));
    expect(result.patterns, isEmpty);
  });

  test('returns fallback for empty transcript', () async {
    final result = await classifier.classifyTranscriptWindow('');

    expect(result.threatLevel, ThreatLevel.safe);
    expect(result.confidence, 0);
  });

  test('truncates long transcripts to the last 600 characters', () async {
    final longText = 'an toàn ' * 200; // way more than 600 chars
    final result = await classifier.classifyTranscriptWindow(longText);

    // Should still work — the window is the last 600 chars
    expect(result.threatLevel, isNotNull);
    expect(result.confidence, greaterThan(0));
  });

  test('ScamType.fromLabel maps all known labels', () {
    expect(ScamType.fromLabel('safe'), ScamType.safe);
    expect(ScamType.fromLabel('bank_fraud'), ScamType.bankFraud);
    expect(ScamType.fromLabel('authority_impersonation'), ScamType.authorityImpersonation);
    expect(ScamType.fromLabel('prize_scam'), ScamType.prizeScam);
    expect(ScamType.fromLabel('delivery_scam'), ScamType.deliveryScam);
    expect(ScamType.fromLabel('investment_scam'), ScamType.investmentScam);
    expect(ScamType.fromLabel('loan_scam'), ScamType.loanScam);
    expect(ScamType.fromLabel('kidnapping_threat'), ScamType.kidnappingThreat);
    expect(ScamType.fromLabel('tech_support'), ScamType.techSupport);
    expect(ScamType.fromLabel('romance_scam'), ScamType.romanceScam);
    expect(ScamType.fromLabel('unknown_garbage'), ScamType.safe);
  });

  test('ScamType threat levels are correct', () {
    expect(ScamType.safe.threatLevel, ThreatLevel.safe);
    for (final type in ScamType.values) {
      if (type != ScamType.safe) {
        expect(type.threatLevel, ThreatLevel.scam);
      }
    }
  });

  group('confidence thresholds', () {
    test('high confidence scam input reports scam', () async {
      // Default thresholds: suspicious=0.4, scam=0.7
      final result = await classifier.classifyTranscriptWindow(
        'ngân hàng ngân hàng ngân',
      );
      // With strong bank_fraud signal, confidence should be high → scam
      expect(result.threatLevel, ThreatLevel.scam);
      expect(result.confidence, greaterThanOrEqualTo(0.7));
    });

    test('low confidence scam drops to safe with strict thresholds', () async {
      final strict = LocalScamClassifier(
        suspiciousThreshold: 0.99,
        scamThreshold: 1.0,
      );
      // Even a scam-like input won't reach 99% confidence with this tiny model
      final result = await strict.classifyTranscriptWindow('ngân hàng');
      expect(
        result.threatLevel,
        anyOf(ThreatLevel.safe, ThreatLevel.suspicious),
      );
    });

    test('safe classification ignores thresholds', () async {
      // Even with very low thresholds, a safe classification stays safe
      final lenient = LocalScamClassifier(
        suspiciousThreshold: 0.01,
        scamThreshold: 0.02,
      );
      final result = await lenient.classifyTranscriptWindow('an toàn an toàn');
      expect(result.threatLevel, ThreatLevel.safe);
      expect(result.patterns, isEmpty);
    });
  });
}
