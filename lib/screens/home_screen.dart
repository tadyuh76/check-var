import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

    if (!mounted) return;
    context.read<HomeStateProvider>().setNewsCheckEnabled(true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lắc điện thoại 2 lần để kiểm tra'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _deactivateNewsCheck() async {
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

  void _toggleScamCall(bool isEnabled) {
    final provider = context.read<HomeStateProvider>();
    provider.setScamCallEnabled(!isEnabled);
    if (!isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lắc điện thoại 2 lần để kiểm tra'),
          duration: Duration(seconds: 3),
        ),
      );
    }
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
                  'Khi bật, hãy mở app tin tức bất kỳ và lắc điện thoại 2 lần. '
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
