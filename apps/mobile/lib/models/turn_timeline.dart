enum TurnTimelineItemStatus {
  inProgress,
  completed,
  failed,
  declined,
}

TurnTimelineItemStatus timelineStatusFromRaw(String rawStatus) {
  switch (rawStatus.trim().toLowerCase()) {
    case 'completed':
    case 'ok':
      return TurnTimelineItemStatus.completed;
    case 'declined':
      return TurnTimelineItemStatus.declined;
    case 'failed':
    case 'error':
      return TurnTimelineItemStatus.failed;
    default:
      return TurnTimelineItemStatus.inProgress;
  }
}

class TurnTimelineItem {
  TurnTimelineItem({
    required this.turnId,
    required this.itemId,
    required this.itemType,
    this.stream,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String turnId;
  final String itemId;
  String itemType;
  String? stream;
  DateTime startedAt;
  DateTime? completedAt;
  TurnTimelineItemStatus status = TurnTimelineItemStatus.inProgress;
  Map<String, dynamic> payload = {};

  final StringBuffer _deltaBuffer = StringBuffer();
  final StringBuffer _outputBuffer = StringBuffer();

  bool get isCommandExecution =>
      itemType == 'commandExecution' || stream == 'commandExecution';
  bool get isFileChange => itemType == 'fileChange' || stream == 'fileChange';
  bool get isReasoning => itemType == 'reasoning' || stream == 'reasoning';
  bool get isPlan => itemType == 'plan' || stream == 'plan';
  bool get isAgentMessage =>
      itemType == 'agentMessage' || stream == 'agentMessage';

  String get textDelta => _deltaBuffer.toString();
  String get outputDelta => _outputBuffer.toString();
  String get command => payload['command']?.toString() ?? '';
  String get cwd => payload['cwd']?.toString() ?? '';
  String get statusLabel => payload['status']?.toString() ?? status.name;

  int? get exitCode {
    final raw = payload['exitCode'];
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }

  int? get durationMs {
    final raw = payload['durationMs'];
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }

  String get aggregatedOutput {
    final persisted = payload['aggregatedOutput'];
    if (persisted is String && persisted.isNotEmpty) {
      return persisted;
    }
    return _outputBuffer.toString();
  }

  void mergeDelta({
    required String stream,
    required String delta,
  }) {
    this.stream = stream;
    if (_deltaBuffer.isNotEmpty) {
      _deltaBuffer.write('');
    }
    _deltaBuffer.write(delta);
    if (stream == 'commandExecution' || stream == 'fileChange') {
      _outputBuffer.write(delta);
    }
  }

  void applyStarted({
    required String itemType,
    Map<String, dynamic>? payload,
  }) {
    this.itemType = itemType;
    status = TurnTimelineItemStatus.inProgress;
    if (payload != null && payload.isNotEmpty) {
      this.payload = payload;
    }
    startedAt = DateTime.now();
    completedAt = null;
  }

  void applyCompleted({
    required String itemType,
    required Map<String, dynamic> payload,
  }) {
    this.itemType = itemType;
    this.payload = {
      ...this.payload,
      ...payload,
    };
    final rawStatus = payload['status']?.toString() ?? 'completed';
    status = timelineStatusFromRaw(rawStatus);
    completedAt = DateTime.now();
    if ((payload['aggregatedOutput'] == null ||
            (payload['aggregatedOutput'] as String?)?.isEmpty == true) &&
        _outputBuffer.isNotEmpty) {
      this.payload = {
        ...this.payload,
        'aggregatedOutput': _outputBuffer.toString(),
      };
    }
  }
}

class TurnTimeline {
  TurnTimeline({required this.turnId});

  final String turnId;
  final Map<String, TurnTimelineItem> _itemsById = {};
  final List<String> _orderedItemIds = [];

  int receivedEvents = 0;
  int renderedEvents = 0;
  bool finalAnswerReceived = false;
  bool executionCollapsed = false;

  List<TurnTimelineItem> get items => _orderedItemIds
      .map((itemId) => _itemsById[itemId])
      .whereType<TurnTimelineItem>()
      .toList(growable: false);

  List<TurnTimelineItem> get commandItems =>
      items.where((item) => item.isCommandExecution).toList(growable: false);

  TurnTimelineItem upsertItem({
    required String itemId,
    required String itemType,
    String? stream,
  }) {
    final existing = _itemsById[itemId];
    if (existing != null) {
      existing.itemType = itemType;
      if (stream != null && stream.isNotEmpty) {
        existing.stream = stream;
      }
      return existing;
    }
    final created = TurnTimelineItem(
      turnId: turnId,
      itemId: itemId,
      itemType: itemType,
      stream: stream,
    );
    _itemsById[itemId] = created;
    _orderedItemIds.add(itemId);
    return created;
  }
}
