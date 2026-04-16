part of 'nomade_provider.dart';

enum _TokenRefreshResult {
  success,
  invalidSession,
  transientFailure,
}

extension NomadeProviderCoreMethods on NomadeProvider {
  Future<void> setApiBaseUrl(
    String rawBaseUrl, {
    bool clearSession = true,
  }) async {
    final normalized = NomadeProvider.normalizeApiBaseUrl(rawBaseUrl);
    final current = api.baseUrl.replaceAll(RegExp(r'/$'), '');
    if (normalized == current) {
      return;
    }

    if (clearSession && (accessToken != null || refreshToken != null)) {
      await logout();
    }

    _api = NomadeApi(baseUrl: normalized);
    await _writeStorage(NomadeProvider._apiBaseUrlKey, value: normalized);
    status = clearSession
        ? 'Server endpoint updated. Sign in again to continue.'
        : 'Server endpoint updated.';
    _notifyListenersSafe();
  }

  void setSelectedSkillPaths(List<String> paths) {
    final normalized = paths
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (listEquals(_selectedSkillPaths, normalized)) {
      return;
    }
    _selectedSkillPaths = normalized;
    persistSession();
    _notifyListenersSafe();
  }

  void toggleSkillPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return;
    }
    final values = [..._selectedSkillPaths];
    if (values.contains(normalized)) {
      values.remove(normalized);
    } else {
      values.add(normalized);
    }
    values.sort();
    _selectedSkillPaths = values;
    persistSession();
    _notifyListenersSafe();
  }

  TurnTimeline timelineForTurn(String turnId) {
    return _timelineByTurn.putIfAbsent(
        turnId, () => TurnTimeline(turnId: turnId));
  }

  TurnTimeline? tryTimelineForTurn(String turnId) {
    return _timelineByTurn[turnId];
  }

  bool get isAuthenticated => accessToken != null;

  int? _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return null;
  }

  Map<String, Map<String, dynamic>> _normalizeRateLimitsByLimitId(
    dynamic value,
  ) {
    final normalized = <String, Map<String, dynamic>>{};
    if (value is! Map) {
      return normalized;
    }
    final source = value.cast<String, dynamic>();
    for (final entry in source.entries) {
      final limitId = entry.key.trim();
      if (limitId.isEmpty) {
        continue;
      }
      final snapshot = _asStringKeyedMap(entry.value);
      if (snapshot == null) {
        continue;
      }
      normalized[limitId] = snapshot;
    }
    return normalized;
  }

  bool _isRateLimitedApiError(Object error) {
    if (error is! ApiException) {
      return false;
    }
    if (error.statusCode == 429) {
      return true;
    }
    return error.errorCode?.trim().toLowerCase() == 'rate_limited';
  }

  int _resolveRateLimitWaitSec(ApiException error,
      {int fallbackSec = 2, int maxSec = 20}) {
    final retry = error.retryAfterSec ?? fallbackSec;
    if (retry < 1) {
      return 1;
    }
    if (retry > maxSec) {
      return maxSec;
    }
    return retry;
  }

  Future<void> _waitOnRateLimit(ApiException error,
      {required String context}) async {
    final waitSec = _resolveRateLimitWaitSec(error);
    status = '$context rate limited. Retrying in ${waitSec}s...';
    _notifyListenersSafe();
    await Future.delayed(Duration(seconds: waitSec));
  }

  Future<String?> _readStorage(
    String key, {
    bool strictDeviceOnly = false,
  }) {
    return _storage.read(
      key: key,
      iOptions: strictDeviceOnly ? NomadeProvider._keychainOptions : null,
      aOptions: strictDeviceOnly ? NomadeProvider._androidOptions : null,
    );
  }

  Future<void> _writeStorage(
    String key, {
    required String? value,
    bool strictDeviceOnly = false,
  }) {
    return _storage.write(
      key: key,
      value: value,
      iOptions: strictDeviceOnly ? NomadeProvider._keychainOptions : null,
      aOptions: strictDeviceOnly ? NomadeProvider._androidOptions : null,
    );
  }

  Future<void> _deleteStorage(
    String key, {
    bool strictDeviceOnly = false,
  }) {
    return _storage.delete(
      key: key,
      iOptions: strictDeviceOnly ? NomadeProvider._keychainOptions : null,
      aOptions: strictDeviceOnly ? NomadeProvider._androidOptions : null,
    );
  }

  Future<String> _ensurePushDeviceId() async {
    final existing = await _readStorage(NomadeProvider._pushDeviceIdKey,
        strictDeviceOnly: true);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final scanDeviceId = await _readStorage(NomadeProvider._scanDeviceIdKey,
        strictDeviceOnly: true);
    if (scanDeviceId != null && scanDeviceId.trim().isNotEmpty) {
      await _writeStorage(
        NomadeProvider._pushDeviceIdKey,
        value: scanDeviceId.trim(),
        strictDeviceOnly: true,
      );
      return scanDeviceId.trim();
    }
    final generated =
        'mobile-${defaultTargetPlatform.name}-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    await _writeStorage(
      NomadeProvider._pushDeviceIdKey,
      value: generated,
      strictDeviceOnly: true,
    );
    return generated;
  }

  Future<void> syncNativePushRegistration({bool force = false}) async {
    final token = accessToken;
    if (token == null) {
      return;
    }
    if (!nativeNotificationsBridgeEnabled) {
      pushRegistrationError = null;
      pushProviderReady = false;
      return;
    }
    if (!canUsePushNotifications) {
      pushProviderReady = false;
      if (_registeredPushToken != null) {
        try {
          await api.unregisterPushDevice(
            accessToken: token,
            token: _registeredPushToken,
          );
        } catch (_) {}
      }
      _registeredPushToken = null;
      pushRegistrationError = null;
      return;
    }

    final registration = await NativeNotificationsBridge.getPushRegistration();
    if (registration == null) {
      pushRegistrationError = 'native_push_token_unavailable';
      return;
    }

    final platform = registration.platform.toLowerCase();
    final normalizedPlatform = platform.contains('ios')
        ? 'ios'
        : platform.contains('android')
            ? 'android'
            : defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android';
    final tokenChanged = _registeredPushToken != registration.token;
    if (!force && !tokenChanged) {
      return;
    }

    final deviceId = registration.deviceId.trim().isNotEmpty
        ? registration.deviceId.trim()
        : await _ensurePushDeviceId();
    try {
      final payload = await api.registerPushDevice(
        accessToken: token,
        deviceId: deviceId,
        platform: normalizedPlatform,
        provider: registration.provider,
        token: registration.token,
      );
      _registeredPushToken = registration.token;
      pushRegistrationError = null;
      pushProviderReady = payload['providerReady'] == true;
      _notifyListenersSafe();
    } on ApiException catch (error) {
      if (error.errorCode == 'feature_not_enabled') {
        pushRegistrationError = null;
      } else {
        pushRegistrationError = error.errorCode ?? error.message;
      }
      pushProviderReady = false;
      _notifyListenersSafe();
    } catch (error) {
      pushRegistrationError = error.toString();
      pushProviderReady = false;
      _notifyListenersSafe();
    }
  }

  Future<void> _restoreE2ERuntime() async {
    final raw = await _readStorage(NomadeProvider._e2eSnapshotKey,
        strictDeviceOnly: true);
    if (raw == null || raw.trim().isEmpty) {
      _e2eRuntime = null;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _e2eRuntime = null;
        return;
      }
      final snapshot =
          MobileE2ESnapshot.fromJson(decoded.cast<String, dynamic>());
      _e2eRuntime = await MobileE2ERuntime.fromSnapshot(snapshot);
    } catch (_) {
      _e2eRuntime = null;
    }
  }

  Future<void> _persistE2ERuntime() async {
    final snapshot = _e2eRuntime?.snapshot();
    if (snapshot == null) {
      await _deleteStorage(NomadeProvider._e2eSnapshotKey,
          strictDeviceOnly: true);
      return;
    }
    await _writeStorage(
      NomadeProvider._e2eSnapshotKey,
      value: jsonEncode(snapshot.toJson()),
      strictDeviceOnly: true,
    );
  }

  Future<bool> _syncE2EPeersFromServer() async {
    final token = accessToken;
    final runtime = _e2eRuntime;
    if (token == null || runtime == null || !runtime.isReady) {
      return false;
    }
    Map<String, dynamic> payload;
    try {
      payload = await api.getE2EDevices(accessToken: token);
    } catch (error) {
      if (await _logoutIfUnauthorized(error)) {
        return false;
      }
      debugPrint('[mobile-e2e] peer sync failed: $error');
      return false;
    }
    final items = (payload['items'] as List?) ?? const [];
    final snapshot = runtime.snapshot();
    final selfDeviceId = snapshot.device.deviceId;
    final currentPeers = Map<String, MobilePeerDevice>.from(snapshot.peers);
    var changed = false;
    for (final raw in items) {
      if (raw is! Map) {
        continue;
      }
      final entry = raw.cast<String, dynamic>();
      final deviceId = entry['deviceId']?.toString().trim() ?? '';
      final signPublicKey = entry['signPublicKey']?.toString().trim() ?? '';
      final encPublicKey = entry['encPublicKey']?.toString().trim() ?? '';
      if (deviceId.isEmpty ||
          signPublicKey.isEmpty ||
          deviceId == selfDeviceId) {
        continue;
      }
      final existing = currentPeers[deviceId];
      final nextEncPublicKey = encPublicKey.isNotEmpty
          ? encPublicKey
          : (existing?.encPublicKey ?? '');
      if (existing != null &&
          existing.signPublicKey == signPublicKey &&
          existing.encPublicKey == nextEncPublicKey) {
        continue;
      }
      final peer = MobilePeerDevice(
        deviceId: deviceId,
        encPublicKey: nextEncPublicKey,
        signPublicKey: signPublicKey,
        addedAt: existing?.addedAt ?? DateTime.now().toUtc().toIso8601String(),
      );
      runtime.addOrUpdatePeer(peer);
      currentPeers[deviceId] = peer;
      changed = true;
    }
    if (!changed) {
      return false;
    }
    await _persistE2ERuntime();
    return true;
  }

  Future<void> _persistPendingScan() async {
    await Future.wait([
      _writeStorage(
        NomadeProvider._scanPendingPayloadKey,
        value: _pendingScanPayload,
        strictDeviceOnly: true,
      ),
      _writeStorage(
        NomadeProvider._scanPendingShortCodeKey,
        value: _pendingScanShortCode,
        strictDeviceOnly: true,
      ),
    ]);
  }

  Future<void> _setPendingScan({
    String? scanPayload,
    String? scanShortCode,
  }) async {
    _pendingScanPayload =
        scanPayload?.trim().isEmpty == true ? null : scanPayload?.trim();
    _pendingScanShortCode = scanShortCode?.trim().isEmpty == true
        ? null
        : scanShortCode?.trim().toUpperCase();
    await _persistPendingScan();
  }

  Future<void> clearPendingScan() => _setPendingScan();

  Future<void> _setSecurityError(String? value) async {
    _securityError = value?.trim().isEmpty == true ? null : value?.trim();
    await _writeStorage(
      NomadeProvider._strictSecurityErrorKey,
      value: _securityError,
      strictDeviceOnly: true,
    );
  }

  Future<void> _clearE2EState() async {
    _e2eRuntime = null;
    await Future.wait([
      _deleteStorage(NomadeProvider._e2eSnapshotKey, strictDeviceOnly: true),
      _deleteStorage(NomadeProvider._scanDeviceIdKey, strictDeviceOnly: true),
      _deleteStorage(NomadeProvider._scanEncPublicKey, strictDeviceOnly: true),
      _deleteStorage(NomadeProvider._scanEncPrivateKey, strictDeviceOnly: true),
      _deleteStorage(NomadeProvider._scanSignPublicKey, strictDeviceOnly: true),
      _deleteStorage(NomadeProvider._scanSignPrivateKey,
          strictDeviceOnly: true),
    ]);
  }

  Future<void> _triggerStrictSecurityFailure(
    String code, {
    Object? cause,
  }) async {
    if (_strictFailureInProgress) {
      return;
    }
    _strictFailureInProgress = true;
    final message = cause == null ? code : '$code: $cause';
    await _setSecurityError(message);
    await _clearE2EState();
    await _setPendingScan();
    try {
      await logout();
    } finally {
      status = 'Security lock: $code. Re-login with secure scan is required.';
      _notifyListenersSafe();
      _strictFailureInProgress = false;
    }
  }

  Future<void> startup() async {
    await restoreSession();
  }

  Future<void> restoreSession() async {
    try {
      final storedApiBaseUrl = await _readStorage(NomadeProvider._apiBaseUrlKey);
      if (storedApiBaseUrl != null && storedApiBaseUrl.trim().isNotEmpty) {
        try {
          _api = NomadeApi(
            baseUrl: NomadeProvider.normalizeApiBaseUrl(storedApiBaseUrl),
          );
        } catch (_) {}
      }

      accessToken = await _readStorage(NomadeProvider._accessTokenKey);
      refreshToken = await _readStorage(NomadeProvider._refreshTokenKey);
      final expiry = await _readStorage(NomadeProvider._accessTokenExpiryKey);
      accessTokenExpiresAt = expiry != null ? DateTime.tryParse(expiry) : null;

      final storedAgentId =
          await _readStorage(NomadeProvider._selectedAgentKey);
      final storedWorkspaceId =
          await _readStorage(NomadeProvider._selectedWorkspaceKey);
      final storedConversationId =
          await _readStorage(NomadeProvider._selectedConversationKey);
      _selectedModel = await _readStorage(NomadeProvider._selectedModelKey);
      _selectedApprovalPolicy =
          await _readStorage(NomadeProvider._selectedApprovalPolicyKey) ??
              _selectedApprovalPolicy;
      _selectedSandboxMode =
          await _readStorage(NomadeProvider._selectedSandboxModeKey) ??
              _selectedSandboxMode;
      _selectedEffort = await _readStorage(NomadeProvider._selectedEffortKey) ??
          _selectedEffort;
      final storedOfflineDefault =
          await _readStorage(NomadeProvider._offlineTurnDefaultKey);
      if (storedOfflineDefault != null &&
          (storedOfflineDefault == 'prompt' ||
              storedOfflineDefault == 'defer' ||
              storedOfflineDefault == 'fail')) {
        _offlineTurnDefault = storedOfflineDefault;
      }
      _selectedCollaborationModeSlug =
          await _readStorage(NomadeProvider._selectedCollaborationModeKey);
      final storedListSortMode =
          await _readStorage(NomadeProvider._listSortModeKey);
      if (storedListSortMode != null) {
        final normalized = storedListSortMode.trim().toLowerCase();
        if (NomadeCodexUtils.isSupportedListSortMode(normalized)) {
          _listSortMode = normalized;
        }
      }
      final selectedSkillsRaw =
          await _readStorage(NomadeProvider._selectedSkillsKey);
      if (selectedSkillsRaw != null && selectedSkillsRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(selectedSkillsRaw);
          if (decoded is List) {
            _selectedSkillPaths = decoded
                .whereType<String>()
                .map((entry) => entry.trim())
                .where((entry) => entry.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
          }
        } catch (_) {
          _selectedSkillPaths = [];
        }
      }
      _pendingScanPayload = await _readStorage(
          NomadeProvider._scanPendingPayloadKey,
          strictDeviceOnly: true);
      _pendingScanShortCode = await _readStorage(
          NomadeProvider._scanPendingShortCodeKey,
          strictDeviceOnly: true);
      _securityError = await _readStorage(
          NomadeProvider._strictSecurityErrorKey,
          strictDeviceOnly: true);
      await _restoreE2ERuntime();

      if (accessToken != null) {
        status = 'Restoring session...';
        _notifyListenersSafe();

        final ready = await ensureFreshToken();
        if (ready) {
          status = 'Authenticated';
          try {
            await approvePendingSecureScanIfAny();
          } catch (_) {
            // Keep authenticated session even if a stale pending scan cannot be resumed.
          }
          await _syncE2EPeersFromServer();
          await connectSocket();
          await bootstrapData(
            storedAgentId: storedAgentId,
            storedWorkspaceId: storedWorkspaceId,
            storedConversationId: storedConversationId,
          );
        } else {
          await logout();
        }
      }
    } on PlatformException catch (e) {
      secureStorageAvailable = false;
      status = 'Secure storage unavailable';
      debugPrint('Secure storage error: $e');
    }
    _notifyListenersSafe();
  }

  Future<void> persistSession() async {
    if (!secureStorageAvailable) return;

    try {
      if (accessToken == null) {
        await _storage.deleteAll();
        await _writeStorage(
          NomadeProvider._apiBaseUrlKey,
          value: api.baseUrl,
        );
        _e2eRuntime = null;
        _pendingScanPayload = null;
        _pendingScanShortCode = null;
        _securityError = null;
        return;
      }

      await Future.wait([
        _writeStorage(NomadeProvider._accessTokenKey, value: accessToken),
        _writeStorage(NomadeProvider._refreshTokenKey, value: refreshToken),
        if (accessTokenExpiresAt != null)
          _writeStorage(NomadeProvider._accessTokenExpiryKey,
              value: accessTokenExpiresAt!.toIso8601String()),
        _writeStorage(NomadeProvider._selectedAgentKey,
            value: _selectedAgent?.id),
        _writeStorage(NomadeProvider._selectedWorkspaceKey,
            value: _selectedWorkspace?.id),
        _writeStorage(NomadeProvider._selectedConversationKey,
            value: _selectedConversation?.id),
        _writeStorage(NomadeProvider._selectedModelKey, value: _selectedModel),
        _writeStorage(NomadeProvider._selectedApprovalPolicyKey,
            value: _selectedApprovalPolicy),
        _writeStorage(NomadeProvider._selectedSandboxModeKey,
            value: _selectedSandboxMode),
        _writeStorage(NomadeProvider._selectedEffortKey,
            value: _selectedEffort),
        _writeStorage(NomadeProvider._offlineTurnDefaultKey,
            value: _offlineTurnDefault),
        _writeStorage(NomadeProvider._listSortModeKey, value: _listSortMode),
        _writeStorage(NomadeProvider._selectedCollaborationModeKey,
            value: _selectedCollaborationModeSlug),
        _writeStorage(NomadeProvider._selectedSkillsKey,
            value: jsonEncode(_selectedSkillPaths)),
        _persistE2ERuntime(),
        _persistPendingScan(),
        _setSecurityError(_securityError),
      ]);
    } catch (e) {
      debugPrint('Persist session error: $e');
    }
  }

  Future<void> logout() async {
    final tokenBeforeLogout = accessToken;
    final pushTokenBeforeLogout = _registeredPushToken;
    if (tokenBeforeLogout != null && pushTokenBeforeLogout != null) {
      try {
        await api.unregisterPushDevice(
          accessToken: tokenBeforeLogout,
          token: pushTokenBeforeLogout,
        );
      } catch (_) {}
    }

    if (accessToken != null && refreshToken != null) {
      try {
        await api.logout(
            accessToken: accessToken!, refreshToken: refreshToken!);
      } catch (_) {}
    }

    accessToken = null;
    refreshToken = null;
    accessTokenExpiresAt = null;
    planCode = null;
    entitlementSource = null;
    currentAgents = null;
    maxAgents = null;
    deviceLimitReached = null;
    canUseTunnels = false;
    canUsePushNotifications = false;
    canUseDeferredTurns = false;
    pushProviderReady = false;
    pushRegistrationError = null;
    _registeredPushToken = null;
    agents = [];
    workspaces = [];
    conversations = [];
    _conversationsWorkspaceId = null;
    turns = [];
    services = [];
    tunnels = [];
    selectedServiceId = null;
    trustedDevMode = false;
    sessionLogsBySession.clear();
    sessionChunks.clear();
    _debugEventsByConversation.clear();
    _runtimeByConversation.clear();
    _timelineByTurn.clear();
    _selectedAgent = null;
    _selectedWorkspace = null;
    _selectedConversation = null;
    _selectedCollaborationModeSlug = null;
    _selectedSkillPaths = [];
    _listSortMode = 'latest';
    _e2eRuntime = null;
    _pendingScanPayload = null;
    _pendingScanShortCode = null;
    _securityError = null;
    _secureScanApprovalInProgress = false;
    _offlineTurnDefault = 'prompt';
    activeTurnId = null;
    status = 'Logged out';

    reconnectTimer?.cancel();
    socketSub?.cancel();
    socket?.sink.close();
    realtimeConnected = false;

    await _storage.deleteAll();
    await _writeStorage(
      NomadeProvider._apiBaseUrlKey,
      value: api.baseUrl,
    );
    _notifyListenersSafe();
  }

  Future<void> deleteAccountAndData({
    String confirmationCode = 'DELETE',
  }) async {
    final token = accessToken;
    final refresh = refreshToken;
    if (token == null || refresh == null) {
      await logout();
      status = 'Account deleted.';
      _notifyListenersSafe();
      return;
    }

    await api.deleteAccount(
      accessToken: token,
      refreshToken: refresh,
      confirmationCode: confirmationCode,
    );

    await logout();
    status = 'Account deleted.';
    _notifyListenersSafe();
  }

  Future<bool> ensureFreshToken() async {
    if (accessToken == null && refreshToken == null) return false;

    final expiry = accessTokenExpiresAt;
    if (accessToken != null &&
        (expiry == null ||
            DateTime.now()
                .isBefore(expiry.subtract(const Duration(seconds: 60))))) {
      return true;
    }

    final refreshResult = await _refreshTokensWithResult();
    if (refreshResult == _TokenRefreshResult.success) {
      return true;
    }
    // During Wi-Fi -> cellular handoff, refresh can fail transiently.
    // Keep the local session and retry via reconnect/backoff instead of logging out.
    if (refreshResult == _TokenRefreshResult.transientFailure &&
        accessToken != null) {
      return true;
    }
    return false;
  }

  Future<bool> refreshTokens() async {
    final result = await _refreshTokensWithResult();
    return result == _TokenRefreshResult.success;
  }

  Future<_TokenRefreshResult> _refreshTokensWithResult() async {
    if (refreshToken == null) return _TokenRefreshResult.invalidSession;
    final inFlight = _refreshTokensInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final pending = () async {
      try {
        final payload = await api.refreshAccessToken(refreshToken!);
        _setTokensFromPayload(payload);
        await persistSession();
        return _TokenRefreshResult.success;
      } on ApiException catch (error) {
        if (_isInvalidRefreshTokenError(error)) {
          return _TokenRefreshResult.invalidSession;
        }
        return _TokenRefreshResult.transientFailure;
      } catch (_) {
        return _TokenRefreshResult.transientFailure;
      } finally {
        _refreshTokensInFlight = null;
      }
    }();

    _refreshTokensInFlight = pending;
    return pending;
  }

  void _setTokensFromPayload(Map<String, dynamic> payload) {
    accessToken = payload['accessToken'] as String?;
    refreshToken = payload['refreshToken'] as String? ?? refreshToken;
    final expiresInSec = (payload['expiresInSec'] as num?)?.toInt();
    accessTokenExpiresAt = expiresInSec == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresInSec));
  }

  bool _isUnauthorizedError(Object error) {
    if (error is! ApiException) {
      return false;
    }
    if (error.statusCode == 401) {
      return true;
    }
    final code = error.errorCode?.trim().toLowerCase();
    return code == 'invalid_token' || code == 'missing_authorization';
  }

  bool _isInvalidRefreshTokenError(Object error) {
    if (error is! ApiException) {
      return false;
    }
    if (error.statusCode == 401) {
      return true;
    }
    final code = error.errorCode?.trim().toLowerCase();
    return code == 'invalid_refresh_token' ||
        code == 'invalid_token' ||
        code == 'missing_authorization';
  }

  Future<bool> _logoutIfUnauthorized(Object error) async {
    if (!_isUnauthorizedError(error)) {
      return false;
    }
    // Access tokens are short-lived; attempt a silent refresh first so iOS
    // resume flows do not force a full re-login after idle periods.
    final refreshResult = await _refreshTokensWithResult();
    if (refreshResult == _TokenRefreshResult.success) {
      unawaited(connectSocket());
      return true;
    }
    if (refreshResult == _TokenRefreshResult.transientFailure) {
      status = 'Session refresh delayed by network change. Reconnecting...';
      _notifyListenersSafe();
      unawaited(connectSocket());
      return true;
    }
    await logout();
    status = 'Session expired. Please sign in again.';
    _notifyListenersSafe();
    return true;
  }

  Future<void> loadEntitlements({bool notifyListenersNow = true}) async {
    if (accessToken == null) {
      return;
    }
    try {
      final payload = await api.getEntitlements(accessToken!);
      planCode = payload['planCode']?.toString() ??
          payload['plan_code']?.toString() ??
          planCode;
      entitlementSource =
          payload['source']?.toString() ?? entitlementSource;
      currentAgents =
          _asInt(payload['currentAgents'] ?? payload['current_agents']) ??
              currentAgents;
      maxAgents =
          _asInt(payload['maxAgents'] ?? payload['max_agents']) ?? maxAgents;
      final rawLimit = payload['limitReached'] ?? payload['limit_reached'];
      if (rawLimit is bool) {
        deviceLimitReached = rawLimit;
      } else if (rawLimit is num) {
        deviceLimitReached = rawLimit != 0;
      } else if (rawLimit is String) {
        final normalized = rawLimit.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') {
          deviceLimitReached = true;
        } else if (normalized == 'false' || normalized == '0') {
          deviceLimitReached = false;
        }
      } else if (currentAgents != null && maxAgents != null) {
        deviceLimitReached = currentAgents! >= maxAgents!;
      }
      final rawFeatures = payload['features'];
      if (rawFeatures is Map) {
        final features = rawFeatures.cast<dynamic, dynamic>();
        canUseTunnels = features['tunnels'] == true;
        canUsePushNotifications = features['pushNotifications'] == true ||
            features['push_notifications'] == true;
        canUseDeferredTurns = features['deferredTurns'] == true ||
            features['deferred_turns'] == true;
      } else {
        canUseTunnels = false;
        canUsePushNotifications = false;
        canUseDeferredTurns = false;
      }
      unawaited(syncNativePushRegistration());
      if (notifyListenersNow) {
        _notifyListenersSafe();
      }
    } catch (error) {
      if (await _logoutIfUnauthorized(error)) {
        return;
      }
    }
  }

  Future<void> bootstrapData(
      {String? storedAgentId,
      String? storedWorkspaceId,
      String? storedConversationId}) async {
    loadingData = true;
    _notifyListenersSafe();
    try {
      await loadEntitlements(notifyListenersNow: false);
      final loadedAgents = await api.listAgents(accessToken!);
      agents = loadedAgents.map((e) => Agent.fromJson(e)).toList();

      if (agents.isNotEmpty) {
        _selectedAgent = agents.firstWhere(
          (a) => a.id == storedAgentId,
          orElse: () =>
              agents.firstWhere((a) => a.isOnline, orElse: () => agents.first),
        );

        await loadWorkspacesForSelectedAgent(
            storedWorkspaceId: storedWorkspaceId);
        await loadCodexOptions();

        if (selectedWorkspace != null) {
          await loadConversations(
            preferredConversationId: storedConversationId,
          );
          await loadDevSettings();
          await loadServices();
          await loadTunnels();
        }
      } else {
        workspaces = [];
        conversations = [];
        _conversationsWorkspaceId = null;
        turns = [];
        services = [];
        tunnels = [];
        trustedDevMode = false;
        selectedServiceId = null;
        _selectedAgent = null;
        _selectedWorkspace = null;
        _selectedConversation = null;
      }
      _notifyListenersSafe();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      _notifyListenersSafe();
    } finally {
      loadingData = false;
      _notifyListenersSafe();
    }
  }

  Future<void> loadWorkspacesForSelectedAgent(
      {String? storedWorkspaceId}) async {
    if (selectedAgent == null) return;
    try {
      final previousWorkspaceId = _selectedWorkspace?.id;
      final loaded =
          await api.listWorkspaces(accessToken!, agentId: selectedAgent!.id);
      workspaces = loaded.map((e) => Workspace.fromJson(e)).toList();

      if (workspaces.isNotEmpty) {
        _selectedWorkspace = workspaces.firstWhere(
          (w) => w.id == storedWorkspaceId,
          orElse: () => workspaces.first,
        );
        if (_selectedWorkspace?.id != previousWorkspaceId) {
          _selectedConversation = null;
          conversations = [];
          _conversationsWorkspaceId = null;
          turns = [];
          services = [];
          tunnels = [];
          trustedDevMode = false;
          selectedServiceId = null;
        }
      } else {
        _selectedWorkspace = null;
        _selectedConversation = null;
        conversations = [];
        _conversationsWorkspaceId = null;
        turns = [];
        services = [];
        tunnels = [];
        trustedDevMode = false;
        selectedServiceId = null;
      }
      _notifyListenersSafe();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      _notifyListenersSafe();
    }
  }

  Future<void> loadConversations({String? preferredConversationId}) async {
    final workspace = selectedWorkspace;
    final token = accessToken;
    if (workspace == null || token == null) return;
    final workspaceId = workspace.id;
    final requestToken = ++_loadConversationsRequestToken;
    try {
      final loaded = await api.listConversations(
        accessToken: token,
        workspaceId: workspaceId,
      );
      if (requestToken != _loadConversationsRequestToken) {
        return;
      }
      if (selectedWorkspace?.id != workspaceId) {
        return;
      }

      conversations = loaded.map((e) => Conversation.fromJson(e)).toList();
      _conversationsWorkspaceId = workspaceId;
      _sortConversationsByActivity();

      final preferredId = preferredConversationId?.trim() ?? '';
      Conversation? preferred;
      if (preferredId.isNotEmpty) {
        for (final entry in conversations) {
          if (entry.id == preferredId) {
            preferred = entry;
            break;
          }
        }
      }

      // Pick default conversation if current selection is missing.
      if (conversations.isNotEmpty) {
        if (_selectedConversation == null ||
            _selectedConversation!.workspaceId != workspaceId ||
            !conversations.any((c) => c.id == _selectedConversation!.id)) {
          _selectedConversation = preferred ?? conversations.first;
          unawaited(persistSession());
          await loadTurns(_selectedConversation!.id);
        }
      } else {
        _selectedConversation = null;
        turns = [];
        unawaited(persistSession());
      }
      _notifyListenersSafe();
    } catch (e) {
      if (requestToken != _loadConversationsRequestToken) {
        return;
      }
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      _notifyListenersSafe();
    }
  }

  Future<void> _refreshAfterCodexSyncEvent({String? agentId}) async {
    if (_realtimeSyncRefreshInProgress) {
      return;
    }
    if (accessToken == null || selectedAgent == null) {
      return;
    }
    final normalizedAgentId = agentId?.trim();
    if (normalizedAgentId != null &&
        normalizedAgentId.isNotEmpty &&
        normalizedAgentId != selectedAgent!.id) {
      return;
    }

    _realtimeSyncRefreshInProgress = true;
    try {
      await loadWorkspacesForSelectedAgent(
          storedWorkspaceId: selectedWorkspace?.id);
      if (selectedWorkspace != null) {
        await loadConversations();
        await loadDevSettings();
        await loadServices();
        await loadTunnels();
      }
    } finally {
      _realtimeSyncRefreshInProgress = false;
    }
  }

  Future<void> loadTurns(String conversationId) async {
    final token = accessToken;
    if (token == null || conversationId.trim().isEmpty) {
      return;
    }
    final runtime = _runtimeByConversation.putIfAbsent(
      conversationId,
      () => ConversationRuntimeTrace(),
    );
    if (_loadTurnsInFlightConversationIds.contains(conversationId)) {
      runtime.turnsReloadSkippedInFlight += 1;
      return;
    }
    final now = DateTime.now();
    final lastLoadAt = _lastLoadTurnsAtByConversation[conversationId];
    if (lastLoadAt != null &&
        now.difference(lastLoadAt) < const Duration(milliseconds: 700)) {
      runtime.turnsReloadThrottled += 1;
      return;
    }
    _loadTurnsInFlightConversationIds.add(conversationId);
    _lastLoadTurnsAtByConversation[conversationId] = now;
    runtime.turnsReloadApiCalls += 1;
    final requestToken = ++_loadTurnsRequestToken;
    final expectedWorkspaceId = _selectedWorkspace?.id;
    try {
      var payload = await api.getConversationTurns(
        accessToken: token,
        conversationId: conversationId,
      );
      final hydration = _asStringKeyedMap(payload['hydration']);
      final hydrationReason = hydration?['reason']?.toString().trim();
      if (hydrationReason == 'legacy_turns_purged') {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'turns.resync',
          message: 'legacy detected and purged; strict resync requested',
        );
        payload = await api.getConversationTurns(
          accessToken: token,
          conversationId: conversationId,
          forceHydrate: true,
        );
      }
      final loaded = ((payload['items'] as List?) ?? [])
          .cast<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
      List<Turn> decodedTurns;
      try {
        decodedTurns = loaded
            .map((raw) => _decryptTurnForUi(Turn.fromJson(raw)))
            .toList(growable: false);
      } on E2ERuntimeException catch (error) {
        if (error.code != 'e2e_unknown_sender_device') {
          rethrow;
        }
        final synced = await _syncE2EPeersFromServer();
        if (!synced) {
          rethrow;
        }
        decodedTurns = loaded
            .map((raw) => _decryptTurnForUi(Turn.fromJson(raw)))
            .toList(growable: false);
      }
      if (requestToken != _loadTurnsRequestToken) {
        return;
      }
      if (_selectedConversation?.id != conversationId) {
        return;
      }
      if (expectedWorkspaceId != null &&
          _selectedWorkspace?.id != expectedWorkspaceId) {
        return;
      }

      turns = decodedTurns;
      for (final turn in decodedTurns) {
        _hydrateTimelineFromTurn(turn);
      }
      String? runningTurnId;
      for (final turn in decodedTurns) {
        if (_turnCountsAsRunning(turn)) {
          runningTurnId = turn.id;
        }
      }
      if (runningTurnId != null) {
        activeTurnId = runningTurnId;
      } else if (_selectedConversation?.id == conversationId) {
        activeTurnId = null;
      }
      unawaited(_persistE2ERuntime());
      _notifyListenersSafe();
    } on E2ERuntimeException catch (error) {
      if (requestToken != _loadTurnsRequestToken) {
        return;
      }
      if (_selectedConversation?.id != conversationId) {
        return;
      }
      debugPrint(
        '[mobile-auth] turn hydration failed for $conversationId with code=${error.code}',
      );
      turns = [];
      if (error.code == 'e2e_runtime_unavailable') {
        status =
            'Login complete. Secure scan is required to read encrypted history.';
      } else {
        status =
            'Encrypted history could not be decrypted (${error.code}). Start a new conversation or complete secure scan.';
      }
      _notifyListenersSafe();
    } catch (e) {
      if (requestToken != _loadTurnsRequestToken) {
        return;
      }
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      _notifyListenersSafe();
    } finally {
      _loadTurnsInFlightConversationIds.remove(conversationId);
    }
  }

  Future<void> loadCodexOptions() async {
    if (selectedAgent == null || !selectedAgent!.isOnline) return;

    loadingCodexOptions = true;
    _notifyListenersSafe();

    try {
      final payload = await api.getCodexOptions(
        accessToken: accessToken!,
        agentId: selectedAgent!.id,
        cwd: selectedWorkspace?.path,
      );
      applyCodexOptionsPayload(payload);
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      debugPrint('Load codex options error: $e');
    } finally {
      loadingCodexOptions = false;
      _notifyListenersSafe();
    }
  }
}
