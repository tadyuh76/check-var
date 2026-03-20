import 'package:flutter/foundation.dart';

enum CheckMode { news, call }

class HomeController extends ChangeNotifier {
  CheckMode _mode = CheckMode.news;
  bool _newsServiceRunning = false;
  bool _callServiceRunning = false;
  bool _callActive = false;

  CheckMode get mode => _mode;
  bool get newsServiceRunning => _newsServiceRunning;
  bool get callServiceRunning => _callServiceRunning;
  bool get callActive => _callActive;
  bool get currentModeServiceRunning => switch (_mode) {
    CheckMode.news => _newsServiceRunning,
    CheckMode.call => _callServiceRunning,
  };

  void setMode(CheckMode mode) {
    _mode = mode;
    notifyListeners();
  }

  void setModeServiceRunning(CheckMode mode, bool running) {
    switch (mode) {
      case CheckMode.news:
        _newsServiceRunning = running;
      case CheckMode.call:
        _callServiceRunning = running;
    }
    notifyListeners();
  }

  void setCallActive(bool active) {
    _callActive = active;
    notifyListeners();
  }
}
