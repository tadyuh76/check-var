import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'local_scam_classifier.dart';

/// ElevenLabs TTS client with locale-based voice selection and disk caching.
///
/// Fallback chain: cache → ElevenLabs API → null (caller falls back to native TTS).
class ElevenLabsTtsService {
  ElevenLabsTtsService({http.Client? client})
      : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 3);
  static const _baseUrl = 'https://api.elevenlabs.io/v1/text-to-speech';
  static const _model = 'eleven_multilingual_v2';
  static const _minCacheFileSize = 1024; // 1KB

  // Premade voices available on free plan (multilingual v2)
  static const _voiceIds = {
    'vi': 'SAz9YHcvj6GT2YYXdXww', // River — multilingual, supports Vietnamese
    'en': 'SAz9YHcvj6GT2YYXdXww', // River — neutral, informative
  };

  final http.Client _client;
  Directory? _cacheDir;

  // Telemetry counters
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _apiFails = 0;

  String get _apiKey => dotenv.env['ELEVENLABS_API_KEY'] ?? '';

  /// Synthesize [text] to MP3 audio bytes using the voice matched to [locale].
  ///
  /// Returns cached audio if available. On API failure returns `null` —
  /// the caller should fall back to Android native TTS.
  Future<Uint8List?> synthesize(String text, String locale) async {
    if (_apiKey.isEmpty) {
      debugPrint('[ElevenLabsTTS] No API key configured');
      return null;
    }

    final voiceId = _voiceIds[locale] ?? _voiceIds['en']!;

    // Check cache first
    final cached = await _readCache(text, locale);
    if (cached != null) {
      _cacheHits++;
      debugPrint('[ElevenLabsTTS] Cache hit ($locale) — '
          'hits=$_cacheHits misses=$_cacheMisses');
      return cached;
    }
    _cacheMisses++;

    // Call ElevenLabs API
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/$voiceId'),
            headers: {
              'xi-api-key': _apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'text': text,
              'model_id': _model,
              'voice_settings': {
                'stability': 0.7,
                'similarity_boost': 0.8,
              },
            }),
          )
          .timeout(_timeout);
      stopwatch.stop();

      debugPrint('[ElevenLabsTTS] API response ${response.statusCode} '
          'in ${stopwatch.elapsedMilliseconds}ms ($locale)');

      if (response.statusCode == 200 && response.bodyBytes.length >= _minCacheFileSize) {
        // Write to cache (fire-and-forget)
        _writeCache(text, locale, response.bodyBytes);
        return response.bodyBytes;
      }

      _apiFails++;
      debugPrint('[ElevenLabsTTS] API failed: ${response.statusCode} — '
          'fails=$_apiFails');
      return null;
    } catch (e) {
      _apiFails++;
      debugPrint('[ElevenLabsTTS] API error: $e — fails=$_apiFails');
      return null;
    }
  }

  /// Synthesize advice for a specific [scamType] using the advice text from
  /// [adviceMap] (loaded from assets/scam_advice.json).
  Future<Uint8List?> synthesizeAdvice(
    ScamType scamType,
    String locale,
    Map<String, Map<String, String>> adviceMap,
  ) {
    final advice = adviceMap[scamType.name]?[locale] ??
        adviceMap[scamType.name]?['vi'] ??
        scamType.advice;
    return synthesize(advice, locale);
  }

  // ── Cache helpers ─────────────────────────────────────────────────────

  Future<Directory> _ensureCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tmp = await getTemporaryDirectory();
    _cacheDir = Directory('${tmp.path}/elevenlabs_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  String _cacheKey(String text, String locale) {
    // Simple hash from text + locale
    final hash = text.hashCode.toUnsigned(32).toRadixString(16);
    return '${locale}_$hash.mp3';
  }

  Future<Uint8List?> _readCache(String text, String locale) async {
    try {
      final dir = await _ensureCacheDir();
      final file = File('${dir.path}/${_cacheKey(text, locale)}');
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();

      // Validate: minimum size + MP3 header check
      if (bytes.length < _minCacheFileSize) {
        await file.delete();
        return null;
      }
      if (!_isValidMp3(bytes)) {
        await file.delete();
        return null;
      }

      return bytes;
    } catch (e) {
      debugPrint('[ElevenLabsTTS] Cache read error: $e');
      return null;
    }
  }

  Future<void> _writeCache(String text, String locale, Uint8List bytes) async {
    try {
      final dir = await _ensureCacheDir();
      final file = File('${dir.path}/${_cacheKey(text, locale)}');
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('[ElevenLabsTTS] Cache write error: $e');
    }
  }

  /// Check for MP3 frame sync (0xFF 0xFB/0xF3/0xF2) or ID3 tag header.
  bool _isValidMp3(Uint8List bytes) {
    if (bytes.length < 3) return false;
    // ID3 tag
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    // MP3 frame sync
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
    return false;
  }

  /// Clear all cached audio files.
  Future<void> clearCache() async {
    try {
      final dir = await _ensureCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _cacheDir = null;
      }
    } catch (e) {
      debugPrint('[ElevenLabsTTS] Cache clear error: $e');
    }
  }
}
