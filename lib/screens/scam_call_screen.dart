import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/scam_call_controller.dart';
import '../models/call_result.dart';
import '../theme/app_theme.dart';

class ScamCallScreen extends StatefulWidget {
  const ScamCallScreen({super.key});

  @override
  State<ScamCallScreen> createState() => _ScamCallScreenState();
}

class _ScamCallScreenState extends State<ScamCallScreen> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    context.read<ScamCallController>().startListening();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  String get _formattedTime {
    final mins = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phát hiện lừa đảo'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            context.read<ScamCallController>().reset();
            Navigator.pop(context);
          },
        ),
      ),
      body: Consumer<ScamCallController>(
        builder: (context, controller, _) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildThreatBanner(context, controller),
                const SizedBox(height: 24),
                Text(
                  _formattedTime,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                ),
                const SizedBox(height: 24),
                Expanded(child: _buildTranscript(context, controller)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () {
                      controller.stopListening();
                      _timer?.cancel();
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Dừng',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildThreatBanner(
      BuildContext context, ScamCallController controller) {
    final (color, icon, label) = switch (controller.currentThreat) {
      ThreatLevel.safe =>
        (AppTheme.success, Icons.verified_user_rounded, 'AN TOÀN'),
      ThreatLevel.suspicious =>
        (AppTheme.warning, Icons.shield_rounded, 'ĐÁNG NGỜ'),
      ThreatLevel.scam =>
        (AppTheme.danger, Icons.gpp_bad_rounded, 'LỪA ĐẢO'),
    };
    final confidence = (controller.confidence * 100).round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Độ tin cậy: $confidence%',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
          ),
          if (controller.patterns.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: controller.patterns
                  .map((p) => Chip(
                        label:
                            Text(p, style: TextStyle(fontSize: 12, color: color)),
                        backgroundColor: color.withValues(alpha: 0.1),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTranscript(
      BuildContext context, ScamCallController controller) {
    if (controller.transcript.isEmpty) {
      return Center(
        child: Text(
          'Đang lắng nghe...',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          controller.transcript,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
