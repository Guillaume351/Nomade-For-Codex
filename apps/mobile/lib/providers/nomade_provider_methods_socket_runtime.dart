part of 'nomade_provider.dart';

extension NomadeProviderSocketRuntimeMethods on NomadeProvider {
  Future<void> connectSocket() async {
    if (accessToken == null) return;
    final tokenReady = await ensureFreshToken();
    if (!tokenReady || accessToken == null) {
      await logout();
      status = 'Session expired. Please sign in again.';
      _notifyListenersSafe();
      return;
    }
    try {
      await socketSub?.cancel();
      await socket?.sink.close();
      socket = api.openUserSocket(accessToken!);
      socketSub = socket!.stream.listen(
        (raw) => _onSocketEvent(raw),
        onError: (e) => _handleSocketDisconnected('Socket error: $e'),
        onDone: () => _handleSocketDisconnected('Socket closed'),
      );
      realtimeConnected = true;
      reconnectAttempts = 0;
      reconnectTimer?.cancel();
      final conversationId = _selectedConversation?.id;
      if (conversationId != null) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'socket.connected',
          message: 'Realtime stream opened',
        );
        if (activeTurnId != null ||
            _hasRunningTurnForConversation(conversationId)) {
          unawaited(loadTurns(conversationId));
        }
      }
      _notifyListenersSafe();
    } catch (e) {
      _handleSocketDisconnected('Connection failed');
    }
  }

  void _onSocketEvent(dynamic raw, {bool allowPeerRecovery = true}) {
    Map<String, dynamic> event;
    try {
      event = _decodeSocketPayload(raw);
      event = _decodeSocketEventStrict(event);
    } on E2ERuntimeException catch (error) {
      if (error.code == 'e2e_runtime_unavailable') {
        status =
            'Realtime encrypted updates are paused. Complete secure scan to continue.';
        _notifyListenersSafe();
        return;
      }
      if (allowPeerRecovery && error.code == 'e2e_unknown_sender_device') {
        unawaited(_retrySocketEventAfterPeerSync(raw));
        return;
      }
      unawaited(
        _triggerStrictSecurityFailure('e2e_socket_event_rejected',
            cause: error),
      );
      return;
    } catch (error) {
      final conversationId = _selectedConversation?.id;
      if (conversationId != null) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'socket.decode.error',
          message: error.toString(),
        );
      }
      return;
    }
    final type = event['type'] as String?;
    final conversationIdFromEvent = event['conversationId']?.toString() ?? '';
    if (type != null &&
        type.startsWith('conversation.') &&
        conversationIdFromEvent.isNotEmpty) {
      _trackConversationEvent(
        conversationId: conversationIdFromEvent,
        method: type,
        rendered: false,
      );
    }

    if (type == 'session.output') {
      final sessionId = event['sessionId']?.toString();
      final stream = event['stream']?.toString() ?? 'stdout';
      final data = event['data']?.toString() ?? '';
      final cursor = (event['cursor'] as num?)?.toInt() ?? 0;
      if (sessionId != null) {
        final buffer =
            sessionLogsBySession.putIfAbsent(sessionId, StringBuffer.new);
        buffer.write(data);
        sessionChunks.add(SessionStreamChunk(
          sessionId: sessionId,
          stream: stream,
          data: data,
          cursor: cursor,
          at: DateTime.now(),
        ));
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'session.status') {
      final sessionId = event['sessionId']?.toString();
      final statusValue = event['status']?.toString() ?? 'unknown';
      if (sessionId != null) {
        final serviceIndex =
            services.indexWhere((service) => service.session?.id == sessionId);
        if (serviceIndex != -1) {
          final service = services[serviceIndex];
          final nextState =
              statusValue == 'running' ? service.state : 'crashed';
          services[serviceIndex] = service.copyWith(
            runtimeStatus: statusValue,
            state: nextState,
            lastError: statusValue == 'running' ? null : 'session_$statusValue',
          );
        }
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'tunnel.status') {
      final tunnelId = event['tunnelId']?.toString();
      final statusValue = event['status']?.toString() ?? 'unknown';
      final probeStatus = event['probeStatus']?.toString();
      final probeCode = (event['probeCode'] as num?)?.toInt();
      final detail = event['detail']?.toString();
      final probeAt = event['probeAt']?.toString();
      final hasDiagnostic = event.containsKey('diagnostic');
      final rawDiagnostic = event['diagnostic'];
      final diagnostic = rawDiagnostic is Map<String, dynamic>
          ? TunnelDiagnostic.fromJson(rawDiagnostic)
          : rawDiagnostic is Map
              ? TunnelDiagnostic.fromJson(rawDiagnostic.cast<String, dynamic>())
              : null;
      if (tunnelId != null) {
        final tunnelIndex = tunnels.indexWhere((item) => item.id == tunnelId);
        if (tunnelIndex != -1) {
          final current = tunnels[tunnelIndex];
          tunnels[tunnelIndex] = current.copyWith(
            status: statusValue,
            isReachable: probeStatus == 'ok' || statusValue == 'healthy',
            lastProbeStatus: probeStatus,
            lastError: detail,
            lastProbeCode: probeCode,
            lastProbeAt: probeAt != null
                ? DateTime.tryParse(probeAt)
                : current.lastProbeAt,
            diagnostic: diagnostic,
            replaceDiagnostic: hasDiagnostic,
          );
        }

        final serviceIndex =
            services.indexWhere((service) => service.tunnel?.id == tunnelId);
        if (serviceIndex != -1) {
          final service = services[serviceIndex];
          final nextState = statusValue == 'healthy'
              ? 'healthy'
              : statusValue == 'unhealthy'
                  ? 'unhealthy'
                  : statusValue == 'stopped'
                      ? 'stopped'
                      : service.state;
          services[serviceIndex] = service.copyWith(
            state: nextState,
            lastError: detail ?? service.lastError,
          );
        }
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.thread.started') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final threadId = event['threadId']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        if (threadId.isNotEmpty) {
          runtime.threadId = threadId;
          _patchConversationLocal(
            conversationId,
            threadId: threadId,
            status: 'running',
          );
        }
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'thread.started',
          message: 'thread=${threadId.isEmpty ? "-" : threadId}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.thread.started',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.item.started') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId']?.toString() ?? '';
      final itemId = event['itemId']?.toString() ?? '';
      final itemType = event['itemType']?.toString() ?? 'unknown';
      final itemPayload = (event['item'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      if (turnId.isNotEmpty && itemId.isNotEmpty) {
        final timeline = timelineForTurn(turnId);
        final item = timeline.upsertItem(
          itemId: itemId,
          itemType: itemType,
        );
        item.applyStarted(itemType: itemType, payload: itemPayload);
      }

      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'item.started',
          message:
              'turn=${turnId.isEmpty ? "-" : turnId} item=$itemType id=${itemId.isEmpty ? "-" : itemId}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.item.started',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.item.delta') {
      final turnId = event['turnId'] as String?;
      final itemId = event['itemId'] as String?;
      final delta = event['delta'] as String?;
      final stream = event['stream'] as String?;
      final conversationId = event['conversationId']?.toString() ?? '';
      if (turnId != null &&
          delta != null &&
          stream != null &&
          (stream == 'agentMessage' ||
              stream == 'reasoning' ||
              stream == 'plan' ||
              stream == 'commandExecution' ||
              stream == 'fileChange')) {
        final timeline = timelineForTurn(turnId);
        final inferredType = switch (stream) {
          'agentMessage' => 'agentMessage',
          'commandExecution' => 'commandExecution',
          'fileChange' => 'fileChange',
          'plan' => 'plan',
          _ => 'reasoning',
        };
        final timelineItem = timeline.upsertItem(
          itemId: itemId ?? 'delta-${DateTime.now().microsecondsSinceEpoch}',
          itemType: inferredType,
          stream: stream,
        );
        timelineItem.mergeDelta(stream: stream, delta: delta);
        if (conversationId.isNotEmpty) {
          _trackConversationEvent(
            conversationId: conversationId,
            method: 'conversation.item.delta',
            rendered: true,
          );
        }
        _notifyListenersSafe();
      } else if (conversationId.isNotEmpty) {
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.item.delta.${stream ?? "unknown"}',
          rendered: false,
        );
      }
      return;
    } else if (type == 'conversation.item.completed') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId']?.toString() ?? '';
      final itemId = event['itemId']?.toString() ?? '';
      final itemType = event['itemType']?.toString() ?? 'unknown';
      final itemPayload = (event['item'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final threadId = event['threadId']?.toString();
      final codexTurnId = event['codexTurnId']?.toString();

      if (turnId.isNotEmpty && itemId.isNotEmpty) {
        final timeline = timelineForTurn(turnId);
        final item = timeline.upsertItem(
          itemId: itemId,
          itemType: itemType,
        );
        item.applyCompleted(
          itemType: itemType,
          payload: itemPayload,
        );
        final phase = itemPayload['phase']?.toString().toLowerCase();
        if (itemType == 'agentMessage' && phase == 'final_answer') {
          timeline.finalAnswerReceived = true;
          timeline.executionCollapsed = true;
        }
      }

      if (conversationId.isNotEmpty) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        if (turnId.isNotEmpty) {
          runtime.turnId = turnId;
        }
        if (threadId != null && threadId.isNotEmpty) {
          runtime.threadId = threadId;
          _patchConversationLocal(conversationId, threadId: threadId);
        }
        if (codexTurnId != null && codexTurnId.isNotEmpty) {
          runtime.codexTurnId = codexTurnId;
        }
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'item.completed',
          message:
              'turn=${turnId.isEmpty ? "-" : turnId} item=$itemType id=${itemId.isEmpty ? "-" : itemId}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.item.completed',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.turn.plan.updated') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId']?.toString() ?? '';
      final plan = (event['plan'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      if (turnId.isNotEmpty) {
        final timeline = timelineForTurn(turnId);
        final item = timeline.upsertItem(
          itemId: 'plan-$turnId',
          itemType: 'plan',
          stream: 'plan',
        );
        item.applyStarted(itemType: 'plan', payload: plan);
      }
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'turn.plan.updated',
          message: 'turn=$turnId',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.turn.plan.updated',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.thread.status.changed') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final threadId = event['threadId']?.toString().trim() ?? '';
      final turnId = event['turnId']?.toString().trim() ?? '';
      final rawStatus = event['status'];
      final statusValue = switch (rawStatus) {
        String() => rawStatus.trim().toLowerCase(),
        Map() => switch (
              (rawStatus['type']?.toString().trim().toLowerCase() ?? '')) {
            'active' => 'running',
            'idle' => 'completed',
            'systemerror' => 'failed',
            _ => 'unknown',
          },
        _ => 'unknown',
      };
      final thread = (event['thread'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rawThreadName = event['threadName']?.toString().trim() ??
          thread['name']?.toString().trim() ??
          '';
      final nextTitle = rawThreadName.isEmpty
          ? null
          : (rawThreadName.length > 240
              ? '${rawThreadName.substring(0, 240)}...'
              : rawThreadName);
      final nextStatus = statusValue == 'running'
          ? 'running'
          : statusValue == 'completed' || statusValue == 'idle'
              ? 'idle'
              : statusValue == 'interrupted'
                  ? 'interrupted'
                  : statusValue == 'failed'
                      ? 'failed'
                      : null;
      if (conversationId.isNotEmpty) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        if (threadId.isNotEmpty) {
          runtime.threadId = threadId;
        }
        if (turnId.isNotEmpty) {
          runtime.turnId = turnId;
        }
        if (nextStatus == 'running') {
          runtime.turnStatus = 'running';
          runtime.turnError = null;
          runtime.completedAt = null;
        } else if (nextStatus == 'idle' ||
            nextStatus == 'interrupted' ||
            nextStatus == 'failed') {
          runtime.turnStatus = nextStatus == 'idle' ? 'completed' : nextStatus;
          runtime.completedAt = DateTime.now();
          if (nextStatus != 'failed') {
            runtime.turnError = null;
          }
        }

        _patchConversationLocal(
          conversationId,
          status: nextStatus,
          title: nextTitle,
        );

        final effectiveTurnId =
            turnId.isNotEmpty ? turnId : (runtime.turnId?.trim() ?? '');
        if (nextStatus != null && nextStatus != 'running') {
          if (effectiveTurnId.isNotEmpty) {
            final timeline = timelineForTurn(effectiveTurnId);
            timeline.executionCollapsed = true;
          }
          if (selectedConversation?.id == conversationId) {
            if (activeTurnId == null || activeTurnId == effectiveTurnId) {
              activeTurnId = null;
            }
          }
        }

        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'thread.status.changed',
          message: 'status=$statusValue title=${nextTitle ?? "-"}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.thread.status.changed',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.thread.name.updated') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final rawThreadName = event['threadName']?.toString().trim() ?? '';
      final nextTitle = rawThreadName.isEmpty
          ? null
          : (rawThreadName.length > 240
              ? '${rawThreadName.substring(0, 240)}...'
              : rawThreadName);
      if (conversationId.isNotEmpty && nextTitle != null) {
        _patchConversationLocal(
          conversationId,
          title: nextTitle,
        );
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'thread.name.updated',
          message: 'title=$nextTitle',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.thread.name.updated',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'account.rate_limits.updated') {
      final updated = _asStringKeyedMap(event['rateLimits']);
      if (updated != null) {
        codexRateLimits = updated;
        final limitId = updated['limitId']?.toString().trim();
        if (limitId != null && limitId.isNotEmpty) {
          final next =
              Map<String, Map<String, dynamic>>.from(codexRateLimitsByLimitId);
          next[limitId] = updated;
          codexRateLimitsByLimitId = next;
        }
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'codex.sync.updated') {
      final agentId = event['agentId']?.toString();
      final hydratedOrRepaired = (event['hydratedOrRepaired'] as num?)?.toInt();
      final importedConversations =
          (event['importedConversations'] as num?)?.toInt();
      if ((hydratedOrRepaired ?? 0) > 0 || (importedConversations ?? 0) > 0) {
        status = 'Codex sync updated your conversations.';
      }
      unawaited(_refreshAfterCodexSyncEvent(agentId: agentId));
      _notifyListenersSafe();
      return;
    } else if (type == 'codex.sync.error') {
      final message = event['message']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        status = message;
      } else {
        status =
            'Codex sync failed. Re-login Codex on your computer and try again.';
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'notification.event') {
      final eventType = event['eventType']?.toString() ?? 'unknown';
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'notification.$eventType',
          message: 'turn=${turnId.isEmpty ? "-" : turnId}',
        );
      }
      if (eventType == 'quota_available') {
        status = 'Quota available: you can resume queued work.';
      } else if (eventType == 'deferred_turn_started') {
        status = 'Queued turn started.';
      } else if (eventType == 'deferred_turn_completed') {
        status = 'Queued turn completed.';
      } else if (eventType == 'action_required') {
        status = 'Action required on a running turn.';
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.thread.token_usage.updated') {
      final conversationId = event['conversationId']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'thread.token_usage.updated',
          message: 'updated',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.thread.token_usage.updated',
          rendered: true,
        );
      }
      return;
    } else if (type == 'conversation.server.request') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId']?.toString() ?? '';
      final requestId = event['requestId']?.toString() ?? '';
      final method = event['method']?.toString() ?? 'unknown';
      final params = (event['params'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      if (turnId.isNotEmpty && requestId.isNotEmpty) {
        final timeline = timelineForTurn(turnId);
        final item = timeline.upsertItem(
          itemId: 'server-request-$requestId',
          itemType: 'serverRequest',
        );
        item.applyStarted(itemType: 'serverRequest', payload: {
          'conversationId': conversationId,
          'turnId': turnId,
          'requestId': requestId,
          'method': method,
          'params': params,
          'status': 'inProgress',
        });
      }
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'server.request',
          message: 'turn=$turnId request=$requestId method=$method',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.server.request',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.server.request.resolved') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId']?.toString() ?? '';
      final requestId = event['requestId']?.toString() ?? '';
      final statusValue = event['status']?.toString() ?? 'completed';
      final error = event['error']?.toString();
      if (turnId.isNotEmpty && requestId.isNotEmpty) {
        final timeline = timelineForTurn(turnId);
        final item = timeline.upsertItem(
          itemId: 'server-request-$requestId',
          itemType: 'serverRequest',
        );
        item.applyCompleted(itemType: 'serverRequest', payload: {
          'requestId': requestId,
          'status': statusValue,
          if (error != null) 'error': error,
        });
      }
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'server.request.resolved',
          message:
              'turn=$turnId request=$requestId status=$statusValue${error != null ? ' error=$error' : ''}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.server.request.resolved',
          rendered: true,
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.turn.diff.updated') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId'] as String?;
      final diff = event['diff'] as String?;
      if (turnId != null && diff != null) {
        final index = turns.indexWhere((t) => t.id == turnId);
        if (index != -1) {
          // In a real app we'd want to update the Turn object in place
          // but for this UI overhaul we'll rely on the stream buffer or reload
        }
      }
      if (conversationId.isNotEmpty && turnId != null) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'turn.diff.updated',
          message: 'turn=$turnId chars=${diff?.length ?? 0}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.turn.diff.updated',
          rendered: true,
        );
      }
      return;
    } else if (type == 'conversation.turn.completed') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId'] as String?;
      final threadId = event['threadId']?.toString();
      final codexTurnId = event['codexTurnId']?.toString();
      final statusValue = event['status']?.toString() ?? 'failed';
      final error = event['error']?.toString();
      if (conversationId.isNotEmpty) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        if (turnId != null && turnId.isNotEmpty) {
          runtime.turnId = turnId;
        }
        if (threadId != null && threadId.isNotEmpty) {
          runtime.threadId = threadId;
          _patchConversationLocal(conversationId, threadId: threadId);
        }
        if (codexTurnId != null && codexTurnId.isNotEmpty) {
          runtime.codexTurnId = codexTurnId;
        }
        runtime.turnStatus = statusValue;
        runtime.turnError = error;
        runtime.completedAt = DateTime.now();

        final conversationStatus = statusValue == 'completed'
            ? 'idle'
            : statusValue == 'interrupted'
                ? 'interrupted'
                : 'failed';
        _patchConversationLocal(conversationId, status: conversationStatus);
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'turn.completed',
          message:
              'turn=${turnId ?? "-"} status=$statusValue codexTurn=${codexTurnId ?? "-"}${error != null && error.isNotEmpty ? ' error=$error' : ''}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.turn.completed',
          rendered: true,
        );
      }
      if (turnId != null) {
        final timeline = timelineForTurn(turnId);
        timeline.executionCollapsed = true;
        if (activeTurnId == turnId) {
          activeTurnId = null;
        }
        // Reload turns to get metrics and final state
        if (conversationId.isNotEmpty) {
          loadTurns(conversationId);
        } else if (selectedConversation != null) {
          loadTurns(selectedConversation!.id);
        }
        unawaited(
          NativeNotificationsBridge.clearRunningStatus(
            conversationId: conversationId.isNotEmpty
                ? conversationId
                : (selectedConversation?.id ?? ''),
            turnId: turnId,
          ),
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'conversation.turn.started') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final turnId = event['turnId'] as String?;
      final threadId = event['threadId']?.toString();
      final codexTurnId = event['codexTurnId']?.toString();
      if (conversationId.isNotEmpty) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        if (turnId != null && turnId.isNotEmpty) {
          runtime.turnId = turnId;
        }
        if (threadId != null && threadId.isNotEmpty) {
          runtime.threadId = threadId;
          _patchConversationLocal(
            conversationId,
            threadId: threadId,
            status: 'running',
          );
        }
        if (codexTurnId != null && codexTurnId.isNotEmpty) {
          runtime.codexTurnId = codexTurnId;
        }
        runtime.turnStatus = 'running';
        runtime.turnError = null;
        runtime.startedAt = DateTime.now();
        runtime.completedAt = null;
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'turn.started',
          message:
              'turn=${turnId ?? "-"} codexTurn=${codexTurnId ?? "-"} thread=${threadId ?? "-"}',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.turn.started',
          rendered: true,
        );
      }
      if (turnId != null) {
        activeTurnId = turnId;
        final timeline = timelineForTurn(turnId);
        timeline.executionCollapsed = false;
        timeline.finalAnswerReceived = false;
        final conversationTitle = _findConversationById(conversationId)?.title;
        unawaited(
          NativeNotificationsBridge.setRunningStatus(
            conversationId: conversationId,
            turnId: turnId,
            title: conversationTitle,
            subtitle: selectedWorkspace?.name,
          ),
        );
      }
      _notifyListenersSafe();
      return;
    } else if (type == 'error') {
      final conversationId = selectedConversation?.id;
      if (conversationId != null) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'socket.error',
          message:
              'code=${event['code']?.toString() ?? "-"} message=${event['message']?.toString() ?? "-"}',
        );
      }
      _notifyListenersSafe();
      return;
    }
    // Handle other events...
  }

  Future<void> _retrySocketEventAfterPeerSync(dynamic raw) async {
    final synced = await _syncE2EPeersFromServer();
    if (!synced) {
      final decoded = _safeDecodeSocketPayload(raw);
      final conversationId = decoded?['conversationId']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'socket.peer_sync.noop',
          message: 'unknown sender device, no peer update from server',
        );
      }
      return;
    }
    _onSocketEvent(raw, allowPeerRecovery: false);
  }

  Map<String, dynamic>? _safeDecodeSocketPayload(dynamic raw) {
    try {
      return _decodeSocketPayload(raw);
    } catch (_) {
      return null;
    }
  }

  void _handleSocketDisconnected(String reason) {
    if (accessToken == null) {
      return;
    }
    realtimeConnected = false;
    status = reason;
    final conversationId = _selectedConversation?.id;
    if (conversationId != null) {
      _appendConversationDebugEvent(
        conversationId: conversationId,
        type: 'socket.disconnected',
        message: reason,
      );
    }
    _notifyListenersSafe();
    _scheduleSocketReconnect();
  }

  bool _hasRunningTurnForConversation(String conversationId) {
    for (final turn in turns) {
      if (turn.conversationId != conversationId) {
        continue;
      }
      if (_turnCountsAsRunning(turn)) {
        return true;
      }
    }
    return false;
  }

  bool _turnCountsAsRunning(Turn turn) {
    if (turn.status == 'running') {
      return true;
    }
    if (turn.status != 'queued') {
      return false;
    }
    return turn.deliveryState != 'deferred';
  }

  void _scheduleSocketReconnect() {
    reconnectTimer?.cancel();
    reconnectAttempts += 1;
    final backoffSec = (1 << (reconnectAttempts - 1)).clamp(1, 20);
    reconnectTimer = Timer(Duration(seconds: backoffSec), () async {
      if (accessToken == null || realtimeConnected) {
        return;
      }
      await connectSocket();
    });
  }
}
