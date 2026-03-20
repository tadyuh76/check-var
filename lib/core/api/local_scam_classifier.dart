import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../../models/scam_alert.dart';
import 'gemini_scam_text_api.dart';

/// Scam type labels with Vietnamese display names and advice.
enum ScamType {
  safe('An toàn', 'Cuộc gọi bình thường, không có dấu hiệu lừa đảo.'),
  bankFraud(
    'Giả mạo ngân hàng',
    'Không cung cấp OTP hoặc thông tin thẻ. Gọi lại hotline ngân hàng chính thức.',
  ),
  authorityImpersonation(
    'Giả mạo cơ quan',
    'Công an không bao giờ yêu cầu chuyển tiền qua điện thoại. Cúp máy ngay.',
  ),
  prizeScam(
    'Lừa trúng thưởng',
    'Không có giải thưởng thật nào yêu cầu đóng phí trước. Bỏ qua.',
  ),
  deliveryScam(
    'Lừa đảo giao hàng',
    'Không đóng phí qua điện thoại. Liên hệ trực tiếp đơn vị vận chuyển.',
  ),
  investmentScam(
    'Lừa đầu tư',
    'Không có khoản đầu tư nào cam kết lợi nhuận cao, rủi ro thấp. Từ chối.',
  ),
  loanScam(
    'Lừa cho vay',
    'Không đóng phí trước khi nhận khoản vay. Đây là dấu hiệu lừa đảo.',
  ),
  kidnappingThreat(
    'Dọa bắt cóc/tống tiền',
    'Giữ bình tĩnh. Gọi trực tiếp cho người thân để xác nhận. Báo công an.',
  ),
  techSupport(
    'Lừa hỗ trợ kỹ thuật',
    'Không cài ứng dụng lạ hoặc cung cấp mật khẩu. Cúp máy ngay.',
  ),
  romanceScam(
    'Lừa tình cảm',
    'Không chuyển tiền cho người chưa gặp mặt ngoài đời. Cẩn thận.',
  );

  const ScamType(this.displayName, this.advice);
  final String displayName;
  final String advice;

  /// Map from model label string to enum value.
  static ScamType fromLabel(String label) {
    return switch (label) {
      'safe' => ScamType.safe,
      'bank_fraud' => ScamType.bankFraud,
      'authority_impersonation' => ScamType.authorityImpersonation,
      'prize_scam' => ScamType.prizeScam,
      'delivery_scam' => ScamType.deliveryScam,
      'investment_scam' => ScamType.investmentScam,
      'loan_scam' => ScamType.loanScam,
      'kidnapping_threat' => ScamType.kidnappingThreat,
      'tech_support' => ScamType.techSupport,
      'romance_scam' => ScamType.romanceScam,
      _ => ScamType.safe,
    };
  }

  ThreatLevel get threatLevel {
    return this == ScamType.safe ? ThreatLevel.safe : ThreatLevel.scam;
  }
}

/// On-device scam transcript classifier using TF-IDF + linear model.
///
/// Implements [ScamTextClassifier] so it's a drop-in replacement for
/// [GeminiScamTextApi]. No network required — runs entirely on device.
class LocalScamClassifier implements ScamTextClassifier {
  /// Creates a classifier that lazily loads model weights on first use.
  ///
  /// [suspiciousThreshold] — if the top scam class confidence is between
  /// this value and [scamThreshold], the result is reported as `suspicious`.
  /// [scamThreshold] — confidence at or above this level is reported as `scam`.
  LocalScamClassifier({
    this.suspiciousThreshold = 0.4,
    this.scamThreshold = 0.7,
  });

  static const _windowCharacters = 600;

  /// Minimum confidence to flag as suspicious (below this → safe).
  final double suspiciousThreshold;

  /// Minimum confidence to flag as scam (below this but above suspicious → suspicious).
  final double scamThreshold;

  // TF-IDF config
  late final Map<String, int> _vocabulary;
  late final List<double> _idf;
  late final int _ngramMin;
  late final int _ngramMax;
  late final bool _sublinearTf;

  // Linear classifier weights
  late final List<String> _classes;
  late final List<List<double>> _coef; // [n_classes][n_features]
  late final List<double> _intercept;  // [n_classes]

  bool _loaded = false;

  /// Create and eagerly load the classifier from bundled assets.
  static Future<LocalScamClassifier> load() async {
    final classifier = LocalScamClassifier();
    await classifier._loadModel();
    return classifier;
  }

