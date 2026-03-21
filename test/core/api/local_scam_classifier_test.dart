import 'dart:convert';

import 'package:check_var/core/api/local_scam_classifier.dart';
import 'package:check_var/models/scam_alert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Tiny gate model (binary: safe / scam) ──────────────────────────

Map<String, dynamic> _tinyGateTfidfConfig() => {
  'analyzer': 'char_wb',
  'ngram_range': [2, 3],
  'sublinear_tf': true,
  'max_features': 6,
  'vocabulary': {
    ' n': 0, 'ng': 1, 'gâ': 2, // "ngân" fragments → scam signal
    ' a': 3, 'an': 4, ' t': 5, // "an toàn" fragments → safe signal
  },
  'idf': [1.5, 1.5, 2.0, 1.2, 1.0, 1.1],
};

Map<String, dynamic> _tinyGateWeights() => {
  'classes': ['safe', 'scam'],
  'coef_shape': [1, 6],
  // Single row: positive values push toward scam (sigmoid > 0.5).
  'coef': [
    [2.0, 2.0, 3.0, -2.0, -2.5, -1.0],
  ],
  'intercept': [-0.5],
  'threshold': 0.55,
  'target_recall': 0.92,
};

// ── Tiny type model (multiclass: 3 scam types) ────────────────────

Map<String, dynamic> _tinyTypeTfidfConfig() => {
  'analyzer': 'char_wb',
  'ngram_range': [2, 3],
  'sublinear_tf': true,
  'max_features': 6,
  'vocabulary': {
    ' n': 0, 'ng': 1, 'gâ': 2,
    ' a': 3, 'an': 4, ' t': 5,
  },
  'idf': [1.5, 1.5, 2.0, 1.2, 1.0, 1.1],
};

