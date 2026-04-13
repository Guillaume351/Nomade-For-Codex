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
  final Set<String> unsupportedMethods = <String>{};
}
