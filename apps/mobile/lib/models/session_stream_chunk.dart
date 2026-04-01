class SessionStreamChunk {
  SessionStreamChunk({
    required this.sessionId,
    required this.stream,
    required this.data,
    required this.cursor,
    required this.at,
  });

  final String sessionId;
  final String stream;
  final String data;
  final int cursor;
  final DateTime at;
}
