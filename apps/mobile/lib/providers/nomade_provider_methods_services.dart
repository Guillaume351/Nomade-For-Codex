part of 'nomade_provider.dart';

extension NomadeProviderServiceMethods on NomadeProvider {
  @visibleForTesting
  void applyCodexOptionsPayload(Map<String, dynamic> payload) {
    codexModels = ((payload['models'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
    codexCollaborationModes =
        NomadeCodexUtils.normalizeCodexCollaborationModesPayload(
            payload['collaborationModes']);
    codexSkills =
        NomadeCodexUtils.normalizeCodexSkillsPayload(payload['skills']);
    codexRateLimits = _asStringKeyedMap(payload['rateLimits']);
    codexRateLimitsByLimitId =
        _normalizeRateLimitsByLimitId(payload['rateLimitsByLimitId']);

    final approvalPolicies = ((payload['approvalPolicies'] as List?) ?? [])
        .whereType<String>()
        .toList();
    final sandboxModes =
        ((payload['sandboxModes'] as List?) ?? []).whereType<String>().toList();
    final reasoningEfforts = ((payload['reasoningEfforts'] as List?) ?? [])
        .whereType<String>()
        .toList();
    final defaults = (payload['defaults'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    if (approvalPolicies.isNotEmpty) codexApprovalPolicies = approvalPolicies;
    if (sandboxModes.isNotEmpty) codexSandboxModes = sandboxModes;
    if (reasoningEfforts.isNotEmpty) codexReasoningEfforts = reasoningEfforts;

    final defaultModel = NomadeCodexUtils.normalizeString(defaults['model']);
    final defaultApproval =
        NomadeCodexUtils.normalizeString(defaults['approvalPolicy']);
    final defaultSandbox =
        NomadeCodexUtils.normalizeString(defaults['sandboxMode']);
    final defaultEffort = NomadeCodexUtils.normalizeString(defaults['effort']);

    if (_selectedModel == null && defaultModel != null) {
      _selectedModel = defaultModel;
    }
    if (_selectedApprovalPolicy == null && defaultApproval != null) {
      _selectedApprovalPolicy = defaultApproval;
    }
    if (_selectedSandboxMode == null && defaultSandbox != null) {
      _selectedSandboxMode = defaultSandbox;
    }
    if (_selectedEffort == null && defaultEffort != null) {
      _selectedEffort = defaultEffort;
    }

    if (_selectedModel == null && codexModels.isNotEmpty) {
      _selectedModel = codexModels.first['model'] as String?;
    }

    final availableSlugs = codexCollaborationModes
        .map((entry) => NomadeCodexUtils.normalizeString(entry['slug']))
        .whereType<String>()
        .toSet();
    final preferredSlug = NomadeCodexUtils.defaultCollaborationModeSlugFor(
      codexCollaborationModes,
    );
    if (_selectedCollaborationModeSlug == null) {
      _selectedCollaborationModeSlug = preferredSlug;
    } else if (!availableSlugs.contains(_selectedCollaborationModeSlug)) {
      _selectedCollaborationModeSlug = preferredSlug;
    }

    final availableSkillPaths =
        codexSkills.map((entry) => entry['path']).whereType<String>().toSet();
    _selectedSkillPaths = _selectedSkillPaths
        .where((path) => availableSkillPaths.contains(path))
        .toList()
      ..sort();
  }

  Future<void> loadDevSettings() async {
    if (selectedWorkspace == null || accessToken == null) return;
    try {
      final payload = await api.getWorkspaceDevSettings(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
      );
      trustedDevMode = payload['trustedDevMode'] == true;
      _notifyListenersSafe();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      // keep local value if server is not ready yet
    }
  }

  Future<void> setTrustedDevMode(bool enabled) async {
    if (selectedWorkspace == null || accessToken == null) return;
    final previous = trustedDevMode;
    trustedDevMode = enabled;
    _notifyListenersSafe();
    try {
      await api.updateWorkspaceDevSettings(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
        trustedDevMode: enabled,
      );
      await loadServices();
      await loadTunnels();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      trustedDevMode = previous;
      status = 'Failed to update trusted mode: $e';
      _notifyListenersSafe();
    }
  }

  Future<void> loadServices() async {
    if (selectedWorkspace == null || accessToken == null) return;
    loadingServices = true;
    _notifyListenersSafe();
    try {
      final payload = await api.listWorkspaceServices(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
      );
      services = payload.map(DevService.fromJson).toList();
      if (selectedServiceId == null ||
          !services.any((service) => service.id == selectedServiceId)) {
        selectedServiceId = services.isNotEmpty ? services.first.id : null;
      }
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Failed to load services: $e';
    } finally {
      loadingServices = false;
      _notifyListenersSafe();
    }
  }

  Future<void> loadTunnels() async {
    if (selectedWorkspace == null || accessToken == null) return;
    loadingTunnels = true;
    _notifyListenersSafe();
    try {
      final payload = await api.listTunnels(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
      );
      tunnels = payload.map(TunnelPreview.fromJson).toList();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Failed to load tunnels: $e';
    } finally {
      loadingTunnels = false;
      _notifyListenersSafe();
    }
  }

  Future<bool> createTunnel({
    required int targetPort,
    String? serviceId,
    int? ttlSec,
  }) async {
    if (targetPort < 1 || targetPort > 65535) {
      status = 'Invalid port: $targetPort';
      _notifyListenersSafe();
      return false;
    }
    if (selectedWorkspace == null ||
        selectedAgent == null ||
        accessToken == null) {
      status = 'Select an online agent and workspace first';
      _notifyListenersSafe();
      return false;
    }
    try {
      final payload = await api.createTunnel(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
        agentId: selectedAgent!.id,
        targetPort: targetPort,
        serviceId: serviceId,
        ttlSec: ttlSec,
      );
      final created = TunnelPreview.fromJson(payload);
      final existingIndex = tunnels.indexWhere((item) => item.id == created.id);
      if (existingIndex == -1) {
        tunnels = [created, ...tunnels];
      } else {
        tunnels[existingIndex] = created;
      }
      await loadTunnels();
      await loadServices();
      status = 'Tunnel created for :$targetPort';
      _notifyListenersSafe();
      return true;
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return false;
      }
      status = 'Tunnel creation failed: $e';
      _notifyListenersSafe();
      return false;
    }
  }

  Future<void> startService(String serviceId) async {
    if (accessToken == null) return;
    try {
      final payload = await api.startService(
        accessToken: accessToken!,
        serviceId: serviceId,
      );
      _upsertService(DevService.fromJson(payload));
      await loadTunnels();
      status = 'Service started';
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Start failed: $e';
    }
    _notifyListenersSafe();
  }

  Future<void> stopService(String serviceId) async {
    if (accessToken == null) return;
    try {
      final payload = await api.stopService(
        accessToken: accessToken!,
        serviceId: serviceId,
      );
      _upsertService(DevService.fromJson(payload));
      status = 'Service stopped';
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Stop failed: $e';
    }
    _notifyListenersSafe();
  }

  Future<void> refreshServiceState(String serviceId) async {
    if (accessToken == null) return;
    try {
      final payload = await api.getServiceState(
        accessToken: accessToken!,
        serviceId: serviceId,
      );
      _upsertService(DevService.fromJson(payload));
      _notifyListenersSafe();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      // ignore transient failures
    }
  }

  Future<String?> issueTunnelLink(String tunnelId) async {
    if (accessToken == null) return null;
    try {
      final payload = await api.issueTunnelToken(
        accessToken: accessToken!,
        tunnelId: tunnelId,
      );
      status = 'Tunnel link issued';
      _notifyListenersSafe();
      return payload['previewUrl']?.toString();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return null;
      }
      status = 'Issue token failed: $e';
      _notifyListenersSafe();
      return null;
    }
  }

  Future<String?> rotateTunnelLink(String tunnelId) async {
    if (accessToken == null) return null;
    try {
      final payload = await api.rotateTunnelToken(
        accessToken: accessToken!,
        tunnelId: tunnelId,
      );
      status = 'Tunnel token rotated';
      _notifyListenersSafe();
      return payload['previewUrl']?.toString();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return null;
      }
      status = 'Rotate token failed: $e';
      _notifyListenersSafe();
      return null;
    }
  }

  Future<void> closeTunnel(String tunnelId) async {
    if (accessToken == null) return;
    try {
      await api.deleteTunnel(
        accessToken: accessToken!,
        tunnelId: tunnelId,
      );
      tunnels = tunnels.where((item) => item.id != tunnelId).toList();
      status = 'Tunnel closed';
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Close tunnel failed: $e';
    }
    _notifyListenersSafe();
  }

  void sendSessionInput(String sessionId, String data) {
    if (socket == null) return;
    final runtime = _e2eRuntime;
    if (runtime == null || !runtime.isReady) {
      status =
          'Secure scan required before sending terminal input. Approve secure scan first.';
      _notifyListenersSafe();
      return;
    }
    try {
      final envelope = runtime.encryptEnvelope(
        scope: 'session:$sessionId',
        plaintext: data,
      );
      unawaited(_persistE2ERuntime());
      socket!.sink.add(jsonEncode({
        'type': 'session.input',
        'sessionId': sessionId,
        'data': '',
        'e2eEnvelope': envelope,
      }));
    } on E2ERuntimeException catch (error) {
      if (error.code == 'e2e_runtime_unavailable') {
        status =
            'Secure scan required before sending terminal input. Approve secure scan first.';
        _notifyListenersSafe();
        return;
      }
      unawaited(
        _triggerStrictSecurityFailure(
          'e2e_session_input_encrypt_failed',
          cause: error,
        ),
      );
    } catch (error) {
      unawaited(
        _triggerStrictSecurityFailure(
          'e2e_session_input_encrypt_failed',
          cause: error,
        ),
      );
    }
  }

  void _respondToServerRequestImpl({
    required String conversationId,
    required String turnId,
    required String requestId,
    dynamic result,
    String? error,
  }) {
    if (socket == null) {
      return;
    }
    final runtime = _e2eRuntime;
    if (runtime == null || !runtime.isReady) {
      status =
          'Secure scan required before approving server actions. Approve secure scan first.';
      _notifyListenersSafe();
      return;
    }
    try {
      final envelope = runtime.encryptEnvelope(
        scope: 'conversation:$conversationId',
        plaintext: jsonEncode({
          if (result != null) 'result': result,
          if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
        }),
      );
      unawaited(_persistE2ERuntime());
      socket!.sink.add(jsonEncode({
        'type': 'conversation.server.response',
        'conversationId': conversationId,
        'turnId': turnId,
        'requestId': requestId,
        'e2eEnvelope': envelope,
      }));
    } on E2ERuntimeException catch (decryptError) {
      if (decryptError.code == 'e2e_runtime_unavailable') {
        status =
            'Secure scan required before approving server actions. Approve secure scan first.';
        _notifyListenersSafe();
        return;
      }
      unawaited(
        _triggerStrictSecurityFailure(
          'e2e_server_response_encrypt_failed',
          cause: decryptError,
        ),
      );
      return;
    } catch (decryptError) {
      unawaited(
        _triggerStrictSecurityFailure(
          'e2e_server_response_encrypt_failed',
          cause: decryptError,
        ),
      );
      return;
    }

    final timeline = timelineForTurn(turnId);
    final item = timeline.upsertItem(
      itemId: 'server-request-$requestId',
      itemType: 'serverRequest',
    );
    final requestStatus = error != null && error.trim().isNotEmpty
        ? 'failed'
        : result is String &&
                (result == 'decline' ||
                    result == 'cancel' ||
                    result == 'declined')
            ? 'declined'
            : 'completed';
    item.applyCompleted(itemType: 'serverRequest', payload: {
      'status': requestStatus,
      if (result != null) 'result': result,
      if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
    });
    _appendConversationDebugEvent(
      conversationId: conversationId,
      type: 'server.response',
      message:
          'turn=$turnId request=$requestId status=$requestStatus${error != null && error.trim().isNotEmpty ? ' error=$error' : ''}',
    );
    _notifyListenersSafe();
  }

  void terminateSession(String sessionId, {String? agentId}) {
    if (socket == null) return;
    socket!.sink.add(jsonEncode({
      'type': 'session.terminate',
      'sessionId': sessionId,
      if (agentId != null) 'agentId': agentId,
    }));
  }

  String serviceLogs(String serviceId) {
    final service = services.firstWhere(
      (item) => item.id == serviceId,
      orElse: () => DevService(
        id: '',
        workspaceId: '',
        agentId: '',
        name: '',
        role: 'service',
        command: '',
        cwd: null,
        port: 0,
        healthPath: '/',
        envTemplate: const {},
        dependsOn: const [],
        autoTunnel: true,
        state: 'stopped',
        runtimeStatus: 'stopped',
      ),
    );
    final sessionId = service.session?.id;
    if (sessionId == null || sessionId.isEmpty) {
      return '';
    }
    return sessionLogsBySession[sessionId]?.toString() ?? '';
  }

  void selectService(String? serviceId) {
    selectedServiceId = serviceId;
    _notifyListenersSafe();
  }

  void _upsertService(DevService incoming) {
    final index = services.indexWhere((item) => item.id == incoming.id);
    if (index == -1) {
      services = [incoming, ...services];
      return;
    }
    services[index] = incoming;
  }

  void _trackConversationEvent({
    required String conversationId,
    required String method,
    required bool rendered,
  }) {
    if (conversationId.isEmpty) {
      return;
    }
    final runtime = _runtimeByConversation.putIfAbsent(
      conversationId,
      () => ConversationRuntimeTrace(),
    );
    if (!rendered) {
      runtime.eventsReceived += 1;
      runtime.unsupportedMethods.add(method);
      return;
    }
    runtime.eventsRendered += 1;
    runtime.unsupportedMethods.remove(method);
  }

  Map<String, dynamic>? _parseEnvelopeMap(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final envelope = value.cast<String, dynamic>();
    final v = (envelope['v'] as num?)?.toInt();
    final alg = envelope['alg']?.toString();
    final sender = envelope['senderDeviceId']?.toString() ?? '';
    final nonce = envelope['nonce']?.toString() ?? '';
    final aad = envelope['aad']?.toString() ?? '';
    final ciphertext = envelope['ciphertext']?.toString() ?? '';
    final sig = envelope['sig']?.toString() ?? '';
    if (v != 1 ||
        alg != 'xchacha20poly1305' ||
        sender.isEmpty ||
        nonce.isEmpty ||
        aad.isEmpty ||
        ciphertext.isEmpty ||
        sig.isEmpty) {
      return null;
    }
    return envelope;
  }

  Map<String, dynamic>? _tryParseJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
