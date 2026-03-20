enum ThreatLevel { safe, suspicious, scam }

class ScamAlert {
  final ThreatLevel threatLevel;
  final double confidence;
  final List<String> patterns;
  final String summary;
  final String advice;

  const ScamAlert({
    required this.threatLevel,
    required this.confidence,
    required this.patterns,
    required this.summary,
    required this.advice,
  });

  ThreatLevel get level => threatLevel;
}

class TranscriptLine {
  final String text;
  final DateTime timestamp;

  const TranscriptLine({required this.text, required this.timestamp});
}
