import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

void main() {
  runApp(const NomadeApp());
}

class NomadeApp extends StatelessWidget {
  const NomadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nomade for Codex',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E8D89)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'nomade.access_token';
  static const _refreshTokenKey = 'nomade.refresh_token';
  static const _accessTokenExpiryKey = 'nomade.access_token_expiry_iso';
  static const _selectedAgentKey = 'nomade.selected_agent_id';
  static const _selectedWorkspaceKey = 'nomade.selected_workspace_id';

  final api = NomadeApi(
    baseUrl: const String.fromEnvironment(
      'NOMADE_API_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );
  final String devEmail =
      const String.fromEnvironment('NOMADE_DEV_EMAIL', defaultValue: '').trim();
  final bool devAutoLogin =
      const bool.fromEnvironment('NOMADE_DEV_AUTO_LOGIN', defaultValue: false);
  bool devAutoLoginTriggered = false;
  bool secureStorageAvailable = true;

  final emailController = TextEditingController();
  final promptController = TextEditingController();
  final newConversationController = TextEditingController();
  final workspaceNameController =
      TextEditingController(text: 'Local workspace');
  final workspacePathController = TextEditingController(text: '.');

  String status = 'Idle';
  String? deviceCode;
  String? userCode;
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiresAt;
  String? pairingCode;

  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> workspaces = [];
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> turns = [];

  String? selectedAgentId;
  String? selectedWorkspaceId;
  String? selectedConversationId;
  String? activeTurnId;
  Map<String, dynamic>? hydrationState;

  WebSocketChannel? socket;
  StreamSubscription<dynamic>? socketSub;
  Timer? reconnectTimer;
  int reconnectAttempts = 0;
  bool realtimeConnected = false;

  final Map<String, StringBuffer> streamByTurn = {};
  final Set<String> autoSyncedAgentIds = <String>{};

  String _formatError(Object error) {
    final text = error.toString();
    return text.replaceFirst(RegExp(r'^(Exception|ApiException):\s*'), '');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_startup());
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    socketSub?.cancel();
    socket?.sink.close();
    emailController.dispose();
    promptController.dispose();
    newConversationController.dispose();
    workspaceNameController.dispose();
    workspacePathController.dispose();
    super.dispose();
  }

  String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }
    return value.substring(0, 8);
  }

  String _formatLastSeen(String? isoTimestamp) {
    if (isoTimestamp == null || isoTimestamp.isEmpty) {
      return 'never';
    }

    final parsed = DateTime.tryParse(isoTimestamp)?.toLocal();
    if (parsed == null) {
      return isoTimestamp;
    }

    final diff = DateTime.now().difference(parsed);
    if (diff.inSeconds < 45) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _selectedAgent() {
    final selected = selectedAgentId;
    if (selected == null) {
      return null;
    }
    for (final agent in agents) {
      if (agent['id'] == selected) {
        return agent;
      }
    }
    return null;
  }

  bool _isAgentOnlineById(String? agentId) {
    if (agentId == null) {
      return false;
    }
    for (final agent in agents) {
      if (agent['id'] == agentId) {
        return agent['is_online'] == true;
      }
    }
    return false;
  }

  String? _pickPreferredAgentId(List<Map<String, dynamic>> loaded) {
    if (loaded.isEmpty) {
      return null;
    }

    final current = selectedAgentId;
    if (current != null) {
      for (final agent in loaded) {
        if (agent['id'] == current) {
          return current;
        }
      }
    }

    for (final agent in loaded) {
      if (agent['is_online'] == true) {
        return agent['id'] as String?;
      }
    }

    return loaded.first['id'] as String?;
  }

  String? _pickPreferredWorkspaceId(List<Map<String, dynamic>> loaded) {
    if (loaded.isEmpty) {
      return null;
    }
    final current = selectedWorkspaceId;
    if (current != null) {
      for (final workspace in loaded) {
        if (workspace['id'] == current) {
          return current;
        }
      }
    }
    return loaded.first['id'] as String?;
  }

  Future<void> _persistSession() async {
    if (!secureStorageAvailable) {
      return;
    }

    try {
      if (accessToken == null) {
        await _storage.deleteAll();
        return;
      }

      final writes = <Future<void>>[
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _selectedAgentKey, value: selectedAgentId),
        _storage.write(key: _selectedWorkspaceKey, value: selectedWorkspaceId),
      ];
      if (refreshToken != null) {
        writes.add(_storage.write(key: _refreshTokenKey, value: refreshToken));
      } else {
        writes.add(_storage.delete(key: _refreshTokenKey));
      }
      if (accessTokenExpiresAt != null) {
        writes.add(
          _storage.write(
            key: _accessTokenExpiryKey,
            value: accessTokenExpiresAt!.toIso8601String(),
          ),
        );
      } else {
        writes.add(_storage.delete(key: _accessTokenExpiryKey));
      }

      await Future.wait(writes);
    } on PlatformException catch (error) {
      _disableSecureStorage(error);
    }
  }

  Future<void> _clearSessionStorage() async {
    if (!secureStorageAvailable) {
      return;
    }
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _accessTokenExpiryKey),
        _storage.delete(key: _selectedAgentKey),
        _storage.delete(key: _selectedWorkspaceKey),
      ]);
    } on PlatformException catch (error) {
      _disableSecureStorage(error);
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

  Future<bool> _refreshTokens({bool updateStatus = false}) async {
    final token = refreshToken;
    if (token == null) {
      return false;
    }

    try {
      if (updateStatus && mounted) {
        setState(() => status = 'Refreshing session...');
      }
      final refreshed = await api.refreshAccessToken(token);
      _setTokensFromPayload(refreshed);
      await _persistSession();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureFreshToken() async {
    if (accessToken == null && refreshToken == null) {
      return false;
    }
    final expiry = accessTokenExpiresAt;
    if (accessToken != null &&
        (expiry == null ||
            DateTime.now()
                .isBefore(expiry.subtract(const Duration(seconds: 60))))) {
      return true;
    }
    return _refreshTokens();
  }

  Future<T> _withAuthorized<T>(
    Future<T> Function(String token) action,
  ) async {
    final ready = await _ensureFreshToken();
    if (!ready || accessToken == null) {
      throw ApiException('Not authenticated', statusCode: 401);
    }

    try {
      return await action(accessToken!);
    } on ApiException catch (error) {
      if (error.statusCode == 401 &&
          await _refreshTokens(updateStatus: false)) {
        if (accessToken == null) {
          rethrow;
        }
        return action(accessToken!);
      }
      if (error.statusCode == 401) {
        await _logout();
      }
      rethrow;
    }
  }

  void _scheduleReconnect() {
    if (reconnectTimer != null || accessToken == null) {
      return;
    }
    reconnectAttempts += 1;
    final seconds = reconnectAttempts <= 1
        ? 1
        : reconnectAttempts == 2
            ? 2
            : reconnectAttempts == 3
                ? 4
                : reconnectAttempts == 4
                    ? 8
                    : reconnectAttempts == 5
                        ? 16
                        : 30;
    reconnectTimer = Timer(Duration(seconds: seconds), () async {
      reconnectTimer = null;
      await _connectSocket(fromReconnect: true);
    });
    if (mounted) {
      setState(() {
        status = 'Realtime disconnected. Reconnecting in ${seconds}s...';
      });
    }
  }

  void _handleSocketDisconnected(String reason) {
    if (!mounted || accessToken == null) {
      return;
    }
    setState(() {
      realtimeConnected = false;
      status = reason;
    });
    _scheduleReconnect();
  }

  Future<void> _reconnectRealtime() async {
    reconnectTimer?.cancel();
    reconnectTimer = null;
    reconnectAttempts = 0;
    await _connectSocket(fromReconnect: true);
  }

  Future<void> _restoreSession() async {
    if (!secureStorageAvailable) {
      return;
    }

    String? storedAccess;
    String? storedRefresh;
    String? storedExpiry;
    String? storedAgent;
    String? storedWorkspace;
    try {
      storedAccess = await _storage.read(key: _accessTokenKey);
      storedRefresh = await _storage.read(key: _refreshTokenKey);
      storedExpiry = await _storage.read(key: _accessTokenExpiryKey);
      storedAgent = await _storage.read(key: _selectedAgentKey);
      storedWorkspace = await _storage.read(key: _selectedWorkspaceKey);
    } on PlatformException catch (error) {
      _disableSecureStorage(error);
      return;
    }

    if (storedAccess == null && storedRefresh == null) {
      return;
    }

    accessToken = storedAccess;
    refreshToken = storedRefresh;
    selectedAgentId = storedAgent;
    selectedWorkspaceId = storedWorkspace;
    accessTokenExpiresAt =
        storedExpiry == null ? null : DateTime.tryParse(storedExpiry);

    if (mounted) {
      setState(() => status = 'Restoring session...');
    }

    final ready = await _ensureFreshToken();
    if (!ready || accessToken == null) {
      await _clearSessionStorage();
      if (mounted) {
        setState(() {
          accessToken = null;
          refreshToken = null;
          accessTokenExpiresAt = null;
          status = 'Session expired. Login again.';
        });
      }
      return;
    }

    await _persistSession();
    if (!mounted) {
      return;
    }
    setState(() => status = 'Authenticated');
    await _connectSocket();
    await _bootstrapData();
  }

  void _disableSecureStorage(PlatformException error) {
    if (!secureStorageAvailable) {
      return;
    }
    secureStorageAvailable = false;
    debugPrint('Secure storage disabled: ${error.code} ${error.message}');
    if (!mounted) {
      return;
    }
    setState(() {
      if (status.startsWith('Error:')) {
        return;
      }
      status =
          'Secure session storage unavailable on this build (keychain entitlement).';
    });
  }

  Future<void> _logout() async {
    final token = accessToken;
    final refresh = refreshToken;
    if (token != null && refresh != null) {
      try {
        await api.logout(accessToken: token, refreshToken: refresh);
      } catch (_) {
        // Local logout still succeeds even if API logout fails.
      }
    }

    accessToken = null;
    refreshToken = null;
    accessTokenExpiresAt = null;

    reconnectTimer?.cancel();
    reconnectTimer = null;
    reconnectAttempts = 0;
    await socketSub?.cancel();
    await socket?.sink.close();
    socketSub = null;
    socket = null;

    await _clearSessionStorage();
    if (!mounted) {
      return;
    }
    setState(() {
      accessToken = null;
      refreshToken = null;
      accessTokenExpiresAt = null;
      pairingCode = null;
      agents = [];
      workspaces = [];
      conversations = [];
      turns = [];
      hydrationState = null;
      selectedAgentId = null;
      selectedWorkspaceId = null;
      selectedConversationId = null;
      activeTurnId = null;
      streamByTurn.clear();
      realtimeConnected = false;
      status = 'Logged out';
    });
  }

  Future<void> _startup() async {
    await _restoreSession();
    if (accessToken == null) {
      _maybeDevAutoLogin();
    }
  }

  void _maybeDevAutoLogin() {
    if (!devAutoLogin || devAutoLoginTriggered || devEmail.isEmpty) {
      return;
    }
    devAutoLoginTriggered = true;
    emailController.text = devEmail;
    if (mounted) {
      setState(() => status = 'Dev mode: auto login...');
    }
    unawaited(runLoginFlow());
  }

  Future<void> runLoginFlow() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => status = 'Enter your email first');
      return;
    }

    try {
      setState(() => status = 'Requesting device code...');
      final started = await api.startDeviceCode();
      deviceCode = started['deviceCode'] as String;
      userCode = started['userCode'] as String;

      if (!mounted) {
        return;
      }

      setState(() => status = 'Approving code...');
      await api.approveDeviceCode(
        userCode: userCode!,
        email: email,
      );

      setState(() => status = 'Polling token...');
      while (mounted) {
        final polled = await api.pollDeviceCode(deviceCode!);
        final pollStatus = polled['status'] as String? ?? 'pending';
        if (pollStatus == 'ok') {
          _setTokensFromPayload(polled);
          await _persistSession();
          setState(() => status = 'Authenticated');
          await _connectSocket();
          await _bootstrapData();
          break;
        }
        if (pollStatus == 'expired') {
          setState(() => status = 'Device code expired, retry login');
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => status = 'Error: ${_formatError(error)}');
    }
  }

  Future<void> makePairingCode() async {
    if (accessToken == null) {
      return;
    }
    try {
      setState(() => status = 'Creating pairing code...');
      final response =
          await _withAuthorized((token) => api.createPairingCode(token));
      setState(() {
        pairingCode = response['pairingCode'] as String;
        status = 'Pairing code ready. Pair an agent then refresh.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => status = 'Error: ${_formatError(error)}');
    }
  }

  Future<void> _connectSocket({bool fromReconnect = false}) async {
    final ready = await _ensureFreshToken();
    final token = accessToken;
    if (!ready || token == null) {
      return;
    }

    reconnectTimer?.cancel();
    reconnectTimer = null;
    await socketSub?.cancel();
    await socket?.sink.close();
    socketSub = null;
    socket = null;
    if (mounted && !fromReconnect) {
      setState(() => status = 'Connecting realtime...');
    }

    try {
      socket = api.openUserSocket(token);
      socketSub = socket!.stream.listen(
        _onSocketRawEvent,
        onError: (_) => _handleSocketDisconnected('Realtime error'),
        onDone: () => _handleSocketDisconnected('Realtime closed'),
        cancelOnError: false,
      );
      reconnectAttempts = 0;
      if (mounted) {
        setState(() {
          realtimeConnected = true;
          if (fromReconnect) {
            status = 'Realtime reconnected';
          }
        });
      }
    } catch (_) {
      _handleSocketDisconnected('Realtime connection failed');
    }
  }

  Future<void> _bootstrapData() async {
    if (accessToken == null && refreshToken == null) {
      return;
    }
    try {
      final loadedAgents =
          await _withAuthorized((token) => api.listAgents(token));
      final nextAgentId = _pickPreferredAgentId(loadedAgents);
      setState(() {
        agents = loadedAgents;
        selectedAgentId = nextAgentId;
      });
      await _persistSession();
      await _loadWorkspacesForSelectedAgent();
      await _syncCodexThreadsForSelectedAgent(autoTriggered: true);
      await _loadWorkspacesForSelectedAgent();

      if (selectedWorkspaceId != null) {
        await _loadConversations();
      }
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _onAgentChanged(String? value) async {
    setState(() {
      selectedAgentId = value;
      selectedWorkspaceId = null;
      selectedConversationId = null;
      workspaces = [];
      conversations = [];
      turns = [];
      hydrationState = null;
      streamByTurn.clear();
    });
    try {
      await _persistSession();
      await _loadWorkspacesForSelectedAgent();
      await _syncCodexThreadsForSelectedAgent(autoTriggered: true);
      await _loadWorkspacesForSelectedAgent();
      if (selectedWorkspaceId != null) {
        await _loadConversations();
      }
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _loadWorkspacesForSelectedAgent() async {
    final agentId = selectedAgentId;
    if (agentId == null) {
      setState(() {
        workspaces = [];
        selectedWorkspaceId = null;
      });
      return;
    }

    final loadedWorkspaces = await _withAuthorized(
      (token) => api.listWorkspaces(token, agentId: agentId),
    );
    final preferredWorkspace = _pickPreferredWorkspaceId(loadedWorkspaces);
    setState(() {
      workspaces = loadedWorkspaces;
      selectedWorkspaceId = preferredWorkspace;
    });
    await _persistSession();
  }

  Future<void> _syncCodexThreadsForSelectedAgent({
    bool autoTriggered = false,
  }) async {
    final agentId = selectedAgentId;
    if (agentId == null) {
      return;
    }
    if (autoTriggered && autoSyncedAgentIds.contains(agentId)) {
      return;
    }
    if (!_isAgentOnlineById(agentId)) {
      if (!autoTriggered && mounted) {
        setState(
          () =>
              status = 'Selected agent is offline. Run: npm run dev:agent:run',
        );
      }
      return;
    }
    if (autoTriggered) {
      autoSyncedAgentIds.add(agentId);
    }

    try {
      setState(() => status = autoTriggered
          ? 'Importing Codex threads...'
          : 'Importing Codex history...');
      final result = await _withAuthorized(
        (token) => api.importCodexThreads(
          accessToken: token,
          agentId: agentId,
        ),
      );
      final importedConversations = (result['imported'] as num?)?.toInt() ??
          (result['importedConversations'] as num?)?.toInt() ??
          0;
      final skipped = (result['skipped'] as num?)?.toInt() ??
          (result['skippedConversations'] as num?)?.toInt() ??
          0;
      final repaired = (result['hydrated_or_repaired'] as num?)?.toInt() ?? 0;
      final scanned = (result['threads_scanned'] as num?)?.toInt() ??
          (result['threadsScanned'] as num?)?.toInt() ??
          0;

      if (!mounted) {
        return;
      }

      if (importedConversations == 0 && repaired == 0) {
        setState(() => status = autoTriggered
            ? 'No Codex threads to import'
            : 'No new Codex threads');
      } else {
        setState(
          () => status =
              'Sync: $importedConversations imported, $repaired repaired, $skipped skipped ($scanned scanned)',
        );
      }

      await _loadWorkspacesForSelectedAgent();
      if (selectedWorkspaceId != null) {
        await _loadConversations();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => status = autoTriggered
            ? 'Codex import unavailable: ${_formatError(error)}'
            : 'Import failed: ${_formatError(error)}',
      );
    }
  }

  Future<void> _refreshData() async {
    try {
      await _bootstrapData();
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _loadConversations() async {
    final workspaceId = selectedWorkspaceId;
    if (workspaceId == null) {
      return;
    }

    try {
      final items = await _withAuthorized(
        (token) => api.listConversations(
          accessToken: token,
          workspaceId: workspaceId,
        ),
      );
      final currentConversation = selectedConversationId;
      String? nextConversation;
      if (currentConversation != null &&
          items.any((entry) => entry['id'] == currentConversation)) {
        nextConversation = currentConversation;
      } else {
        nextConversation =
            items.isNotEmpty ? items.first['id'] as String : null;
      }

      setState(() {
        conversations = items;
        selectedConversationId = nextConversation;
        turns = [];
        hydrationState = null;
        streamByTurn.clear();
      });
      await _persistSession();
      if (selectedConversationId != null) {
        await _loadTurns(selectedConversationId!);
      }
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _loadTurns(String conversationId,
      {bool forceHydrate = false}) async {
    try {
      final payload = await _withAuthorized(
        (token) => api.getConversationTurns(
          accessToken: token,
          conversationId: conversationId,
          forceHydrate: forceHydrate,
        ),
      );
      final items = ((payload['items'] as List?) ?? [])
          .cast<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      final hydration = (payload['hydration'] as Map?)?.cast<String, dynamic>();
      setState(() {
        turns = items;
        hydrationState = hydration;
        if ((hydration?['deferred'] as bool? ?? false) == true) {
          status =
              'History hydration deferred: ${hydration?['reason'] ?? 'agent_offline'}';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _createWorkspace() async {
    final agentId = selectedAgentId;
    if (agentId == null) {
      return;
    }
    if (!_isAgentOnlineById(agentId)) {
      setState(
          () => status = 'Selected agent is offline. Start it then retry.');
      return;
    }
    try {
      setState(() => status = 'Creating workspace...');
      await _withAuthorized(
        (token) => api.createWorkspace(
          accessToken: token,
          agentId: agentId,
          name: workspaceNameController.text.trim(),
          path: workspacePathController.text.trim(),
        ),
      );
      setState(() => status = 'Workspace created');
      await _loadWorkspacesForSelectedAgent();
      if (selectedWorkspaceId != null) {
        await _loadConversations();
      }
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _createConversation({String? initialPrompt}) async {
    final workspaceId = selectedWorkspaceId;
    final agentId = selectedAgentId;
    if (workspaceId == null || agentId == null) {
      return;
    }
    if (!_isAgentOnlineById(agentId)) {
      setState(
          () => status = 'Selected agent is offline. Start it then retry.');
      return;
    }

    final title = newConversationController.text.trim().isNotEmpty
        ? newConversationController.text.trim()
        : (initialPrompt ?? 'New conversation').split('\n').first;

    try {
      final created = await _withAuthorized(
        (token) => api.createConversation(
          accessToken: token,
          workspaceId: workspaceId,
          agentId: agentId,
          title: title.length > 80 ? '${title.substring(0, 80)}...' : title,
        ),
      );

      setState(() {
        conversations = [created, ...conversations];
        selectedConversationId = created['id'] as String;
        turns = [];
        hydrationState = null;
        newConversationController.clear();
      });
      await _persistSession();
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _sendPrompt() async {
    if (selectedAgentId != null && !_isAgentOnlineById(selectedAgentId)) {
      setState(() =>
          status = 'Selected agent is offline. Run: npm run dev:agent:run');
      return;
    }

    final prompt = promptController.text.trim();
    if (prompt.isEmpty) {
      return;
    }

    if (selectedConversationId == null) {
      await _createConversation(initialPrompt: prompt);
    }
    final conversationId = selectedConversationId;
    if (conversationId == null) {
      return;
    }

    try {
      final created = await _withAuthorized(
        (token) => api.createTurn(
          accessToken: token,
          conversationId: conversationId,
          prompt: prompt,
        ),
      );

      setState(() {
        final seeded = Map<String, dynamic>.from(created);
        seeded['items'] = <Map<String, dynamic>>[];
        turns = [...turns, seeded];
        activeTurnId = created['id'] as String;
        promptController.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  Future<void> _interruptTurn() async {
    final conversationId = selectedConversationId;
    final turnId = activeTurnId;
    if (conversationId == null || turnId == null) {
      return;
    }
    try {
      await _withAuthorized(
        (token) => api.interruptTurn(
          accessToken: token,
          conversationId: conversationId,
          turnId: turnId,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Error: ${_formatError(error)}');
      }
    }
  }

  void _onSocketRawEvent(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      _onSocketEvent(decoded);
    } catch (_) {
      // Ignore malformed events.
    }
  }

  void _onSocketEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == null) {
      return;
    }

    if (type == 'conversation.thread.started') {
      final conversationId = event['conversationId'] as String?;
      final threadId = event['threadId'] as String?;
      if (conversationId == null || threadId == null) {
        return;
      }
      setState(() {
        for (final conversation in conversations) {
          if (conversation['id'] == conversationId) {
            conversation['codex_thread_id'] = threadId;
          }
        }
      });
      return;
    }

    if (type == 'conversation.turn.started') {
      final turnId = event['turnId'] as String?;
      if (turnId == null) {
        return;
      }
      setState(() {
        final turn = _upsertTurn(turnId);
        turn['status'] = 'running';
        turn['codex_turn_id'] = event['codexTurnId'];
        activeTurnId = turnId;
      });
      return;
    }

    if (type == 'conversation.item.delta') {
      final turnId = event['turnId'] as String?;
      final stream = event['stream'] as String?;
      final delta = event['delta'] as String?;
      if (turnId == null || stream == null || delta == null) {
        return;
      }

      if (stream == 'agentMessage' ||
          stream == 'reasoning' ||
          stream == 'plan') {
        final buffer = streamByTurn.putIfAbsent(turnId, StringBuffer.new);
        buffer.write(delta);
        setState(() {});
      }
      return;
    }

    if (type == 'conversation.item.completed') {
      final turnId = event['turnId'] as String?;
      final itemType = event['itemType'] as String?;
      final item = (event['item'] as Map?)?.cast<String, dynamic>();
      if (turnId == null || itemType == null || item == null) {
        return;
      }

      setState(() {
        final turn = _upsertTurn(turnId);
        final items = _ensureTurnItems(turn);
        items.add({
          'item_id': event['itemId'],
          'item_type': itemType,
          'payload': item,
        });
      });
      return;
    }

    if (type == 'conversation.turn.diff.updated') {
      final turnId = event['turnId'] as String?;
      if (turnId == null) {
        return;
      }
      setState(() {
        final turn = _upsertTurn(turnId);
        turn['diff'] = event['diff'] as String? ?? '';
      });
      return;
    }

    if (type == 'conversation.turn.completed') {
      final turnId = event['turnId'] as String?;
      final completedStatus = event['status'] as String? ?? 'completed';
      final error = event['error'] as String?;
      if (turnId == null) {
        return;
      }
      setState(() {
        final turn = _upsertTurn(turnId);
        turn['status'] = completedStatus;
        turn['error'] = error;
        if (activeTurnId == turnId) {
          activeTurnId = null;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Turn $completedStatus')),
        );
      }
    }
  }

  Map<String, dynamic> _upsertTurn(String turnId) {
    for (final turn in turns) {
      if (turn['id'] == turnId) {
        return turn;
      }
    }
    final created = <String, dynamic>{
      'id': turnId,
      'user_prompt': '',
      'status': 'running',
      'diff': '',
      'items': <Map<String, dynamic>>[],
    };
    turns = [...turns, created];
    return created;
  }

  List<Map<String, dynamic>> _ensureTurnItems(Map<String, dynamic> turn) {
    final existing = turn['items'];
    if (existing is List<Map<String, dynamic>>) {
      return existing;
    }
    if (existing is List) {
      final normalized = existing
          .cast<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      turn['items'] = normalized;
      return normalized;
    }
    final created = <Map<String, dynamic>>[];
    turn['items'] = created;
    return created;
  }

  Map<String, dynamic> _itemPayload(Map<String, dynamic> item) {
    final payload = (item['payload'] as Map?)?.cast<String, dynamic>() ?? item;
    final nested = (payload['payload'] as Map?)?.cast<String, dynamic>();
    if (nested != null) {
      return nested;
    }
    return payload;
  }

  String _itemType(Map<String, dynamic> item, Map<String, dynamic> payload) {
    final rawType = item['item_type'];
    if (rawType is String && rawType.isNotEmpty && rawType != 'unknown') {
      return rawType;
    }
    final wrappedPayload = (item['payload'] as Map?)?.cast<String, dynamic>();
    final wrappedType =
        wrappedPayload == null ? null : wrappedPayload['itemType'];
    if (wrappedType is String && wrappedType.isNotEmpty) {
      return wrappedType;
    }
    final payloadType = payload['type'];
    if (payloadType is String && payloadType.isNotEmpty) {
      return payloadType;
    }
    return rawType is String ? rawType : '';
  }

  String _assistantMarkdown(Map<String, dynamic> turn) {
    final buffer = StringBuffer();
    final items = (turn['items'] as List?)?.cast<Map>() ?? const [];
    for (final raw in items) {
      final item = raw.cast<String, dynamic>();
      final payload = _itemPayload(item);
      final type = _itemType(item, payload);
      if (type == 'agentMessage') {
        final text = _extractText(payload);
        if (text.isNotEmpty) {
          buffer.writeln(text);
          buffer.writeln();
        }
      }
    }

    final turnId = turn['id'] as String?;
    final live = turnId == null ? null : streamByTurn[turnId]?.toString();
    if (live != null && live.isNotEmpty) {
      buffer.write(live);
    }

    return buffer.toString().trim();
  }

  String _extractText(Map<String, dynamic> payload) {
    final direct = payload['text'];
    if (direct is String && direct.isNotEmpty) {
      return direct;
    }

    final content = payload['content'];
    if (content is List) {
      final buffer = StringBuffer();
      for (final entry in content) {
        if (entry is Map) {
          final map = entry.cast<String, dynamic>();
          final text = map['text'] ?? map['value'] ?? map['content'];
          if (text is String && text.isNotEmpty) {
            buffer.writeln(text);
          }
        }
      }
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }

    final message = payload['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (accessToken == null) {
      return _buildAuthScaffold();
    }
    return _buildConversationScaffold();
  }

  Widget _buildAuthScaffold() {
    return Scaffold(
      appBar: AppBar(title: const Text('Nomade for Codex')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              children: [
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use your email to start the device-code flow.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: runLoginFlow,
                  child: const Text('Continue'),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Status: $status'),
                        const SizedBox(height: 4),
                        Text('API: ${api.baseUrl}'),
                        if (userCode != null) ...[
                          const SizedBox(height: 8),
                          SelectableText('User code: $userCode'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nomade Conversations'),
        actions: [
          IconButton(
            tooltip: 'Refresh data',
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Reconnect realtime',
            onPressed: _reconnectRealtime,
            icon: Icon(
              realtimeConnected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 960;
          final sidebar = _buildSidebar();
          final content = _buildConversationView();

          if (wide) {
            return Row(
              children: [
                SizedBox(width: 320, child: sidebar),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
          }

          return Column(
            children: [
              SizedBox(height: 280, child: sidebar),
              const Divider(height: 1),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    final selectedAgent = _selectedAgent();
    final selectedAgentOnline = _isAgentOnlineById(selectedAgentId);
    final selectedAgentLastSeen = selectedAgent?['last_seen_at'] as String?;
    final realtimeLabel = realtimeConnected ? 'Connected' : 'Disconnected';
    final selectedAgentName =
        (selectedAgent?['display_name'] as String?) ??
            (selectedAgent?['name'] as String?) ??
            'No agent selected';
    final hasAgent = selectedAgent != null;
    final hasWorkspace = selectedWorkspaceId != null;
    final canManageWorkspaces = hasAgent && selectedAgentOnline;
    final canCreateConversation = hasWorkspace && selectedAgentOnline;
    final hasError = status.toLowerCase().contains('error');

    Widget conversationsPane() {
      if (!hasAgent) {
        return const Center(
          child: Text('Pair an agent to unlock workspaces and conversations.'),
        );
      }
      if (!hasWorkspace) {
        return const Center(
          child: Text('Select or create a workspace.'),
        );
      }
      if (conversations.isEmpty) {
        return const Center(
          child: Text('No conversations yet. Create your first one.'),
        );
      }
      return ListView.builder(
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          final conversationId = conversation['id'] as String;
          final selected = conversationId == selectedConversationId;
          return Card(
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: ListTile(
              title: Text(conversation['title'] as String? ?? 'Conversation'),
              subtitle: Text(
                conversation['status'] as String? ?? 'idle',
              ),
              onTap: () async {
                setState(() {
                  selectedConversationId = conversationId;
                  hydrationState = null;
                });
                await _persistSession();
                await _loadTurns(conversationId);
              },
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: hasError
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: $status'),
                  const SizedBox(height: 4),
                  Text('API: ${api.baseUrl}'),
                  const SizedBox(height: 4),
                  Text('Realtime: $realtimeLabel'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Agent',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (agents.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('No paired agent found for this account.'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: makePairingCode,
              child: const Text('Create join pairing code'),
            ),
            if (pairingCode != null) ...[
              const SizedBox(height: 8),
              SelectableText('Pairing code: $pairingCode'),
              const SizedBox(height: 4),
              SelectableText(
                'Run: npm run dev:agent:pair -- --server-url ${api.baseUrl} --pairing-code <CODE>',
              ),
              const SizedBox(height: 4),
              const SelectableText('Then: npm run dev:agent:run'),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _refreshData,
              child: const Text('Refresh agents'),
            ),
          ] else ...[
            const SizedBox(height: 6),
            DropdownButton<String>(
              isExpanded: true,
              value: selectedAgentId,
              hint: const Text('Select agent'),
              items: agents
                  .map(
                    (agent) => DropdownMenuItem<String>(
                      value: agent['id'] as String,
                      child: Text(
                        '${(agent['display_name'] as String?) ?? (agent['name'] as String? ?? 'Agent')}'
                        ' • ${(agent['is_online'] == true) ? 'Online' : 'Offline'}'
                        ' • ${_shortId(agent['id'] as String)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => unawaited(_onAgentChanged(value)),
            ),
            const SizedBox(height: 4),
            Text(
              '$selectedAgentName • ${selectedAgentOnline ? 'Online' : 'Offline'} • last seen ${_formatLastSeen(selectedAgentLastSeen)}',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: makePairingCode,
                    child: const Text('Create join pairing code'),
                  ),
                ),
              ],
            ),
            if (pairingCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText('Pairing code: $pairingCode'),
              ),
            const SizedBox(height: 8),
            if (!selectedAgentOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Selected agent is offline. Start it with: npm run dev:agent:run',
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: selectedAgentOnline
                  ? () =>
                      _syncCodexThreadsForSelectedAgent(autoTriggered: false)
                  : null,
              child: const Text('Import Codex history'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Workspace',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (workspaces.isNotEmpty) ...[
              const SizedBox(height: 6),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedWorkspaceId,
                hint: const Text('Select workspace'),
                items: workspaces
                    .map(
                      (workspace) => DropdownMenuItem<String>(
                        value: workspace['id'] as String,
                        child:
                            Text(workspace['name'] as String? ?? 'Workspace'),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  setState(() => selectedWorkspaceId = value);
                  await _persistSession();
                  await _loadConversations();
                },
              ),
            ],
            if (workspaces.isEmpty && canManageWorkspaces) ...[
              const SizedBox(height: 6),
              const Text('Create your first workspace'),
              TextField(
                controller: workspaceNameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: workspacePathController,
                decoration: const InputDecoration(labelText: 'Path on agent'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _createWorkspace,
                child: const Text('Create workspace'),
              ),
            ],
            if (workspaces.isEmpty && !canManageWorkspaces) ...[
              const SizedBox(height: 6),
              const Text('Connect an online agent to create a workspace.'),
            ],
            if (selectedWorkspaceId != null) ...[
              const SizedBox(height: 12),
              const Text(
                'New conversation',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: newConversationController,
                decoration:
                    const InputDecoration(labelText: 'Conversation title'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: canCreateConversation
                    ? () => _createConversation()
                    : null,
                child: const Text('Create conversation'),
              ),
            ],
          ],
          const SizedBox(height: 12),
          const Text(
            'Conversations',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(child: conversationsPane()),
        ],
      ),
    );
  }

  Widget _buildConversationView() {
    if (selectedConversationId == null) {
      return const Center(
        child: Text('Create or select a conversation'),
      );
    }

    final hydrationDeferred = (hydrationState?['deferred'] as bool?) ?? false;
    final hydrationReason = hydrationState?['reason'] as String?;
    final canSend = _isAgentOnlineById(selectedAgentId);

    return Column(
      children: [
        if (hydrationDeferred)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'History sync deferred: ${hydrationReason ?? 'agent_offline'}.',
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () =>
                      _loadTurns(selectedConversationId!, forceHydrate: true),
                  child: const Text('Retry hydrate'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: turns.length,
            itemBuilder: (context, index) {
              final turn = turns[index];
              return _buildTurn(turn);
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: promptController,
                  minLines: 1,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Ask Codex...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: canSend ? _sendPrompt : null,
                child: const Text('Send'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: activeTurnId == null ? null : _interruptTurn,
                child: const Text('Stop'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTurn(Map<String, dynamic> turn) {
    final prompt = turn['user_prompt'] as String? ?? '';
    final status = turn['status'] as String? ?? 'queued';
    final error = turn['error'] as String?;
    final diff = turn['diff'] as String? ?? '';
    final markdown = _assistantMarkdown(turn);
    final isRunning = status == 'running' || activeTurnId == turn['id'];

    final items = (turn['items'] as List?)?.cast<Map>() ?? const [];
    final normalizedItems =
        items.map((entry) => entry.cast<String, dynamic>()).toList();
    final commandItems = normalizedItems
        .where(
          (entry) =>
              _itemType(entry, _itemPayload(entry)) == 'commandExecution',
        )
        .toList();
    final fileChangeItems = normalizedItems
        .where((entry) => _itemType(entry, _itemPayload(entry)) == 'fileChange')
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (prompt.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(prompt),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 860),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text(status)),
                      if (isRunning)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (error != null && error.isNotEmpty)
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  if (markdown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    MarkdownBody(
                      data: markdown,
                      selectable: true,
                    ),
                  ],
                  if (commandItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Commands',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ...commandItems.map(_buildCommandItem),
                  ],
                  if (fileChangeItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'File Changes',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ...fileChangeItems.map(_buildFileChangeItem),
                  ],
                  if (diff.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: const Text('Diff'),
                      tilePadding: EdgeInsets.zero,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: SelectableText(
                            diff,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandItem(Map<String, dynamic> item) {
    final payload = _itemPayload(item);
    final command =
        payload['command'] ?? payload['cmd'] ?? payload['text'] ?? '';
    final status = payload['status'] ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$command${status.toString().isNotEmpty ? " ($status)" : ""}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _buildFileChangeItem(Map<String, dynamic> item) {
    final payload = _itemPayload(item);
    final summary = payload['summary'] ??
        payload['path'] ??
        payload['description'] ??
        jsonEncode(payload);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(summary.toString()),
    );
  }
}
