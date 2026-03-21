import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'controllers/news_check_controller.dart';
import 'features/scam_call/scam_call_screen.dart';
import 'providers/home_state_provider.dart';
import 'services/platform_channel.dart';
import 'services/shake_service.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/news_check_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 1; // Default to Home (middle tab)
  StreamSubscription<String>? _shakeSub;
  bool _isProcessing = false;
  bool _hasNavigatedToResult = false;

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

    if (mode == 'call') {
      await _handleCallShake();
      return;
    }

    final controller = NewsCheckController.instance;
    if (controller.isProcessing) return;

    final homeState = context.read<HomeStateProvider>();
    if (!homeState.newsCheckEnabled) return;

    _isProcessing = true;
    _hasNavigatedToResult = false;

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
        if (mounted && !_hasNavigatedToResult) {
          _hasNavigatedToResult = true;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewsCheckScreen()),
          );
        }

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

  Future<void> _handleCallShake() async {
    final homeState = context.read<HomeStateProvider>();
    if (!homeState.scamCallEnabled) return;

    _isProcessing = true;
    try {
      HapticFeedback.heavyImpact();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ScamCallScreen(
              modeLabel: 'Live Caption',
            ),
          ),
        );
      }
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Lịch sử',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
