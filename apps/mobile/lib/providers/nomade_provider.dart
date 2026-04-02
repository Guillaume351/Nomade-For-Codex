import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/nomade_api.dart';
import '../models/agent.dart';
import '../models/conversation.dart';
import '../models/dev_service.dart';
import '../models/session_stream_chunk.dart';
import '../models/tunnel.dart';
import '../models/turn.dart';
import '../models/turn_timeline.dart';
import '../models/workspace.dart';

class ConversationDebugEvent {
  ConversationDebugEvent({
    required this.at,
    required this.type,
    required this.message,
  });

  final DateTime at;
  final String type;
  final String message;
}

class ConversationRuntimeTrace {
  DateTime? requestedAt;
  DateTime? startedAt;
  DateTime? completedAt;
  String? requestedCwd;
  String? requestedModel;
  String? requestedApprovalPolicy;
  String? requestedSandboxMode;
  String? requestedEffort;
  String? threadId;
  String? turnId;
  String? codexTurnId;
  String? turnStatus;
  String? turnError;
  int eventsReceived = 0;
  int eventsRendered = 0;
  final Set<String> unsupportedMethods = <String>{};
}

class NomadeProvider with ChangeNotifier {
  NomadeProvider({required String baseUrl}) : api = NomadeApi(baseUrl: baseUrl);

  final NomadeApi api;
  final _storage = const FlutterSecureStorage();

  static const _accessTokenKey = 'nomade.access_token';
  static const _refreshTokenKey = 'nomade.refresh_token';
  static const _accessTokenExpiryKey = 'nomade.access_token_expiry_iso';
  static const _selectedAgentKey = 'nomade.selected_agent_id';
  static const _selectedWorkspaceKey = 'nomade.selected_workspace_id';
  static const _selectedModelKey = 'nomade.selected_model';
  static const _selectedApprovalPolicyKey = 'nomade.selected_approval_policy';
  static const _selectedSandboxModeKey = 'nomade.selected_sandbox_mode';
  static const _selectedEffortKey = 'nomade.selected_effort';
  static const _selectedCollaborationModeKey =
      'nomade.selected_collaboration_mode';
  static const _selectedSkillsKey = 'nomade.selected_skills_json';

  String status = 'Idle';
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiresAt;

  List<Agent> agents = [];
  List<Workspace> workspaces = [];
  List<Conversation> conversations = [];
  List<Turn> turns = [];
  List<DevService> services = [];
  List<TunnelPreview> tunnels = [];
  final Map<String, StringBuffer> sessionLogsBySession = {};
  final List<SessionStreamChunk> sessionChunks = [];
  final Map<String, List<ConversationDebugEvent>> _debugEventsByConversation =
      {};
  final Map<String, ConversationRuntimeTrace> _runtimeByConversation = {};
  final Map<String, TurnTimeline> _timelineByTurn = {};
  bool trustedDevMode = false;
  bool loadingServices = false;
  bool loadingTunnels = false;
  String? selectedServiceId;

  Agent? _selectedAgent;
  Agent? get selectedAgent => _selectedAgent;
  set selectedAgent(Agent? value) {
    if (_selectedAgent == value) return;
    _selectedAgent = value;
    persistSession();
    notifyListeners();
  }

  Workspace? _selectedWorkspace;
  Workspace? get selectedWorkspace => _selectedWorkspace;
  set selectedWorkspace(Workspace? value) {
    if (_selectedWorkspace == value) return;
    _selectedWorkspace = value;
    persistSession();
    notifyListeners();
  }

  Conversation? _selectedConversation;
  Conversation? get selectedConversation => _selectedConversation;
  set selectedConversation(Conversation? value) {
    if (_selectedConversation == value) return;
    _selectedConversation = value;
    if (value != null) {
      _appendConversationDebugEvent(
        conversationId: value.id,
        type: 'conversation.selected',
        message:
            'workspace=${value.workspaceId} thread=${value.codexThreadId ?? "-"}',
      );
    }
    persistSession();
    notifyListeners();
  }

