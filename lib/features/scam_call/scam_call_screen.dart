import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/scam_alert.dart';
import '../../widgets/scam_detail_sheet.dart';
import '../../widgets/transcript_bubble.dart';
import 'scam_call_controller.dart';

class ScamCallScreen extends StatefulWidget {
  const ScamCallScreen({
    super.key,
    this.controller,
    this.modeLabel,
    this.disposeController = false,
    this.manageSessionLifecycle = true,
  });

  final ScamCallController? controller;
  final String? modeLabel;
  final bool disposeController;
  final bool manageSessionLifecycle;

  @override
  State<ScamCallScreen> createState() => _ScamCallScreenState();
}

class _ScamCallScreenState extends State<ScamCallScreen> {
  late final ScamCallController _controller;
  late final bool _ownsController;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ScamCallController();
    _controller.addListener(_onUpdate);
    if (widget.manageSessionLifecycle) {
      unawaited(_controller.startListening());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    if (widget.manageSessionLifecycle) {
      unawaited(_controller.stopListening());
    }
    if (_ownsController || widget.disposeController) {
      _controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) {
      return;
    }

    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phát hiện lừa đảo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildThreatBanner(colorScheme),
          _buildStatusCard(colorScheme),
          _buildAnalysisCard(colorScheme),
          Expanded(
            child: _controller.transcript.isEmpty
                ? _buildWaiting(colorScheme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _controller.transcript.length,
                    itemBuilder: (context, index) {
                      return TranscriptBubble(
                        line: _controller.transcript[index],
                      );
                    },
                  ),
          ),
          _buildControls(colorScheme),
        ],
      ),
    );
  }

  void _showDetailSheet() {
    ScamDetailSheet.show(
      context,
      threatLevel: _controller.threatLevel,
      confidence: _controller.confidence,
      summary: _controller.summary,
      advice: _controller.advice,
      patterns: _controller.patterns,
    );
  }

  Widget _buildThreatBanner(ColorScheme colorScheme) {
    final (color, icon, label) = switch (_controller.threatLevel) {
      ThreatLevel.safe => (Colors.green, Icons.verified_user_rounded, 'AN TOÀN'),
      ThreatLevel.suspicious => (Colors.amber, Icons.warning_rounded, 'ĐÁNG NGỜ'),
      ThreatLevel.scam => (Colors.red, Icons.gpp_bad_rounded, 'LỪA ĐẢO'),
    };

    final hasAnalysis =
        _controller.summary.isNotEmpty || _controller.patterns.isNotEmpty;

    return GestureDetector(
      onTap: hasAnalysis ? _showDetailSheet : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        color: color.withValues(alpha: 0.15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
            if (hasAnalysis) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.info_outline_rounded,
                color: color.withValues(alpha: 0.6),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.modeLabel != null) ...[
                Text(
                  widget.modeLabel!,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Trạng thái',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                _controller.sessionStatusLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_controller.sessionWarning != null) ...[
                const SizedBox(height: 6),
                Text(
                  _controller.sessionWarning!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.secondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(ColorScheme colorScheme) {
    final hasAnalysis =
        _controller.summary.isNotEmpty || _controller.advice.isNotEmpty;
    if (!hasAnalysis && _controller.patterns.isEmpty) {
      return const SizedBox.shrink();
    }

    final threatColor = switch (_controller.threatLevel) {
      ThreatLevel.safe => Colors.green,
      ThreatLevel.suspicious => Colors.amber,
      ThreatLevel.scam => Colors.red,
    };

    return GestureDetector(
      onTap: _showDetailSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_controller.summary.isNotEmpty) ...[
                  Text(
                    _controller.summary,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (_controller.advice.isNotEmpty) ...[
                  Text(
                    _controller.advice,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // Tap hint
                Row(
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 16,
                      color: threatColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Nhấn để xem chi tiết',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: threatColor.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaiting(ColorScheme colorScheme) {
    if (_controller.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _controller.errorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.closed_caption,
            size: 64,
            color: _controller.isListening
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _controller.isListening
                ? 'Đang chờ phụ đề...'
                : 'Đang kết nối Live Caption...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ColorScheme colorScheme) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SizedBox(
        key: const Key('scam_call_controls_button'),
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () async {
            if (_controller.isListening) {
              await _controller.stopListening();
            } else {
              await _controller.startListening();
            }
          },
          icon: Icon(_controller.isListening ? Icons.stop : Icons.mic),
          label: Text(
            _controller.isListening ? 'Dừng nghe' : 'Bắt đầu nghe',
            style: const TextStyle(fontSize: 16),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _controller.isListening
                ? colorScheme.error
                : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
