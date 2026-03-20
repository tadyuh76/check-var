enum SpeakerTestVerdict { usable, borderline, notUsable }

class PhraseAccuracyResult {
  const PhraseAccuracyResult({
    required this.expected,
    required this.recognized,
    required this.matchedWords,
    required this.expectedWords,
    required this.accuracy,
    required this.verdict,
  });

  final String expected;
  final String recognized;
  final int matchedWords;
  final int expectedWords;
  final double accuracy;
  final SpeakerTestVerdict verdict;
}

/// Scores how well [recognized] text matches [expected] text.
///
/// Lowercases both, strips punctuation, splits into words,
/// and computes matched/total expected words.
PhraseAccuracyResult scorePhraseAccuracy({
  required String expected,
  required String recognized,
}) {
  final expectedWords = _normalize(expected);
  final recognizedWords = _normalize(recognized);

  if (expectedWords.isEmpty) {
    return PhraseAccuracyResult(
      expected: expected,
      recognized: recognized,
      matchedWords: 0,
      expectedWords: 0,
      accuracy: 0.0,
      verdict: SpeakerTestVerdict.notUsable,
    );
  }

  final matched = expectedWords.where(recognizedWords.contains).length;
  final accuracy = matched / expectedWords.length;

  return PhraseAccuracyResult(
    expected: expected,
    recognized: recognized,
    matchedWords: matched,
    expectedWords: expectedWords.length,
    accuracy: accuracy,
    verdict: _verdictFromAccuracy(accuracy),
  );
}

/// Returns an overall verdict from an average accuracy score.
SpeakerTestVerdict overallVerdict(double averageAccuracy) {
  return _verdictFromAccuracy(averageAccuracy);
}

SpeakerTestVerdict _verdictFromAccuracy(double accuracy) {
  if (accuracy >= 0.8) return SpeakerTestVerdict.usable;
  if (accuracy >= 0.5) return SpeakerTestVerdict.borderline;
  return SpeakerTestVerdict.notUsable;
}

List<String> _normalize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}
