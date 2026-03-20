import 'package:flutter/material.dart';

import '../../../widgets/transcript_bubble.dart';
import 'phrase_accuracy.dart';
import 'speaker_test_gateway.dart';
import 'speaker_transcript_controller.dart';

/// Default phrases used for the controlled pre-set test.
const kDefaultTestPhrases = [
  'Vui lòng xác nhận số tài khoản của bạn',
  'Chuyển tiền ngay lập tức',
  'Chúng tôi cần số chứng minh nhân dân của bạn',
  'Bạn đã trúng thưởng một giải thưởng lớn',
  'Thanh toán bằng thẻ quà tặng',
];

class SpeakerTranscriptTestScreen extends StatefulWidget {
  const SpeakerTranscriptTestScreen({
    super.key,
    required this.controller,
  });

  final SpeakerTranscriptController controller;

  @override
  State<SpeakerTranscriptTestScreen> createState() =>
      _SpeakerTranscriptTestScreenState();
}

class _SpeakerTranscriptTestScreenState
    extends State<SpeakerTranscriptTestScreen> {
  final _scrollController = ScrollController();

  SpeakerTranscriptController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
    _ctrl.loadReadiness();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speaker Call Test'),
        actions: [
          if (_ctrl.summaryVerdict != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _VerdictChip(verdict: _ctrl.summaryVerdict!),
            ),
        ],
      ),
      body: Column(
        children: [
          // Everything scrolls together except the bottom button
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
              children: [
                // Error / blocking banner
                if (_ctrl.blockingMessage != null)
                  _ErrorBanner(
                    message: _ctrl.blockingMessage!,
                    color: colorScheme.error,
                  ),
                if (_ctrl.errorMessage != null)
                  _ErrorBanner(
                    message: _ctrl.errorMessage!,
                    color: colorScheme.error,
                  ),

                // Readiness card
                if (!_ctrl.isRunning && _ctrl.phraseScores.isEmpty)
                  _ReadinessCard(readiness: _ctrl.readiness),

                // Test phrases with progress indicators
                if (_ctrl.phraseScores.isEmpty ||
                    _ctrl.isRunning ||
                    _ctrl.phraseScores.length < _ctrl.expectedPhrases.length)
                  _TestPhrasesCard(
                    phrases: _ctrl.expectedPhrases,
                    currentIndex: _ctrl.currentPhraseIndex,
                    isPlaying: _ctrl.isPlayingPhrase,
                    completedCount: _ctrl.phraseScores.length,
                    isRunning: _ctrl.isRunning,
                  ),

                // Finalized transcript lines
                for (final line in _ctrl.transcriptHistory)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TranscriptBubble(line: line),
                  ),

                // Partial transcript
                if (_ctrl.partialTranscript.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child:
                        _PartialTranscriptTile(text: _ctrl.partialTranscript),
                  ),

                // Phrase accuracy results
                if (_ctrl.phraseScores.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const _SectionHeader(title: 'Phrase Accuracy'),
                  ),
                  for (final score in _ctrl.phraseScores)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _PhraseScoreTile(result: score),
                    ),
                  if (_ctrl.phraseScores.length >= 2)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _AverageAccuracyTile(
                        accuracy: _ctrl.averageAccuracy,
                        verdict: _ctrl.summaryVerdict,
                      ),
                    ),
                ],

                // Waiting state while test is running
                if (_ctrl.isRunning && _ctrl.transcriptHistory.isEmpty)
                  const _WaitingForSpeech(),
              ],
            ),
          ),

          // Run / Stop button
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + bottomInset,
            ),
            child: SizedBox(
              key: const Key('speaker_test_run_button'),
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _ctrl.readiness.isReadyToListen || _ctrl.isRunning
                    ? () => _ctrl.isRunning
                        ? _ctrl.stopTest()
                        : _ctrl.runTest()
                    : null,
                icon: Icon(
                  _ctrl.isRunning ? Icons.stop : Icons.play_arrow,
                ),
                label: Text(
                  _ctrl.isRunning ? 'Stop Test' : 'Run Speaker Test',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.color});
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.15),
      child: Text(
        message,
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});
  final SpeakerTestReadiness readiness;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Readiness Check',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _ReadinessRow(
              label: 'Microphone',
              ready: readiness.hasMicrophonePermission,
            ),
            _ReadinessRow(
              label: 'Speech Recognizer',
              ready: readiness.recognizerAvailable,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.label, required this.ready});
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: ready ? Colors.green : colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Shows the list of test phrases with progress: done, playing, or pending.
class _TestPhrasesCard extends StatelessWidget {
  const _TestPhrasesCard({
    required this.phrases,
    required this.currentIndex,
    required this.isPlaying,
    required this.completedCount,
    required this.isRunning,
  });

  final List<String> phrases;
  final int currentIndex;
  final bool isPlaying;
  final int completedCount;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRunning
                  ? 'Playing phrases through speaker...'
                  : 'Test Phrases — will be played aloud:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < phrases.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    // Status icon
                    if (i < completedCount)
                      const Icon(Icons.check_circle,
                          size: 16, color: Colors.green)
                    else if (isRunning && i == currentIndex && isPlaying)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    else if (isRunning && i == currentIndex)
                      Icon(Icons.hearing, size: 16, color: colorScheme.primary)
                    else
                      Icon(Icons.circle_outlined,
                          size: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${i + 1}. "${phrases[i]}"',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              fontWeight: (isRunning && i == currentIndex)
                                  ? FontWeight.bold
                                  : null,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartialTranscriptTile extends StatelessWidget {
  const _PartialTranscriptTile({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _PhraseScoreTile extends StatelessWidget {
  const _PhraseScoreTile({required this.result});
  final PhraseAccuracyResult result;

  @override
  Widget build(BuildContext context) {
    final pct = (result.accuracy * 100).toStringAsFixed(0);
    final color = _verdictColor(result.verdict);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(
          'Played: "${result.expected}"',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        subtitle: Text(
          'Mic heard: "${result.recognized}"',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$pct%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _AverageAccuracyTile extends StatelessWidget {
  const _AverageAccuracyTile({
    required this.accuracy,
    required this.verdict,
  });
  final double accuracy;
  final SpeakerTestVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final pct = (accuracy * 100).toStringAsFixed(0);
    final color = verdict != null ? _verdictColor(verdict!) : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Average: $pct%',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _VerdictChip(verdict: verdict ?? SpeakerTestVerdict.notUsable),
          ],
        ),
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.verdict});
  final SpeakerTestVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final color = _verdictColor(verdict);
    final label = switch (verdict) {
      SpeakerTestVerdict.usable => 'Usable',
      SpeakerTestVerdict.borderline => 'Borderline',
      SpeakerTestVerdict.notUsable => 'Not Usable',
    };

    return Chip(
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _WaitingForSpeech extends StatelessWidget {
  const _WaitingForSpeech();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.volume_up, size: 48, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Playing phrases through speaker...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _verdictColor(SpeakerTestVerdict verdict) {
  return switch (verdict) {
    SpeakerTestVerdict.usable => Colors.green,
    SpeakerTestVerdict.borderline => Colors.amber,
    SpeakerTestVerdict.notUsable => Colors.red,
  };
}