  DevService? get selectedService {
    final id = selectedServiceId;
    if (id == null) {
      return null;
    }
    for (final service in services) {
      if (service.id == id) {
        return service;
      }
    }
    return null;
  }

  ConversationRuntimeTrace? runtimeTraceForConversation(String conversationId) {
    if (conversationId.isEmpty) {
      return null;
    }
    return _runtimeByConversation[conversationId];
  }

  List<ConversationDebugEvent> debugEventsForConversation(
    String conversationId, {
    int limit = 12,
  }) {
    if (conversationId.isEmpty) {
      return const [];
    }
    final events = _debugEventsByConversation[conversationId];
    if (events == null || events.isEmpty) {
      return const [];
    }
    if (events.length <= limit) {
      return List<ConversationDebugEvent>.unmodifiable(events);
    }
    return List<ConversationDebugEvent>.unmodifiable(
      events.sublist(events.length - limit),
    );
  }

  String buildConversationDebugReport(String conversationId) {
    final conversation = _findConversationById(conversationId);
    final runtime = runtimeTraceForConversation(conversationId);
    final events = debugEventsForConversation(conversationId, limit: 20);
    final agent = selectedAgent;
    final workspace = selectedWorkspace;

    final lines = <String>[
      'generatedAt=${DateTime.now().toIso8601String()}',
      'apiBaseUrl=${api.baseUrl}',
      'status=$status',
      'socket=${realtimeConnected ? "connected" : "disconnected"}',
      'agentId=${agent?.id ?? "-"}',
      'agentOnline=${agent?.isOnline == true ? "true" : "false"}',
      'workspaceId=${workspace?.id ?? "-"}',
      'workspacePath=${workspace?.path ?? "-"}',
      'workspaceTrustedDev=${trustedDevMode ? "true" : "false"}',
      'conversationId=${conversation?.id ?? conversationId}',
      'conversationStatus=${conversation?.status ?? "-"}',
      'conversationThread=${conversation?.codexThreadId ?? "-"}',
      'selectedModel=${selectedModel ?? "-"}',
      'selectedApproval=${selectedApprovalPolicy ?? "-"}',
      'selectedSandbox=${selectedSandboxMode ?? "-"}',
      'selectedEffort=${selectedEffort ?? "-"}',
      'selectedCollaborationMode=${selectedCollaborationModeSlug ?? "-"}',
      'selectedSkills=${_selectedSkillPaths.isEmpty ? "-" : _selectedSkillPaths.join(",")}',
      'runtimeTurnId=${runtime?.turnId ?? "-"}',
      'runtimeCodexTurnId=${runtime?.codexTurnId ?? "-"}',
      'runtimeThreadId=${runtime?.threadId ?? "-"}',
      'runtimeTurnStatus=${runtime?.turnStatus ?? "-"}',
      'runtimeTurnError=${runtime?.turnError ?? "-"}',
      'runtimeRequestedAt=${runtime?.requestedAt?.toIso8601String() ?? "-"}',
      'runtimeStartedAt=${runtime?.startedAt?.toIso8601String() ?? "-"}',
      'runtimeCompletedAt=${runtime?.completedAt?.toIso8601String() ?? "-"}',
      'runtimeRequestedCwd=${runtime?.requestedCwd ?? "-"}',
      'runtimeRequestedModel=${runtime?.requestedModel ?? "-"}',
      'runtimeRequestedApproval=${runtime?.requestedApprovalPolicy ?? "-"}',
      'runtimeRequestedSandbox=${runtime?.requestedSandboxMode ?? "-"}',
      'runtimeRequestedEffort=${runtime?.requestedEffort ?? "-"}',
      'eventsReceived=${runtime?.eventsReceived ?? 0}',
      'eventsRendered=${runtime?.eventsRendered ?? 0}',
      'eventsNotRenderedMethods=${runtime == null || runtime.unsupportedMethods.isEmpty ? "-" : runtime.unsupportedMethods.join(",")}',
    ];

    if (events.isNotEmpty) {
      lines.add('events=');
      for (final event in events) {
        lines.add(
          '  ${event.at.toIso8601String()} ${event.type} ${event.message}',
        );
      }
    }

    return lines.join('\n');
  }

