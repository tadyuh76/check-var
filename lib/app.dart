import 'package:flutter/material.dart';

import 'config/theme.dart';
import 'features/home/home_screen.dart';

class CheckVarApp extends StatelessWidget {
  const CheckVarApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheckVar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: home ?? const HomeScreen(),
    );
  }
}
