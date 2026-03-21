import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../../models/scam_alert.dart';
import 'gemini_scam_text_api.dart';

/// Scam type labels with Vietnamese display names and advice.
///
/// The 41 model labels map to enum values via [fromLabel].  The special
/// [safe] value is not produced by the type classifier — it is returned
/// when the gate classifier determines the call is safe.
enum ScamType {
  safe('An toàn', 'Cuộc gọi bình thường, không có dấu hiệu lừa đảo.'),

  // AI / Deepfake ──────────────────────────────────────────────────────
  aiFlashCall(
    'Cuộc gọi nháy AI',
    'Không gọi lại số lạ. Đây có thể là bẫy thu phí.',
  ),
  deepfakeVideoCall(
    'Deepfake video call',
    'Không tin video call từ người lạ. Xác minh bằng cách khác.',
  ),
  deepfakeVoiceClone(
    'Giả giọng nói (Deepfake)',
    'Giọng nói có thể bị giả mạo bằng AI. Gọi lại số chính thức để xác minh.',
  ),

  // Bank / Financial ───────────────────────────────────────────────────
  bankCardUpgrade(
    'Nâng cấp thẻ ngân hàng giả',
    'Ngân hàng không yêu cầu thông tin thẻ qua điện thoại. Gọi lại hotline chính thức.',
  ),
  bankFraudAlert(
    'Cảnh báo gian lận ngân hàng giả',
    'Không cung cấp OTP hoặc thông tin thẻ. Gọi lại hotline ngân hàng chính thức.',
  ),
  ewalletScam(
    'Lừa đảo ví điện tử',
    'Không chuyển tiền hoặc cung cấp mã OTP cho người lạ.',
  ),

  // Government / Authority ─────────────────────────────────────────────
  customsOfficial(
    'Giả mạo hải quan',
    'Hải quan không yêu cầu đóng phí qua điện thoại. Xác minh tại cơ quan.',
  ),
  governmentOrderFake(
    'Giả lệnh cơ quan nhà nước',
    'Cơ quan nhà nước không gửi lệnh qua điện thoại. Xác minh trực tiếp.',
  ),
  policeImpersonation(
    'Giả mạo công an',
    'Công an không bao giờ yêu cầu chuyển tiền qua điện thoại. Cúp máy ngay.',
  ),
  prosecutorCourt(
    'Giả mạo viện kiểm sát/tòa án',
    'Tòa án triệu tập bằng giấy, không qua điện thoại. Cúp máy.',
  ),
  taxAuthority(
    'Giả mạo cơ quan thuế',
    'Cơ quan thuế không yêu cầu chuyển tiền qua điện thoại. Kiểm tra tại chi cục thuế.',
  ),
  socialInsurance(
    'Giả mạo bảo hiểm xã hội',
    'BHXH không yêu cầu đóng phí qua điện thoại. Liên hệ trực tiếp cơ quan BHXH.',
  ),

  // Delivery / Package ─────────────────────────────────────────────────
  fakeShipper(
    'Lừa đảo giao hàng',
    'Không đóng phí qua điện thoại. Liên hệ trực tiếp đơn vị vận chuyển.',
  ),
  giftPackage(
    'Lừa gói quà tặng',
    'Không nhận quà từ người lạ. Đây có thể là chiêu lừa đảo.',
  ),

  // Investment / Finance ───────────────────────────────────────────────
  investmentScam(
    'Lừa đầu tư',
    'Không có khoản đầu tư nào cam kết lợi nhuận cao, rủi ro thấp. Từ chối.',
  ),
  mergeExploit(
    'Lừa sáp nhập/hợp tác kinh doanh',
    'Không chuyển tiền cho đối tác chưa xác minh. Tìm hiểu kỹ.',
  ),

  // Loan ───────────────────────────────────────────────────────────────
  fakeLoan(
    'Lừa cho vay',
    'Không đóng phí trước khi nhận khoản vay. Đây là dấu hiệu lừa đảo.',
  ),
  salaryAdvance(
    'Lừa ứng lương trước',
    'Không cung cấp thông tin tài khoản. Xác minh với công ty trực tiếp.',
  ),