  String? activeTurnId;

  // Codex Options
  List<Map<String, dynamic>> codexModels = [];
  List<Map<String, dynamic>> codexCollaborationModes = [];
  List<Map<String, dynamic>> codexSkills = [];
  List<String> codexApprovalPolicies = [
    'untrusted',
    'on-failure',
    'on-request',
    'never'
  ];
  List<String> codexSandboxModes = [
    'read-only',
    'workspace-write',
    'danger-full-access'
  ];
  List<String> codexReasoningEfforts = [
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh'
  ];

  String? _selectedModel;
  String? get selectedModel => _selectedModel;
  set selectedModel(String? value) {
    if (_selectedModel == value) return;
    _selectedModel = value;
    persistSession();
    notifyListeners();
  }

  String? _selectedApprovalPolicy = 'on-request';
  String? get selectedApprovalPolicy => _selectedApprovalPolicy;
  set selectedApprovalPolicy(String? value) {
    if (_selectedApprovalPolicy == value) return;
    _selectedApprovalPolicy = value;
    persistSession();
    notifyListeners();
  }

  String? _selectedSandboxMode = 'workspace-write';
  String? get selectedSandboxMode => _selectedSandboxMode;
  set selectedSandboxMode(String? value) {
    if (_selectedSandboxMode == value) return;
    _selectedSandboxMode = value;
    persistSession();
    notifyListeners();
  }

  String? _selectedEffort = 'medium';
  String? get selectedEffort => _selectedEffort;
  set selectedEffort(String? value) {
    if (_selectedEffort == value) return;
    _selectedEffort = value;
    persistSession();
    notifyListeners();
  }

  bool loadingCodexOptions = false;
  bool importingHistory = false;
  bool loadingData = false;

  WebSocketChannel? socket;
  StreamSubscription<dynamic>? socketSub;
  Timer? reconnectTimer;
  int reconnectAttempts = 0;
  bool realtimeConnected = false;

  bool secureStorageAvailable = true;

  String? _selectedCollaborationModeSlug;
  String? get selectedCollaborationModeSlug => _selectedCollaborationModeSlug;
  set selectedCollaborationModeSlug(String? value) {
    if (_selectedCollaborationModeSlug == value) return;
    _selectedCollaborationModeSlug = value;
    persistSession();
    notifyListeners();
  }

