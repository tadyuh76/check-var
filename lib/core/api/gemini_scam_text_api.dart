import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_keys.dart';
import '../../models/scam_alert.dart';

abstract interface class ScamTextClassifier {
  Future<ScamAnalysisResult> classifyTranscriptWindow(String transcript);
}

class ScamAnalysisResult {
  const ScamAnalysisResult({
    required this.threatLevel,
    required this.confidence,
    required this.patterns,
    required this.summary,
    required this.advice,
    this.scamProbability = 0.0,
  });

  final ThreatLevel threatLevel;
  final double confidence;
  final List<String> patterns;
  final String summary;
  final String advice;

  /// Raw probability that the call is a scam, on a consistent 0–1 scale
  /// (higher = more likely scam).  Unlike [confidence], which inverts for
  /// safe results, this value is always directly comparable across analyses.
  final double scamProbability;

  ScamAlert toAlert() {
    return ScamAlert(
      threatLevel: threatLevel,
      confidence: confidence,
      patterns: patterns,
      summary: summary,
      advice: advice,
    );
  }
}

class GeminiScamTextApi implements ScamTextClassifier {
  GeminiScamTextApi({
    http.Client? client,
    String? apiKey,
    this.model = 'gemini-2.5-flash',
  }) : _client = client ?? http.Client(),
       _apiKey = apiKey ?? geminiApiKey;

  static const _timeout = Duration(seconds: 30);
  static const _windowCharacters = 600;

  final http.Client _client;
  final String _apiKey;
  final String model;

  @override
  Future<ScamAnalysisResult> classifyTranscriptWindow(String transcript) async {
    final window = _latestWindow(transcript);

    try {
      final response = await _client
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/'
              '$model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text':
                          '''
Analyze the following phone-call transcript window for scam indicators.

Return JSON only. Use these fields:
- threat_level: safe, suspicious, or scam
- confidence: 0.0 to 1.0
- patterns_detected: short string list
- summary: short explanation
- advice: short safety action

TRANSCRIPT WINDOW:
$window
''',
                    },
                  ],
                },
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'responseSchema': {
                  'type': 'object',
                  'properties': {
                    'threat_level': {
                      'type': 'string',
                      'enum': ['safe', 'suspicious', 'scam'],
                    },
                    'confidence': {'type': 'number'},
                    'patterns_detected': {
                      'type': 'array',
                      'items': {'type': 'string'},
                    },
                    'summary': {'type': 'string'},
                    'advice': {'type': 'string'},
                  },
                  'required': [
                    'threat_level',
                    'confidence',
                    'patterns_detected',
                    'summary',
                    'advice',
                  ],
                },
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return _fallbackResult();
      }

      final text = _extractCandidateText(response.body);
      if (text == null) {
        return _fallbackResult();
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return _fallbackResult();
      }

      final threatLevel = _parseThreatLevel(decoded['threat_level'] as String?);
      final confidence = (decoded['confidence'] as num?)?.toDouble() ?? 0;

      return ScamAnalysisResult(
        threatLevel: threatLevel,
        confidence: confidence,
        scamProbability: threatLevel == ThreatLevel.safe
            ? 1.0 - confidence
            : confidence,
        patterns: (decoded['patterns_detected'] as List<dynamic>? ?? const [])
            .map((pattern) => pattern.toString())
            .toList(),
        summary:
            decoded['summary'] as String? ??
            'Unable to analyze the transcript clearly.',
        advice:
            decoded['advice'] as String? ??
            'Slow down and verify independently before taking action.',
      );
    } catch (_) {
      return _fallbackResult();
    }
  }

  String _latestWindow(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.length <= _windowCharacters) {
      return trimmed;
    }
    return trimmed.substring(trimmed.length - _windowCharacters);
  }

  String? _extractCandidateText(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final candidates = decoded['candidates'] as List<dynamic>?;
    final firstCandidate = candidates?.isNotEmpty == true
        ? candidates!.first
        : null;
    final content =
        (firstCandidate as Map<String, dynamic>?)?['content']
            as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    final firstPart = parts?.isNotEmpty == true ? parts!.first : null;
    return (firstPart as Map<String, dynamic>?)?['text'] as String?;
  }

  ThreatLevel _parseThreatLevel(String? rawValue) {
    return switch ((rawValue ?? '').toLowerCase()) {
      'scam' => ThreatLevel.scam,
      'suspicious' => ThreatLevel.suspicious,
      _ => ThreatLevel.safe,
    };
  }

  ScamAnalysisResult _fallbackResult() {
    return const ScamAnalysisResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0,
      patterns: [],
      summary: 'Unable to analyze the transcript clearly.',
      advice: 'Slow down and verify independently before taking action.',
    );
  }
}
