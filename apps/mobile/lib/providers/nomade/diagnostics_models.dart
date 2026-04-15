class ConversationDebugEvent {
  ConversationDebugEvent({
    required this.at,
    required this.type,
    required this.message,
  });

  final DateTime at;
  final String type;
  final String message;
}

class ConversationRuntimeTrace {
  DateTime? requestedAt;
  DateTime? startedAt;
  DateTime? completedAt;
  String? requestedCwd;
  String? requestedModel;
  String? requestedApprovalPolicy;
  String? requestedSandboxMode;
  String? requestedEffort;
  String? threadId;
  String? turnId;
  String? codexTurnId;
  String? turnStatus;
  String? turnError;
  int eventsReceived = 0;
  int eventsRendered = 0;
  int turnsReloadApiCalls = 0;
  int turnsReloadThrottled = 0;
  int turnsReloadSkippedInFlight = 0;
  int socketConnectAttempts = 0;
  int socketConnectSuccess = 0;
  int socketConnectSkips = 0;
  int socketDisconnects = 0;
  int socketReconnectScheduled = 0;
  final Set<String> unsupportedMethods = <String>{};
}