  List<String> _selectedSkillPaths = [];
  List<String> get selectedSkillPaths =>
      List<String>.unmodifiable(_selectedSkillPaths);

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
    notifyListeners();
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
    notifyListeners();
  }

  TurnTimeline timelineForTurn(String turnId) {
    return _timelineByTurn.putIfAbsent(
        turnId, () => TurnTimeline(turnId: turnId));
  }

  TurnTimeline? tryTimelineForTurn(String turnId) {
    return _timelineByTurn[turnId];
  }

  bool get isAuthenticated => accessToken != null;

  Future<void> startup() async {
    await restoreSession();
  }

  Future<void> restoreSession() async {
    try {
      accessToken = await _storage.read(key: _accessTokenKey);
      refreshToken = await _storage.read(key: _refreshTokenKey);
      final expiry = await _storage.read(key: _accessTokenExpiryKey);
      accessTokenExpiresAt = expiry != null ? DateTime.tryParse(expiry) : null;

      final storedAgentId = await _storage.read(key: _selectedAgentKey);
      final storedWorkspaceId = await _storage.read(key: _selectedWorkspaceKey);
      _selectedModel = await _storage.read(key: _selectedModelKey);
      _selectedApprovalPolicy =
          await _storage.read(key: _selectedApprovalPolicyKey) ??
              _selectedApprovalPolicy;
      _selectedSandboxMode =
          await _storage.read(key: _selectedSandboxModeKey) ??
              _selectedSandboxMode;
      _selectedEffort =
          await _storage.read(key: _selectedEffortKey) ?? _selectedEffort;
      _selectedCollaborationModeSlug =
          await _storage.read(key: _selectedCollaborationModeKey);
      final selectedSkillsRaw = await _storage.read(key: _selectedSkillsKey);
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

      if (accessToken != null) {
        status = 'Restoring session...';
        notifyListeners();

        final ready = await ensureFreshToken();
        if (ready) {
          status = 'Authenticated';
          await connectSocket();
          await bootstrapData(
            storedAgentId: storedAgentId,
            storedWorkspaceId: storedWorkspaceId,
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
    notifyListeners();
  }

  Future<void> persistSession() async {
    if (!secureStorageAvailable) return;

    try {
      if (accessToken == null) {
        await _storage.deleteAll();
        return;
      }

      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
        if (accessTokenExpiresAt != null)
          _storage.write(
              key: _accessTokenExpiryKey,
              value: accessTokenExpiresAt!.toIso8601String()),
        _storage.write(key: _selectedAgentKey, value: _selectedAgent?.id),
        _storage.write(
            key: _selectedWorkspaceKey, value: _selectedWorkspace?.id),
        _storage.write(key: _selectedModelKey, value: _selectedModel),
        _storage.write(
            key: _selectedApprovalPolicyKey, value: _selectedApprovalPolicy),
        _storage.write(
            key: _selectedSandboxModeKey, value: _selectedSandboxMode),
        _storage.write(key: _selectedEffortKey, value: _selectedEffort),
        _storage.write(
            key: _selectedCollaborationModeKey,
            value: _selectedCollaborationModeSlug),
        _storage.write(
            key: _selectedSkillsKey, value: jsonEncode(_selectedSkillPaths)),
      ]);
    } catch (e) {
      debugPrint('Persist session error: $e');
    }
  }

  Future<void> logout() async {
    if (accessToken != null && refreshToken != null) {
      try {
        await api.logout(
            accessToken: accessToken!, refreshToken: refreshToken!);
      } catch (_) {}
    }

    accessToken = null;
    refreshToken = null;
    accessTokenExpiresAt = null;
    agents = [];
    workspaces = [];
    conversations = [];
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
    activeTurnId = null;
    status = 'Logged out';

    reconnectTimer?.cancel();
    socketSub?.cancel();
    socket?.sink.close();
    realtimeConnected = false;

    await _storage.deleteAll();
    notifyListeners();
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

    return refreshTokens();
  }

  Future<bool> refreshTokens() async {
    if (refreshToken == null) return false;
    try {
      final payload = await api.refreshAccessToken(refreshToken!);
      _setTokensFromPayload(payload);
      await persistSession();
      return true;
    } catch (_) {
      return false;
    }
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

  Future<bool> _logoutIfUnauthorized(Object error) async {
    if (!_isUnauthorizedError(error)) {
      return false;
    }
    await logout();
    status = 'Session expired. Please sign in again.';
    notifyListeners();
    return true;
  }

  Future<void> bootstrapData(
      {String? storedAgentId, String? storedWorkspaceId}) async {
    loadingData = true;
    notifyListeners();
    try {
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
          await loadConversations();
          await loadDevSettings();
          await loadServices();
          await loadTunnels();
        } else {
          await importCodexHistory(silent: true);
        }
      } else {
        workspaces = [];
        conversations = [];
        turns = [];
        services = [];
        tunnels = [];
        trustedDevMode = false;
        selectedServiceId = null;
        _selectedAgent = null;
        _selectedWorkspace = null;
        _selectedConversation = null;
      }
      notifyListeners();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      notifyListeners();
    } finally {
      loadingData = false;
      notifyListeners();
    }
  }

  Future<void> loadWorkspacesForSelectedAgent(
      {String? storedWorkspaceId}) async {
    if (selectedAgent == null) return;
    try {
      final loaded =
          await api.listWorkspaces(accessToken!, agentId: selectedAgent!.id);
      workspaces = loaded.map((e) => Workspace.fromJson(e)).toList();

      if (workspaces.isNotEmpty) {
        _selectedWorkspace = workspaces.firstWhere(
          (w) => w.id == storedWorkspaceId,
          orElse: () => workspaces.first,
        );
      } else {
        _selectedWorkspace = null;
        _selectedConversation = null;
        conversations = [];
        turns = [];
        services = [];
        tunnels = [];
        trustedDevMode = false;
        selectedServiceId = null;
      }
      notifyListeners();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> loadConversations() async {
    if (selectedWorkspace == null) return;
    try {
      final loaded = await api.listConversations(
          accessToken: accessToken!, workspaceId: selectedWorkspace!.id);
      conversations = loaded.map((e) => Conversation.fromJson(e)).toList();

      // Pick first conversation by default if none selected or not in current list
      if (conversations.isNotEmpty) {
        if (_selectedConversation == null ||
            !conversations.any((c) => c.id == _selectedConversation!.id)) {
          _selectedConversation = conversations.first;
          await loadTurns(_selectedConversation!.id);
        }
      } else {
        _selectedConversation = null;
        turns = [];
      }
      notifyListeners();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> loadTurns(String conversationId) async {
    try {
      final loaded = await api.listConversationTurns(
          accessToken: accessToken!, conversationId: conversationId);
      turns = loaded.map((e) => Turn.fromJson(e)).toList();
      for (final turn in turns) {
        _hydrateTimelineFromTurn(turn);
      }
      notifyListeners();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      status = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> loadCodexOptions() async {
    if (selectedAgent == null || !selectedAgent!.isOnline) return;

    loadingCodexOptions = true;
    notifyListeners();

    try {
      final payload = await api.getCodexOptions(
        accessToken: accessToken!,
        agentId: selectedAgent!.id,
        cwd: selectedWorkspace?.path,
      );

      codexModels = ((payload['models'] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
      codexCollaborationModes = ((payload['collaborationModes'] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
      codexSkills = ((payload['skills'] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();

      final approvalPolicies = ((payload['approvalPolicies'] as List?) ?? [])
          .whereType<String>()
          .toList();
      final sandboxModes = ((payload['sandboxModes'] as List?) ?? [])
          .whereType<String>()
          .toList();
      final reasoningEfforts = ((payload['reasoningEfforts'] as List?) ?? [])
          .whereType<String>()
          .toList();
      final defaults =
          (payload['defaults'] as Map?)?.cast<String, dynamic>() ?? {};

      if (approvalPolicies.isNotEmpty) codexApprovalPolicies = approvalPolicies;
      if (sandboxModes.isNotEmpty) codexSandboxModes = sandboxModes;
      if (reasoningEfforts.isNotEmpty) codexReasoningEfforts = reasoningEfforts;

      final defaultModel = defaults['model'] is String
          ? (defaults['model'] as String).trim()
          : null;
      final defaultApproval = defaults['approvalPolicy'] is String
          ? (defaults['approvalPolicy'] as String).trim()
          : null;
      final defaultSandbox = defaults['sandboxMode'] is String
          ? (defaults['sandboxMode'] as String).trim()
          : null;
      final defaultEffort = defaults['effort'] is String
          ? (defaults['effort'] as String).trim()
          : null;

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

      // Fallback if still null
      if (_selectedModel == null && codexModels.isNotEmpty) {
        _selectedModel = codexModels.first['model'] as String?;
      }

      final availableSlugs = codexCollaborationModes
          .map((entry) => entry['slug'])
          .whereType<String>()
          .toSet();
      if (_selectedCollaborationModeSlug == null &&
          codexCollaborationModes.isNotEmpty) {
        _selectedCollaborationModeSlug =
            codexCollaborationModes.first['slug']?.toString();
      } else if (_selectedCollaborationModeSlug != null &&
          !availableSlugs.contains(_selectedCollaborationModeSlug)) {
        _selectedCollaborationModeSlug = codexCollaborationModes.isNotEmpty
            ? codexCollaborationModes.first['slug']?.toString()
            : null;
      }

      final availableSkillPaths =
          codexSkills.map((entry) => entry['path']).whereType<String>().toSet();
      _selectedSkillPaths = _selectedSkillPaths
          .where((path) => availableSkillPaths.contains(path))
          .toList()
        ..sort();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      debugPrint('Load codex options error: $e');
    } finally {
      loadingCodexOptions = false;
      notifyListeners();
    }
  }

  Future<void> loadDevSettings() async {
    if (selectedWorkspace == null || accessToken == null) return;
    try {
      final payload = await api.getWorkspaceDevSettings(
        accessToken: accessToken!,
        workspaceId: selectedWorkspace!.id,
      );
      trustedDevMode = payload['trustedDevMode'] == true;
      notifyListeners();
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
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> loadServices() async {
    if (selectedWorkspace == null || accessToken == null) return;
    loadingServices = true;
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> loadTunnels() async {
    if (selectedWorkspace == null || accessToken == null) return;
    loadingTunnels = true;
    notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> refreshServiceState(String serviceId) async {
    if (accessToken == null) return;
    try {
      final payload = await api.getServiceState(
        accessToken: accessToken!,
        serviceId: serviceId,
      );
      _upsertService(DevService.fromJson(payload));
      notifyListeners();
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
      notifyListeners();
      return payload['previewUrl']?.toString();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return null;
      }
      status = 'Issue token failed: $e';
      notifyListeners();
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
      notifyListeners();
      return payload['previewUrl']?.toString();
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return null;
      }
      status = 'Rotate token failed: $e';
      notifyListeners();
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
    notifyListeners();
  }

  void sendSessionInput(String sessionId, String data) {
    if (socket == null) return;
    socket!.sink.add(jsonEncode({
      'type': 'session.input',
      'sessionId': sessionId,
      'data': data,
    }));
  }

  void respondToServerRequest({
    required String conversationId,
    required String turnId,
    required String requestId,
    dynamic result,
    String? error,
  }) {
    if (socket == null) {
      return;
    }
    socket!.sink.add(jsonEncode({
      'type': 'conversation.server.response',
      'conversationId': conversationId,
      'turnId': turnId,
      'requestId': requestId,
      if (result != null) 'result': result,
      if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
    }));

    final timeline = timelineForTurn(turnId);
    final item = timeline.upsertItem(
      itemId: 'server-request-$requestId',
      itemType: 'serverRequest',
    );
    final status = error != null && error.trim().isNotEmpty
        ? 'failed'
        : result is String &&
                (result == 'decline' ||
                    result == 'cancel' ||
                    result == 'declined')
            ? 'declined'
            : 'completed';
    item.applyCompleted(itemType: 'serverRequest', payload: {
      'status': status,
      if (result != null) 'result': result,
      if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
    });
    _appendConversationDebugEvent(
      conversationId: conversationId,
      type: 'server.response',
      message:
          'turn=$turnId request=$requestId status=$status${error != null && error.trim().isNotEmpty ? ' error=$error' : ''}',
    );
    notifyListeners();
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
    notifyListeners();
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

  void _patchConversationLocal(
    String conversationId, {
    String? threadId,
    String? status,
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
      title: current.title,
      status: status ?? current.status,
      codexThreadId: threadId ?? current.codexThreadId,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    conversations[idx] = updated;
    if (_selectedConversation?.id == conversationId) {
      _selectedConversation = updated;
    }
  }

  Future<void> connectSocket() async {
    if (accessToken == null) return;
    try {
      await socketSub?.cancel();
      await socket?.sink.close();
      socket = api.openUserSocket(accessToken!);
      socketSub = socket!.stream.listen(
        _onSocketEvent,
        onError: (e) => _handleSocketDisconnected('Socket error: $e'),
        onDone: () => _handleSocketDisconnected('Socket closed'),
      );
      realtimeConnected = true;
      final conversationId = _selectedConversation?.id;
      if (conversationId != null) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'socket.connected',
          message: 'Realtime stream opened',
        );
      }
      notifyListeners();
    } catch (e) {
      _handleSocketDisconnected('Connection failed');
    }
  }

  void _onSocketEvent(dynamic raw) {
    final event = jsonDecode(raw as String) as Map<String, dynamic>;
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
      notifyListeners();
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
      notifyListeners();
      return;
    } else if (type == 'tunnel.status') {
      final tunnelId = event['tunnelId']?.toString();
      final statusValue = event['status']?.toString() ?? 'unknown';
      final probeStatus = event['probeStatus']?.toString();
      final probeCode = (event['probeCode'] as num?)?.toInt();
      final detail = event['detail']?.toString();
      final probeAt = event['probeAt']?.toString();
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
      notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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
        notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
      return;
    } else if (type == 'conversation.thread.status.changed') {
      final conversationId = event['conversationId']?.toString() ?? '';
      final statusValue = event['status']?.toString() ?? 'unknown';
      if (conversationId.isNotEmpty) {
        _appendConversationDebugEvent(
          conversationId: conversationId,
          type: 'thread.status.changed',
          message: 'status=$statusValue',
        );
        _trackConversationEvent(
          conversationId: conversationId,
          method: 'conversation.thread.status.changed',
          rendered: true,
        );
      }
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
      notifyListeners();
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
      notifyListeners();
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
        if (activeTurnId == turnId) activeTurnId = null;
        // Reload turns to get metrics and final state
        if (conversationId.isNotEmpty) {
          loadTurns(conversationId);
        } else if (selectedConversation != null) {
          loadTurns(selectedConversation!.id);
        }
      }
      notifyListeners();
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
      }
      notifyListeners();
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
      notifyListeners();
      return;
    }
    // Handle other events...
  }

  void _handleSocketDisconnected(String reason) {
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
    notifyListeners();
    // Reconnect logic...
  }

  Future<void> sendPrompt(String prompt) async {
    if (accessToken == null) return;

    try {
      if (selectedWorkspace == null) {
        final ready = await createDefaultWorkspace();
        if (!ready) {
          status = 'No workspace available';
          notifyListeners();
          return;
        }
      }

      if (selectedConversation == null) {
        final created = await createConversation(
          title: prompt.split('\n').first.trim(),
        );
        if (!created) {
          status = 'Unable to create conversation';
          notifyListeners();
          return;
        }
      }

      final requestedAt = DateTime.now();
      final conversationId = selectedConversation!.id;
      final requestedCwd = selectedWorkspace?.path;
      final requestedModel = selectedModel;
      final requestedApproval = selectedApprovalPolicy;
      final requestedSandbox = selectedSandboxMode;
      final requestedEffort = selectedEffort;

      _appendConversationDebugEvent(
        conversationId: conversationId,
        type: 'turn.create.request',
        message:
            'cwd=${requestedCwd ?? "-"} sandbox=${requestedSandbox ?? "-"} approval=${requestedApproval ?? "-"} model=${requestedModel ?? "-"} effort=${requestedEffort ?? "-"} collaboration=${_selectedCollaborationModeSlug ?? "-"} skills=${_selectedSkillPaths.length}',
      );

      final inputItems = <Map<String, dynamic>>[
        {
          'type': 'text',
          'text': prompt,
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

      Map<String, dynamic>? collaborationMode;
      if (_selectedCollaborationModeSlug != null) {
        final selectedMode = codexCollaborationModes.firstWhere(
          (entry) =>
              entry['slug']?.toString() == _selectedCollaborationModeSlug,
          orElse: () => {},
        );
        final value = selectedMode['value'];
        if (value is Map) {
          collaborationMode = value.cast<String, dynamic>();
        }
      }

      final turn = await api.createTurn(
        accessToken: accessToken!,
        conversationId: conversationId,
        prompt: prompt,
        inputItems: inputItems,
        collaborationMode: collaborationMode,
        model: requestedModel,
        cwd: requestedCwd,
        approvalPolicy: requestedApproval,
        sandboxMode: requestedSandbox,
        effort: requestedEffort,
      );

      activeTurnId = turn['id'] as String;
      final runtime = _runtimeByConversation.putIfAbsent(
          conversationId, () => ConversationRuntimeTrace());
      runtime.requestedAt = requestedAt;
      runtime.requestedCwd = requestedCwd;
      runtime.requestedModel = requestedModel;
      runtime.requestedApprovalPolicy = requestedApproval;
      runtime.requestedSandboxMode = requestedSandbox;
      runtime.requestedEffort = requestedEffort;
      runtime.turnId = activeTurnId;
      runtime.turnStatus = 'queued';
      runtime.turnError = null;
      runtime.startedAt = null;
      runtime.completedAt = null;

      _appendConversationDebugEvent(
        conversationId: conversationId,
        type: 'turn.create.accepted',
        message: 'turn=${activeTurnId ?? "-"}',
      );

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
      notifyListeners();
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
      notifyListeners();
    }
  }

  // Device Code Login Flow
  String? deviceCode;
  String? userCode;

  Future<Map<String, String>> startLogin() async {
    final started = await api.startDeviceCode();
    deviceCode = started['deviceCode'] as String;
    userCode = started['userCode'] as String;
    return {'userCode': userCode!, 'deviceCode': deviceCode!};
  }

  Future<void> approveAndPoll(String email) async {
    if (userCode == null || deviceCode == null) return;

    await api.approveDeviceCode(userCode: userCode!, email: email);

    while (true) {
      final polled = await api.pollDeviceCode(deviceCode!);
      final pollStatus = polled['status'] as String? ?? 'pending';
      if (pollStatus == 'ok') {
        _setTokensFromPayload(polled);
        await persistSession();
        status = 'Authenticated';
        await connectSocket();
        await bootstrapData();
        break;
      } else if (pollStatus == 'expired') {
        status = 'Expired';
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    notifyListeners();
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
    notifyListeners();

    await loadWorkspacesForSelectedAgent();
    await loadCodexOptions();
    if (selectedWorkspace != null) {
      await loadConversations();
      await loadDevSettings();
      await loadServices();
      await loadTunnels();
    } else {
      await importCodexHistory(silent: true);
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
    notifyListeners();
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
      notifyListeners();
      return selectedWorkspace != null;
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return false;
      }
      status = 'Workspace creation failed: $e';
      notifyListeners();
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
      _selectedConversation = conversation;
      turns = [];
      _appendConversationDebugEvent(
        conversationId: conversation.id,
        type: 'conversation.created',
        message: 'workspace=${conversation.workspaceId}',
      );
      notifyListeners();
      return true;
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return false;
      }
      status = 'Conversation creation failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> importCodexHistory({bool silent = false}) async {
    if (accessToken == null || selectedAgent == null) return;
    if (!selectedAgent!.isOnline) {
      if (!silent) {
        status = 'Import unavailable: selected agent is offline';
        notifyListeners();
      }
      return;
    }
    if (importingHistory) return;

    importingHistory = true;
    if (!silent) {
      status = 'Importing Codex history...';
      notifyListeners();
    } else {
      notifyListeners();
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
        status = 'Import complete: $imported new, $repaired repaired';
      }
    } catch (e) {
      if (await _logoutIfUnauthorized(e)) {
        return;
      }
      if (!silent) {
        status = 'Import failed: $e';
      }
    } finally {
      importingHistory = false;
      notifyListeners();
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
