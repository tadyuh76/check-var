import 'package:flutter/material.dart';

class HomeStateProvider extends ChangeNotifier {
  bool _newsCheckEnabled = false;
  bool _scamCallEnabled = false;

  bool get newsCheckEnabled => _newsCheckEnabled;
  bool get scamCallEnabled => _scamCallEnabled;

  void setNewsCheckEnabled(bool value) {
    _newsCheckEnabled = value;
    notifyListeners();
  }

  void setScamCallEnabled(bool value) {
    _scamCallEnabled = value;
    notifyListeners();
  }
}
