import 'package:flutter/material.dart';
import '../models/call_result.dart';

enum CallCheckStatus { idle, listening, done, error }

class ScamCallController extends ChangeNotifier {
  CallCheckStatus _status = CallCheckStatus.idle;
  CallResult? _result;
  String _transcript = '';
  ThreatLevel _currentThreat = ThreatLevel.safe;
  double _confidence = 0.0;
  List<String> _patterns = [];
  Duration _duration = Duration.zero;
  String? _error;

  CallCheckStatus get status => _status;
  CallResult? get result => _result;
  String get transcript => _transcript;
  ThreatLevel get currentThreat => _currentThreat;
  double get confidence => _confidence;
  List<String> get patterns => _patterns;
  Duration get duration => _duration;
  String? get error => _error;

  void startListening() {
    _status = CallCheckStatus.listening;
    _transcript = '';
    _currentThreat = ThreatLevel.safe;
    _confidence = 0.0;
    _patterns = [];
    _duration = Duration.zero;
    _error = null;
    notifyListeners();
  }

  void stopListening() {
    _status = CallCheckStatus.done;
    _result = CallResult(
      threatLevel: _currentThreat,
      confidence: _confidence,
      transcript: _transcript,
      patterns: _patterns,
      duration: _duration,
    );
    notifyListeners();
  }

  void reset() {
    _status = CallCheckStatus.idle;
    _result = null;
    _transcript = '';
    _currentThreat = ThreatLevel.safe;
    _confidence = 0.0;
    _patterns = [];
    _duration = Duration.zero;
    _error = null;
    notifyListeners();
  }
}
