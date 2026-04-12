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
    this.deliveryPolicy = 'immediate',
    this.deliveryState = 'pending',
    this.deliveryAttempts = 0,
    this.deliveryError,
    this.nextDeliveryAt,
    this.items = const [],
  });

  factory Turn.fromJson(Map<String, dynamic> json) {
    final rawAttempts = json['delivery_attempts'] ?? json['deliveryAttempts'];
    final deliveryAttempts = rawAttempts is num
        ? rawAttempts.toInt()
        : int.tryParse(rawAttempts?.toString() ?? '') ?? 0;
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
      deliveryPolicy: (json['delivery_policy'] ?? json['deliveryPolicy']) as String? ??
          'immediate',
      deliveryState:
          (json['delivery_state'] ?? json['deliveryState']) as String? ?? 'pending',
      deliveryAttempts: deliveryAttempts,
      deliveryError: (json['delivery_error'] ?? json['deliveryError']) as String?,
      nextDeliveryAt: (json['next_delivery_at'] ?? json['nextDeliveryAt']) != null
          ? DateTime.tryParse(
              (json['next_delivery_at'] ?? json['nextDeliveryAt']) as String,
            )
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
  final String deliveryPolicy;
  final String deliveryState;
  final int deliveryAttempts;
  final String? deliveryError;
  final DateTime? nextDeliveryAt;
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
