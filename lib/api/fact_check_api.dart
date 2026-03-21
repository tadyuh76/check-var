import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import '../models/check_result.dart';

// ---------------------------------------------------------------------------
// 1. Clean OCR text (runs on-device, no network needed)
// ---------------------------------------------------------------------------

/// Regex matching OCR junk: timestamps, status-bar noise, app names,
/// UI chrome, ads, metadata, and CheckVar's own UI strings.
final RegExp _ocrJunk = RegExp(
  r'^\d{1,2}:\d{2}(\s*(AM|PM|am|pm))?$|'
  r'^O{3,}$|'
  r'^\d+\s*%$|'
  r'^[A-Z\s]*\d+\s*%$|'
  r'^I\s*D\s*\d+%$|'
  r'^(Facebook|Messenger|Chrome|Safari|Zalo|Google Lens|TikTok)$|'
  r'^(CHIA SẺ|Nghe đọc bài|Mua ngay|Mở rộng|Hot|Mới)$|'
  r'^tài trợ$|'
  r'^\d{1,3}(\.\d{3})*(đ|₫)$|'
  r'^(TRANG THÔNG TIN|reviewer\.|m\.genk\.vn)$|'
  r'^(CheckVar|Analysis failed|Đang phân tích)$',
  caseSensitive: false,
);

/// Cleans raw OCR output by removing junk lines, merging short fragments into
/// paragraphs, and validating minimum content length.
String cleanOcrText(String text) {
  final lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  final filtered = <String>[];
  for (final line in lines) {
    final wordCount =
        line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount < 4 && line.length <= 15) continue;
    if (_ocrJunk.hasMatch(line)) continue;
    filtered.add(line);
  }

  final paragraphs = <String>[];
  for (final line in filtered) {
    final endsWithPunctuation = RegExp(r'[.!?]$').hasMatch(line);
    if (paragraphs.isNotEmpty && line.length < 50 && !endsWithPunctuation) {
      paragraphs[paragraphs.length - 1] = '${paragraphs.last} $line';
    } else {
      paragraphs.add(line);
    }
  }

  final result = paragraphs.join('\n');

  if (result.length < 20) {
    throw Exception('Không đủ nội dung');
  }

  return result;
}

// ---------------------------------------------------------------------------
// 2. Call AWS Lambda for fact-checking (query extraction + search + classify)
// ---------------------------------------------------------------------------

/// Sends cleaned text to the AWS Lambda endpoint which handles:
/// - Search query extraction (Groq LLM)
/// - Web search (Serper)
/// - News classification (Groq LLM)
///
/// Returns a [CheckResult] with verdict, confidence, summary, and sources.
Future<CheckResult> factCheck(String cleanedText) async {
  try {
    final response = await http
        .post(
          Uri.parse(awsFactCheckEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': cleanedText}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      return CheckResult(
        verdict: Verdict.uncertain,
        confidence: 0.0,
        extractedText: cleanedText,
        summary: 'Server error: HTTP ${response.statusCode}',
        sources: [],
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final verdictStr =
        (data['verdict'] as String? ?? 'uncertain').toLowerCase();
    final verdict = switch (verdictStr) {
      'real' => Verdict.real,
      'fake' => Verdict.fake,
      _ => Verdict.uncertain,
    };

    final confidence =
        (data['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    final summary = data['summary'] as String? ?? '';

    final sourcesJson = data['sources'] as List<dynamic>? ?? [];
    final sources = sourcesJson
        .map((s) => SearchSource.fromJson(s as Map<String, dynamic>))
        .toList();

    return CheckResult(
      verdict: verdict,
      confidence: confidence,
      extractedText: cleanedText,
      summary: summary,
      sources: sources,
    );
  } catch (e) {
    return CheckResult(
      verdict: Verdict.uncertain,
      confidence: 0.0,
      extractedText: cleanedText,
      summary: 'Lỗi kết nối server: $e',
      sources: [],
    );
  }
}
