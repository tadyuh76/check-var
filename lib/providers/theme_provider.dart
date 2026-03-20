import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _boxName = 'settings';
  static const String _key = 'isDarkMode';

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final box = await Hive.openBox(_boxName);
    _isDarkMode = box.get(_key, defaultValue: false);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final box = await Hive.openBox(_boxName);
    await box.put(_key, _isDarkMode);
    notifyListeners();
  }
}
