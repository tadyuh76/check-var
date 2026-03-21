import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/history_entry.dart';
import '../models/check_result.dart';
import '../models/call_result.dart';
import '../theme/app_theme.dart';

String _confidenceLabel(double confidence) {
  if (confidence >= 0.85) return 'Rất chắc chắn';
  if (confidence >= 0.65) return 'Khá chắc chắn';
  if (confidence >= 0.45) return 'Chưa rõ ràng';
  if (confidence >= 0.25) return 'Không chắc chắn';
  return 'Rất không chắc chắn';
}

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.type == HistoryType.news
            ? 'Chi tiết kiểm tra'
            : 'Chi tiết cuộc gọi'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: entry.type == HistoryType.news
            ? _buildNewsDetail(context)
            : _buildCallDetail(context),
      ),
    );
  }

  Widget _buildNewsDetail(BuildContext context) {
    final (color, icon, label) = switch (entry.verdict) {
      Verdict.real => (AppTheme.success, Icons.verified_rounded, 'Tin thật'),
      Verdict.fake => (AppTheme.danger, Icons.dangerous_rounded, 'Tin giả'),
      Verdict.uncertain =>
        (AppTheme.warning, Icons.help_outline_rounded, 'Chưa xác định'),
    };
    final confidenceLabel = _confidenceLabel(entry.confidence);
    final extractedText = entry.extractedText.length > 300
        ? '${entry.extractedText.substring(0, 300)}...'
        : entry.extractedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Verdict card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha:0.25)),
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
                confidenceLabel,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: color),
              ),
              const SizedBox(height: 12),
              Text(
                entry.summary,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),

        // Extracted text
        const SizedBox(height: 20),
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
            extractedText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),

        // Sources
        if (entry.sources.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Nguồn tham khảo',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          ...entry.sources.map((source) => _buildSourceTile(context, source)),
        ],
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

  Widget _buildCallDetail(BuildContext context) {
    final (color, icon, label) = switch (entry.threatLevel) {
      ThreatLevel.safe =>
        (AppTheme.success, Icons.verified_user_rounded, 'AN TOÀN'),
      ThreatLevel.suspicious =>
        (AppTheme.warning, Icons.shield_rounded, 'ĐÁNG NGỜ'),
      ThreatLevel.scam =>
        (AppTheme.danger, Icons.gpp_bad_rounded, 'LỪA ĐẢO'),
    };
    final confidence = (entry.confidence * 100).round();
    final duration = entry.callDuration;
    final durationStr =
        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Verdict card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha:0.25)),
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
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: color),
              ),
              if (entry.patterns.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: entry.patterns
                      .map((p) => Chip(
                            label: Text(p,
                                style:
                                    TextStyle(fontSize: 12, color: color)),
                            backgroundColor: color.withValues(alpha:0.1),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        Center(
          child: Text(
            'Thời gian: $durationStr',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),

        // Transcript
        if (entry.transcript.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Nội dung cuộc gọi',
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
              entry.transcript,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
