class Conversation {
  Conversation({
    required this.id,
    required this.userId,
    required this.workspaceId,
    required this.agentId,
    required this.title,
    required this.status,
    this.codexThreadId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      workspaceId: json['workspace_id'] as String,
      agentId: json['agent_id'] as String,
      title: json['title'] as String? ?? 'New Conversation',
      status: json['status'] as String? ?? 'idle',
      codexThreadId: json['codex_thread_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final String userId;
  final String workspaceId;
  final String agentId;
  final String title;
  final String status;
  final String? codexThreadId;
  final DateTime createdAt;
  final DateTime updatedAt;
}
