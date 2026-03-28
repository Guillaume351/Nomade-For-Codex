import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/nomade_api.dart';
import '../models/agent.dart';
import '../models/conversation.dart';
import '../models/turn.dart';
import '../models/workspace.dart';

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
  static const _selectedCwdOverrideKey = 'nomade.selected_cwd_override';

  String status = 'Idle';
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiresAt;

  List<Agent> agents = [];
  List<Workspace> workspaces = [];
  List<Conversation> conversations = [];
  List<Turn> turns = [];

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
    persistSession();
    notifyListeners();
  }

  String? activeTurnId;

  // Codex Options
  List<Map<String, dynamic>> codexModels = [];
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

  WebSocketChannel? socket;
  StreamSubscription<dynamic>? socketSub;
  Timer? reconnectTimer;
  int reconnectAttempts = 0;
  bool realtimeConnected = false;

  final Map<String, StringBuffer> streamByTurn = {};
  bool secureStorageAvailable = true;

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
      _selectedSandboxMode = await _storage.read(key: _selectedSandboxModeKey) ??
          _selectedSandboxMode;
      _selectedEffort =
          await _storage.read(key: _selectedEffortKey) ?? _selectedEffort;

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
      ]);
    } catch (e) {
      debugPrint('Persist session error: $e');
    }
  }

  Future<void> logout() async {
    if (accessToken != null && refreshToken != null) {
      try {
        await api.logout(accessToken: accessToken!, refreshToken: refreshToken!);
      } catch (_) {}
    }

    accessToken = null;
    refreshToken = null;
    accessTokenExpiresAt = null;
    agents = [];
    workspaces = [];
    conversations = [];
    turns = [];
    _selectedAgent = null;
    _selectedWorkspace = null;
    _selectedConversation = null;
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

  Future<void> bootstrapData(
      {String? storedAgentId, String? storedWorkspaceId}) async {
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
        }
      }
      notifyListeners();
    } catch (e) {
      status = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> loadWorkspacesForSelectedAgent({String? storedWorkspaceId}) async {
    if (selectedAgent == null) return;
    final loaded = await api.listWorkspaces(accessToken!, agentId: selectedAgent!.id);
    workspaces = loaded.map((e) => Workspace.fromJson(e)).toList();

    if (workspaces.isNotEmpty) {
      _selectedWorkspace = workspaces.firstWhere(
        (w) => w.id == storedWorkspaceId,
        orElse: () => workspaces.first,
      );
    } else {
      _selectedWorkspace = null;
    }
    notifyListeners();
  }

  Future<void> loadConversations() async {
    if (selectedWorkspace == null) return;
    final loaded = await api.listConversations(
        accessToken: accessToken!, workspaceId: selectedWorkspace!.id);
    conversations = loaded.map((e) => Conversation.fromJson(e)).toList();

    // Pick first conversation by default if none selected or not in current list
    if (conversations.isNotEmpty) {
      if (_selectedConversation == null || !conversations.any((c) => c.id == _selectedConversation!.id)) {
        _selectedConversation = conversations.first;
        await loadTurns(_selectedConversation!.id);
      }
    } else {
      _selectedConversation = null;
    }
    notifyListeners();
  }

  Future<void> loadTurns(String conversationId) async {
    final loaded = await api.listConversationTurns(
        accessToken: accessToken!, conversationId: conversationId);
    turns = loaded.map((e) => Turn.fromJson(e)).toList();
    notifyListeners();
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

      final defaultModel = defaults['model'] is String ? (defaults['model'] as String).trim() : null;
      final defaultApproval = defaults['approvalPolicy'] is String ? (defaults['approvalPolicy'] as String).trim() : null;
      final defaultSandbox = defaults['sandboxMode'] is String ? (defaults['sandboxMode'] as String).trim() : null;
      final defaultEffort = defaults['effort'] is String ? (defaults['effort'] as String).trim() : null;

      if (_selectedModel == null && defaultModel != null) _selectedModel = defaultModel;
      if (_selectedApprovalPolicy == null && defaultApproval != null) _selectedApprovalPolicy = defaultApproval;
      if (_selectedSandboxMode == null && defaultSandbox != null) _selectedSandboxMode = defaultSandbox;
      if (_selectedEffort == null && defaultEffort != null) _selectedEffort = defaultEffort;

      // Fallback if still null
      if (_selectedModel == null && codexModels.isNotEmpty) {
        _selectedModel = codexModels.first['model'] as String?;
      }
    } catch (e) {
      debugPrint('Load codex options error: $e');
    } finally {
      loadingCodexOptions = false;
      notifyListeners();
    }
  }

  Future<void> connectSocket() async {
    if (accessToken == null) return;
    try {
      socket = api.openUserSocket(accessToken!);
      socketSub = socket!.stream.listen(
        _onSocketEvent,
        onError: (e) => _handleSocketDisconnected('Socket error: $e'),
        onDone: () => _handleSocketDisconnected('Socket closed'),
      );
      realtimeConnected = true;
      notifyListeners();
    } catch (e) {
      _handleSocketDisconnected('Connection failed');
    }
  }

  void _onSocketEvent(dynamic raw) {
    final event = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = event['type'] as String?;

    if (type == 'conversation.item.delta') {
      final turnId = event['turnId'] as String?;
      final delta = event['delta'] as String?;
      final stream = event['stream'] as String?;
      if (turnId != null && delta != null && (stream == 'agentMessage' || stream == 'reasoning' || stream == 'plan')) {
        final buffer = streamByTurn.putIfAbsent(turnId, StringBuffer.new);
        buffer.write(delta);
        notifyListeners();
      }
    } else if (type == 'conversation.turn.diff.updated') {
      final turnId = event['turnId'] as String?;
      final diff = event['diff'] as String?;
      if (turnId != null && diff != null) {
        final index = turns.indexWhere((t) => t.id == turnId);
        if (index != -1) {
          // In a real app we'd want to update the Turn object in place
          // but for this UI overhaul we'll rely on the stream buffer or reload
        }
      }
    } else if (type == 'conversation.turn.completed') {
      final turnId = event['turnId'] as String?;
      if (turnId != null) {
        if (activeTurnId == turnId) activeTurnId = null;
        // Reload turns to get metrics and final state
        if (selectedConversation != null) {
          loadTurns(selectedConversation!.id);
        }
      }
    } else if (type == 'conversation.turn.started') {
      final turnId = event['turnId'] as String?;
      if (turnId != null) {
        activeTurnId = turnId;
        notifyListeners();
      }
    }
    // Handle other events...
  }

  void _handleSocketDisconnected(String reason) {
    realtimeConnected = false;
    status = reason;
    notifyListeners();
    // Reconnect logic...
  }

  Future<void> sendPrompt(String prompt) async {
    if (selectedConversation == null || accessToken == null) return;

    try {
      final turn = await api.createTurn(
        accessToken: accessToken!,
        conversationId: selectedConversation!.id,
        prompt: prompt,
        model: selectedModel,
        cwd: selectedWorkspace?.path,
        approvalPolicy: selectedApprovalPolicy,
        sandboxMode: selectedSandboxMode,
        effort: selectedEffort,
      );
      
      activeTurnId = turn['id'] as String;
      await loadTurns(selectedConversation!.id);
    } catch (e) {
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
}
