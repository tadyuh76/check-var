import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/history_entry.dart';
import '../models/check_result.dart';
import '../models/call_result.dart';
import '../theme/app_theme.dart';

String _confidenceLabel(double confidence) {
  if (confidence >= 0.85) return 'confidence.very_sure'.tr();
  if (confidence >= 0.65) return 'confidence.quite_sure'.tr();
  if (confidence >= 0.45) return 'confidence.unclear'.tr();
  if (confidence >= 0.25) return 'confidence.not_sure'.tr();
  return 'confidence.very_unsure'.tr();
}

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.type == HistoryType.news
            ? 'detail.check_detail'.tr()
            : 'detail.call_detail'.tr()),
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
      Verdict.real => (AppTheme.success, Icons.verified_rounded, 'verdict.real'.tr()),
      Verdict.fake => (AppTheme.danger, Icons.dangerous_rounded, 'verdict.fake'.tr()),
      Verdict.uncertain =>
        (AppTheme.warning, Icons.help_outline_rounded, 'verdict.uncertain_full'.tr()),
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
              const SizedBox(height: 8),
              Text(
                'ai_disclaimer'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),

        // Extracted text
        const SizedBox(height: 20),
        Text(
          'news_check.extracted_content'.tr(),
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
            'news_check.reference_sources'.tr(),
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
    if (!entry.wasAnalyzed) {
      return _buildUnanalyzedCallDetail(context);
    }

    final (color, icon, label) = switch (entry.threatLevel) {
      ThreatLevel.safe =>
        (AppTheme.success, Icons.verified_user_rounded, 'threat.safe_upper'.tr()),
      ThreatLevel.suspicious =>
        (AppTheme.warning, Icons.shield_rounded, 'threat.suspicious_upper'.tr()),
      ThreatLevel.scam =>
        (AppTheme.danger, Icons.gpp_bad_rounded, 'threat.scam_upper'.tr()),
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
                'confidence.level'.tr(args: [confidence.toString()]),
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: color),
              ),
              if (entry.scamProbability != null) ...[
                const SizedBox(height: 4),
                Text(
                  'call_detail.scam_probability'.tr(args: ['${(entry.scamProbability! * 100).round()}']),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color.withValues(alpha: 0.8),
                      ),
                ),
              ],
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
                            backgroundColor: color.withValues(alpha: 0.1),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),

        // Caller number
        if (entry.callerNumber != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Số gọi: ${entry.callerNumber}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Center(
          child: Text(
            'detail.duration'.tr(args: [durationStr]),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),

        // Summary & advice
        if (entry.callSummary != null && entry.callSummary!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Tóm tắt',
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
              entry.callSummary!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
        if (entry.callAdvice != null && entry.callAdvice!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 20,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.callAdvice!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Transcript
        if (entry.transcript.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'detail.call_content'.tr(),
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

  Widget _buildUnanalyzedCallDetail(BuildContext context) {
    final duration = entry.callDuration;
    final durationStr =
        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              const Icon(Icons.phone_missed_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'call_history.not_analyzed'.tr().toUpperCase(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'call_detail.not_activated'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),

        if (entry.callerNumber != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Số gọi: ${entry.callerNumber}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Center(
          child: Text(
            'Thời gian: $durationStr',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
