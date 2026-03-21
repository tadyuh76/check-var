import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/platform_channel.dart' as core_channel;
import '../features/scam_call/live/simulated_call_scenario.dart';
import '../features/scam_call/scam_call_screen.dart' as feature_screen;
import '../features/scam_call/scam_call_session_manager.dart';
import '../theme/app_theme.dart';
import '../providers/home_state_provider.dart';
import '../services/platform_channel.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _waitingForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _waitingForPermission = false;
      _activateNewsCheck();
    }
  }

  Future<void> _activateNewsCheck() async {
    await NotificationService.requestPermission();

    final hasAccessibility =
        await PlatformChannel.checkAccessibilityPermission();
    if (!hasAccessibility) {
      if (!mounted) return;
      final shouldOpen = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Cần quyền Accessibility'),
          content: const Text(
            'CheckVar cần quyền Accessibility Service để chụp màn hình khi bạn lắc điện thoại.\n\n'
            'Vui lòng tìm và bật "CheckVar" trong cài đặt Accessibility.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mở cài đặt'),
            ),
          ],
        ),
      );
      if (shouldOpen == true) {
        _waitingForPermission = true;
        await PlatformChannel.openAccessibilitySettings();
      }
      return;
    }

    final hasOverlay = await PlatformChannel.checkOverlayPermission();
    if (!hasOverlay) {
      if (!mounted) return;
      final shouldOpen = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Cần quyền hiển thị trên ứng dụng khác'),
          content: const Text(
            'CheckVar cần quyền này để hiện hiệu ứng khi lắc điện thoại.\n\n'
            'Vui lòng bật "Hiển thị trên ứng dụng khác" cho CheckVar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mở cài đặt'),
            ),
          ],
        ),
      );
      if (shouldOpen == true) {
        _waitingForPermission = true;
        await PlatformChannel.requestOverlayPermission();
      }
      return;
    }

    // All permissions granted
    await PlatformChannel.startShakeService();
    await PlatformChannel.setMode('news');
    await core_channel.PlatformChannel.setNewsDetectionEnabled(true);

    if (!mounted) return;
    context.read<HomeStateProvider>().setNewsCheckEnabled(true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lắc điện thoại 3 lần để kiểm tra'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _deactivateNewsCheck() async {
    await core_channel.PlatformChannel.setNewsDetectionEnabled(false);
    await PlatformChannel.stopShakeService();
    if (!mounted) return;
    context.read<HomeStateProvider>().setNewsCheckEnabled(false);
  }

  void _toggleNewsCheck(bool isEnabled) {
    if (isEnabled) {
      _deactivateNewsCheck();
    } else {
      _activateNewsCheck();
    }
  }

  Future<void> _toggleScamCall(bool isEnabled) async {
    final provider = context.read<HomeStateProvider>();
    if (isEnabled) {
      await core_channel.PlatformChannel.setCallDetectionEnabled(false);
      provider.setScamCallEnabled(false);
      return;
    }

    // Turning on — check permissions first.
    final ready = await _ensureLiveCaptionPermissions();
    if (!ready || !mounted) return;

    // Overlay permission is required to bring the app to foreground
    // when the user shakes during a call (Android 12+ restriction).
    final hasOverlay = await PlatformChannel.checkOverlayPermission();
    if (!hasOverlay) {
      if (!mounted) return;
      final shouldOpen = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Cần quyền hiển thị trên ứng dụng khác'),
          content: const Text(
            'CheckVar cần quyền này để hiện lên khi phát hiện lừa đảo '
            'trong cuộc gọi.\n\n'
            'Vui lòng bật "Hiển thị trên ứng dụng khác" cho CheckVar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mở cài đặt'),
            ),
          ],
        ),
      );
      if (shouldOpen == true) {
        _waitingForPermission = true;
        await PlatformChannel.requestOverlayPermission();
        await _waitForResume();
        final granted = await PlatformChannel.checkOverlayPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Quyền hiển thị trên ứng dụng khác chưa được bật.'),
              ),
            );
          }
          return;
        }
      } else {
        return;
      }
    }

    // READ_PHONE_STATE is required by CallMonitorService to listen for
    // call state changes. Must be granted before starting the service.
    final phoneGranted =
        await core_channel.PlatformChannel.requestPhoneStatePermission();
    if (!phoneGranted || !mounted) return;

    // Enable call detection on the native side — this starts the shake
    // service and call monitor via syncServices().
    await core_channel.PlatformChannel.setCallDetectionEnabled(true);

    provider.setScamCallEnabled(true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lắc điện thoại 3 lần trong cuộc gọi để kiểm tra'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _launchSimulationSheet() async {
    final ready = await _ensureLiveCaptionPermissions();
    if (!ready || !mounted) return;

    final scenario = await showModalBottomSheet<SimulatedCallScenario>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CallSimulationSheet(),
    );
    if (!mounted || scenario == null) return;

    final sessionManager = context.read<ScamCallSessionManager>();
    await sessionManager.startSimulationSession(scenario);
    if (!mounted) return;

    final controller = sessionManager.detachController();
    if (controller == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => feature_screen.ScamCallScreen(
          controller: controller,
          modeLabel: 'Simulation: ${scenario.title}',
          disposeController: true,
        ),
      ),
    );
  }

  /// Pre-flight check: ensures Accessibility Service and Live Caption are
  /// both enabled before running a simulation. Returns true when ready.
  Future<bool> _ensureLiveCaptionPermissions() async {
    // 1. Accessibility Service
    final hasAccessibility =
        await PlatformChannel.checkAccessibilityPermission();
    if (!hasAccessibility) {
      if (!mounted) return false;
      final opened = await _showPermissionDialog(
        title: 'Bật Accessibility Service',
        content:
            'CheckVar cần quyền Accessibility để đọc phụ đề từ Live Caption.\n\n'
            'Vui lòng tìm và bật "CheckVar" trong cài đặt Accessibility.',
      );
      if (opened) {
        _waitingForPermission = true;
        await PlatformChannel.openAccessibilitySettings();
        // Wait for user to return from settings.
        await _waitForResume();
        // Re-check after returning.
        final granted =
            await PlatformChannel.checkAccessibilityPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Accessibility Service chưa được bật.'),
              ),
            );
          }
          return false;
        }
      } else {
        return false;
      }
    }

    // 2. Live Caption — informational prompt.
    //    The `oda_enabled` Settings.Secure check is undocumented and unreliable
    //    across devices, so we always show instructions and let the user confirm.
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Bật Live Caption'),
        content: const Text(
          'Live Caption cần được bật để phụ đề cuộc gọi hiển thị.\n\n'
          'Mở Cài đặt và tìm "Live Caption" trong thanh tìm kiếm, '
          'sau đó bật lên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đã bật'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<bool> _showPermissionDialog({
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Để sau'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mở cài đặt'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Waits until the app is resumed (user returns from settings).
  Future<void> _waitForResume() {
    final completer = Completer<void>();
    late final _ResumeObserver observer;
    observer = _ResumeObserver(() {
      _waitingForPermission = false;
      WidgetsBinding.instance.removeObserver(observer);
      if (!completer.isCompleted) completer.complete();
    });
    WidgetsBinding.instance.addObserver(observer);
    return completer.future;
  }

  void _showInfoSheet(String title, String description) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeState = context.watch<HomeStateProvider>();
    final brightness = Theme.of(context).brightness;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'CheckVar',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _buildFeatureCard(
                context,
                isEnabled: homeState.newsCheckEnabled,
                title: 'Kiểm tra\ntin giả',
                icon: Icons.newspaper_rounded,
                onGradient: AppTheme.newsCardOnGradient,
                offColor: AppTheme.cardOffColor(brightness),
                onTap: () => _toggleNewsCheck(homeState.newsCheckEnabled),
                onInfoTap: () => _showInfoSheet(
                  'Kiểm tra tin giả',
                  'Khi bật, hãy mở app tin tức bất kỳ và lắc điện thoại 3 lần. '
                      'CheckVar sẽ tự động chụp màn hình, trích xuất nội dung, '
                      'tìm kiếm nguồn xác minh và phân tích độ tin cậy bằng AI.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildFeatureCard(
                context,
                isEnabled: homeState.scamCallEnabled,
                title: 'Phát hiện\nlừa đảo',
                icon: Icons.shield_rounded,
                onGradient: AppTheme.callCardOnGradient,
                offColor: AppTheme.cardOffColor(brightness),
                onTap: () => _toggleScamCall(homeState.scamCallEnabled),
                onInfoTap: () => _showInfoSheet(
                  'Phát hiện lừa đảo',
                  'Khi bật, CheckVar sẽ theo dõi cuộc gọi đến và phân tích '
                      'nội dung cuộc trò chuyện theo thời gian thực. Nếu phát hiện '
                      'dấu hiệu lừa đảo (giả danh, áp lực chuyển tiền...), '
                      'ứng dụng sẽ cảnh báo ngay lập tức.',
                ),
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('home_simulate_call_button'),
                  onPressed: _launchSimulationSheet,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Simulate Call'),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required bool isEnabled,
    required String title,
    required IconData icon,
    required LinearGradient onGradient,
    required Color offColor,
    required VoidCallback onTap,
    required VoidCallback onInfoTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: isEnabled ? onGradient : null,
        color: isEnabled ? null : offColor,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              // Background icon decoration
              Positioned(
                right: -20,
                top: -20,
                child: Icon(
                  icon,
                  size: 180,
                  color: (isEnabled ? Colors.black : Colors.grey)
                      .withValues(alpha: 0.06),
                ),
              ),
              // Info button top-left
              Positioned(
                top: 12,
                left: 12,
                child: IconButton(
                  icon: Icon(
                    Icons.info_outline_rounded,
                    color: isEnabled
                        ? Colors.black54
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onInfoTap,
                ),
              ),
              // Status badge top-right
              Positioned(
                top: 16,
                right: 16,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? AppTheme.success.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isEnabled ? 'Đang bật' : 'Tắt',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isEnabled ? AppTheme.success : Colors.grey,
                    ),
                  ),
                ),
              ),
              // Title bottom-left
              Positioned(
                bottom: 24,
                left: 24,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isEnabled
                        ? Colors.black87
                        : Theme.of(context).textTheme.bodyLarge?.color,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
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
    final bottomInset =
        mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
            ? mediaQuery.viewInsets.bottom
            : mediaQuery.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
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
