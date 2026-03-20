import 'dart:async';
import 'platform_channel.dart';

class ShakeService {
  static ShakeService? _instance;
  static ShakeService get instance => _instance ??= ShakeService._();
  ShakeService._();

  StreamSubscription? _subscription;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get onShake => _controller.stream;

  void startListening() {
    _subscription?.cancel();
    _subscription = PlatformChannel.eventStream.listen((event) {
      if (event is Map && event['type'] == 'shake') {
        final mode = event['mode'] as String? ?? 'news';
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
