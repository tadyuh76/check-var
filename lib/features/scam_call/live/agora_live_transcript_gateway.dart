import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/api/agora_service.dart';
import '../../../core/api/live_transcript_source.dart';
import 'live_audio_frame.dart';
import 'live_transcript_models.dart';

abstract interface class LiveAudioSource {
  Stream<LiveAudioFrame> get audioFrames;

  Future<void> initialize();

  Future<void> startListening();

  Future<void> stopListening();
}

abstract interface class ScamCallTranscriptGateway {
  Stream<LiveTranscriptEvent> get transcripts;

  Future<void> start();

  Future<void> restartLiveSession();

  Future<void> stop();
}

class AgoraLiveTranscriptGateway implements ScamCallTranscriptGateway {
  AgoraLiveTranscriptGateway({
    LiveAudioSource? audioSource,
    required LiveTranscriptSource liveSource,
  }) : _audioSource = audioSource ?? AgoraServiceAudioSource(AgoraService()),
       _liveSource = liveSource;

  final LiveAudioSource _audioSource;
  final LiveTranscriptSource _liveSource;

  StreamSubscription<LiveAudioFrame>? _audioSub;
  bool _started = false;

  @override
  Stream<LiveTranscriptEvent> get transcripts => _liveSource.events;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    await _audioSource.initialize();
    await _liveSource.connect();
    _audioSub = _audioSource.audioFrames.listen(_forwardAudioFrame);
    await _audioSource.startListening();
    _started = true;
  }

  @override
  Future<void> restartLiveSession() async {
    await _liveSource.disconnect();
    await _liveSource.connect();
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _audioSub?.cancel();
    _audioSub = null;
    await _audioSource.stopListening();
    await _liveSource.disconnect();
  }

  void _forwardAudioFrame(LiveAudioFrame frame) {
    if (frame.channels != 1 || frame.bytesPerSample != 2) {
      debugPrint(
        'Dropping unsupported live audio frame: '
        '${frame.channels}ch/${frame.bytesPerSample}B',
      );
      return;
    }

    unawaited(_sendAudioFrame(frame));
  }

  Future<void> _sendAudioFrame(LiveAudioFrame frame) async {
    try {
      await _liveSource.sendAudioPcm(
        frame.pcmBytes,
        sampleRate: frame.sampleRate,
      );
    } on StateError catch (error) {
      debugPrint('Dropping live audio frame: $error');
    }
  }
}

class AgoraServiceAudioSource implements LiveAudioSource {
  AgoraServiceAudioSource(this._service);

  final AgoraService _service;

  @override
  Stream<LiveAudioFrame> get audioFrames => _service.audioFrames;

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<void> startListening() => _service.startListening();

  @override
  Future<void> stopListening() => _service.stopListening();
}
