import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'controllers/news_check_controller.dart';
import 'core/platform_channel.dart' as core_channel;
import 'features/scam_call/scam_call_screen.dart';
import 'features/scam_call/scam_call_session_manager.dart';
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
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  late final ScamCallSessionManager _sessionManager;
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
    _sessionManager = ScamCallSessionManager();
    ShakeService.instance.startListening();
    _shakeSub = ShakeService.instance.onShake.listen(_handleShake);
    _eventSub = core_channel.PlatformChannel.shakeEvents.listen(_handlePlatformEvent);
  }

  @override
  void dispose() {
    _shakeSub?.cancel();
    _eventSub?.cancel();
    _sessionManager.dispose();
    super.dispose();
  }

  void _handlePlatformEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'call_state':
        final isActive = event['isActive'] as bool? ?? false;
        debugPrint('AppShell: call_state isActive=$isActive');
        if (!isActive) {
          _onCallEnded();
        }
      case 'overlay_tap':
        debugPrint('AppShell: overlay_tap received');
        _handleOverlayTap();
      default:
        break; // shake, caption_text, tts_done handled elsewhere
    }
  }

  Future<void> _handleShake(String mode) async {
    debugPrint('AppShell._handleShake: mode=$mode, isProcessing=$_isProcessing');
    if (_isProcessing) return;

    if (mode == 'call') {
      debugPrint('AppShell: routing to _handleCallShake');
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
    if (_sessionManager.hasActiveSession) return; // already running

    HapticFeedback.heavyImpact();
    debugPrint('AppShell: starting background scam call session');
    await _sessionManager.startLiveCallSession();
  }

  Future<void> _onCallEnded() async {
    // Stop caption capture immediately for optimization,
    // regardless of who owns the controller.
    try {
      await core_channel.PlatformChannel.stopCaptionCapture();
    } catch (_) {}

    // If the session manager still owns the controller, full cleanup.
    if (_sessionManager.hasActiveSession) {
      await _sessionManager.stopSession();
    }
  }

  void _handleOverlayTap() {
    final controller = _sessionManager.detachController();
    if (controller == null) return;
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScamCallScreen(
          controller: controller,
          modeLabel: 'Live Caption',
          disposeController: true,
          manageSessionLifecycle: true,
        ),
      ),
    );
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
