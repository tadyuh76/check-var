import 'package:flutter/foundation.dart';
import '../api/fact_check_api.dart';
import '../models/check_result.dart';
import '../models/history_entry.dart';
import '../services/history_service.dart';
import '../services/platform_channel.dart';

String _confidenceLabel(double confidence) {
  if (confidence >= 0.85) return 'Rất chắc chắn';
  if (confidence >= 0.65) return 'Khá chắc chắn';
  if (confidence >= 0.45) return 'Chưa rõ ràng';
  if (confidence >= 0.25) return 'Không chắc chắn';
  return 'Rất không chắc chắn';
}

enum NewsCheckStatus { idle, extracting, searching, classifying, done, error }

class NewsCheckController extends ChangeNotifier {
  static final NewsCheckController instance = NewsCheckController._();
  NewsCheckController._();

  NewsCheckStatus _status = NewsCheckStatus.idle;
  CheckResult? _result;
  String _errorMessage = '';

  NewsCheckStatus get status => _status;
  CheckResult? get result => _result;
  String get errorMessage => _errorMessage;

  bool get isProcessing =>
      _status == NewsCheckStatus.extracting ||
      _status == NewsCheckStatus.searching ||
      _status == NewsCheckStatus.classifying;

  void _setStatus(NewsCheckStatus status) {
    _status = status;
    notifyListeners();
  }

  Future<void> runCheckWithText(String screenText) async {
    if (isProcessing) return;

    _result = null;
    _errorMessage = '';

    try {
      // Show analysis overlay first, then glow ON TOP
      await PlatformChannel.showAnalysisOverlay();
      try { await PlatformChannel.showGlowOverlay(); } catch (_) {}

      // Step 1: Clean OCR text
      _setStatus(NewsCheckStatus.extracting);
      await PlatformChannel.updateAnalysisStatus('Đang trích xuất nội dung...');
      final cleanedText = cleanOcrText(screenText);

      // Step 2: Extract search query via LLM
      await PlatformChannel.updateAnalysisStatus('Đang tạo câu hỏi tìm kiếm...');
      final query = await extractSearchQuery(cleanedText);

      // Step 3: Web search via Serper
      _setStatus(NewsCheckStatus.searching);
      await PlatformChannel.updateAnalysisStatus('Đang tìm kiếm nguồn...');
      final sources = await webSearch(query);

      // Step 4: LLM classification
      _setStatus(NewsCheckStatus.classifying);
      await PlatformChannel.updateAnalysisStatus('Đang phân tích độ tin cậy...');
      final result = await classifyNews(cleanedText, sources);

      _result = result;
      _setStatus(NewsCheckStatus.done);

      // Show result on native overlay
      await PlatformChannel.showAnalysisResult(
        verdict: result.verdict.name,
        confidence: _confidenceLabel(result.confidence),
        summary: result.summary,
      );

      // Save to history
      final entry = HistoryEntry.fromCheckResult(result);
      await HistoryService.instance.save(entry);

    } catch (e) {
      _errorMessage = e.toString();
      _setStatus(NewsCheckStatus.error);
      await PlatformChannel.showAnalysisError(_errorMessage);
    }
  }

  void reset() {
    _status = NewsCheckStatus.idle;
    _result = null;
    _errorMessage = '';
    notifyListeners();
  }
}
