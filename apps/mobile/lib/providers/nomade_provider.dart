import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import '../models/turn_item.dart';
import '../models/turn_timeline.dart';
import '../models/workspace.dart';
import 'nomade/codex_utils.dart';
import 'nomade/diagnostics_models.dart';
import 'nomade/support_report_builder.dart';
import '../services/mobile_e2e_runtime.dart';
import '../services/native_notifications_bridge.dart';
import '../services/revenuecat_service.dart';
import '../services/secure_scan_parser.dart';

part 'nomade_provider_methods_core.dart';
part 'nomade_provider_methods_services.dart';
part 'nomade_provider_methods_socket_decode.dart';
part 'nomade_provider_methods_socket_runtime.dart';
part 'nomade_provider_methods_turns_scan.dart';

class NomadeProvider with ChangeNotifier {
  NomadeProvider({required String baseUrl})
      : _defaultApiBaseUrl = normalizeApiBaseUrl(baseUrl),
        _api = NomadeApi(baseUrl: normalizeApiBaseUrl(baseUrl));

  static const upgradePromptReasonDeferredTurns = 'deferred_turns';
  static const upgradePromptReasonDeviceLimit = 'device_limit';
  static const upgradePromptReasonConcurrentConversations =
      'concurrent_conversations';

  final String _defaultApiBaseUrl;
  NomadeApi _api;
  NomadeApi get api => _api;
  String get apiBaseUrl => _api.baseUrl;
  String get defaultApiBaseUrl => _defaultApiBaseUrl;
  bool get isUsingDefaultApiBaseUrl => apiBaseUrl == _defaultApiBaseUrl;
  final _storage = const FlutterSecureStorage();

  static const _accessTokenKey = 'nomade.access_token';
  static const _refreshTokenKey = 'nomade.refresh_token';
  static const _accessTokenExpiryKey = 'nomade.access_token_expiry_iso';
  static const _apiBaseUrlKey = 'nomade.api_base_url';
  static const _selectedAgentKey = 'nomade.selected_agent_id';
  static const _selectedWorkspaceKey = 'nomade.selected_workspace_id';
  static const _selectedConversationKey = 'nomade.selected_conversation_id';
  static const _selectedModelKey = 'nomade.selected_model';
  static const _selectedApprovalPolicyKey = 'nomade.selected_approval_policy';
  static const _selectedSandboxModeKey = 'nomade.selected_sandbox_mode';
  static const _selectedEffortKey = 'nomade.selected_effort';
  static const _offlineTurnDefaultKey = 'nomade.offline_turn_default';
  static const _listSortModeKey = 'nomade.list_sort_mode';
  static const _pushDeviceIdKey = 'nomade.push.device_id';
  static const _selectedCollaborationModeKey =
      'nomade.selected_collaboration_mode';
  static const _selectedSkillsKey = 'nomade.selected_skills_json';
  static const _scanDeviceIdKey = 'nomade.scan.device_id';
  static const _scanEncPublicKey = 'nomade.scan.enc_public_key';
  static const _scanEncPrivateKey = 'nomade.scan.enc_private_key';
  static const _scanSignPublicKey = 'nomade.scan.sign_public_key';
  static const _scanSignPrivateKey = 'nomade.scan.sign_private_key';
  static const _scanPendingPayloadKey = 'nomade.scan.pending_payload';
  static const _scanPendingShortCodeKey = 'nomade.scan.pending_short_code';
  static const _e2eSnapshotKey = 'nomade.e2e.snapshot_json';
  static const _strictSecurityErrorKey = 'nomade.e2e.strict_error';

