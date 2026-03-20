import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'live_transcript_source.dart';
import '../../features/scam_call/live/live_transcript_models.dart';

typedef LiveSocketFactory = Future<LiveSocket> Function(String url);

abstract interface class LiveSocket {
  int? get closeCode;
  String? get closeReason;
  Stream<Object?> get stream;

  void send(String message);

  Future<void> close([int? code, String? reason]);
}

Future<LiveSocket> defaultLiveSocketFactory(String url) async {
  final socket = await WebSocket.connect(url);
  return _WebSocketLiveSocket(socket);
}

/// Hackathon-only Live API client.
///
/// WARNING: This connects directly from Flutter with a long-lived Gemini API
/// key. Replace this with ephemeral tokens before any production or broad
/// distribution build.
class GeminiLiveApiClient implements LiveTranscriptSource {
  GeminiLiveApiClient({
    required this.apiKey,
    required this.model,
    LiveSocketFactory? socketFactory,
  }) : _socketFactory = socketFactory ?? defaultLiveSocketFactory;

  static const _baseUrl =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.'
      'BidiGenerateContent';

  final String apiKey;
  final String model;
  final LiveSocketFactory _socketFactory;
  final StreamController<LiveTranscriptEvent> _events =
      StreamController<LiveTranscriptEvent>.broadcast();

  LiveSocket? _socket;
  StreamSubscription<Object?>? _socketSub;

  @override
  Stream<LiveTranscriptEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    if (_socket != null) {
      return;
    }

    // Hackathon-only auth: the API key is passed directly on the websocket URL.
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {'key': apiKey});
    final socket = await _socketFactory(uri.toString());
    _socket = socket;
    _socketSub = socket.stream.listen(
      _handleMessage,
      onDone: _handleSocketClosed,
      onError: _handleSocketError,
      cancelOnError: false,
    );

    socket.send(
      jsonEncode({
        'setup': {
          'model': 'models/$model',
          'generationConfig': {
            'responseModalities': ['AUDIO'],
          },
          'inputAudioTranscription': {},
        },
      }),
    );
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    await _socketSub?.cancel();
    _socketSub = null;
    if (socket != null) {
      await socket.close();
    }
  }

  @override
  Future<void> sendAudioPcm(
    Uint8List pcmBytes, {
    required int sampleRate,
  }) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Gemini Live API socket is not connected.');
    }

    socket.send(
      jsonEncode({
        'realtimeInput': {
          'audio': {
            'data': base64Encode(pcmBytes),
            'mimeType': 'audio/pcm;rate=$sampleRate',
          },
        },
      }),
    );
  }

  void _handleMessage(Object? message) {
    final text = switch (message) {
      String() => message,
      List<int>() => utf8.decode(message),
      _ => null,
    };
    if (text == null) {
      return;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final event = LiveTranscriptEvent.fromServerMessage(decoded);
    if (event != null) {
      _events.add(event);
    }
  }

  void _handleSocketClosed() {
    final socket = _socket;
    _socket = null;
    _socketSub = null;
    _events.add(
      LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.error,
        detail:
            'Live API socket closed'
            '${socket?.closeCode != null ? ' (${socket!.closeCode})' : ''}'
            '${socket?.closeReason != null ? ': ${socket!.closeReason}' : ''}',
      ),
    );
  }

  void _handleSocketError(Object error, [StackTrace? stackTrace]) {
    _events.add(
      LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.error,
        detail: error.toString(),
      ),
    );
  }
}

class _WebSocketLiveSocket implements LiveSocket {
  _WebSocketLiveSocket(this._socket);

  final WebSocket _socket;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;

  @override
  Stream<Object?> get stream => _socket;

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);

  @override
  void send(String message) {
    _socket.add(message);
  }
}
