class TurnItem {
  TurnItem({
    required this.id,
    required this.turnId,
    required this.itemId,
    required this.itemType,
    required this.ordinal,
    required this.payload,
    required this.createdAt,
  });

  factory TurnItem.fromJson(Map<String, dynamic> json) {
    return TurnItem(
      id: json['id'] as String? ?? '',
      turnId: json['turn_id'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      itemType: json['item_type'] as String? ?? 'unknown',
      ordinal: (json['ordinal'] as num? ?? 0).toInt(),
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? {},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  final String id;
  final String turnId;
  final String itemId;
  final String itemType;
  final int ordinal;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  // Helper to extract tokens if available
  int? get tokens {
    final usage = payload['usage'];
    if (usage is Map) {
      final totalTokens = usage['total_tokens'];
      if (totalTokens is num) {
        return totalTokens.toInt();
      }
    }
    return null;
  }
}
