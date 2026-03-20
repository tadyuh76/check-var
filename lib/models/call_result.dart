enum ThreatLevel { safe, suspicious, scam }

class CallResult {
  final ThreatLevel threatLevel;
  final double confidence;
  final String transcript;
  final List<String> patterns;
  final Duration duration;

  const CallResult({
    required this.threatLevel,
    required this.confidence,
    required this.transcript,
    required this.patterns,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'threatLevel': threatLevel.name,
        'confidence': confidence,
        'transcript': transcript,
        'patterns': patterns,
        'duration': duration.inSeconds,
      };

  factory CallResult.fromJson(Map<String, dynamic> json) {
    return CallResult(
      threatLevel: ThreatLevel.values.firstWhere(
        (t) => t.name == json['threatLevel'],
        orElse: () => ThreatLevel.safe,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      transcript: json['transcript'] ?? '',
      patterns: List<String>.from(json['patterns'] ?? []),
      duration: Duration(seconds: json['duration'] ?? 0),
    );
  }
}
