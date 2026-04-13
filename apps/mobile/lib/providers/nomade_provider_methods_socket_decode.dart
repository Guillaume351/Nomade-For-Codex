part of 'nomade_provider.dart';

extension NomadeProviderSocketDecodeMethods on NomadeProvider {
  Map<String, dynamic> _decodeSocketPayload(dynamic raw) {
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }

    String payload;
    if (raw is String) {
      payload = raw;
    } else if (raw is Uint8List) {
      payload = utf8.decode(raw);
    } else if (raw is ByteBuffer) {
      payload = utf8.decode(raw.asUint8List());
    } else if (raw is List<int>) {
      payload = utf8.decode(raw);
    } else {
      throw FormatException(
          'unsupported socket payload type: ${raw.runtimeType}');
    }

    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('socket payload is not a JSON object');
    }
    return decoded.cast<String, dynamic>();
  }

  String _decryptEnvelopeToString({
    required String scope,
    required Map<String, dynamic> envelope,
    bool enforceReplayProtection = true,
  }) {
    final runtime = _e2eRuntime;
    if (runtime == null || !runtime.isReady) {
      throw const E2ERuntimeException('e2e_runtime_unavailable');
    }
    return runtime.decryptEnvelope(
      scope: scope,
      envelope: envelope,
      enforceReplayProtection: enforceReplayProtection,
    );
  }

  Map<String, dynamic> _decryptEnvelopeToObject({
    required String scope,
    required Map<String, dynamic> envelope,
    bool enforceReplayProtection = true,
  }) {
    final plaintext = _decryptEnvelopeToString(
      scope: scope,
      envelope: envelope,
      enforceReplayProtection: enforceReplayProtection,
    ).trim();
    if (plaintext.isEmpty) {
      return <String, dynamic>{};
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (_) {
      throw const E2ERuntimeException('e2e_payload_invalid_json');
    }
    if (decoded is! Map) {
      throw const E2ERuntimeException('e2e_payload_invalid_json');
    }
    return decoded.cast<String, dynamic>();
  }

  bool _eventRequiresE2EEnvelope(String type) {
    switch (type) {
      case 'session.output':
      case 'conversation.turn.diff.updated':
      case 'conversation.item.started':
      case 'conversation.item.delta':
      case 'conversation.item.completed':
      case 'conversation.turn.plan.updated':
      case 'conversation.server.request':
      case 'conversation.server.request.resolved':
        return true;
      default:
        return false;
    }
  }

  Turn _decryptTurnForUi(Turn turn) {
    final scope = 'conversation:${turn.conversationId}';
    const replaySafeForHistory = false;
    var userPrompt = turn.userPrompt;
    if (userPrompt.trim().isNotEmpty) {
      final parsedPrompt = _tryParseJsonObject(userPrompt);
      if (parsedPrompt == null) {
        throw const E2ERuntimeException('e2e_turn_prompt_missing_envelope');
      }
      final promptEnvelope = _parseEnvelopeMap(parsedPrompt);
      if (promptEnvelope == null) {
        throw const E2ERuntimeException('e2e_turn_prompt_invalid_envelope');
      }
      final promptPlain = _decryptEnvelopeToString(
        scope: scope,
        envelope: promptEnvelope,
        enforceReplayProtection: replaySafeForHistory,
      );
      final promptParsed = _tryParseJsonObject(promptPlain);
      if (promptParsed != null && promptParsed['prompt'] != null) {
        userPrompt = promptParsed['prompt']?.toString() ?? '';
      } else {
        userPrompt = promptPlain;
      }
    }

    var diff = turn.diff;
    if (diff.trim().isNotEmpty) {
      final parsedDiff = _tryParseJsonObject(diff);
      if (parsedDiff == null) {
        throw const E2ERuntimeException('e2e_turn_diff_missing_envelope');
      }
      final nestedRaw = parsedDiff['e2eEnvelope'];
      final nestedEnvelope = nestedRaw is Map
          ? _parseEnvelopeMap(nestedRaw.cast<String, dynamic>())
          : null;
      final diffEnvelope = nestedEnvelope ?? _parseEnvelopeMap(parsedDiff);
      if (diffEnvelope == null) {
        throw const E2ERuntimeException('e2e_turn_diff_invalid_envelope');
      }
      final diffPayload = _decryptEnvelopeToObject(
        scope: scope,
        envelope: diffEnvelope,
        enforceReplayProtection: replaySafeForHistory,
      );
      diff = diffPayload['diff']?.toString() ?? '';
    }

    final decryptedItems = <TurnItem>[];
    for (final item in turn.items) {
      final nestedRaw = item.payload['e2eEnvelope'];
      final nestedEnvelope = nestedRaw is Map
          ? _parseEnvelopeMap(nestedRaw.cast<String, dynamic>())
          : null;
      final envelope = nestedEnvelope ?? _parseEnvelopeMap(item.payload);
      if (envelope == null) {
        throw const E2ERuntimeException('e2e_turn_item_missing_envelope');
      }
      final itemPayload = _decryptEnvelopeToObject(
        scope: scope,
        envelope: envelope,
        enforceReplayProtection: replaySafeForHistory,
      );
      final value = itemPayload['item'];
      final normalizedPayload = value is Map
          ? value.cast<String, dynamic>()
          : itemPayload.cast<String, dynamic>();
      decryptedItems.add(
        TurnItem(
          id: item.id,
          turnId: item.turnId,
          itemId: item.itemId,
          itemType: item.itemType,
          ordinal: item.ordinal,
          payload: normalizedPayload,
          createdAt: item.createdAt,
        ),
      );
    }

    return Turn(
      id: turn.id,
      conversationId: turn.conversationId,
      userPrompt: userPrompt,
      codexTurnId: turn.codexTurnId,
      status: turn.status,
      diff: diff,
      error: turn.error,
      deliveryPolicy: turn.deliveryPolicy,
      deliveryState: turn.deliveryState,
      deliveryAttempts: turn.deliveryAttempts,
      deliveryError: turn.deliveryError,
      nextDeliveryAt: turn.nextDeliveryAt,
      createdAt: turn.createdAt,
      updatedAt: turn.updatedAt,
      completedAt: turn.completedAt,
      items: decryptedItems,
    );
  }

  Map<String, dynamic> _decodeSocketEventStrict(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if (!_eventRequiresE2EEnvelope(type)) {
      return event;
    }
    final envelope = _parseEnvelopeMap(event['e2eEnvelope']);
    if (envelope == null) {
      throw const E2ERuntimeException('e2e_event_missing_envelope');
    }

    if (type == 'session.output') {
      final sessionId = event['sessionId']?.toString() ?? '';
      if (sessionId.isEmpty) {
        throw const E2ERuntimeException('e2e_session_scope_missing');
      }
      event['data'] = _decryptEnvelopeToString(
        scope: 'session:$sessionId',
        envelope: envelope,
      );
      return event;
    }

    final conversationId = event['conversationId']?.toString() ?? '';
    if (conversationId.isEmpty) {
      throw const E2ERuntimeException('e2e_conversation_scope_missing');
    }
    final scope = 'conversation:$conversationId';
    final payload = _decryptEnvelopeToObject(scope: scope, envelope: envelope);

    if (type == 'conversation.turn.diff.updated') {
      event['diff'] = payload['diff']?.toString() ?? '';
      return event;
    }
    if (type == 'conversation.item.started' ||
        type == 'conversation.item.completed') {
      final item = payload['item'];
      if (item is! Map) {
        throw const E2ERuntimeException('e2e_event_item_missing');
      }
      event['item'] = item.cast<String, dynamic>();
      return event;
    }
    if (type == 'conversation.item.delta') {
      event['delta'] = payload['delta']?.toString() ?? '';
      final stream = payload['stream']?.toString();
      if (stream != null && stream.isNotEmpty) {
        event['stream'] = stream;
      }
      return event;
    }
    if (type == 'conversation.turn.plan.updated') {
      final plan = payload['plan'];
      if (plan is! Map) {
        throw const E2ERuntimeException('e2e_event_plan_missing');
      }
      event['plan'] = plan.cast<String, dynamic>();
      return event;
    }
    if (type == 'conversation.server.request') {
      final params = payload['params'];
      if (params is! Map) {
        throw const E2ERuntimeException('e2e_event_params_missing');
      }
      event['params'] = params.cast<String, dynamic>();
      return event;
    }
    if (type == 'conversation.server.request.resolved') {
      if (payload.containsKey('status')) {
        event['status'] = payload['status'];
      }
      if (payload.containsKey('result')) {
        event['result'] = payload['result'];
      }
      if (payload.containsKey('error')) {
        event['error'] = payload['error'];
      }
      return event;
    }
    return event;
  }

  void _hydrateTimelineFromTurn(Turn turn) {
    final timeline = timelineForTurn(turn.id);
    for (final item in turn.items) {
      final itemId = item.itemId.isNotEmpty ? item.itemId : item.id;
      if (itemId.isEmpty) {
        continue;
      }
      final timelineItem = timeline.upsertItem(
        itemId: itemId,
        itemType: item.itemType,
      );
      timelineItem.applyCompleted(
        itemType: item.itemType,
        payload: item.payload,
      );
      if (item.itemType == 'agentMessage') {
        final phase = item.payload['phase']?.toString().toLowerCase();
        if (phase == 'final_answer') {
          timeline.finalAnswerReceived = true;
        }
      }
    }
    if (turn.status != 'running') {
      timeline.executionCollapsed = true;
    }
  }

  void _appendConversationDebugEvent({
    required String conversationId,
    required String type,
    required String message,
  }) {
    if (conversationId.isEmpty) {
      return;
    }
    final events = _debugEventsByConversation.putIfAbsent(
      conversationId,
      () => <ConversationDebugEvent>[],
    );
    events.add(
      ConversationDebugEvent(
        at: DateTime.now(),
        type: type,
        message: message,
      ),
    );
    const maxEvents = 80;
    if (events.length > maxEvents) {
      events.removeRange(0, events.length - maxEvents);
    }
  }

  Conversation? _findConversationById(String conversationId) {
    if (conversationId.isEmpty) {
      return null;
    }
    for (final conversation in conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    final selected = _selectedConversation;
    if (selected != null && selected.id == conversationId) {
      return selected;
    }
    return null;
  }

  void _sortConversationsByActivity() {
    conversations.sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) {
        return byUpdated;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  List<Workspace> sortWorkspacesForDisplay(Iterable<Workspace> source) {
    final values = source.toList(growable: false);
    values.sort((a, b) {
      switch (_listSortMode) {
        case 'oldest':
          return a.createdAt.compareTo(b.createdAt);
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'latest':
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });
    return values;
  }

  List<Conversation> sortConversationsForDisplay(
    Iterable<Conversation> source,
  ) {
    final values = source.toList(growable: false);
    values.sort((a, b) {
      switch (_listSortMode) {
        case 'oldest':
          final byUpdated = a.updatedAt.compareTo(b.updatedAt);
          if (byUpdated != 0) {
            return byUpdated;
          }
          return a.createdAt.compareTo(b.createdAt);
        case 'name':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'latest':
        default:
          final byUpdated = b.updatedAt.compareTo(a.updatedAt);
          if (byUpdated != 0) {
            return byUpdated;
          }
          return b.createdAt.compareTo(a.createdAt);
      }
    });
    return values;
  }

  @visibleForTesting
  String? findCollaborationModeSlugByKind(String modeKind) {
    return NomadeCodexUtils.findCollaborationModeSlugByKind(
      collaborationModes: codexCollaborationModes,
      modeKind: modeKind,
    );
  }

  bool isPlanModeSelected() {
    return NomadeCodexUtils.isPlanModeSelected(
      collaborationModes: codexCollaborationModes,
      selectedSlug: _selectedCollaborationModeSlug,
    );
  }

  void selectCollaborationModeByKind(String modeKind) {
    final slug = NomadeCodexUtils.findCollaborationModeSlugByKind(
      collaborationModes: codexCollaborationModes,
      modeKind: modeKind,
    );
    if (slug == null) {
      return;
    }
    selectedCollaborationModeSlug = slug;
  }

  void _patchConversationLocal(
    String conversationId, {
    String? threadId,
    String? status,
    String? title,
  }) {
    if (conversationId.isEmpty) {
      return;
    }
    final idx = conversations
        .indexWhere((conversation) => conversation.id == conversationId);
    if (idx == -1) {
      return;
    }
    final current = conversations[idx];
    final updated = Conversation(
      id: current.id,
      userId: current.userId,
      workspaceId: current.workspaceId,
      agentId: current.agentId,
      title: title ?? current.title,
      status: status ?? current.status,
      codexThreadId: threadId ?? current.codexThreadId,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    conversations[idx] = updated;
    final selectedId = _selectedConversation?.id;
    _sortConversationsByActivity();
    if (selectedId != null) {
      for (final conversation in conversations) {
        if (conversation.id == selectedId) {
          _selectedConversation = conversation;
          break;
        }
      }
    }
  }
}
