import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../config/api_keys.dart';
import '../../features/scam_call/live/live_audio_frame.dart';

typedef TranscriptCallback = void Function(String text);

abstract interface class AgoraEnginePort {
  Future<void> initialize({
    required String appId,
    required ChannelProfileType channelProfile,
  });

  Future<void> setAudioProfile({
    required AudioProfileType profile,
    required AudioScenarioType scenario,
  });

  Future<void> setParameters(String parameters);

  Future<void> setAINSMode({
    required bool enabled,
    required AudioAinsMode mode,
  });

  Future<void> setRecordingAudioFrameParameters({
    required int sampleRate,
    required int channel,
    required RawAudioFrameOpModeType mode,
    required int samplesPerCall,
  });

  void registerAudioFrameObserver(AudioFrameObserver observer);

  void unregisterAudioFrameObserver(AudioFrameObserver observer);

  Future<void> enableAudio();

  Future<void> adjustRecordingSignalVolume(int volume);

  Future<void> startPreview();

  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  });

  Future<void> leaveChannel();

  Future<void> stopPreview();

  Future<void> disableAudio();

  Future<void> release();
}

class AgoraService {
  AgoraService({AgoraEnginePort? enginePort})
    : _enginePort = enginePort ?? RtcEngineAgoraPort();

  static const _localChannelId = 'checkvar_local';

  final AgoraEnginePort _enginePort;
  final StreamController<LiveAudioFrame> _audioFrames =
      StreamController<LiveAudioFrame>.broadcast();

  AudioFrameObserver? _audioObserver;
  bool _isInitialized = false;
  bool _isActive = false;
  TranscriptCallback? onTranscript;

  Stream<LiveAudioFrame> get audioFrames => _audioFrames.stream;
  bool get isActive => _isActive;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    await _enginePort.initialize(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    );

    await _enginePort.setAudioProfile(
      profile: AudioProfileType.audioProfileDefault,
      scenario: AudioScenarioType.audioScenarioDefault,
    );

    await _enginePort.setParameters('{"che.audio.aec.enable":false}');
    await _enginePort.setParameters('{"che.audio.agc.enable":false}');

    await _enginePort.setAINSMode(
      enabled: true,
      mode: AudioAinsMode.ainsModeBalanced,
    );

    _isInitialized = true;
  }

  Future<void> startListening() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_isActive) {
      return;
    }

    await _enginePort.setRecordingAudioFrameParameters(
      sampleRate: 16000,
      channel: 1,
      mode: RawAudioFrameOpModeType.rawAudioFrameOpModeReadOnly,
      samplesPerCall: 1600,
    );

    _audioObserver ??= AudioFrameObserver(
      onRecordAudioFrame: _handleRecordedAudioFrame,
    );
    _enginePort.registerAudioFrameObserver(_audioObserver!);

    _isActive = true;
    await _enginePort.enableAudio();
    await _enginePort.adjustRecordingSignalVolume(200);
    await _enginePort.startPreview();
    await _enginePort.joinChannel(
      token: '',
      channelId: _localChannelId,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        autoSubscribeAudio: true,
      ),
    );
  }

  Future<void> stopListening() async {
    if (!_isActive) {
      return;
    }

    _isActive = false;
    await _enginePort.leaveChannel();
    await _enginePort.stopPreview();
    await _enginePort.disableAudio();
  }

  Future<void> dispose() async {
    _isActive = false;
    await _enginePort.leaveChannel();
    if (_audioObserver != null) {
      _enginePort.unregisterAudioFrameObserver(_audioObserver!);
      _audioObserver = null;
    }
    await _audioFrames.close();
    await _enginePort.release();
    _isInitialized = false;
  }

  void _handleRecordedAudioFrame(String channelId, AudioFrame audioFrame) {
    final buffer = audioFrame.buffer;
    final sampleRate = audioFrame.samplesPerSec;
    final channels = audioFrame.channels;
    final bytesPerSample = audioFrame.bytesPerSample?.value();
    if (buffer == null ||
        sampleRate == null ||
        channels == null ||
        bytesPerSample == null) {
      return;
    }

    _audioFrames.add(
      LiveAudioFrame(
        pcmBytes: buffer,
        sampleRate: sampleRate,
        channels: channels,
        bytesPerSample: bytesPerSample,
        timestamp: DateTime.now(),
      ),
    );
  }
}

class RtcEngineAgoraPort implements AgoraEnginePort {
  RtcEngineAgoraPort([RtcEngine? engine])
    : _engine = engine ?? createAgoraRtcEngine();

  final RtcEngine _engine;

  @override
  Future<void> adjustRecordingSignalVolume(int volume) {
    return _engine.adjustRecordingSignalVolume(volume);
  }

  @override
  Future<void> disableAudio() => _engine.disableAudio();

  @override
  Future<void> enableAudio() => _engine.enableAudio();

  @override
  Future<void> initialize({
    required String appId,
    required ChannelProfileType channelProfile,
  }) {
    return _engine.initialize(
      RtcEngineContext(appId: appId, channelProfile: channelProfile),
    );
  }

  @override
  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  }) {
    return _engine.joinChannel(
      token: token,
      channelId: channelId,
      uid: uid,
      options: options,
    );
  }

  @override
  Future<void> leaveChannel() => _engine.leaveChannel();

  @override
  void registerAudioFrameObserver(AudioFrameObserver observer) {
    _engine.getMediaEngine().registerAudioFrameObserver(observer);
  }

  @override
  Future<void> release() => _engine.release();

  @override
  Future<void> setParameters(String parameters) {
    return _engine.setParameters(parameters);
  }

  @override
  Future<void> setAINSMode({
    required bool enabled,
    required AudioAinsMode mode,
  }) {
    return _engine.setAINSMode(enabled: enabled, mode: mode);
  }

  @override
  Future<void> setAudioProfile({
    required AudioProfileType profile,
    required AudioScenarioType scenario,
  }) {
    return _engine.setAudioProfile(profile: profile, scenario: scenario);
  }

  @override
  Future<void> setRecordingAudioFrameParameters({
    required int sampleRate,
    required int channel,
    required RawAudioFrameOpModeType mode,
    required int samplesPerCall,
  }) {
    return _engine.setRecordingAudioFrameParameters(
      sampleRate: sampleRate,
      channel: channel,
      mode: mode,
      samplesPerCall: samplesPerCall,
    );
  }

  @override
  Future<void> startPreview() => _engine.startPreview();

  @override
  Future<void> stopPreview() => _engine.stopPreview();

  @override
  void unregisterAudioFrameObserver(AudioFrameObserver observer) {
    _engine.getMediaEngine().unregisterAudioFrameObserver(observer);
  }
}
