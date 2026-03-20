import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/news_check_controller.dart';
import '../models/check_result.dart';
import '../theme/app_theme.dart';

class NewsCheckScreen extends StatelessWidget {
  const NewsCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả kiểm tra'),
        centerTitle: true,
      ),
      body: Consumer<NewsCheckController>(
        builder: (context, controller, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildContent(context, controller),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, NewsCheckController controller) {
    switch (controller.status) {
      case NewsCheckStatus.idle:
        return const Center(child: Text('Không có dữ liệu'));
      case NewsCheckStatus.extracting:
        return _buildLoading(context, 'Đang trích xuất nội dung...', 0);
      case NewsCheckStatus.searching:
        return _buildLoading(context, 'Đang tìm kiếm nguồn...', 1);
      case NewsCheckStatus.classifying:
        return _buildLoading(context, 'Đang phân tích độ tin cậy...', 2);
      case NewsCheckStatus.error:
        return _buildError(context, controller);
      case NewsCheckStatus.done:
        return _buildResult(context, controller);
    }
  }

  Widget _buildLoading(BuildContext context, String message, int activeStep) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            _buildStepDots(activeStep),
          ],
        ),
      ),
    );
  }

  Widget _buildStepDots(int activeStep) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isActive = index == activeStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary : Colors.grey.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildError(BuildContext context, NewsCheckController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
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
            FilledButton(
              onPressed: () {
                controller.reset();
                Navigator.pop(context);
              },
              child: const Text('Quay lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, NewsCheckController controller) {
    final result = controller.result;
    if (result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildVerdictCard(context, result),
        const SizedBox(height: 20),
        _buildExtractedText(context, result),
        if (result.sources.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildSourcesList(context, result),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              controller.reset();
              Navigator.pop(context);
            },
            child: const Text('Kiểm tra lại'),
          ),
        ),
      ],
    );
  }

  Widget _buildVerdictCard(BuildContext context, CheckResult result) {
    final (color, icon, label) = switch (result.verdict) {
      Verdict.real => (AppTheme.success, Icons.verified_rounded, 'Tin thật'),
      Verdict.fake =>
        (AppTheme.danger, Icons.dangerous_rounded, 'Tin giả'),
      Verdict.uncertain =>
        (AppTheme.warning, Icons.help_outline_rounded, 'Chưa xác định'),
    };

    final confidence = (result.confidence * 100).round();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
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
            'Độ tin cậy: $confidence%',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
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

  Widget _buildExtractedText(BuildContext context, CheckResult result) {
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

  Widget _buildSourcesList(BuildContext context, CheckResult result) {
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
        ...result.sources.map((source) => _buildSourceTile(context, source)),
      ],
    );
  }

  Widget _buildSourceTile(BuildContext context, SearchSource source) {
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
}
