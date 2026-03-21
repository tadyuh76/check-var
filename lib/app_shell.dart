import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'controllers/news_check_controller.dart';
import 'providers/home_state_provider.dart';
import 'services/platform_channel.dart';
import 'services/shake_service.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 1; // Default to Home (middle tab)
  StreamSubscription<String>? _shakeSub;
  bool _isProcessing = false;

  final _screens = const [
    HistoryScreen(),
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    ShakeService.instance.startListening();
    _shakeSub = ShakeService.instance.onShake.listen(_handleShake);
  }

  @override
  void dispose() {
    _shakeSub?.cancel();
    super.dispose();
  }

  Future<void> _handleShake(String mode) async {
    if (_isProcessing) return;

    final controller = NewsCheckController.instance;
    if (controller.isProcessing) return;

    final homeState = context.read<HomeStateProvider>();
    if (!homeState.newsCheckEnabled) return;

    _isProcessing = true;

    try {
      HapticFeedback.heavyImpact();

      try {
        await PlatformChannel.showGlowOverlay();
      } catch (_) {}

      // Poll for OCR result — screenshot + ML Kit can take 1-5 seconds
      String? screenText;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        screenText = await PlatformChannel.getPendingText();
        if (screenText != null && screenText.isNotEmpty) break;
      }

      debugPrint('CheckVar: got screenText length=${screenText?.length ?? 0}');

      if (screenText != null && screenText.isNotEmpty) {
        await controller.runCheckWithText(screenText);
      } else {
        debugPrint('CheckVar: no text from OCR after 5s');
      }
    } catch (e) {
      debugPrint('Error handling shake: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: 'nav.history'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: 'nav.home'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: 'nav.settings'.tr(),
          ),
        ],
      ),
    );
  }
}
