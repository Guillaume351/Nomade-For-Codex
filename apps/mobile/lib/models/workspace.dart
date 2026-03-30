class Workspace {
  Workspace({
    required this.id,
    required this.agentId,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'];
    final parsedCreatedAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;

    return Workspace(
      id: (json['id'] ?? '').toString(),
      agentId: (json['agent_id'] ?? json['agentId'] ?? '').toString(),
      name: (json['name'] ?? 'Workspace').toString(),
      path: (json['path'] ?? '.').toString(),
      createdAt: parsedCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String agentId;
  final String name;
  final String path;
  final DateTime createdAt;
}
