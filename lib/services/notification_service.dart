import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
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
        'notification.analyzing'.tr(),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'checkvar_analyzing',
            'notification.channel_status'.tr(),
            channelDescription: 'notification.channel_status'.tr(),
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
      Verdict.real => 'notification.real'.tr(),
      Verdict.fake => 'notification.fake'.tr(),
      Verdict.uncertain => 'notification.uncertain'.tr(),
    };

    final confidence = (result.confidence * 100).round();

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'CheckVar: $verdictText ($confidence%)',
      result.summary,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'checkvar_results',
          'notification.channel_results'.tr(),
          channelDescription: 'notification.channel_desc'.tr(),
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