  Future<void> _loadModel() async {
    if (_loaded) return;

    // Load TF-IDF config
    final tfidfJson = await rootBundle.loadString(
      'assets/models/tfidf_config.json',
    );
    final tfidfConfig = jsonDecode(tfidfJson) as Map<String, dynamic>;

    final rawVocab = tfidfConfig['vocabulary'] as Map<String, dynamic>;
    _vocabulary = rawVocab.map((k, v) => MapEntry(k, (v as num).toInt()));
    _idf = (tfidfConfig['idf'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final ngramRange = tfidfConfig['ngram_range'] as List<dynamic>;
    _ngramMin = (ngramRange[0] as num).toInt();
    _ngramMax = (ngramRange[1] as num).toInt();
    _sublinearTf = tfidfConfig['sublinear_tf'] as bool? ?? true;

    // Load classifier weights
    final weightsJson = await rootBundle.loadString(
      'assets/models/classifier_weights.json',
    );
    final weights = jsonDecode(weightsJson) as Map<String, dynamic>;

    _classes = (weights['classes'] as List<dynamic>).cast<String>();
    _coef = (weights['coef'] as List<dynamic>)
        .map(
          (row) => (row as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList(),
        )
        .toList();
    _intercept = (weights['intercept'] as List<dynamic>)
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

    // 1. Extract character n-grams (char_wb: word-boundary aware)
    final tfidfVector = _computeTfidf(window);

    // 2. Linear transform: scores = coef · tfidf + intercept
    final scores = List<double>.filled(_classes.length, 0.0);
    for (var c = 0; c < _classes.length; c++) {
      var score = _intercept[c];
      for (final entry in tfidfVector.entries) {
        score += _coef[c][entry.key] * entry.value;
      }
      scores[c] = score;
    }

    // 3. Softmax to get probabilities
    final probabilities = _softmax(scores);

    // 4. Find best class
    var bestIdx = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[bestIdx]) bestIdx = i;
    }

    final scamType = ScamType.fromLabel(_classes[bestIdx]);
    final confidence = probabilities[bestIdx];

    // If the classifier's top pick is safe, report safe regardless of confidence.
    // Otherwise, use confidence thresholds to decide safe / suspicious / scam.
    final ThreatLevel effectiveThreat;
    if (scamType == ScamType.safe) {
      effectiveThreat = ThreatLevel.safe;
    } else if (confidence >= scamThreshold) {
      effectiveThreat = ThreatLevel.scam;
    } else if (confidence >= suspiciousThreshold) {
      effectiveThreat = ThreatLevel.suspicious;
    } else {
      effectiveThreat = ThreatLevel.safe;
    }

    final isThreat = effectiveThreat != ThreatLevel.safe;

    return ScamAnalysisResult(
      threatLevel: effectiveThreat,
      confidence: confidence,
      patterns: isThreat ? [scamType.displayName] : [],
      summary: isThreat ? scamType.displayName : ScamType.safe.displayName,
      advice: isThreat ? scamType.advice : ScamType.safe.advice,
    );
  }

  /// Compute sparse TF-IDF vector for the input text.
  Map<int, double> _computeTfidf(String text) {
    // Count term frequencies using char_wb n-grams.
    // Use Unicode property escapes to match word characters — Python's \w
    // includes Unicode letters, but Dart's \w is ASCII-only. Using \p{L}
    // (Unicode letters) and \p{N} (Unicode numbers) matches Python's behavior.
    final tf = <int, double>{};
    final words = RegExp(r'[\p{L}\p{N}_]+', unicode: true)
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

    for (final word in words) {
      // char_wb pads words with spaces: " word "
      final padded = ' $word ';
      for (var n = _ngramMin; n <= _ngramMax; n++) {
        for (var i = 0; i <= padded.length - n; i++) {
          final ngram = padded.substring(i, i + n);
          final idx = _vocabulary[ngram];
          if (idx != null) {
            tf[idx] = (tf[idx] ?? 0) + 1;
          }
        }
      }
    }

    // Apply sublinear TF scaling: tf = 1 + log(tf)
    if (_sublinearTf) {
      for (final key in tf.keys.toList()) {
        tf[key] = 1 + math.log(tf[key]!);
      }
    }

    // Multiply by IDF
    for (final key in tf.keys.toList()) {
      tf[key] = tf[key]! * _idf[key];
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
      patterns: [],
      summary: 'Không thể phân tích.',
      advice: 'Hãy cẩn thận và xác minh độc lập.',
    );
  }
}
