import 'package:hive/hive.dart';
import 'check_result.dart';
import 'call_result.dart';

enum HistoryType { news, call }

class HistoryEntry {
  final int id;
  final HistoryType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const HistoryEntry({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.data,
  });

  factory HistoryEntry.fromCheckResult(CheckResult result) {
    final now = DateTime.now();
    return HistoryEntry(
      id: now.millisecondsSinceEpoch,
      type: HistoryType.news,
      timestamp: now,
      data: {
        'verdict': result.verdict.name,
        'confidence': result.confidence,
        'summary': result.summary,
        'extractedText': result.extractedText,
        'sources': result.sources.map((s) => s.toJson()).toList(),
      },
    );
  }

  factory HistoryEntry.fromCallResult(CallResult result) {
    final now = DateTime.now();
    return HistoryEntry(
      id: now.millisecondsSinceEpoch,
      type: HistoryType.call,
      timestamp: now,
      data: {
        'threatLevel': result.threatLevel.name,
        'confidence': result.confidence,
        'transcript': result.transcript,
        'patterns': result.patterns,
        'duration': result.duration.inSeconds,
      },
    );
  }

  // News-specific getters
  Verdict get verdict {
    final v = data['verdict'] as String? ?? 'uncertain';
    switch (v) {
      case 'real':
        return Verdict.real;
      case 'fake':
        return Verdict.fake;
      default:
        return Verdict.uncertain;
    }
  }

  double get confidence => (data['confidence'] as num?)?.toDouble() ?? 0.5;
  String get summary => data['summary'] as String? ?? '';
  String get extractedText => data['extractedText'] as String? ?? '';

  List<SearchSource> get sources {
    final list = data['sources'] as List<dynamic>? ?? [];
    return list
        .map((e) => SearchSource.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // Call-specific getters
  ThreatLevel get threatLevel {
    final t = data['threatLevel'] as String? ?? 'safe';
    return ThreatLevel.values.firstWhere(
      (l) => l.name == t,
      orElse: () => ThreatLevel.safe,
    );
  }

  String get transcript => data['transcript'] as String? ?? '';

  List<String> get patterns =>
      List<String>.from(data['patterns'] as List<dynamic>? ?? []);

  Duration get callDuration =>
      Duration(seconds: (data['duration'] as int?) ?? 0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as int,
        type: HistoryType.values.firstWhere(
          (t) => t.name == (json['type'] as String? ?? 'news'),
          orElse: () => HistoryType.news,
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        data: Map<String, dynamic>.from(json['data'] as Map),
      );
}

class HistoryEntryAdapter extends TypeAdapter<HistoryEntry> {
  @override
  final int typeId = 0;

  @override
  HistoryEntry read(BinaryReader reader) {
    final map = Map<String, dynamic>.from(reader.readMap());
    return HistoryEntry.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, HistoryEntry obj) {
    writer.writeMap(obj.toJson());
  }
}
