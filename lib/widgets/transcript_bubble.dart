import 'package:flutter/material.dart';
import '../models/scam_alert.dart';

class TranscriptBubble extends StatelessWidget {
  final TranscriptLine line;

  const TranscriptBubble({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time =
        '${line.timestamp.hour.toString().padLeft(2, '0')}:${line.timestamp.minute.toString().padLeft(2, '0')}:${line.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                line.text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
