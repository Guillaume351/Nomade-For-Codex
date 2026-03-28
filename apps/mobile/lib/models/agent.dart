class Agent {
  Agent({
    required this.id,
    required this.displayName,
    required this.isOnline,
    this.lastSeenAt,
    required this.createdAt,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'Unknown Agent',
      isOnline: json['is_online'] == true,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String displayName;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
}
