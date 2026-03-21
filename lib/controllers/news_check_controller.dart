import 'package:flutter/foundation.dart';
import '../api/fact_check_api.dart';
import '../models/check_result.dart';
import '../models/history_entry.dart';
import '../services/history_service.dart';
import '../services/notification_service.dart';

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
      await NotificationService.showAnalyzing();

      // Step 1: Clean OCR text
      _setStatus(NewsCheckStatus.extracting);
      final cleanedText = cleanOcrText(screenText);

      // Step 2: Extract search query via LLM
      final query = await extractSearchQuery(cleanedText);

      // Step 3: Web search via Serper
      _setStatus(NewsCheckStatus.searching);
      final sources = await webSearch(query);

      // Step 4: LLM classification
      _setStatus(NewsCheckStatus.classifying);
      final result = await classifyNews(cleanedText, sources);

      _result = result;
      _setStatus(NewsCheckStatus.done);

      // Save to history
      final entry = HistoryEntry.fromCheckResult(result);
      await HistoryService.instance.save(entry);

      // Show notification
      await NotificationService.showResult(result);
    } catch (e) {
      await NotificationService.cancelAnalyzing();
      _errorMessage = e.toString();
      _setStatus(NewsCheckStatus.error);
    }
  }

  void reset() {
    _status = NewsCheckStatus.idle;
    _result = null;
    _errorMessage = '';
    notifyListeners();
  }
}
