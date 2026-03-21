import 'package:flutter/services.dart';

class PlatformChannel {
  static const _methods = MethodChannel('com.checkvar/methods');

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
}
