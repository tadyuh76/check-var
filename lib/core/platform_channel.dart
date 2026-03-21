import 'package:flutter/services.dart';

class PlatformChannel {
  static const _methodChannel = MethodChannel('com.checkvar/service');
  static const _eventChannel = EventChannel('com.checkvar/events');

  /// Shared broadcast stream — only one EventChannel listener at a time.
  static Stream<Map<String, dynamic>>? _sharedEventStream;

  /// Start the foreground shake detection service
  static Future<void> startShakeService() async {
    await _methodChannel.invokeMethod('startShakeService');
  }

  /// Stop the foreground shake detection service
  static Future<void> stopShakeService() async {
    await _methodChannel.invokeMethod('stopShakeService');
  }

  /// Set current mode: "news" or "call"
  static Future<void> setMode(String mode) async {
    await _methodChannel.invokeMethod('setMode', {'mode': mode});
  }

  /// Enable or disable news shake detection without affecting call detection.
  static Future<void> setNewsDetectionEnabled(bool enabled) async {
    await _methodChannel.invokeMethod('setNewsDetectionEnabled', {
      'enabled': enabled,
    });
  }

  /// Enable or disable call shake detection without affecting news detection.
  static Future<void> setCallDetectionEnabled(bool enabled) async {
    await _methodChannel.invokeMethod('setCallDetectionEnabled', {
      'enabled': enabled,
    });
  }

  /// Set up MediaProjection permission (call once when starting service)
  static Future<bool> setupProjection() async {
    final result = await _methodChannel.invokeMethod<bool>('setupProjection');
    return result ?? false;
  }

  /// Get screenshot bytes that were captured by native side on shake
  static Future<Uint8List?> getPendingScreenshot() async {
    final result = await _methodChannel.invokeMethod<Uint8List>('getPendingScreenshot');
    return result;
  }

  /// Single shared stream of events from native service.
  /// Safe to listen from multiple places.
  static Stream<Map<String, dynamic>> get shakeEvents {
    _sharedEventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map))
        .asBroadcastStream();
    return _sharedEventStream!;
  }

  // ── Phone State Permission ──────────────────────────────────────────────

  /// Request READ_PHONE_STATE runtime permission.
  /// Returns true if granted.
  static Future<bool> requestPhoneStatePermission() async {
    final result = await _methodChannel
        .invokeMethod<bool>('requestPhoneStatePermission');
    return result ?? false;
  }

  // ── Live Caption Capture ────────────────────────────────────────────────

  /// Start forwarding Live Caption text from AccessibilityService.
  static Future<void> startCaptionCapture() async {
    await _methodChannel.invokeMethod('startCaptionCapture');
  }

  /// Stop forwarding Live Caption text.
  static Future<void> stopCaptionCapture() async {
    await _methodChannel.invokeMethod('stopCaptionCapture');
  }

  /// Check if Live Caption is enabled in device settings.
  /// Best-effort check via Settings.Secure (undocumented key).
  static Future<bool> checkLiveCaptionEnabled() async {
    final result = await _methodChannel.invokeMethod<bool>('checkLiveCaptionEnabled');
    return result ?? false;
  }

  /// Open the device's Live Caption settings screen.
  static Future<void> openLiveCaptionSettings() async {
    await _methodChannel.invokeMethod('openLiveCaptionSettings');
  }

  // ── Call Monitor ────────────────────────────────────────────────────────

  /// Start the cellular call monitor foreground service.
  static Future<void> startCallMonitorService() async {
    await _methodChannel.invokeMethod('startCallMonitorService');
  }

  /// Stop the cellular call monitor service.
  static Future<void> stopCallMonitorService() async {
    await _methodChannel.invokeMethod('stopCallMonitorService');
  }

  // ── Overlay ─────────────────────────────────────────────────────────────

  /// Request the SYSTEM_ALERT_WINDOW overlay permission.
  static Future<bool> requestOverlayPermission() async {
    final result =
        await _methodChannel.invokeMethod<bool>('requestOverlayPermission');
    return result ?? false;
  }

  /// Show the overlay bubble (indicates scam detector is active).
  static Future<void> showOverlayBubble() async {
    await _methodChannel.invokeMethod('showOverlayBubble');
  }

  /// Hide the overlay bubble.
  static Future<void> hideOverlayBubble() async {
    await _methodChannel.invokeMethod('hideOverlayBubble');
  }

  /// Update the overlay bubble status (verdict color + label + confidence).
  static Future<void> updateOverlayStatus({
    required String threatLevel,
    required String sessionStatus,
    int confidence = -1,
  }) async {
    await _methodChannel.invokeMethod('updateOverlayStatus', {
      'threatLevel': threatLevel,
      'sessionStatus': sessionStatus,
      'confidence': confidence,
    });
  }

  // ── TTS ─────────────────────────────────────────────────────────────────

  /// Play [text] aloud using the device's TTS engine.
  static Future<void> speakText(
    String text, {
    bool preferSpeaker = false,
  }) async {
    await _methodChannel.invokeMethod('speakText', {
      'text': text,
      'preferSpeaker': preferSpeaker,
    });
  }

  /// Stop any in-progress TTS playback.
  static Future<void> stopSpeaking() async {
    await _methodChannel.invokeMethod('stopSpeaking');
  }
}
