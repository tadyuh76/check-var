import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/check_result.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
    _initialized = true;
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
}
