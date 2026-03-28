class Workspace {
  Workspace({
    required this.id,
    required this.agentId,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      agentId: json['agent_id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String agentId;
  final String name;
  final String path;
  final DateTime createdAt;
}