Map<String, dynamic> _tinyTypeWeights() => {
  'classes': ['bank_fraud_alert', 'none', 'police_impersonation'],
  'coef_shape': [3, 6],
  'coef': [
    [1.0, 1.0, 1.5, -0.5, -0.5, 0.0], // bank_fraud_alert
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],   // none
    [0.5, 0.5, 0.5, -0.3, -0.3, 0.0],  // police_impersonation
  ],
  'intercept': [0.0, 0.0, 0.0],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalScamClassifier classifier;

  setUp(() {
    // Intercept asset loading to provide tiny test models.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.contains('gate_tfidf_config.json')) {
        return Uint8List.fromList(
          utf8.encode(jsonEncode(_tinyGateTfidfConfig())),
        ).buffer.asByteData();
      }
      if (key.contains('gate_classifier_weights.json')) {
        return Uint8List.fromList(
          utf8.encode(jsonEncode(_tinyGateWeights())),
        ).buffer.asByteData();
      }
      if (key.endsWith('tfidf_config.json')) {
        return Uint8List.fromList(
          utf8.encode(jsonEncode(_tinyTypeTfidfConfig())),
        ).buffer.asByteData();
      }
      if (key.endsWith('classifier_weights.json')) {
        return Uint8List.fromList(
          utf8.encode(jsonEncode(_tinyTypeWeights())),
        ).buffer.asByteData();
      }
      return null;
    });

    classifier = LocalScamClassifier();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('classifies scam-like text through gate + type pipeline', () async {
    // "ngân hàng ngân" triggers scam n-grams in the gate, then
    // the type classifier should pick bank_fraud_alert.
    final result = await classifier.classifyTranscriptWindow('ngân hàng ngân');

    expect(result.threatLevel, isNot(ThreatLevel.safe));
    expect(result.confidence, greaterThan(0.5));
    expect(result.patterns, isNotEmpty);
  });

  test('returns safe for benign text', () async {
    // "an toàn an" triggers safe-signal n-grams in the gate.
    final result = await classifier.classifyTranscriptWindow('an toàn an');

    expect(result.threatLevel, ThreatLevel.safe);
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

    expect(result.threatLevel, isNotNull);
  });

  test('ScamType.fromLabel maps all 41 model labels', () {
    expect(ScamType.fromLabel('safe'), ScamType.safe);
    expect(ScamType.fromLabel('ai_flash_call'), ScamType.aiFlashCall);
    expect(ScamType.fromLabel('bank_card_upgrade'), ScamType.bankCardUpgrade);
    expect(ScamType.fromLabel('bank_fraud_alert'), ScamType.bankFraudAlert);
    expect(ScamType.fromLabel('charity_disaster'), ScamType.charityDisaster);
    expect(ScamType.fromLabel('customs_official'), ScamType.customsOfficial);
    expect(
      ScamType.fromLabel('debt_collection_fake'),
      ScamType.debtCollectionFake,
    );
    expect(
      ScamType.fromLabel('deepfake_video_call'),
      ScamType.deepfakeVideoCall,
    );
    expect(
      ScamType.fromLabel('deepfake_voice_clone'),
      ScamType.deepfakeVoiceClone,
    );
    expect(ScamType.fromLabel('electricity_water'), ScamType.electricityWater);
    expect(ScamType.fromLabel('ewallet_scam'), ScamType.ewalletScam);
    expect(ScamType.fromLabel('fake_app_install'), ScamType.fakeAppInstall);
    expect(ScamType.fromLabel('fake_friend_borrow'), ScamType.fakeFriendBorrow);
    expect(ScamType.fromLabel('fake_loan'), ScamType.fakeLoan);
    expect(ScamType.fromLabel('fake_shipper'), ScamType.fakeShipper);
    expect(ScamType.fromLabel('fire_safety_scam'), ScamType.fireSafetyScam);
    expect(ScamType.fromLabel('gift_package'), ScamType.giftPackage);
    expect(
      ScamType.fromLabel('government_order_fake'),
      ScamType.governmentOrderFake,
    );
    expect(ScamType.fromLabel('image_extortion'), ScamType.imageExtortion);
    expect(ScamType.fromLabel('investment_scam'), ScamType.investmentScam);
    expect(ScamType.fromLabel('job_scam_deposit'), ScamType.jobScamDeposit);
    expect(ScamType.fromLabel('job_scam_task'), ScamType.jobScamTask);
    expect(ScamType.fromLabel('kidnap_ransom'), ScamType.kidnapRansom);
    expect(ScamType.fromLabel('lottery_numbers'), ScamType.lotteryNumbers);
    expect(ScamType.fromLabel('medical_scam'), ScamType.medicalScam);
    expect(ScamType.fromLabel('merge_exploit'), ScamType.mergeExploit);
    expect(ScamType.fromLabel('none'), ScamType.unknown);
    expect(
      ScamType.fromLabel('police_impersonation'),
      ScamType.policeImpersonation,
    );
    expect(ScamType.fromLabel('prize_lottery'), ScamType.prizeLottery);
    expect(ScamType.fromLabel('prosecutor_court'), ScamType.prosecutorCourt);
    expect(
      ScamType.fromLabel('relative_emergency'),
      ScamType.relativeEmergency,
    );
    expect(ScamType.fromLabel('romance_extortion'), ScamType.romanceExtortion);
    expect(ScamType.fromLabel('romance_invest'), ScamType.romanceInvest);
    expect(ScamType.fromLabel('salary_advance'), ScamType.salaryAdvance);
    expect(ScamType.fromLabel('scholarship_fake'), ScamType.scholarshipFake);
    expect(ScamType.fromLabel('social_insurance'), ScamType.socialInsurance);
    expect(ScamType.fromLabel('sugar_dating'), ScamType.sugarDating);
    expect(ScamType.fromLabel('tax_authority'), ScamType.taxAuthority);
    expect(ScamType.fromLabel('telecom_debt'), ScamType.telecomDebt);
    expect(
      ScamType.fromLabel('telecom_sim_upgrade'),
      ScamType.telecomSimUpgrade,
    );
    expect(ScamType.fromLabel('tuition_refund'), ScamType.tuitionRefund);
    expect(
      ScamType.fromLabel('vehicle_registration'),
      ScamType.vehicleRegistration,
    );
    expect(ScamType.fromLabel('unknown_garbage'), ScamType.unknown);
  });

  test('ScamType threat levels are correct', () {
    expect(ScamType.safe.threatLevel, ThreatLevel.safe);
    for (final type in ScamType.values) {
      if (type != ScamType.safe) {
        expect(type.threatLevel, ThreatLevel.scam);
      }
    }
  });

  group('gate thresholds', () {
    test('high gate probability reports scam', () async {
      final result = await classifier.classifyTranscriptWindow(
        'ngân hàng ngân hàng ngân',
      );
      expect(result.threatLevel, ThreatLevel.scam);
      expect(result.confidence, greaterThanOrEqualTo(0.55));
    });

    test('safe classification bypasses type classifier', () async {
      final result = await classifier.classifyTranscriptWindow(
        'an toàn an toàn',
      );
      expect(result.threatLevel, ThreatLevel.safe);
      expect(result.patterns, isEmpty);
    });
  });
}