  // Prize / Lottery ────────────────────────────────────────────────────
  prizeLottery(
    'Lừa trúng thưởng',
    'Không có giải thưởng thật nào yêu cầu đóng phí trước. Bỏ qua.',
  ),
  lotteryNumbers(
    'Lừa số lô đề',
    'Không ai có thể dự đoán chính xác số lô đề. Đừng tin.',
  ),

  // Kidnap / Threat ────────────────────────────────────────────────────
  kidnapRansom(
    'Dọa bắt cóc/tống tiền',
    'Giữ bình tĩnh. Gọi trực tiếp cho người thân để xác nhận. Báo công an.',
  ),
  imageExtortion(
    'Tống tiền bằng hình ảnh',
    'Không chuyển tiền. Báo công an ngay. Giữ bằng chứng.',
  ),

  // Tech ───────────────────────────────────────────────────────────────
  fakeAppInstall(
    'Cài ứng dụng giả mạo',
    'Không cài ứng dụng lạ hoặc cung cấp mật khẩu. Cúp máy ngay.',
  ),

  // Romance ────────────────────────────────────────────────────────────
  romanceExtortion(
    'Lừa tình cảm/tống tiền',
    'Không chuyển tiền cho người chưa gặp mặt ngoài đời. Cẩn thận.',
  ),
  romanceInvest(
    'Lừa tình cảm đầu tư',
    'Không đầu tư theo hướng dẫn của người quen online. Đây là bẫy.',
  ),
  sugarDating(
    'Lừa hẹn hò/sugar dating',
    'Không chuyển tiền cho người hẹn hò online. Đây là lừa đảo.',
  ),

  // Job ────────────────────────────────────────────────────────────────
  jobScamDeposit(
    'Lừa việc làm đặt cọc',
    'Không đóng phí tuyển dụng. Công ty uy tín không thu phí.',
  ),
  jobScamTask(
    'Lừa việc làm online',
    'Không làm nhiệm vụ trả tiền online. Đây là bẫy lừa đảo.',
  ),

  // Utility / Telecom ──────────────────────────────────────────────────
  electricityWater(
    'Giả mạo điện/nước',
    'Liên hệ trực tiếp công ty điện/nước. Không đóng phí qua điện thoại.',
  ),
  telecomDebt(
    'Giả mạo nợ cước viễn thông',
    'Gọi lại tổng đài chính thức của nhà mạng để xác minh.',
  ),
  telecomSimUpgrade(
    'Lừa nâng cấp SIM',
    'Không cung cấp mã OTP. Đến trực tiếp cửa hàng nhà mạng.',
  ),

  // Social / Family ────────────────────────────────────────────────────
  fakeFriendBorrow(
    'Giả mạo bạn bè vay tiền',
    'Gọi lại trực tiếp cho bạn bè để xác minh. Đừng vội chuyển tiền.',
  ),
  relativeEmergency(
    'Giả mạo người thân cấp cứu',
    'Gọi trực tiếp cho người thân. Đây là chiêu lừa phổ biến.',
  ),

  // Education ──────────────────────────────────────────────────────────
  scholarshipFake(
    'Lừa học bổng',
    'Không đóng phí để nhận học bổng. Xác minh tại trường.',
  ),
  tuitionRefund(
    'Lừa hoàn học phí',
    'Không cung cấp thông tin tài khoản. Xác minh tại trường.',
  ),

  // Other ──────────────────────────────────────────────────────────────
  charityDisaster(
    'Lừa từ thiện/thiên tai',
    'Chỉ quyên góp qua tổ chức uy tín có xác minh.',
  ),
  debtCollectionFake(
    'Đòi nợ giả mạo',
    'Không chuyển tiền cho người lạ tự xưng đòi nợ. Xác minh.',
  ),
  fireSafetyScam(
    'Lừa phòng cháy chữa cháy',
    'PCCC không yêu cầu đóng phí qua điện thoại. Xác minh.',
  ),
  medicalScam(
    'Lừa đảo y tế/thuốc',
    'Không mua thuốc hoặc dịch vụ y tế qua điện thoại người lạ.',
  ),
  vehicleRegistration(
    'Lừa đăng ký xe',
    'Không đóng phí đăng ký xe qua điện thoại. Đến trực tiếp cơ quan.',
  ),

