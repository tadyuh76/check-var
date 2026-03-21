import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'controllers/news_check_controller.dart';
import 'core/platform_channel.dart' as core_channel;
import 'features/scam_call/scam_call_session_manager.dart';
import 'models/call_result.dart';
import 'models/history_entry.dart';
import 'providers/home_state_provider.dart';
import 'services/history_service.dart';
import 'services/notification_service.dart';
import 'services/platform_channel.dart';
import 'services/shake_service.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/history_detail_screen.dart';
import 'screens/settings_screen.dart';

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
  DateTime? _callStartTime;
  String? _callerNumber;

  final _screens = const [
    HistoryScreen(),
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _sessionManager = ScamCallSessionManager(
      onSessionFinalized: _onSessionFinalized,
    );
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

  Future<void> _onSessionFinalized(CallResult result) async {
    final entry = HistoryEntry.fromCallResult(result);
    await HistoryService.instance.save(entry);
    await NotificationService.showScamCallResult(
      result,
      historyEntryId: entry.id,
    );
  }

  void _handlePlatformEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'call_state':
        final isActive = event['isActive'] as bool? ?? false;
        final callerDisplayText = event['callerDisplayText'] as String?;
        debugPrint('AppShell: call_state isActive=$isActive, caller=$callerDisplayText');
        if (isActive) {
          _onCallStarted(callerDisplayText: callerDisplayText);
        } else {
          _onCallEnded();
        }
      case 'overlay_activate':
        debugPrint('AppShell: overlay_activate received');
        _handleOverlayActivate();
      case 'open_detail':
        final controller = NewsCheckController.instance;
        final result = controller.result;
        if (result != null) {
          final entry = HistoryEntry.fromCheckResult(result);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => HistoryDetailScreen(entry: entry)),
          );
        }
      default:
        break;
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

  Future<void> _handleCallShake() async {
    debugPrint(
      'AppShell._handleCallShake: '
      'scamCallEnabled=${context.read<HomeStateProvider>().scamCallEnabled}, '
      'hasActiveSession=${_sessionManager.hasActiveSession}',
    );
    HapticFeedback.heavyImpact();
    await _tryStartScamSession();
  }

  Future<void> _handleOverlayActivate() async {
    debugPrint(
      'AppShell._handleOverlayActivate: '
      'scamCallEnabled=${context.read<HomeStateProvider>().scamCallEnabled}, '
      'hasActiveSession=${_sessionManager.hasActiveSession}',
    );
    await _tryStartScamSession();
    // No haptic — tap already provides tactile feedback via the OS.
  }

  /// Shared guard: checks preconditions and starts a live-call session.
  Future<void> _tryStartScamSession() async {
    final homeState = context.read<HomeStateProvider>();
    if (!homeState.scamCallEnabled) return;
    if (_sessionManager.hasActiveSession) return;

    debugPrint('AppShell: starting background scam call session');
    _sessionManager.setCallTiming(
      callStartTime: _callStartTime ?? DateTime.now(),
      callerNumber: _callerNumber,
    );
    await _sessionManager.startLiveCallSession();
    debugPrint(
      'AppShell: session started, '
      'isListening=${_sessionManager.controller?.isListening}',
    );
  }

  Future<void> _onCallStarted({String? callerDisplayText}) async {
    final homeState = context.read<HomeStateProvider>();
    if (!homeState.scamCallEnabled) return;

    _callStartTime = DateTime.now();
    _callerNumber = callerDisplayText;

    debugPrint('AppShell: call started — showing overlay reminder');
    try {
      await core_channel.PlatformChannel.showOverlayBubble(
          locale: context.locale.languageCode);
    } catch (e) {
      debugPrint('AppShell: failed to show overlay bubble: $e');
    }
  }

  Future<void> _onCallEnded() async {
    try {
      await core_channel.PlatformChannel.stopCaptionCapture();
    } catch (_) {}

    if (_sessionManager.hasActiveSession) {
      _sessionManager.setCallTiming(
        callStartTime: _callStartTime ?? DateTime.now(),
        callerNumber: _callerNumber,
      );
      await _sessionManager.stopSession();
    } else {
      await _saveUnanalyzedCall();
      try {
        await core_channel.PlatformChannel.hideOverlayBubble();
      } catch (_) {}
    }

    _callStartTime = null;
    _callerNumber = null;
  }

  Future<void> _saveUnanalyzedCall() async {
    final now = DateTime.now();
    final result = CallResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0.0,
      transcript: '',
      patterns: [],
      duration: now.difference(_callStartTime ?? now),
      callerNumber: _callerNumber,
      callStartTime: _callStartTime ?? now,
      callEndTime: now,
      wasAnalyzed: false,
    );
    final entry = HistoryEntry.fromCallResult(result);
    await HistoryService.instance.save(entry);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScamCallSessionManager>.value(
      value: _sessionManager,
      child: Scaffold(
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
      ),
    );
  }
}
