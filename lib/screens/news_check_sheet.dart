import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/news_check_controller.dart';
import '../models/check_result.dart';
import '../theme/app_theme.dart';

String _confidenceLabel(double confidence) {
  if (confidence >= 0.85) return 'Rất chắc chắn';
  if (confidence >= 0.65) return 'Khá chắc chắn';
  if (confidence >= 0.45) return 'Chưa rõ ràng';
  if (confidence >= 0.25) return 'Không chắc chắn';
  return 'Rất không chắc chắn';
}

/// Shows the news check bottom sheet overlay.
void showNewsCheckSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _NewsCheckSheet(),
  );
}

class _NewsCheckSheet extends StatefulWidget {
  const _NewsCheckSheet();

  @override
  State<_NewsCheckSheet> createState() => _NewsCheckSheetState();
}

class _NewsCheckSheetState extends State<_NewsCheckSheet>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dotsController;
  late AnimationController _resultSlideController;
  late Animation<double> _resultSlideAnimation;
  bool _showResult = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _resultSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _resultSlideAnimation = CurvedAnimation(
      parent: _resultSlideController,
      curve: Curves.easeOutCubic,
    );

    NewsCheckController.instance.addListener(_onStatusChange);
  }

  void _onStatusChange() {
    final status = NewsCheckController.instance.status;
    if (status == NewsCheckStatus.done || status == NewsCheckStatus.error) {
      if (!_showResult) {
        setState(() => _showResult = true);
        _pulseController.stop();
        _dotsController.stop();
        _resultSlideController.forward();
      }
    }
  }

  @override
  void dispose() {
    NewsCheckController.instance.removeListener(_onStatusChange);
    _pulseController.dispose();
    _dotsController.dispose();
    _resultSlideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: NewsCheckController.instance,
      child: Consumer<NewsCheckController>(
        builder: (context, controller, _) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            height: _showResult
                ? MediaQuery.of(context).size.height * 0.85
                : MediaQuery.of(context).size.height * 0.35,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A1A1A)
                  : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: Column(
                children: [
                  _buildHandle(),
                  if (!_showResult) _buildAnalyzing(controller),
                  if (_showResult) _buildResultContent(controller),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildAnalyzing(NewsCheckController controller) {
    final statusText = switch (controller.status) {
      NewsCheckStatus.extracting => 'Đang trích xuất nội dung...',
      NewsCheckStatus.searching => 'Đang tìm kiếm nguồn...',
      NewsCheckStatus.classifying => 'Đang phân tích độ tin cậy...',
      _ => 'Đang chuẩn bị...',
    };

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo with pulse
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              final opacity = 0.6 + (_pulseController.value * 0.4);
              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              );
            },
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.fact_check_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'CheckVar',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 24),
          // Animated wave dots
          _buildWaveDots(),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              statusText,
              key: ValueKey(statusText),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveDots() {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final offset = index / 5;
            final value =
                sin((_dotsController.value + offset) * 2 * pi).abs();
            final dotColor = Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : AppTheme.primary;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8 + (value * 16),
              decoration: BoxDecoration(
                color: dotColor.withValues(alpha: 0.3 + (value * 0.7)),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildResultContent(NewsCheckController controller) {
    return Expanded(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(_resultSlideAnimation),
        child: FadeTransition(
          opacity: _resultSlideAnimation,
          child: controller.status == NewsCheckStatus.error
              ? _buildError(controller)
              : _buildResult(controller),
        ),
      ),
    );
  }

  Widget _buildError(NewsCheckController controller) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 56, color: AppTheme.danger),
          const SizedBox(height: 16),
          Text(
            'Đã xảy ra lỗi',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.danger,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.errorMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildResult(NewsCheckController controller) {
    final result = controller.result;
    if (result == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildVerdictCard(result),
          const SizedBox(height: 16),
          _buildExtractedText(result),
          if (result.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSourcesList(result),
          ],
          const SizedBox(height: 20),
          _buildCloseButton(),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildVerdictCard(CheckResult result) {
    final (color, icon, label) = switch (result.verdict) {
      Verdict.real => (AppTheme.success, Icons.verified_rounded, 'Tin thật'),
      Verdict.fake => (AppTheme.danger, Icons.dangerous_rounded, 'Tin giả'),
      Verdict.uncertain =>
        (AppTheme.warning, Icons.help_outline_rounded, 'Chưa xác định'),
    };

    final confidenceText = _confidenceLabel(result.confidence);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            confidenceText,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: color),
          ),
          const SizedBox(height: 12),
          Text(
            result.summary,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedText(CheckResult result) {
    final text = result.extractedText.length > 300
        ? '${result.extractedText.substring(0, 300)}...'
        : result.extractedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nội dung trích xuất',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesList(CheckResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nguồn tham khảo',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        ...result.sources.map((source) => _buildSourceTile(source)),
      ],
    );
  }

  Widget _buildSourceTile(SearchSource source) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          final uri = Uri.tryParse(source.url);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () {
          NewsCheckController.instance.reset();
          Navigator.pop(context);
        },
        child: const Text('Đóng'),
      ),
    );
  }
}
