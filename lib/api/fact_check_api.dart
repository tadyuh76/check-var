import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_keys.dart';
import '../models/check_result.dart';

// ---------------------------------------------------------------------------
// 1. Clean OCR text
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
// 2. Extract search query via LLM (Groq Llama)
// ---------------------------------------------------------------------------

/// Sends cleaned text to Groq LLM to extract a single search query
/// that best represents the core claim.
Future<String> extractSearchQuery(String cleanedText) async {
  final truncated =
      cleanedText.length > 1000 ? cleanedText.substring(0, 1000) : cleanedText;

  final prompt =
      '''From the following text, extract the single most important factual claim and turn it into a concise Google search query (Vietnamese or English, matching the text language). Return ONLY the search query, nothing else.

TEXT:
$truncated''';

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
            'temperature': 0.0,
            'max_tokens': 100,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You extract search queries from text. Return ONLY the query string, no quotes, no explanation.',
              },
              {
                'role': 'user',
                'content': prompt,
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Groq HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (data['choices'] as List<dynamic>?)
            ?.firstOrNull?['message']?['content'] as String? ??
        '';

    final query = content.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    if (query.isEmpty) throw Exception('Empty query from LLM');
    return query;
  } catch (e) {
    // Fallback: use longest line from text
    final lines = cleanedText.split('\n').where((l) => l.length > 20).toList();
    if (lines.isEmpty) return cleanedText.substring(0, cleanedText.length.clamp(0, 100));
    final longest = lines.reduce((a, b) => a.length >= b.length ? a : b);
    return longest.length > 100 ? longest.substring(0, 100) : longest;
  }
}

// ---------------------------------------------------------------------------
// 3. Web search via Serper.dev
// ---------------------------------------------------------------------------

/// Performs a Google search using Serper.dev and returns up to 10 results.
Future<List<SearchSource>> webSearch(String query) async {
  try {
    final response = await http
        .post(
          Uri.parse('https://google.serper.dev/search'),
          headers: {
            'X-API-KEY': serperApiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'q': query,
            'num': 10,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final organic = data['organic'] as List<dynamic>? ?? [];

    return organic.take(10).map((r) {
      final item = r as Map<String, dynamic>;
      return SearchSource(
        title: item['title'] as String? ?? '',
        url: item['link'] as String? ?? '',
        snippet: item['snippet'] as String? ?? '',
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

// ---------------------------------------------------------------------------
// 4. Classify news via Groq LLM
// ---------------------------------------------------------------------------

/// Sends the claim text and search sources to the Groq LLM for
/// fact-checking classification.
Future<CheckResult> classifyNews(
  String text,
  List<SearchSource> sources,
) async {
  final truncated = text.length > 500 ? text.substring(0, 500) : text;

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
        summary: 'Lỗi LLM: HTTP ${response.statusCode}',
        sources: sources,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (data['choices'] as List<dynamic>?)
            ?.firstOrNull?['message']?['content'] as String? ??
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

Map<String, dynamic>? _extractJson(String raw) {
  try {
    var s = raw;
    s = s.replaceAll(RegExp(r'```json\s*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'```\s*'), '');
    s = s.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    s = s.trim();

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
