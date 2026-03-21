import 'package:flutter/services.dart';

class PlatformChannel {
  static const _methods = MethodChannel('com.checkvar/methods');
  static const _events = EventChannel('com.checkvar/events');

  static Future<void> startShakeService() async {
    await _methods.invokeMethod('startShakeService');
  }

  static Future<void> stopShakeService() async {
    await _methods.invokeMethod('stopShakeService');
  }

  static Future<void> setMode(String mode) async {
    await _methods.invokeMethod('setMode', {'mode': mode});
  }

  static Future<String?> getPendingText() async {
    return await _methods.invokeMethod<String>('getPendingText');
  }

  static Future<bool> checkAccessibilityPermission() async {
    return await _methods.invokeMethod<bool>('checkAccessibilityPermission') ?? false;
  }

  static Future<void> openAccessibilitySettings() async {
    await _methods.invokeMethod('openAccessibilitySettings');
  }

  static Future<void> showGlowOverlay() async {
    await _methods.invokeMethod('showGlowOverlay');
  }

  static Future<void> hideGlowOverlay() async {
    await _methods.invokeMethod('hideGlowOverlay');
  }

  static Future<bool> checkOverlayPermission() async {
    return await _methods.invokeMethod<bool>('checkOverlayPermission') ?? false;
  }

  static Future<void> requestOverlayPermission() async {
    await _methods.invokeMethod('requestOverlayPermission');
  }

  // Analysis overlay (system overlay on top of other apps)
  static Future<void> showAnalysisOverlay({String? initialStatus}) async {
    await _methods.invokeMethod('showAnalysisOverlay', {
      'initialStatus': initialStatus ?? '',
    });
  }

  static Future<void> hideAnalysisOverlay() async {
    await _methods.invokeMethod('hideAnalysisOverlay');
  }

  static Future<void> updateAnalysisStatus(String status) async {
    await _methods.invokeMethod('updateAnalysisStatus', {'status': status});
  }

  static Future<void> showAnalysisResult({
    required String verdict,
    required String verdictLabel,
    required String confidence,
    required String summary,
    required String closeLabel,
  }) async {
    await _methods.invokeMethod('showAnalysisResult', {
      'verdict': verdict,
      'verdictLabel': verdictLabel,
      'confidence': confidence,
      'summary': summary,
      'closeLabel': closeLabel,
    });
  }

  static Future<void> showAnalysisError(
    String message, {
    String errorLabel = 'Error',
    String closeLabel = 'Close',
  }) async {
    await _methods.invokeMethod('showAnalysisError', {
      'message': message,
      'errorLabel': errorLabel,
      'closeLabel': closeLabel,
    });
  }

  static Stream<dynamic> get eventStream => _events.receiveBroadcastStream();
}
