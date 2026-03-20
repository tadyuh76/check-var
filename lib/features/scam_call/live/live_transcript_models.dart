enum LiveTranscriptEventKind {
  setupComplete,
  inputTranscript,
  modelText,
  goAway,
  error,
}

class LiveTranscriptEvent {
  const LiveTranscriptEvent({
    required this.kind,
    this.text = '',
    this.isFinal = false,
    this.detail,
  });

  final LiveTranscriptEventKind kind;
  final String text;
  final bool isFinal;
  final String? detail;

  static LiveTranscriptEvent? fromServerMessage(Map<String, dynamic> json) {
    if (json['setupComplete'] != null) {
      return const LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.setupComplete,
      );
    }

    final serverContent = json['serverContent'] as Map<String, dynamic>?;
    final input = serverContent?['inputTranscription'] as Map<String, dynamic>?;
    if (input != null) {
      return LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.inputTranscript,
        text: input['text'] as String? ?? '',
        isFinal: true,
      );
    }

    final modelText = _extractModelText(serverContent);
    if (modelText.isNotEmpty) {
      return LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.modelText,
        text: modelText,
        isFinal: true,
      );
    }

    final goAway = json['goAway'] as Map<String, dynamic>?;
    if (goAway != null) {
      return LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.goAway,
        detail: goAway['timeLeft'] as String?,
      );
    }

    final error = json['error'];
    if (error != null) {
      return LiveTranscriptEvent(
        kind: LiveTranscriptEventKind.error,
        detail: switch (error) {
          Map<String, dynamic>() =>
            error['message'] as String? ?? error.toString(),
          _ => error.toString(),
        },
      );
    }

    return null;
  }

  static String _extractModelText(Map<String, dynamic>? serverContent) {
    final modelTurn = serverContent?['modelTurn'] as Map<String, dynamic>?;
    final parts = modelTurn?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      return '';
    }

    final text = parts
        .map((part) => (part as Map<String, dynamic>)['text'] as String? ?? '')
        .where((part) => part.isNotEmpty)
        .join('\n');
    return text.trim();
  }
}
