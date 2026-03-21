import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import '../api/fact_check_api.dart';
import '../models/check_result.dart';
import '../models/history_entry.dart';
import '../services/history_service.dart';
import '../services/platform_channel.dart';

String _confidenceLabel(double confidence) {
  if (confidence >= 0.85) return 'confidence.very_sure'.tr();
  if (confidence >= 0.65) return 'confidence.quite_sure'.tr();
  if (confidence >= 0.45) return 'confidence.unclear'.tr();
  if (confidence >= 0.25) return 'confidence.not_sure'.tr();
  return 'confidence.very_unsure'.tr();
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
      await PlatformChannel.showAnalysisOverlay(
        initialStatus: 'news_check.preparing'.tr(),
      );

      // Step 1: Clean OCR text (on-device)
      _setStatus(NewsCheckStatus.extracting);
      await PlatformChannel.updateAnalysisStatus('news_check.extracting'.tr());
      final cleanedText = cleanOcrText(screenText);

      // Step 2: Send to AWS for fact-checking (query extraction + search + classify)
      _setStatus(NewsCheckStatus.searching);
      await PlatformChannel.updateAnalysisStatus('news_check.analyzing'.tr());
      final result = await factCheck(cleanedText);

      _result = result;
      _setStatus(NewsCheckStatus.done);

      // Show result on native overlay
      final verdictLabel = switch (result.verdict) {
        Verdict.real => 'verdict.real'.tr(),
        Verdict.fake => 'verdict.fake'.tr(),
        Verdict.uncertain => 'verdict.uncertain_full'.tr(),
      };
      await PlatformChannel.showAnalysisResult(
        verdict: result.verdict.name,
        verdictLabel: verdictLabel,
        confidence: _confidenceLabel(result.confidence),
        summary: result.summary,
        detailLabel: 'news_check.view_detail'.tr(),
      );

      // Save to history
      final entry = HistoryEntry.fromCheckResult(result);
      await HistoryService.instance.save(entry);

    } catch (e) {
      _errorMessage = e.toString();
      _setStatus(NewsCheckStatus.error);
      await PlatformChannel.showAnalysisError(
        _errorMessage,
        errorLabel: 'news_check.error_occurred'.tr(),
        closeLabel: 'news_check.close'.tr(),
      );
    }
  }

  void reset() {
    _status = NewsCheckStatus.idle;
    _result = null;
    _errorMessage = '';
    notifyListeners();
  }
}
