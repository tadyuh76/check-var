import 'dart:typed_data';

class LiveAudioFrame {
  const LiveAudioFrame({
    required this.pcmBytes,
    required this.sampleRate,
    required this.channels,
    required this.bytesPerSample,
    required this.timestamp,
  });

  final Uint8List pcmBytes;
  final int sampleRate;
  final int channels;
  final int bytesPerSample;
  final DateTime timestamp;
}
