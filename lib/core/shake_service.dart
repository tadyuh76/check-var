import 'dart:async';
import 'platform_channel.dart';

typedef ShakeCallback = void Function(String mode);
typedef CallStateCallback = void Function(bool isActive);
typedef OverlayTapCallback = void Function();

class ShakeService {
  StreamSubscription? _subscription;
  ShakeCallback? onShake;
  CallStateCallback? onCallStateChanged;
  OverlayTapCallback? onOverlayTap;

  void startListening() {
    _subscription = PlatformChannel.shakeEvents.listen((event) {
      final type = event['type'] as String?;
      if (type == 'shake') {
        final mode = event['mode'] as String? ?? 'news';
        onShake?.call(mode);
      } else if (type == 'call_state') {
        final isActive = event['isActive'] as bool? ?? false;
        onCallStateChanged?.call(isActive);
      } else if (type == 'overlay_tap') {
        onOverlayTap?.call();
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopListening();
  }
}
