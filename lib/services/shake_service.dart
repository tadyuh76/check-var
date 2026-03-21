import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/platform_channel.dart' as core_channel;

class ShakeService {
  static ShakeService? _instance;
  static ShakeService get instance => _instance ??= ShakeService._();
  ShakeService._();

  StreamSubscription<Map<String, dynamic>>? _subscription;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get onShake => _controller.stream;

  void startListening() {
    _subscription?.cancel();
    debugPrint('ShakeService: startListening, subscribing to shakeEvents');
    _subscription = core_channel.PlatformChannel.shakeEvents.listen((event) {
      debugPrint('ShakeService: received event type=${event['type']}');
      if (event['type'] == 'shake') {
        final mode = event['mode'] as String? ?? 'news';
        debugPrint('ShakeService: shake detected, mode=$mode');
        _controller.add(mode);
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopListening();
    _controller.close();
  }
}