  /// Catch-all for scam calls that don't match a specific subtype.
  unknown(
    'Lừa đảo khác',
    'Cuộc gọi có dấu hiệu lừa đảo. Hãy cúp máy và xác minh.',
  );

  const ScamType(this.displayName, this.advice);
  final String displayName;
  final String advice;

  /// Map from model label string to enum value.
  static ScamType fromLabel(String label) {
    return switch (label) {
      'safe' => ScamType.safe,
      'ai_flash_call' => ScamType.aiFlashCall,
      'bank_card_upgrade' => ScamType.bankCardUpgrade,
      'bank_fraud_alert' => ScamType.bankFraudAlert,
      'charity_disaster' => ScamType.charityDisaster,
      'customs_official' => ScamType.customsOfficial,
      'debt_collection_fake' => ScamType.debtCollectionFake,
      'deepfake_video_call' => ScamType.deepfakeVideoCall,
      'deepfake_voice_clone' => ScamType.deepfakeVoiceClone,
      'electricity_water' => ScamType.electricityWater,
      'ewallet_scam' => ScamType.ewalletScam,
      'fake_app_install' => ScamType.fakeAppInstall,
      'fake_friend_borrow' => ScamType.fakeFriendBorrow,
      'fake_loan' => ScamType.fakeLoan,
      'fake_shipper' => ScamType.fakeShipper,
      'fire_safety_scam' => ScamType.fireSafetyScam,
      'gift_package' => ScamType.giftPackage,
      'government_order_fake' => ScamType.governmentOrderFake,
      'image_extortion' => ScamType.imageExtortion,
      'investment_scam' => ScamType.investmentScam,
      'job_scam_deposit' => ScamType.jobScamDeposit,
      'job_scam_task' => ScamType.jobScamTask,
      'kidnap_ransom' => ScamType.kidnapRansom,
      'lottery_numbers' => ScamType.lotteryNumbers,
      'medical_scam' => ScamType.medicalScam,
      'merge_exploit' => ScamType.mergeExploit,
      'none' => ScamType.unknown,
      'police_impersonation' => ScamType.policeImpersonation,
      'prize_lottery' => ScamType.prizeLottery,
      'prosecutor_court' => ScamType.prosecutorCourt,
      'relative_emergency' => ScamType.relativeEmergency,
      'romance_extortion' => ScamType.romanceExtortion,
      'romance_invest' => ScamType.romanceInvest,
      'salary_advance' => ScamType.salaryAdvance,
      'scholarship_fake' => ScamType.scholarshipFake,
      'social_insurance' => ScamType.socialInsurance,
      'sugar_dating' => ScamType.sugarDating,
      'tax_authority' => ScamType.taxAuthority,
      'telecom_debt' => ScamType.telecomDebt,
      'telecom_sim_upgrade' => ScamType.telecomSimUpgrade,
      'tuition_refund' => ScamType.tuitionRefund,
      'vehicle_registration' => ScamType.vehicleRegistration,
      _ => ScamType.unknown,
    };
  }

  ThreatLevel get threatLevel {
    return this == ScamType.safe ? ThreatLevel.safe : ThreatLevel.scam;
  }
}

/// On-device two-stage scam classifier using TF-IDF + linear models.
///
/// **Stage 1 — Gate** (binary):
/// A high-recall sigmoid classifier decides safe vs scam.  Its threshold
/// is baked into the model weights (`gate_classifier_weights.json`).
///
/// **Stage 2 — Type** (multiclass):
/// Runs only when the gate flags a scam.  A softmax classifier over 41
/// scam subtypes identifies the specific scam category.
///
/// Implements [ScamTextClassifier] so it's a drop-in replacement for
/// [GeminiScamTextApi].  No network required — runs entirely on device.
class LocalScamClassifier implements ScamTextClassifier {
  /// [suspiciousThreshold] — gate probability between this and the model's
  /// scam threshold produces a `suspicious` result.
  LocalScamClassifier({this.suspiciousThreshold = 0.50});

  static const _windowCharacters = 600;

  /// Gate probability below this is always safe.
  final double suspiciousThreshold;

