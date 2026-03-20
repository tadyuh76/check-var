import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform_channel.dart';
import '../../core/shake_service.dart';
import '../../widgets/scam_detail_sheet.dart';
import '../scam_call/live/simulated_call_scenario.dart';
import '../scam_call/scam_call_screen.dart';
import '../scam_call/scam_call_session_manager.dart';
import '../scam_call/speaker_test/platform_speaker_test_gateway.dart';
import '../scam_call/speaker_test/speaker_transcript_controller.dart';
import '../scam_call/speaker_test/speaker_transcript_test_screen.dart';
import 'home_controller.dart';

typedef SimulationScreenBuilder =
    Widget Function(BuildContext context, SimulatedCallScenario scenario);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.shakeService,
    this.callModeScreenBuilder,
    this.simulationScreenBuilder,
    this.sessionManager,
  });

  final ShakeService? shakeService;
  final WidgetBuilder? callModeScreenBuilder;
  final SimulationScreenBuilder? simulationScreenBuilder;
  final ScamCallSessionManager? sessionManager;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ShakeService _shakeService;

  @override
  void initState() {
    super.initState();
    _shakeService = widget.shakeService ?? ShakeService();
    _shakeService.onShake = _handleShake;
    _shakeService.onCallStateChanged = _handleCallState;
    _shakeService.onOverlayTap = _handleOverlayTap;
    _shakeService.startListening();
  }

  @override
  void dispose() {
    _shakeService.dispose();
    super.dispose();
  }

  void _handleShake(String mode) async {
    HapticFeedback.heavyImpact();
    if (mode == 'news') {
      // News check feature not available in this build.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('News check is not available in this build.'),
        ),
      );
    } else if (mode == 'call') {
      final controller = context.read<HomeController>();
      if (!controller.callActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Start or answer a call before shaking to detect scams.',
            ),
          ),
        );
        return;
      }
      await _sessionManager.startLiveCallSession();
    }
  }

  void _handleCallState(bool isActive) {
    if (!mounted) return;
    context.read<HomeController>().setCallActive(isActive);
    if (!isActive && _sessionManager.sessionKind == ScamCallSessionKind.liveCall) {
      unawaited(_sessionManager.stopSession());
    }
  }

  void _handleOverlayTap() {
    if (!_sessionManager.hasActiveSession) {
      return;
    }
    _showQuickStats();
  }

  void _showQuickStats() {
    final controller = _sessionManager.controller;
    if (controller == null) return;

    ScamDetailSheet.show(
      context,
      threatLevel: controller.threatLevel,
      confidence: controller.confidence,
      summary: controller.summary,
      advice: controller.advice,
      patterns: controller.patterns,
    );
  }

  ScamCallSessionManager get _sessionManager =>
      widget.sessionManager ?? context.read<ScamCallSessionManager>();

  void _openDebugScreen() {
    final controller = _sessionManager.controller;
    if (controller == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: widget.callModeScreenBuilder ??
            (_) => ScamCallScreen(
              controller: controller,
              modeLabel: _sessionManager.modeLabel,
              manageSessionLifecycle: false,
            ),
      ),
    );
  }

  Future<void> _launchSimulationSheet() async {
    final scenario = await showModalBottomSheet<SimulatedCallScenario>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CallSimulationSheet(),
    );
    if (!mounted || scenario == null) {
      return;
    }

    await _sessionManager.startSimulationSession(scenario);
    if (!mounted) {
      return;
    }

    _launchSimulatedCallScreen(scenario);
  }

  void _launchSimulatedCallScreen(SimulatedCallScenario scenario) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (buildContext) {
          if (widget.simulationScreenBuilder != null) {
            return widget.simulationScreenBuilder!(buildContext, scenario);
          }

          return ScamCallScreen(
            controller: _sessionManager.controller,
            modeLabel: _sessionManager.modeLabel,
            manageSessionLifecycle: false,
          );
        },
      ),
    );
  }

  void _launchSpeakerTest() {
    final gateway = PlatformSpeakerTestGateway();
    final controller = SpeakerTranscriptController(
      gateway: gateway,
      expectedPhrases: kDefaultTestPhrases,
      onOverlayShow: () => PlatformChannel.showOverlayBubble(),
      onOverlayHide: () => PlatformChannel.hideOverlayBubble(),
      onOverlayTranscriptUpdate: (text) =>
          PlatformChannel.updateOverlayTranscript(text),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpeakerTranscriptTestScreen(controller: controller),
      ),
    );
  }

  Future<void> _toggleService() async {
    final controller = context.read<HomeController>();
    final mode = controller.mode;
    if (controller.currentModeServiceRunning) {
      if (mode == CheckMode.news) {
        await PlatformChannel.setNewsDetectionEnabled(false);
      } else {
        await PlatformChannel.setCallDetectionEnabled(false);
        await _sessionManager.stopSession();
      }
      controller.setModeServiceRunning(mode, false);
      return;
    }

    if (mode == CheckMode.news) {
      try {
        await PlatformChannel.setupProjection();
      } catch (_) {
        // User denied permission; news mode can still keep the service alive.
      }
      await PlatformChannel.setNewsDetectionEnabled(true);
    } else {
      await PlatformChannel.requestSpeakerTestPermissions();
      await PlatformChannel.requestOverlayPermission();
      await PlatformChannel.setCallDetectionEnabled(true);
    }

    controller.setModeServiceRunning(mode, true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              'CheckVar',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Shake to verify',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Icon(
              Icons.vibration,
              size: 120,
              color: controller.currentModeServiceRunning
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              controller.currentModeServiceRunning
                  ? 'Listening for shake...'
                  : 'Service inactive',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: controller.currentModeServiceRunning
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            if (controller.mode == CheckMode.call &&
                controller.callServiceRunning &&
                controller.callActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_in_talk,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Call active - shake to start scam detection',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SegmentedButton<CheckMode>(
                segments: const [
                  ButtonSegment(
                    value: CheckMode.news,
                    label: Text('News'),
                    icon: Icon(Icons.article_outlined),
                  ),
                  ButtonSegment(
                    value: CheckMode.call,
                    label: Text('Call'),
                    icon: Icon(Icons.phone_outlined),
                  ),
                ],
                selected: {controller.mode},
                onSelectionChanged: (selected) {
                  controller.setMode(selected.first);
                },
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('home_toggle_service_button'),
                      onPressed: _toggleService,
                  icon: Icon(
                    controller.currentModeServiceRunning
                        ? Icons.stop
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    controller.currentModeServiceRunning
                        ? 'Stop Service'
                        : 'Start Service',
                  ),
                ),
              ),
            ),
            if (controller.mode == CheckMode.call) ...[
              const SizedBox(height: 12),
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('home_simulate_call_button'),
                      onPressed: _launchSimulationSheet,
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Simulate Call'),
                    ),
                  ),
                ),
              if (kDebugMode) const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('home_speaker_test_button'),
                    onPressed: _launchSpeakerTest,
                    icon: const Icon(Icons.mic_external_on),
                    label: const Text('Diagnostics Speaker Test'),
                  ),
                ),
              ),
            ],
            SizedBox(
              key: const Key('home_bottom_actions_spacer'),
              height: 24 + bottomInset,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallSimulationSheet extends StatefulWidget {
  const _CallSimulationSheet();

  @override
  State<_CallSimulationSheet> createState() => _CallSimulationSheetState();
}

class _CallSimulationSheetState extends State<_CallSimulationSheet> {
  final TextEditingController _customTranscriptController =
      TextEditingController();
  SimulatedCallScenario _selectedScenario = SimulatedCallScenario.safeCall;

  @override
  void dispose() {
    _customTranscriptController.dispose();
    super.dispose();
  }

  void _startSimulation() {
    final customTranscript = _customTranscriptController.text.trim();
    final scenario = customTranscript.isNotEmpty
        ? SimulatedCallScenario.customScript(customTranscript)
        : _selectedScenario;
    Navigator.of(context).pop(scenario);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Call Simulator',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SimulatedCallScenario.presets.map((scenario) {
                return ChoiceChip(
                  label: Text(scenario.title),
                  selected: identical(scenario, _selectedScenario),
                  onSelected: (_) {
                    setState(() {
                      _selectedScenario = scenario;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customTranscriptController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Custom script',
                hintText: 'Paste the words you want TTS to speak',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _startSimulation,
                child: const Text('Start Simulation'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
