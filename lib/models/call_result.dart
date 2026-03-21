enum ThreatLevel { safe, suspicious, scam }

class CallResult {
  final ThreatLevel threatLevel;
  final double confidence;
  final String transcript;
  final List<String> patterns;
  final Duration duration;
  final String? callerNumber;
  final DateTime callStartTime;
  final DateTime callEndTime;
  final bool wasAnalyzed;
  final String? summary;
  final String? advice;
  final double? scamProbability;

  const CallResult({
    required this.threatLevel,
    required this.confidence,
    required this.transcript,
    required this.patterns,
    required this.duration,
    required this.callStartTime,
    required this.callEndTime,
    required this.wasAnalyzed,
    this.callerNumber,
    this.summary,
    this.advice,
    this.scamProbability,
  });

  Map<String, dynamic> toJson() => {
        'threatLevel': threatLevel.name,
        'confidence': confidence,
        'transcript': transcript,
        'patterns': patterns,
        'duration': duration.inSeconds,
        'callerNumber': callerNumber,
        'callStartTime': callStartTime.toIso8601String(),
        'callEndTime': callEndTime.toIso8601String(),
        'wasAnalyzed': wasAnalyzed,
        'summary': summary,
        'advice': advice,
        'scamProbability': scamProbability,
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
      callerNumber: json['callerNumber'] as String?,
      callStartTime: DateTime.parse(json['callStartTime'] as String),
      callEndTime: DateTime.parse(json['callEndTime'] as String),
      wasAnalyzed: json['wasAnalyzed'] as bool? ?? false,
      summary: json['summary'] as String?,
      advice: json['advice'] as String?,
      scamProbability: (json['scamProbability'] as num?)?.toDouble(),
    );
  }
}
