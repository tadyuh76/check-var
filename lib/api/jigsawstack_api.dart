import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_keys.dart';
import '../models/check_result.dart';

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

// ---------------------------------------------------------------------------
// 1. Clean OCR text
// ---------------------------------------------------------------------------

/// Cleans raw OCR output by removing junk lines, merging short fragments into
/// paragraphs, and validating minimum content length.
String cleanOcrText(String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  // Filter out junk lines
  final filtered = <String>[];
  for (final line in lines) {
    final wordCount = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount < 4 && line.length <= 15) continue;
    if (_ocrJunk.hasMatch(line)) continue;
    filtered.add(line);
  }

  // Merge short consecutive lines into paragraphs
  final paragraphs = <String>[];
  for (final line in filtered) {
    final endsWithPunctuation = RegExp(r'[.!?]$').hasMatch(line);
    if (paragraphs.isNotEmpty && line.length < 50 && !endsWithPunctuation) {
      // Append to the previous paragraph (same sentence)
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
// 2. Extract search queries
// ---------------------------------------------------------------------------

/// Extracts one or two search queries from OCR text.
/// Q1 = longest qualifying line, Q2 = first qualifying line.
List<String> extractSearchQueries(String text) {
  // text is already text by controller — don't double-clean
  final longLines =
      text.split('\n').where((l) => l.length > 20).toList();

  if (longLines.isEmpty) {
    return [text.length > 100 ? text.substring(0, 100) : text];
  }

  // Q1: longest line (truncated to 100 chars)
  final longest = longLines.reduce((a, b) => a.length >= b.length ? a : b);
  final q1 = longest.length > 100 ? longest.substring(0, 100) : longest;

  // Q2: first long line (truncated to 100 chars)
  final first = longLines.first;
  final q2 = first.length > 100 ? first.substring(0, 100) : first;

  if (q1 == q2) return [q1];
  return [q1, q2];
}

// ---------------------------------------------------------------------------
// 3. Web search via JigsawStack
// ---------------------------------------------------------------------------

/// Performs a web search using the JigsawStack API and returns up to 5 results.
Future<List<SearchSource>> webSearch(String query) async {
  try {
    final response = await http
        .post(
          Uri.parse('https://api.jigsawstack.com/v1/web/search'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': jigsawStackApiKey,
          },
          body: jsonEncode({'query': query}),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];

    return results
        .take(5)
        .map((r) => SearchSource.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

// ---------------------------------------------------------------------------
// 4. Classify news via Groq LLM
// ---------------------------------------------------------------------------

/// Sends the text text and search sources to the Groq LLM for
/// fact-checking classification.
Future<CheckResult> classifyNews(
  String text,
  List<SearchSource> sources,
) async {
  // text is already text by controller — don't double-clean
  final truncated =
      text.length > 500 ? text.substring(0, 500) : text;

  // Build source summary block
  final sourceSummary = sources.isNotEmpty
      ? sources.map((s) => '- [${s.title}]: ${s.snippet}').join('\n')
      : '(no sources available)';

  final today = DateTime.now().toIso8601String().substring(0, 10);

  final prompt = '''You are a fact-checker. Today is $today. Return ONLY JSON.

IMPORTANT: Base your verdict ONLY on the SOURCES below — NOT on your training data.
The sources are real-time web search results from today.
Your knowledge cutoff does NOT matter.

Rules:
- If SOURCES confirm the claim → "real"
- If SOURCES contradict the claim → "fake"
- If no sources or sources are irrelevant → "uncertain"
- Rumors/opinions/non-news/ads/memes → "uncertain"
- NEVER say "beyond knowledge cutoff" — use the sources instead

CLAIM:
$truncated

TODAY'S WEB SEARCH RESULTS:
$sourceSummary

{"verdict":"real|fake|uncertain","confidence":0.0-1.0,"summary":"1-2 sentence Vietnamese explanation based on sources"}''';

  try {
    final response = await http
        .post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $groqApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'temperature': 0.1,
            'max_tokens': 200,
            'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'system',
                'content':
                    'You always respond with a single JSON object only. No explanations.',
              },
              {
                'role': 'user',
                'content': prompt,
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      return CheckResult(
        verdict: Verdict.uncertain,
        confidence: 0.0,
        extractedText: text,
        summary: 'Loi LLM: HTTP ${response.statusCode}',
        sources: sources,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (data['choices'] as List<dynamic>?)
            ?.firstOrNull
            ?['message']?['content'] as String? ??
        '';

    final parsed = _extractJson(content);

    if (parsed == null) {
      return CheckResult(
        verdict: Verdict.uncertain,
        confidence: 0.0,
        extractedText: text,
        summary: 'Không thể phân tích phản hồi từ AI.',
        sources: sources,
      );
    }

    // Map verdict string to enum
    final verdictStr =
        (parsed['verdict'] as String? ?? 'uncertain').toLowerCase();
    Verdict verdict;
    switch (verdictStr) {
      case 'real':
        verdict = Verdict.real;
        break;
      case 'fake':
        verdict = Verdict.fake;
        break;
      default:
        verdict = Verdict.uncertain;
    }

    final confidence =
        (parsed['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    var summary = parsed['summary'] as String? ?? '';

    if (sources.isEmpty) {
      summary =
          '⚠️ Web search không khả dụng, kết quả chỉ dựa trên AI.\n$summary';
    }

    return CheckResult(
      verdict: verdict,
      confidence: confidence,
      extractedText: text,
      summary: summary,
      sources: sources,
    );
  } catch (e) {
    return CheckResult(
      verdict: Verdict.uncertain,
      confidence: 0.0,
      extractedText: text,
      summary: 'Lỗi khi gọi AI: $e',
      sources: sources,
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Extract JSON from LLM response
// ---------------------------------------------------------------------------

/// Attempts to extract a JSON object from arbitrary LLM output.
/// Strips markdown code fences, think tags, and finds the outermost
/// balanced braces.
Map<String, dynamic>? _extractJson(String raw) {
  try {
    var s = raw;

    // Strip markdown code blocks: ```json ... ``` or ``` ... ```
    s = s.replaceAll(RegExp(r'```json\s*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'```\s*'), '');

    // Strip <think>...</think> tags and their content
    s = s.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );

    s = s.trim();

    // Find outermost balanced { }
    final start = s.indexOf('{');
    if (start == -1) return null;

    int depth = 0;
    int? end;
    for (int i = start; i < s.length; i++) {
      if (s[i] == '{') {
        depth++;
      } else if (s[i] == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }

    if (end == null) return null;

    final jsonStr = s.substring(start, end + 1);
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}
