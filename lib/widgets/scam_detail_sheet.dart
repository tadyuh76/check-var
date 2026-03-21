import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../models/scam_alert.dart';

/// Elder-friendly bottom sheet showing scam analysis details.
class ScamDetailSheet extends StatelessWidget {
  const ScamDetailSheet({
    super.key,
    required this.threatLevel,
    required this.confidence,
    required this.summary,
    required this.advice,
    required this.patterns,
  });

  final ThreatLevel threatLevel;
  final double confidence;
  final String summary;
  final String advice;
  final List<String> patterns;

  static Future<void> show(
    BuildContext context, {
    required ThreatLevel threatLevel,
    required double confidence,
    required String summary,
    required String advice,
    required List<String> patterns,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScamDetailSheet(
        threatLevel: threatLevel,
        confidence: confidence,
        summary: summary,
        advice: advice,
        patterns: patterns,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon, label, description) = switch (threatLevel) {
      ThreatLevel.safe => (
        Colors.green,
        Icons.verified_user_rounded,
        'threat.safe'.tr(),
        'scam_detail.safe_desc'.tr(),
      ),
      ThreatLevel.suspicious => (
        Colors.amber,
        Icons.warning_rounded,
        'threat.suspicious'.tr(),
        'scam_detail.suspicious_desc'.tr(),
      ),
      ThreatLevel.scam => (
        Colors.red,
        Icons.gpp_bad_rounded,
        'threat.scam'.tr(),
        'scam_detail.scam_desc'.tr(),
      ),
    };

    final confidencePercent = (confidence * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Big threat icon + status
              _buildThreatHeader(context, color, icon, label),
              const SizedBox(height: 20),

              // Confidence meter
              _buildConfidenceMeter(context, color, confidencePercent),
              const SizedBox(height: 20),

              // Description
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // Scam type chips
              if (patterns.isNotEmpty) ...[
                _buildScamTypeSection(context, color),
                const SizedBox(height: 16),
              ],

              // Advice box
              if (advice.isNotEmpty) _buildAdviceBox(context, color),

              const SizedBox(height: 20),

              // Close button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.2),
                    foregroundColor: color,
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text('scam_detail.understood'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreatHeader(
    BuildContext context,
    Color color,
    IconData icon,
    String label,
  ) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 44),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 26,
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceMeter(
    BuildContext context,
    Color color,
    int percent,
  ) {
    return Column(
      children: [
        Text(
          'confidence.label'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        // Big percentage
        Text(
          '$percent%',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 44,
          ),
        ),
        const SizedBox(height: 10),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: LinearProgressIndicator(
              value: confidence,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScamTypeSection(BuildContext context, Color color) {
    return Column(
      children: [
        Text(
          'scam_detail.scam_types'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: patterns.map((pattern) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                pattern,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAdviceBox(BuildContext context, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_rounded,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'scam_detail.advice'.tr(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  advice,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