  static const _keychainOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  static String normalizeApiBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Endpoint cannot be empty.');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.trim().isEmpty) {
      throw const FormatException(
        'Endpoint must be a valid http(s) URL, for example https://app.example.com.',
      );
    }
    final normalized = parsed
        .replace(
          path: '',
          queryParameters: null,
          fragment: null,
        )
        .toString();
    return normalized.replaceAll(RegExp(r'/$'), '');
  }

  String status = 'Idle';
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiresAt;
  String? planCode;
  String? entitlementSource;
  String? currentUserId;
  String? currentUserEmail;
  String? deviceCode;
  String? userCode;
  int? currentAgents;
  int? maxAgents;
  bool? deviceLimitReached;
  bool canUseTunnels = false;
  bool canUsePushNotifications = false;
  bool canUseDeferredTurns = false;
  final bool nativeNotificationsBridgeEnabled =
      NativeNotificationsBridge.enabled;
  bool pushProviderReady = false;
  String? pushRegistrationError;
  String? _registeredPushToken;
  Future<_TokenRefreshResult>? _refreshTokensInFlight;

  List<Agent> agents = [];
  List<Workspace> workspaces = [];
  List<Conversation> conversations = [];
  String? _conversationsWorkspaceId;
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
  MobileE2ERuntime? _e2eRuntime;
  String? _securityError;
  String? _pendingScanPayload;
  String? _pendingScanShortCode;
  bool _strictFailureInProgress = false;
  bool _cancelLoginWait = false;
  bool _secureScanApprovalInProgress = false;
  String? _upgradePromptReason;
  bool _upgradePromptDismissed = false;

  bool get e2eReady => _e2eRuntime?.isReady == true;
  String? get securityError => _securityError;
  String? get pendingScanPayload => _pendingScanPayload;
  String? get pendingScanShortCode => _pendingScanShortCode;
  bool get isSelfHostedEndpoint =>
      entitlementSource == 'self_host' || planCode == 'self_host';
  bool get hasCloudProAccess {
    final normalized = planCode?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return normalized != 'free' && normalized != 'self_host';
  }

  bool get shouldShowUpgradePrompt =>
      !isSelfHostedEndpoint &&
      !hasCloudProAccess &&
      _upgradePromptReason != null &&
      !_upgradePromptDismissed;
  String? get upgradePromptReason => _upgradePromptReason;
  bool get billingUiSupported => RevenueCatService.isSupportedOnCurrentPlatform;
  bool get billingConfigured => RevenueCatService.hasApiKeyForCurrentPlatform;
  int? get remainingAgentSlots {
    final current = currentAgents;
    final max = maxAgents;
    if (current == null || max == null) {
      return null;
    }
    final remaining = max - current;
    return remaining < 0 ? 0 : remaining;
  }

  void _notifyListenersSafe() {
    notifyListeners();
  }

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

  String? get conversationsWorkspaceId => _conversationsWorkspaceId;

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
    final now = DateTime.now().toUtc();
    final targetConversationId = conversation?.id ?? conversationId;
    final conversationTurns = turns
        .where((turn) => targetConversationId.isEmpty
            ? true
            : turn.conversationId == targetConversationId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final turnsSnapshot = conversationTurns.take(10).toList(growable: false);
    final timelineTurn = _selectTimelineTurnForSupportBundle(conversationTurns);
    final timeline =
        timelineTurn == null ? null : tryTimelineForTurn(timelineTurn.id);
    final rateSnapshot = activeCodexRateLimitSnapshot;
    final primaryWindow = _asStringKeyedMap(rateSnapshot?['primary']);
    final secondaryWindow = _asStringKeyedMap(rateSnapshot?['secondary']);
    return NomadeSupportReportBuilder.build(
      NomadeSupportReportContext(
        generatedAtUtc: now,
        apiBaseUrl: api.baseUrl,
        status: status,
        realtimeConnected: realtimeConnected,
        selectedAgent: agent,
        selectedWorkspace: workspace,
        trustedDevMode: trustedDevMode,
        conversation: conversation,
        targetConversationId: targetConversationId,
        selectedModel: selectedModel,
        selectedApprovalPolicy: selectedApprovalPolicy,
        selectedSandboxMode: selectedSandboxMode,
        selectedEffort: selectedEffort,
        selectedCollaborationModeSlug: selectedCollaborationModeSlug,
        selectedSkillPaths: _selectedSkillPaths,
        nativeNotificationsBridgeEnabled: nativeNotificationsBridgeEnabled,
        canUsePushNotifications: canUsePushNotifications,
        pushProviderReady: pushProviderReady,
        pushRegistrationError: pushRegistrationError,
        rateSnapshot: rateSnapshot,
        primaryWindow: primaryWindow,
        secondaryWindow: secondaryWindow,
        e2eReady: e2eReady,
        securityError: securityError,
        pendingScanPayload: pendingScanPayload,
        pendingScanShortCode: pendingScanShortCode,
        runtime: runtime,
        events: events,
        turnsSnapshot: turnsSnapshot,
        timelineTurn: timelineTurn,
        timeline: timeline,
      ),
    );
  }

  Turn? _selectTimelineTurnForSupportBundle(List<Turn> conversationTurns) {
    final activeId = activeTurnId;
    if (activeId != null && activeId.isNotEmpty) {
      for (final turn in conversationTurns) {
        if (turn.id == activeId) {
          return turn;
        }
      }
    }
    for (final turn in conversationTurns) {
      if (_turnCountsAsRunning(turn)) {
        return turn;
      }
    }
    if (conversationTurns.isEmpty) {
      return null;
    }
    return conversationTurns.first;
  }

  String? activeTurnId;
  int _loadConversationsRequestToken = 0;
  int _loadTurnsRequestToken = 0;

  // Codex Options
  List<Map<String, dynamic>> codexModels = [];
  List<Map<String, dynamic>> codexCollaborationModes = [];
  List<Map<String, dynamic>> codexSkills = [];
  List<Map<String, dynamic>> codexMcpServers = [];
  Map<String, dynamic>? codexRateLimits;
  Map<String, Map<String, dynamic>> codexRateLimitsByLimitId = {};
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

  Map<String, dynamic>? get activeCodexRateLimitSnapshot {
    final codexBucket = codexRateLimitsByLimitId['codex'];
    if (codexBucket != null) {
      return codexBucket;
    }
    if (codexRateLimitsByLimitId.isNotEmpty) {
      return codexRateLimitsByLimitId.values.first;
    }
    return codexRateLimits;
  }

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

  String _offlineTurnDefault = 'prompt';
  String get offlineTurnDefault => _offlineTurnDefault;
  set offlineTurnDefault(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized != 'prompt' &&
        normalized != 'defer' &&
        normalized != 'fail') {
      return;
    }
    if (_offlineTurnDefault == normalized) {
      return;
    }
    _offlineTurnDefault = normalized;
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
  bool _realtimeSyncRefreshInProgress = false;
  final Set<String> _loadTurnsInFlightConversationIds = <String>{};
  final Map<String, DateTime> _lastLoadTurnsAtByConversation =
      <String, DateTime>{};

  bool secureStorageAvailable = true;

  String _listSortMode = 'latest';
  String get listSortMode => _listSortMode;
  set listSortMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (!NomadeCodexUtils.isSupportedListSortMode(normalized)) {
      return;
    }
    if (_listSortMode == normalized) {
      return;
    }
    _listSortMode = normalized;
    persistSession();
    notifyListeners();
  }

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

  void respondToServerRequest({
    required String conversationId,
    required String turnId,
    required String requestId,
    dynamic result,
    String? error,
  }) {
    _respondToServerRequestImpl(
      conversationId: conversationId,
      turnId: turnId,
      requestId: requestId,
      result: result,
      error: error,
    );
  }

  @override
  void dispose() {
    socketSub?.cancel();
    socket?.sink.close();
    reconnectTimer?.cancel();
    super.dispose();
  }
}
