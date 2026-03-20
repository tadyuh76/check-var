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
  /// Safe to listen from multiple places (ShakeService + PlatformSpeakerTestGateway).
  static Stream<Map<String, dynamic>> get shakeEvents {
    _sharedEventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map))
        .asBroadcastStream();
    return _sharedEventStream!;
  }

  // ── Speaker Test Methods ────────────────────────────────────────────────

  /// Request READ_PHONE_STATE and RECORD_AUDIO runtime permissions.
  /// Returns true if all were granted.
  static Future<bool> requestSpeakerTestPermissions() async {
    final result = await _methodChannel
        .invokeMethod<bool>('requestSpeakerTestPermissions');
    return result ?? false;
  }

  /// Get readiness state for the speaker transcription test.
  static Future<Map<String, dynamic>> getSpeakerTestReadiness() async {
    final result = await _methodChannel
        .invokeMapMethod<String, dynamic>('getSpeakerTestReadiness');
    return result ?? {};
  }

  /// Start on-device speech recognition.
  static Future<void> startSpeakerRecognition({
    String language = 'vi-VN',
  }) async {
    await _methodChannel.invokeMethod('startSpeakerRecognition', {
      'language': language,
    });
  }

  /// Stop on-device speech recognition.
  static Future<void> stopSpeakerRecognition() async {
    await _methodChannel.invokeMethod('stopSpeakerRecognition');
  }

  /// Start the cellular call monitor foreground service.
  static Future<void> startCallMonitorService() async {
    await _methodChannel.invokeMethod('startCallMonitorService');
  }

  /// Stop the cellular call monitor service.
  static Future<void> stopCallMonitorService() async {
    await _methodChannel.invokeMethod('stopCallMonitorService');
  }

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

  /// Update the transcript text displayed in the overlay.
  static Future<void> updateOverlayTranscript(String text) async {
    await _methodChannel
        .invokeMethod('updateOverlayTranscript', {'text': text});
  }

  /// Show the compact status bubble for real call detection.
  static Future<void> showCallStatusBubble() async {
    await _methodChannel.invokeMethod('showCallStatusBubble');
  }

  /// Hide the compact status bubble for real call detection.
  static Future<void> hideCallStatusBubble() async {
    await _methodChannel.invokeMethod('hideCallStatusBubble');
  }

  /// Update the compact overlay bubble status.
  static Future<void> updateOverlayStatus({
    required String threatLevel,
    required String sessionStatus,
  }) async {
    await _methodChannel.invokeMethod('updateOverlayStatus', {
      'threatLevel': threatLevel,
      'sessionStatus': sessionStatus,
    });
  }

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
