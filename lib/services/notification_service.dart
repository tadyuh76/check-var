import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/check_result.dart';
import '../models/call_result.dart';

typedef NotificationTapCallback = void Function(String? payload);

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static NotificationTapCallback? _onNotificationTap;

  static Future<void> init({NotificationTapCallback? onNotificationTap}) async {
    if (_initialized) return;
    _onNotificationTap = onNotificationTap;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    _initialized = true;
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    _onNotificationTap?.call(response.payload);
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  static const _analyzingId = 999;

  static Future<void> showAnalyzing() async {
    try {
      await _plugin.show(
        _analyzingId,
        'CheckVar',
        'Dang phan tich noi dung...',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'checkvar_analyzing',
            'Trang thai phan tich',
            channelDescription: 'Trang thai phan tich',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true,
            autoCancel: false,
            showProgress: true,
            indeterminate: true,
          ),
        ),
      );
    } catch (e) {
      // Don't crash the analysis flow if notification fails
    }
  }

  static Future<void> cancelAnalyzing() async {
    await _plugin.cancel(_analyzingId);
  }

  static Future<void> showResult(CheckResult result) async {
    await cancelAnalyzing();
    final verdictText = switch (result.verdict) {
      Verdict.real => 'Tin that',
      Verdict.fake => 'Tin gia',
      Verdict.uncertain => 'Chua ro',
    };

    final confidence = (result.confidence * 100).round();

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'CheckVar: $verdictText ($confidence%)',
      result.summary,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'checkvar_results',
          'Ket qua kiem tra',
          channelDescription: 'Thong bao ket qua kiem tra tin tuc',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  // --- Scam call notification support ---

  static String buildScamCallTitle(CallResult result) {
    final verdictVn = switch (result.threatLevel) {
      ThreatLevel.safe => 'An toàn',
      ThreatLevel.suspicious => 'Đáng ngờ',
      ThreatLevel.scam => 'Lừa đảo',
    };
    final confidence = (result.confidence * 100).round();
    return 'CheckVar: $verdictVn ($confidence%)';
  }

  static String? buildScamCallBody(CallResult result) {
    if (result.patterns.isNotEmpty) {
      return result.patterns.first;
    }
    return result.summary;
  }

  static Future<void> showScamCallResult(
    CallResult result, {
    required int historyEntryId,
  }) async {
    final title = buildScamCallTitle(result);
    final body = buildScamCallBody(result);

    await _plugin.show(
      historyEntryId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'checkvar_scam_call',
          'Ket qua cuoc goi',
          channelDescription: 'Thong bao ket qua phan tich cuoc goi',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: historyEntryId.toString(),
    );
  }
}
