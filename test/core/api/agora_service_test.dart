import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:check_var/core/api/agora_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initialize configures Agora for speaker pickup', () async {
    final engine = FakeAgoraEnginePort();
    final service = AgoraService(enginePort: engine);

    await service.initialize();

    expect(engine.audioProfile, AudioProfileType.audioProfileDefault);
    expect(engine.audioScenario, AudioScenarioType.audioScenarioDefault);
    expect(engine.ainsEnabled, isTrue);
    expect(engine.ainsMode, AudioAinsMode.ainsModeBalanced);
    expect(engine.parametersCalls, const [
      '{"che.audio.aec.enable":false}',
      '{"che.audio.agc.enable":false}',
    ]);
  });

  test(
    'startListening registers the audio observer and emits pcm frames',
    () async {
      final engine = FakeAgoraEnginePort();
      final service = AgoraService(enginePort: engine);

      await service.initialize();
      await service.startListening();

      final frameFuture = service.audioFrames.first;
      engine.emitRecordedFrame(
        bytes: Uint8List.fromList(List.filled(3200, 1)),
        samplesPerSec: 16000,
        channels: 1,
        bytesPerSample: 2,
      );

      final frame = await frameFuture;
      expect(engine.didRegisterAudioObserver, isTrue);
      expect(engine.recordingSignalVolume, 200);
      expect(frame.sampleRate, 16000);
      expect(frame.channels, 1);
      expect(frame.pcmBytes.length, 3200);
    },
  );
}

class FakeAgoraEnginePort implements AgoraEnginePort {
  AudioFrameObserver? _observer;

  bool didRegisterAudioObserver = false;
  int? sampleRate;
  int? channelCount;
  RawAudioFrameOpModeType? mode;
  int? samplesPerCall;
  AudioProfileType? audioProfile;
  AudioScenarioType? audioScenario;
  bool? ainsEnabled;
  AudioAinsMode? ainsMode;
  int? recordingSignalVolume;
  final List<String> parametersCalls = [];

  @override
  Future<void> disableAudio() async {}

  @override
  Future<void> enableAudio() async {}

  void emitRecordedFrame({
    required Uint8List bytes,
    required int samplesPerSec,
    required int channels,
    required int bytesPerSample,
  }) {
    _observer?.onRecordAudioFrame?.call(
      'checkvar_local',
      AudioFrame(
        buffer: bytes,
        samplesPerSec: samplesPerSec,
        channels: channels,
        bytesPerSample: bytesPerSample == 2
            ? BytesPerSample.twoBytesPerSample
            : null,
      ),
    );
  }

  @override
  Future<void> initialize({
    required String appId,
    required ChannelProfileType channelProfile,
  }) async {}

  @override
  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  }) async {}

  @override
  Future<void> leaveChannel() async {}

  @override
  void registerAudioFrameObserver(AudioFrameObserver observer) {
    didRegisterAudioObserver = true;
    _observer = observer;
  }

  @override
  Future<void> release() async {}

  @override
  Future<void> setParameters(String parameters) async {
    parametersCalls.add(parameters);
  }

  @override
  Future<void> adjustRecordingSignalVolume(int volume) async {
    recordingSignalVolume = volume;
  }

  @override
  Future<void> setAINSMode({
    required bool enabled,
    required AudioAinsMode mode,
  }) async {
    ainsEnabled = enabled;
    ainsMode = mode;
  }

  @override
  Future<void> setAudioProfile({
    required AudioProfileType profile,
    required AudioScenarioType scenario,
  }) async {
    audioProfile = profile;
    audioScenario = scenario;
  }

  @override
  Future<void> setRecordingAudioFrameParameters({
    required int sampleRate,
    required int channel,
    required RawAudioFrameOpModeType mode,
    required int samplesPerCall,
  }) async {
    this.sampleRate = sampleRate;
    channelCount = channel;
    this.mode = mode;
    this.samplesPerCall = samplesPerCall;
  }

  @override
  Future<void> startPreview() async {}

  @override
  Future<void> stopPreview() async {}

  @override
  void unregisterAudioFrameObserver(AudioFrameObserver observer) {
    if (identical(_observer, observer)) {
      _observer = null;
    }
  }
}