  // ── Gate model (binary: safe / scam) ──────────────────────────────
  late final Map<String, int> _gateVocabulary;
  late final List<double> _gateIdf;
  late final int _gateNgramMin;
  late final int _gateNgramMax;
  late final bool _gateSublinearTf;
  late final List<double> _gateCoef; // single row [n_features]
  late final double _gateIntercept;
  late final double _gateThreshold; // from model (e.g. 0.55)

  // ── Type model (multiclass: 41 scam subtypes) ────────────────────
  late final Map<String, int> _typeVocabulary;
  late final List<double> _typeIdf;
  late final int _typeNgramMin;
  late final int _typeNgramMax;
  late final bool _typeSublinearTf;
  late final List<String> _typeClasses;
  late final List<List<double>> _typeCoef; // [n_classes][n_features]
  late final List<double> _typeIntercept; // [n_classes]

  bool _loaded = false;

  /// Create and eagerly load the classifier from bundled assets.
  static Future<LocalScamClassifier> load() async {
    final classifier = LocalScamClassifier();
    await classifier._loadModel();
    return classifier;
  }

  Future<void> _loadModel() async {
    if (_loaded) return;

    // ── Load gate TF-IDF config ────────────────────────────────────
    final gateTfidfJson = await rootBundle.loadString(
      'assets/models/gate_tfidf_config.json',
    );
    final gateTfidf = jsonDecode(gateTfidfJson) as Map<String, dynamic>;

    final gateRawVocab = gateTfidf['vocabulary'] as Map<String, dynamic>;
    _gateVocabulary = gateRawVocab.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );
    _gateIdf = (gateTfidf['idf'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final gateNgram = gateTfidf['ngram_range'] as List<dynamic>;
    _gateNgramMin = (gateNgram[0] as num).toInt();
    _gateNgramMax = (gateNgram[1] as num).toInt();
    _gateSublinearTf = gateTfidf['sublinear_tf'] as bool? ?? true;

    // ── Load gate classifier weights ───────────────────────────────
    final gateWeightsJson = await rootBundle.loadString(
      'assets/models/gate_classifier_weights.json',
    );
    final gateWeights = jsonDecode(gateWeightsJson) as Map<String, dynamic>;

    // Binary classifier: coef is [[...]] (1 row), intercept is [x].
    _gateCoef = ((gateWeights['coef'] as List<dynamic>).first as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    _gateIntercept =
        ((gateWeights['intercept'] as List<dynamic>).first as num).toDouble();
    _gateThreshold = (gateWeights['threshold'] as num?)?.toDouble() ?? 0.55;

    // ── Load type TF-IDF config ────────────────────────────────────
    final typeTfidfJson = await rootBundle.loadString(
      'assets/models/tfidf_config.json',
    );
    final typeTfidf = jsonDecode(typeTfidfJson) as Map<String, dynamic>;

    final typeRawVocab = typeTfidf['vocabulary'] as Map<String, dynamic>;
    _typeVocabulary = typeRawVocab.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );
    _typeIdf = (typeTfidf['idf'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final typeNgram = typeTfidf['ngram_range'] as List<dynamic>;
    _typeNgramMin = (typeNgram[0] as num).toInt();
    _typeNgramMax = (typeNgram[1] as num).toInt();
    _typeSublinearTf = typeTfidf['sublinear_tf'] as bool? ?? true;

    // ── Load type classifier weights ───────────────────────────────
    final typeWeightsJson = await rootBundle.loadString(
      'assets/models/classifier_weights.json',
    );
    final typeWeights = jsonDecode(typeWeightsJson) as Map<String, dynamic>;

    _typeClasses = (typeWeights['classes'] as List<dynamic>).cast<String>();
    _typeCoef = (typeWeights['coef'] as List<dynamic>)
        .map(
          (row) => (row as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList(),
        )
        .toList();
    _typeIntercept = (typeWeights['intercept'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();

    _loaded = true;
  }

  @override
  Future<ScamAnalysisResult> classifyTranscriptWindow(
    String transcript,
  ) async {
    if (!_loaded) await _loadModel();

    final window = _latestWindow(transcript);
    if (window.isEmpty) return _fallbackResult();

    // ── Stage 1: Gate (binary safe / scam) ─────────────────────────
    final gateTfidf = _computeTfidf(
      window,
      vocabulary: _gateVocabulary,
      idf: _gateIdf,
      ngramMin: _gateNgramMin,
      ngramMax: _gateNgramMax,
      sublinearTf: _gateSublinearTf,
    );

    var gateLogit = _gateIntercept;
    for (final entry in gateTfidf.entries) {
      gateLogit += _gateCoef[entry.key] * entry.value;
    }
    final gateProb = _sigmoid(gateLogit);

    // Gate says safe → return immediately.
    if (gateProb < suspiciousThreshold) {
      return ScamAnalysisResult(
        threatLevel: ThreatLevel.safe,
        confidence: 1.0 - gateProb,
        scamProbability: gateProb,
        patterns: const [],
        summary: ScamType.safe.displayName,
        advice: ScamType.safe.advice,
      );
    }

    // ── Stage 2: Type classifier (41-class) ────────────────────────
    final typeTfidf = _computeTfidf(
      window,
      vocabulary: _typeVocabulary,
      idf: _typeIdf,
      ngramMin: _typeNgramMin,
      ngramMax: _typeNgramMax,
      sublinearTf: _typeSublinearTf,
    );

    final scores = List<double>.filled(_typeClasses.length, 0.0);
    for (var c = 0; c < _typeClasses.length; c++) {
      var score = _typeIntercept[c];
      for (final entry in typeTfidf.entries) {
        score += _typeCoef[c][entry.key] * entry.value;
      }
      scores[c] = score;
    }

    final probabilities = _softmax(scores);

    var bestIdx = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[bestIdx]) bestIdx = i;
    }

    final scamType = ScamType.fromLabel(_typeClasses[bestIdx]);

    // Determine threat level from gate probability.
    final ThreatLevel effectiveThreat;
    if (gateProb >= _gateThreshold) {
      effectiveThreat = ThreatLevel.scam;
    } else {
      effectiveThreat = ThreatLevel.suspicious;
    }

    return ScamAnalysisResult(
      threatLevel: effectiveThreat,
      confidence: gateProb,
      scamProbability: gateProb,
      patterns: [scamType.displayName],
      summary: scamType.displayName,
      advice: scamType.advice,
    );
  }

  // ── TF-IDF computation (shared by both stages) ───────────────────

  Map<int, double> _computeTfidf(
    String text, {
    required Map<String, int> vocabulary,
    required List<double> idf,
    required int ngramMin,
    required int ngramMax,
    required bool sublinearTf,
  }) {
    final tf = <int, double>{};
    final words = RegExp(r'[\p{L}\p{N}_]+', unicode: true)
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

    for (final word in words) {
      final padded = ' $word ';
      for (var n = ngramMin; n <= ngramMax; n++) {
        for (var i = 0; i <= padded.length - n; i++) {
          final ngram = padded.substring(i, i + n);
          final idx = vocabulary[ngram];
          if (idx != null) {
            tf[idx] = (tf[idx] ?? 0) + 1;
          }
        }
      }
    }

    if (sublinearTf) {
      for (final key in tf.keys.toList()) {
        tf[key] = 1 + math.log(tf[key]!);
      }
    }

    for (final key in tf.keys.toList()) {
      tf[key] = tf[key]! * idf[key];
    }

    // L2 normalize
    var norm = 0.0;
    for (final v in tf.values) {
      norm += v * v;
    }
    if (norm > 0) {
      norm = math.sqrt(norm);
      for (final key in tf.keys.toList()) {
        tf[key] = tf[key]! / norm;
      }
    }

    return tf;
  }

  // ── Math helpers ──────────────────────────────────────────────────

  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  List<double> _softmax(List<double> scores) {
    final maxScore = scores.reduce(math.max);
    final exps = scores.map((s) => math.exp(s - maxScore)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  String _latestWindow(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.length <= _windowCharacters) return trimmed;
    return trimmed.substring(trimmed.length - _windowCharacters);
  }

  ScamAnalysisResult _fallbackResult() {
    return const ScamAnalysisResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0,
      scamProbability: 0,
      patterns: [],
      summary: 'Không thể phân tích.',
      advice: 'Hãy cẩn thận và xác minh độc lập.',
    );
  }
}
