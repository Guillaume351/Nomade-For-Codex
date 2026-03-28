import 'turn_item.dart';

class Turn {
  Turn({
    required this.id,
    required this.conversationId,
    required this.userPrompt,
    this.codexTurnId,
    required this.status,
    this.diff = '',
    this.error,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.items = const [],
  });

  factory Turn.fromJson(Map<String, dynamic> json) {
    return Turn(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      userPrompt: json['user_prompt'] as String? ?? '',
      codexTurnId: json['codex_turn_id'] as String?,
      status: json['status'] as String? ?? 'queued',
      diff: json['diff'] as String? ?? '',
      error: json['error'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      items: (json['items'] as List?)
              ?.map((e) => TurnItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  final String id;
  final String conversationId;
  final String userPrompt;
  final String? codexTurnId;
  final String status;
  final String diff;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final List<TurnItem> items;

  Duration? get duration {
    if (completedAt == null) {
      return null;
    }
    return completedAt!.difference(createdAt);
  }

  int get totalTokens {
    int total = 0;
    for (final item in items) {
      total += item.tokens ?? 0;
    }
    return total;
  }
}
