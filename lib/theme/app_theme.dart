import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF2196F3);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color danger = Color(0xFFF44336);

  static const newsCardOnGradient = LinearGradient(
    colors: [Color(0xFFE8D5F5), Color(0xFFF5E6D0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const callCardOnGradient = LinearGradient(
    colors: [Color(0xFFD5E8F5), Color(0xFFE8F5D5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color cardOffColor(Brightness brightness) =>
      brightness == Brightness.light
          ? const Color(0xFFF0F0F0)
          : const Color(0xFF2A2A2A);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: primary,
    scaffoldBackgroundColor: Colors.white,
    cardTheme: CardThemeData(
      color: const Color(0xFFF5F5F5),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFE3F2FD),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: primary,
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF121212),
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF121212),
    ),
  );
}
