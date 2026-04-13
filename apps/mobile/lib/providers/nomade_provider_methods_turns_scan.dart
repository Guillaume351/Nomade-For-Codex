part of 'nomade_provider.dart';

extension NomadeProviderTurnsAndScanMethods on NomadeProvider {
  Future<void> sendPrompt(
    String prompt, {
    String? deliveryPolicyOverride,
    List<Map<String, dynamic>>? extraInputItems,
  }) async {
    if (accessToken == null) return;

    try {
      final commandResolution =
          NomadeCodexUtils.resolvePromptSlashCommand(prompt);
      final modeKindFromCommand = commandResolution.collaborationModeKind;
      final modeSlugFromCommand = modeKindFromCommand == null
          ? null
          : NomadeCodexUtils.findCollaborationModeSlugByKind(
              collaborationModes: codexCollaborationModes,
              modeKind: modeKindFromCommand,
            );
      if (modeSlugFromCommand != null &&
          modeSlugFromCommand != _selectedCollaborationModeSlug) {
        _selectedCollaborationModeSlug = modeSlugFromCommand;
        unawaited(persistSession());
      }
      final effectivePrompt = commandResolution.prompt;
      if (commandResolution.commandDetected && effectivePrompt.isEmpty) {
        if (modeSlugFromCommand == null && modeKindFromCommand != null) {
          status = 'Requested mode "$modeKindFromCommand" is unavailable.';
        } else if (modeKindFromCommand == 'plan') {
          status = 'Plan mode selected. Send your next prompt.';
        } else if (modeKindFromCommand == 'default') {
          status = 'Default mode selected. Send your next prompt.';
        } else {
          status = 'Command applied.';
        }
        _notifyListenersSafe();
        return;
      }

      if (selectedWorkspace == null) {
        final ready = await createDefaultWorkspace();
        if (!ready) {
          status = 'No workspace available';
          _notifyListenersSafe();
          return;
        }
      }

      if (selectedConversation == null) {
        final created = await createConversation(
          title: effectivePrompt.split('\n').first.trim(),
        );
        if (!created) {
          status = 'Unable to create conversation';
          _notifyListenersSafe();
          return;
        }
      }

      final requestedAt = DateTime.now();
      final conversationId = selectedConversation!.id;
      final requestedCwd = selectedWorkspace?.path;
      final requestedApproval = selectedApprovalPolicy;
      final requestedSandbox = selectedSandboxMode;
      final selectedMode = codexCollaborationModes.firstWhere(
        (entry) =>
            entry['slug']?.toString() ==
            NomadeCodexUtils.normalizeString(_selectedCollaborationModeSlug),
        orElse: () => const <String, dynamic>{},
      );
      final selectedModeMask = selectedMode['modeMask'] is Map
          ? (selectedMode['modeMask'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final modeMaskModel = NomadeCodexUtils.normalizeString(
        selectedMode['model'] ?? selectedModeMask['model'],
      );
      final codexDefaultModel = codexModels.isEmpty
          ? null
          : NomadeCodexUtils.normalizeString(codexModels.first['model']);
      final modeMaskEffort = NomadeCodexUtils.normalizeReasoningEffort(
        selectedMode['reasoningEffort'] ?? selectedModeMask['reasoning_effort'],
      );
      final requestedModel =
          NomadeCodexUtils.normalizeString(selectedModel) ??
              modeMaskModel ??
              codexDefaultModel;
      final requestedEffort =
          NomadeCodexUtils.normalizeReasoningEffort(selectedEffort) ??
              modeMaskEffort;
      final normalizedPolicyOverride = deliveryPolicyOverride?.trim();
      final effectiveDeliveryPolicy = normalizedPolicyOverride ==
                  'defer_if_offline' ||
              normalizedPolicyOverride == 'immediate'
          ? normalizedPolicyOverride
          : (_offlineTurnDefault == 'defer' ? 'defer_if_offline' : 'immediate');
      if (effectiveDeliveryPolicy == 'defer_if_offline' &&
          !canUseDeferredTurns) {
        status = 'Queued execution is not available on your current plan.';
        _notifyListenersSafe();
        return;
      }
      final e2eRuntime = _e2eRuntime;
      if (e2eRuntime == null || !e2eRuntime.isReady) {
        status =
            'Secure scan required before sending messages. Tap the shield icon to approve secure scan.';
        _notifyListenersSafe();
        return;
      }
      // Always refresh the realtime socket before a new turn to avoid stale
      // half-open mobile websocket sessions that can miss turn events.
      await connectSocket();

      _appendConversationDebugEvent(
        conversationId: conversationId,
        type: 'turn.create.request',
        message:
            'cwd=${requestedCwd ?? "-"} sandbox=${requestedSandbox ?? "-"} approval=${requestedApproval ?? "-"} model=${requestedModel ?? "-"} effort=${requestedEffort ?? "-"} delivery=$effectiveDeliveryPolicy collaboration=${modeSlugFromCommand ?? _selectedCollaborationModeSlug ?? "-"} skills=${_selectedSkillPaths.length}',
      );

      final inputItems = <Map<String, dynamic>>[
        {
          'type': 'text',
          'text': effectivePrompt,
        },
      ];
      for (final skillPath in _selectedSkillPaths) {
        final skill = codexSkills.firstWhere(
          (entry) => entry['path']?.toString() == skillPath,
          orElse: () => {'path': skillPath},
        );
        inputItems.add({
          'type': 'skill',
          'path': skillPath,
          if ((skill['name']?.toString() ?? '').isNotEmpty)
            'name': skill['name']?.toString(),
        });
      }
      final normalizedExtraItems = extraInputItems
              ?.whereType<Map<String, dynamic>>()
              .map(NomadeCodexUtils.normalizeOutgoingInputItem)
              .whereType<Map<String, dynamic>>()
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      if (normalizedExtraItems.isNotEmpty) {
        inputItems.addAll(normalizedExtraItems);
      }

      final collaborationMode =
          NomadeCodexUtils.buildSelectedCollaborationModePayload(
        collaborationModes: codexCollaborationModes,
        selectedSlug: modeSlugFromCommand ?? _selectedCollaborationModeSlug,
      );

      Map<String, dynamic> e2ePromptEnvelope;
      try {
        e2ePromptEnvelope = e2eRuntime.encryptEnvelope(
          scope: 'conversation:$conversationId',
          plaintext: jsonEncode({
            'prompt': effectivePrompt,
            'inputItems': inputItems,
          }),
        );
      } on E2ERuntimeException catch (error) {
        if (error.code == 'e2e_runtime_unavailable') {
          status =
              'Secure scan required before sending messages. Tap the shield icon to approve secure scan.';
          _notifyListenersSafe();
          return;
        }
        await _triggerStrictSecurityFailure('e2e_prompt_encrypt_failed',
            cause: error);
        return;
      } catch (error) {
        await _triggerStrictSecurityFailure('e2e_prompt_encrypt_failed',
            cause: error);
        return;
      }
      unawaited(_persistE2ERuntime());

      final turn = await api.createTurn(
        accessToken: accessToken!,
        conversationId: conversationId,
        e2ePromptEnvelope: e2ePromptEnvelope,
        collaborationMode: collaborationMode,
        model: requestedModel,
        cwd: requestedCwd,
        approvalPolicy: requestedApproval,
        sandboxMode: requestedSandbox,
        effort: requestedEffort,
        deliveryPolicy: effectiveDeliveryPolicy,
      );

      final createdTurnId = turn['id'] as String?;
      final createdDeliveryState = turn['delivery_state']?.toString() ?? '';
      activeTurnId = createdDeliveryState == 'deferred' ? null : createdTurnId;
      final runtime = _runtimeByConversation.putIfAbsent(
          conversationId, () => ConversationRuntimeTrace());
      runtime.requestedAt = requestedAt;
      runtime.requestedCwd = requestedCwd;
      runtime.requestedModel = requestedModel;
      runtime.requestedApprovalPolicy = requestedApproval;
      runtime.requestedSandboxMode = requestedSandbox;
      runtime.requestedEffort = requestedEffort;
      runtime.turnId = createdTurnId;
      runtime.turnStatus = 'queued';
      runtime.turnError =
          createdDeliveryState == 'deferred' ? 'deferred_agent_offline' : null;
      runtime.startedAt = null;
      runtime.completedAt = null;

      _appendConversationDebugEvent(
        conversationId: conversationId,
        type: 'turn.create.accepted',
        message:
            'turn=${createdTurnId ?? "-"} deliveryState=${createdDeliveryState.isEmpty ? "-" : createdDeliveryState}',
      );

      if (createdDeliveryState == 'deferred') {
        _patchConversationLocal(conversationId, status: 'queued');
        status = 'Turn queued and will run when your agent reconnects.';
      }

      await loadTurns(conversationId);
    } on ApiException catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      final conversationId = selectedConversation?.id;
      if (conversationId != null) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        runtime.turnStatus = 'failed';
        runtime.turnError = e.errorCode ?? e.message;
        runtime.completedAt = DateTime.now();
        if (e.errorCode == 'agent_offline') {
          _patchConversationLocal(conversationId, status: 'failed');
          _appendConversationDebugEvent(
            conversationId: conversationId,
            type: 'turn.create.rejected',
            message:
                'agent_offline: turn stored locally but not executed on Codex',
          );
        } else {
          _appendConversationDebugEvent(
            conversationId: conversationId,
            type: 'turn.create.error',
            message: e.message,
          );
        }
        await loadTurns(conversationId);
      }
      status = 'Error: ${e.message}';
      _notifyListenersSafe();
    } catch (e) {
      final conversationId = selectedConversation?.id;
      if (conversationId != null) {
        final runtime = _runtimeByConversation.putIfAbsent(
          conversationId,
          () => ConversationRuntimeTrace(),
        );
        runtime.turnStatus = 'failed';
        runtime.turnError = e.toString();
        runtime.completedAt = DateTime.now();
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'turn.create.error',
          message: e.toString(),
        );
        await loadTurns(conversationId);
      }
      status = 'Error: $e';
      _notifyListenersSafe();
    }
  }

  Future<MobileDeviceIdentity> _ensureScanDeviceIdentity() async {
    final existing = MobileDeviceIdentity(
      deviceId: await _readStorage(NomadeProvider._scanDeviceIdKey,
              strictDeviceOnly: true) ??
          '',
      encPublicKey: await _readStorage(NomadeProvider._scanEncPublicKey,
              strictDeviceOnly: true) ??
          '',
      encPrivateKey: await _readStorage(NomadeProvider._scanEncPrivateKey,
              strictDeviceOnly: true) ??
          '',
      signPublicKey: await _readStorage(NomadeProvider._scanSignPublicKey,
              strictDeviceOnly: true) ??
          '',
      signPrivateKey: await _readStorage(NomadeProvider._scanSignPrivateKey,
              strictDeviceOnly: true) ??
          '',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    if (existing.deviceId.isNotEmpty &&
        existing.encPublicKey.isNotEmpty &&
        existing.encPrivateKey.isNotEmpty &&
        existing.signPublicKey.isNotEmpty &&
        existing.signPrivateKey.isNotEmpty) {
      return existing;
    }

    final created = await MobileE2ERuntime.generateDeviceIdentity();
    await Future.wait([
      _writeStorage(
        NomadeProvider._scanDeviceIdKey,
        value: created.deviceId,
        strictDeviceOnly: true,
      ),
      _writeStorage(
        NomadeProvider._scanEncPublicKey,
        value: created.encPublicKey,
        strictDeviceOnly: true,
      ),
      _writeStorage(
        NomadeProvider._scanEncPrivateKey,
        value: created.encPrivateKey,
        strictDeviceOnly: true,
      ),
      _writeStorage(
        NomadeProvider._scanSignPublicKey,
        value: created.signPublicKey,
        strictDeviceOnly: true,
      ),
      _writeStorage(
        NomadeProvider._scanSignPrivateKey,
        value: created.signPrivateKey,
        strictDeviceOnly: true,
      ),
    ]);
    return created;
  }

  String? _scanScopeFromPayload(String? scanPayload) {
    final raw = scanPayload?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parts = raw.split('.');
    if (parts.length < 2) {
      return null;
    }
    try {
      final claims = jsonDecode(utf8.decode(fromBase64Url(parts[1])))
          as Map<String, dynamic>;
      final deviceCode = claims['deviceCode']?.toString() ?? '';
      if (deviceCode.isEmpty) {
        return null;
      }
      return 'scan:$deviceCode';
    } catch (_) {
      return null;
    }
  }

  String? _scanScopeFromBundle(Map<String, dynamic> bundle) {
    try {
      final decodedAad =
          utf8.decode(fromBase64Url(bundle['aad']?.toString() ?? ''));
      final aad = jsonDecode(decodedAad) as Map<String, dynamic>;
      final scope = aad['scope']?.toString() ?? '';
      return scope.isEmpty ? null : scope;
    } catch (_) {
      return null;
    }
  }

  Future<ParsedSecureScan> stagePendingSecureScan(String rawInput) async {
    final parsed = parseSecureScanInput(rawInput);
    if (parsed == null || !parsed.hasData) {
      throw Exception('invalid_scan_payload');
    }
    await stagePendingSecureScanData(
      scanPayload: parsed.scanPayload,
      scanShortCode: parsed.scanShortCode,
      serverUrl: parsed.serverUrl,
    );
    return parsed;
  }

  Future<void> stagePendingSecureScanData({
    String? scanPayload,
    String? scanShortCode,
    String? serverUrl,
  }) async {
    final normalizedServer = serverUrl?.trim();
    if (normalizedServer != null && normalizedServer.isNotEmpty) {
      final expected = api.baseUrl.replaceAll(RegExp(r'/$'), '');
      final actual = normalizedServer.replaceAll(RegExp(r'/$'), '');
      if (expected != actual) {
        throw Exception('scan_server_mismatch:$actual');
      }
    }
    if ((scanPayload == null || scanPayload.trim().isEmpty) &&
        (scanShortCode == null || scanShortCode.trim().isEmpty)) {
      throw Exception('invalid_scan_payload');
    }
    await _setPendingScan(
      scanPayload: scanPayload,
      scanShortCode: scanShortCode,
    );
    _notifyListenersSafe();
  }

  Future<void> approvePendingSecureScanIfAny() async {
    if (accessToken == null) {
      return;
    }
    final payload = _pendingScanPayload;
    final shortCode = _pendingScanShortCode;
    if ((payload == null || payload.trim().isEmpty) &&
        (shortCode == null || shortCode.trim().isEmpty)) {
      return;
    }
    await approveSecureScan(
      scanPayload: payload,
      scanShortCode: shortCode,
    );
  }

  Future<Map<String, String>> startLogin() async {
    _cancelLoginWait = false;
    final started = await api.startDeviceCode();
    deviceCode = started['deviceCode'] as String;
    userCode = started['userCode'] as String;
    final verificationUriComplete =
        started['verificationUriComplete']?.toString().trim() ?? '';
    final verificationUri = started['verificationUri']?.toString().trim() ?? '';
    final fallbackVerificationUri = verificationUri.isNotEmpty
        ? verificationUri
        : '${api.baseUrl.replaceAll(RegExp(r'/$'), '')}/web/activate';
    final launchUrl = verificationUriComplete.isNotEmpty
        ? verificationUriComplete
        : '$fallbackVerificationUri?user_code=${Uri.encodeComponent(userCode!)}';
    status = 'Awaiting browser authorization...';
    debugPrint('[mobile-auth] device code started');
    _notifyListenersSafe();
    return {
      'userCode': userCode!,
      'deviceCode': deviceCode!,
      'verificationUriComplete': launchUrl,
    };
  }

  Future<void> cancelLoginAttempt() async {
    _cancelLoginWait = true;
    deviceCode = null;
    userCode = null;
    status = 'Login canceled';
    _notifyListenersSafe();
  }

  Future<void> approveSecureScan({
    String? scanPayload,
    String? scanShortCode,
  }) async {
    if (accessToken == null) {
      throw Exception('auth_required');
    }
    if (_secureScanApprovalInProgress) {
      status = 'Secure scan already in progress...';
      _notifyListenersSafe();
      return;
    }
    final normalizedPayload = scanPayload?.trim();
    final normalizedShortCode = scanShortCode?.trim().toUpperCase();
    if ((normalizedPayload == null || normalizedPayload.isEmpty) &&
        (normalizedShortCode == null || normalizedShortCode.isEmpty)) {
      throw Exception('scan_payload_or_short_code_required');
    }

    _secureScanApprovalInProgress = true;
    try {
      await _setPendingScan(
        scanPayload: normalizedPayload,
        scanShortCode: normalizedShortCode,
      );

      final identity = await _ensureScanDeviceIdentity();
      final exchangeKeyPair =
          await MobileE2ERuntime.generateOneTimeScanExchangeKeyPair();
      final startedAt = DateTime.now();

      while (true) {
        try {
          await api.approveScanSecure(
            accessToken: accessToken!,
            scanPayload: normalizedPayload,
            scanShortCode: normalizedShortCode,
            mobileDevice: {
              'deviceId': identity.deviceId,
              'name': 'Nomade Mobile',
              'platform': defaultTargetPlatform.name,
              'encPublicKey': identity.encPublicKey,
              'signPublicKey': identity.signPublicKey,
              'exchangePublicKey': exchangeKeyPair.publicKey,
            },
          );
          break;
        } on ApiException catch (error) {
          if (!_isRateLimitedApiError(error)) {
            rethrow;
          }
          if (DateTime.now().difference(startedAt).inSeconds >= 120) {
            throw Exception('scan_rate_limited_timeout');
          }
          await _waitOnRateLimit(error, context: 'Secure scan');
        }
      }

      while (DateTime.now().difference(startedAt).inSeconds < 120) {
        Map<String, dynamic> state;
        try {
          state = await api.scanMobileAck(
            accessToken: accessToken!,
            scanPayload: normalizedPayload,
            scanShortCode: normalizedShortCode,
          );
        } on ApiException catch (error) {
          if (!_isRateLimitedApiError(error)) {
            rethrow;
          }
          await _waitOnRateLimit(error, context: 'Secure scan');
          continue;
        }

        final statusValue = state['status']?.toString() ?? 'pending';
        if (statusValue == 'ready') {
          final hostBundleRaw = state['hostBundle'];
          if (hostBundleRaw is! Map) {
            throw Exception('scan_host_bundle_missing');
          }
          final hostBundle = hostBundleRaw.cast<String, dynamic>();
          final hostExchangePublicKey =
              state['hostExchangePublicKey']?.toString() ?? '';
          if (hostExchangePublicKey.isEmpty) {
            throw Exception('scan_host_exchange_key_missing');
          }
          final scanScope = _scanScopeFromPayload(normalizedPayload) ??
              _scanScopeFromBundle(hostBundle);
          if (scanScope == null || scanScope.isEmpty) {
            throw Exception('scan_scope_missing');
          }
          ScanBootstrapState bootstrap;
          try {
            bootstrap = await MobileE2ERuntime.decryptScanBootstrap(
              hostBundle: hostBundle,
              scanScope: scanScope,
              mobileExchangePrivateKey: exchangeKeyPair.privateKey,
              hostExchangePublicKey: hostExchangePublicKey,
            );
            final snapshot = MobileE2ESnapshot(
              epoch: bootstrap.epoch,
              rootKey: bootstrap.rootKey,
              device: identity,
              peers: {
                bootstrap.hostDeviceId: MobilePeerDevice(
                  deviceId: bootstrap.hostDeviceId,
                  encPublicKey: bootstrap.hostEncPublicKey,
                  signPublicKey: bootstrap.hostSignPublicKey,
                  addedAt: DateTime.now().toUtc().toIso8601String(),
                ),
              },
              seqByScope: const {},
            );
            _e2eRuntime = await MobileE2ERuntime.fromSnapshot(snapshot);
            if (_e2eRuntime == null || !_e2eRuntime!.isReady) {
              throw const E2ERuntimeException('e2e_runtime_init_failed');
            }
          } on E2ERuntimeException catch (error) {
            await _triggerStrictSecurityFailure('e2e_scan_bootstrap_failed',
                cause: error);
            rethrow;
          } catch (error) {
            await _triggerStrictSecurityFailure('e2e_scan_bootstrap_failed',
                cause: error);
            rethrow;
          }
          await _setSecurityError(null);
          await _persistE2ERuntime();

          while (true) {
            try {
              await api.scanMobileAck(
                accessToken: accessToken!,
                scanPayload: normalizedPayload,
                scanShortCode: normalizedShortCode,
                ack: true,
              );
              break;
            } on ApiException catch (error) {
              if (!_isRateLimitedApiError(error)) {
                rethrow;
              }
              if (DateTime.now().difference(startedAt).inSeconds >= 120) {
                throw Exception('scan_rate_limited_timeout');
              }
              await _waitOnRateLimit(error, context: 'Secure scan');
            }
          }

          await _syncE2EPeersFromServer();
          await clearPendingScan();
          status = 'Secure scan approved';
          _notifyListenersSafe();
          return;
        }
        if (statusValue == 'pending_key_exchange' || statusValue == 'pending') {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        throw Exception('scan_state_unexpected:$statusValue');
      }
      throw Exception('scan_key_exchange_timeout');
    } finally {
      _secureScanApprovalInProgress = false;
    }
  }

  Future<void> waitForBrowserApproval() async {
    if (deviceCode == null) {
      throw Exception('device_code_missing');
    }
    _cancelLoginWait = false;
    String? lastPollStatus;
    while (true) {
      if (_cancelLoginWait) {
        break;
      }
      final polled = await api.pollDeviceCode(deviceCode!);
      final pollStatus = polled['status'] as String? ?? 'pending';
      if (pollStatus != lastPollStatus) {
        debugPrint('[mobile-auth] device poll status=$pollStatus');
        lastPollStatus = pollStatus;
      }
      if (pollStatus == 'ok') {
        _setTokensFromPayload(polled);
        await persistSession();
        status = 'Authenticated';
        try {
          await approvePendingSecureScanIfAny();
        } catch (error) {
          debugPrint(
            '[mobile-auth] pending secure scan resume failed after auth: $error',
          );
          // Continue account login even if secure scan resume fails.
        }
        await _syncE2EPeersFromServer();
        await connectSocket();
        await bootstrapData();
        debugPrint('[mobile-auth] browser authorization completed');
        break;
      } else if (pollStatus == 'expired') {
        status = 'Expired';
        break;
      } else if (pollStatus == 'pending_scan') {
        status = 'Waiting for secure scan approval...';
      } else if (pollStatus == 'pending_key_exchange') {
        status = 'Waiting for secure key exchange...';
      } else {
        status = 'Waiting for browser authorization...';
      }
      _notifyListenersSafe();
      await Future.delayed(const Duration(seconds: 2));
    }
    deviceCode = null;
    userCode = null;
    _cancelLoginWait = false;
    _notifyListenersSafe();
  }

  Future<void> onAgentSelected(Agent agent) async {
    selectedAgent = agent;
    _selectedWorkspace = null;
    _selectedConversation = null;
    workspaces = [];
    conversations = [];
    turns = [];
    services = [];
    tunnels = [];
    trustedDevMode = false;
    selectedServiceId = null;
    _notifyListenersSafe();

    await loadWorkspacesForSelectedAgent();
    await loadCodexOptions();
    if (selectedWorkspace != null) {
      await loadConversations();
      await loadDevSettings();
      await loadServices();
      await loadTunnels();
    }
  }

  Future<void> onWorkspaceSelected(Workspace workspace) async {
    selectedWorkspace = workspace;
    await loadCodexOptions();
    await loadConversations();
    await loadDevSettings();
    await loadServices();
    await loadTunnels();
  }

  Future<bool> createDefaultWorkspace() async {
    if (accessToken == null || selectedAgent == null) return false;
    if (selectedWorkspace != null) return true;

    status = 'Creating workspace...';
    _notifyListenersSafe();
    try {
      await api.createWorkspace(
        accessToken: accessToken!,
        agentId: selectedAgent!.id,
        name: 'Local workspace',
        path: '.',
      );
      await loadWorkspacesForSelectedAgent();
      if (selectedWorkspace != null) {
        await loadConversations();
        await loadDevSettings();
        await loadServices();
        await loadTunnels();
      }
      status = 'Workspace ready';
      _notifyListenersSafe();
      return selectedWorkspace != null;
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return false;
      }
      status = 'Workspace creation failed: $e';
      _notifyListenersSafe();
      return false;
    }
  }

  Future<bool> createConversation({String? title}) async {
    if (accessToken == null ||
        selectedWorkspace == null ||
        selectedAgent == null) {
      return false;
    }

    final fallback = (title ?? 'New conversation').trim();
    final rawTitle = fallback.isEmpty ? 'New conversation' : fallback;
    final clipped =
        rawTitle.length > 120 ? '${rawTitle.substring(0, 120)}...' : rawTitle;

    try {
      final created = await api.createConversation(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
        agentId: selectedAgent!.id,
        title: clipped,
      );
      final conversation = Conversation.fromJson(created);
      conversations = [conversation, ...conversations];
      _sortConversationsByActivity();
      _selectedConversation = conversation;
      turns = [];
      _appendConversationDebugEvent(
        conversationId: conversation.id,
        type: 'conversation.created',
        message: 'workspace=${conversation.workspaceId}',
      );
      _notifyListenersSafe();
      return true;
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return false;
      }
      status = 'Conversation creation failed: $e';
      _notifyListenersSafe();
      return false;
    }
  }

  Future<void> importCodexHistory({bool silent = false}) async {
    if (accessToken == null || selectedAgent == null) return;
    if (!selectedAgent!.isOnline) {
      if (!silent) {
        status = 'Import unavailable: selected agent is offline';
        _notifyListenersSafe();
      }
      return;
    }
    if (importingHistory) return;

    importingHistory = true;
    if (!silent) {
      status = 'Importing Codex history...';
      _notifyListenersSafe();
    } else {
      _notifyListenersSafe();
    }

    try {
      final result = await api.importCodexThreads(
        accessToken: accessToken!,
        agentId: selectedAgent!.id,
      );
      await loadWorkspacesForSelectedAgent(
          storedWorkspaceId: selectedWorkspace?.id);
      if (selectedWorkspace != null) {
        await loadConversations();
        await loadDevSettings();
        await loadServices();
        await loadTunnels();
      }

      if (!silent) {
        final imported = (result['imported'] as num?)?.toInt() ?? 0;
        final repaired = (result['hydrated_or_repaired'] as num?)?.toInt() ?? 0;
        final readTimeouts =
            (result['thread_read_timeouts'] as num?)?.toInt() ?? 0;
        if (readTimeouts > 0) {
          status =
              'Import complete: $imported new, $repaired repaired ($readTimeouts read timeouts)';
        } else {
          status = 'Import complete: $imported new, $repaired repaired';
        }
      }
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      if (!silent) {
        if (e is ApiException && e.errorCode == 'import_in_progress') {
          status = 'Import already running on this agent';
        } else {
          status = 'Import failed: $e';
        }
      }
    } finally {
      importingHistory = false;
      _notifyListenersSafe();
    }
  }

  Future<void> refreshSelectedConversationFromDesktop() async {
    final conversation = selectedConversation;
    if (conversation == null) {
      return;
    }

    final conversationId = conversation.id;
    if (selectedWorkspace == null) {
      await loadTurns(conversationId);
      return;
    }

    try {
      await loadConversations();
    } catch (_) {
      await loadTurns(conversationId);
      return;
    }

    for (final entry in conversations) {
      if (entry.id == conversationId) {
        _selectedConversation = entry;
        await loadTurns(conversationId);
        return;
      }
    }
  }

  Future<void> refreshAll() async {
    if (!isAuthenticated || accessToken == null) return;

    final ready = await ensureFreshToken();
    if (!ready) {
      await logout();
      return;
    }
    await connectSocket();
    await bootstrapData(
      storedAgentId: selectedAgent?.id,
      storedWorkspaceId: selectedWorkspace?.id,
    );
  }
}
