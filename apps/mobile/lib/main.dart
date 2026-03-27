import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
  final api = NomadeApi(
    baseUrl: const String.fromEnvironment(
      'NOMADE_API_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );

  final emailController = TextEditingController();
  final promptController = TextEditingController();
  final newConversationController = TextEditingController();
  final workspaceNameController = TextEditingController(text: 'Local workspace');
  final workspacePathController = TextEditingController(text: '.');

  String status = 'Idle';
  String? deviceCode;
  String? userCode;
  String? accessToken;
  String? pairingCode;

  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> workspaces = [];
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> turns = [];

  String? selectedAgentId;
  String? selectedWorkspaceId;
  String? selectedConversationId;
  String? activeTurnId;

  WebSocketChannel? socket;
  StreamSubscription<dynamic>? socketSub;

  final Map<String, StringBuffer> streamByTurn = {};

  @override
  void dispose() {
    socketSub?.cancel();
    socket?.sink.close();
    emailController.dispose();
    promptController.dispose();
    newConversationController.dispose();
    workspaceNameController.dispose();
    workspacePathController.dispose();
    super.dispose();
  }

  Future<void> runLoginFlow() async {
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
      email: emailController.text.trim(),
    );

    setState(() => status = 'Polling token...');
    while (mounted) {
      final polled = await api.pollDeviceCode(deviceCode!);
      if (polled['status'] == 'ok') {
        accessToken = polled['accessToken'] as String;
        setState(() => status = 'Authenticated');
        await _connectSocket();
        await _bootstrapData();
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> makePairingCode() async {
    if (accessToken == null) {
      return;
    }
    setState(() => status = 'Creating pairing code...');
    final response = await api.createPairingCode(accessToken!);
    setState(() {
      pairingCode = response['pairingCode'] as String;
      status = 'Pairing code ready';
    });
  }

  Future<void> _connectSocket() async {
    final token = accessToken;
    if (token == null) {
      return;
    }

    await socketSub?.cancel();
    await socket?.sink.close();

    socket = api.openUserSocket(token);
    socketSub = socket!.stream.listen(
      _onSocketRawEvent,
      onError: (_) {
        setState(() => status = 'Realtime disconnected');
      },
      onDone: () {
        setState(() => status = 'Realtime closed');
      },
      cancelOnError: false,
    );
  }

  Future<void> _bootstrapData() async {
    final token = accessToken;
    if (token == null) {
      return;
    }

    final loadedAgents = await api.listAgents(token);
    final loadedWorkspaces = await api.listWorkspaces(token);
    setState(() {
      agents = loadedAgents;
      workspaces = loadedWorkspaces;
      selectedAgentId = agents.isNotEmpty ? agents.first['id'] as String : null;
      selectedWorkspaceId =
          workspaces.isNotEmpty ? workspaces.first['id'] as String : null;
    });

    if (selectedWorkspaceId != null) {
      await _loadConversations();
    }
  }

  Future<void> _loadConversations() async {
    final token = accessToken;
    final workspaceId = selectedWorkspaceId;
    if (token == null || workspaceId == null) {
      return;
    }

    final items = await api.listConversations(
      accessToken: token,
      workspaceId: workspaceId,
    );
    setState(() {
      conversations = items;
      selectedConversationId = items.isNotEmpty ? items.first['id'] as String : null;
      turns = [];
      streamByTurn.clear();
    });
    if (selectedConversationId != null) {
      await _loadTurns(selectedConversationId!);
    }
  }

  Future<void> _loadTurns(String conversationId) async {
    final token = accessToken;
    if (token == null) {
      return;
    }
    final items = await api.listConversationTurns(
      accessToken: token,
      conversationId: conversationId,
    );
    setState(() {
      turns = items;
    });
  }

  Future<void> _createWorkspace() async {
    final token = accessToken;
    final agentId = selectedAgentId;
    if (token == null || agentId == null) {
      return;
    }
    setState(() => status = 'Creating workspace...');
    await api.createWorkspace(
      accessToken: token,
      agentId: agentId,
      name: workspaceNameController.text.trim(),
      path: workspacePathController.text.trim(),
    );
    setState(() => status = 'Workspace created');
    await _bootstrapData();
  }

  Future<void> _createConversation({String? initialPrompt}) async {
    final token = accessToken;
    final workspaceId = selectedWorkspaceId;
    final agentId = selectedAgentId;
    if (token == null || workspaceId == null || agentId == null) {
      return;
    }

    final title = newConversationController.text.trim().isNotEmpty
        ? newConversationController.text.trim()
        : (initialPrompt ?? 'New conversation').split('\n').first;

    final created = await api.createConversation(
      accessToken: token,
      workspaceId: workspaceId,
      agentId: agentId,
      title: title.length > 80 ? '${title.substring(0, 80)}...' : title,
    );

    setState(() {
      conversations = [created, ...conversations];
      selectedConversationId = created['id'] as String;
      turns = [];
      newConversationController.clear();
    });
  }

  Future<void> _sendPrompt() async {
    final token = accessToken;
    if (token == null) {
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

    final created = await api.createTurn(
      accessToken: token,
      conversationId: conversationId,
      prompt: prompt,
    );

    setState(() {
      final seeded = Map<String, dynamic>.from(created);
      seeded['items'] = <Map<String, dynamic>>[];
      turns = [...turns, seeded];
      activeTurnId = created['id'] as String;
      promptController.clear();
    });
  }

  Future<void> _interruptTurn() async {
    final token = accessToken;
    final conversationId = selectedConversationId;
    final turnId = activeTurnId;
    if (token == null || conversationId == null || turnId == null) {
      return;
    }
    await api.interruptTurn(
      accessToken: token,
      conversationId: conversationId,
      turnId: turnId,
    );
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

      if (stream == 'agentMessage' || stream == 'reasoning' || stream == 'plan') {
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

  String _assistantMarkdown(Map<String, dynamic> turn) {
    final buffer = StringBuffer();
    final items = (turn['items'] as List?)?.cast<Map>() ?? const [];
    for (final raw in items) {
      final item = raw.cast<String, dynamic>();
      final type = item['item_type'] as String? ?? '';
      final payload = (item['payload'] as Map?)?.cast<String, dynamic>() ?? item;
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: runLoginFlow,
              child: const Text('Login with Device Code'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: makePairingCode,
              child: const Text('Create Agent Pairing Code'),
            ),
            const SizedBox(height: 16),
            Text('Status: $status'),
            if (userCode != null) Text('User code: $userCode'),
            if (pairingCode != null) Text('Pairing code: $pairingCode'),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nomade Conversations'),
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
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status: $status'),
          const SizedBox(height: 8),
          if (agents.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: selectedAgentId,
              hint: const Text('Select agent'),
              items: agents
                  .map(
                    (agent) => DropdownMenuItem<String>(
                      value: agent['id'] as String,
                      child: Text(agent['name'] as String? ?? 'Agent'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => selectedAgentId = value),
            ),
          if (workspaces.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: selectedWorkspaceId,
              hint: const Text('Select workspace'),
              items: workspaces
                  .map(
                    (workspace) => DropdownMenuItem<String>(
                      value: workspace['id'] as String,
                      child: Text(workspace['name'] as String? ?? 'Workspace'),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                setState(() => selectedWorkspaceId = value);
                await _loadConversations();
              },
            ),
          if (workspaces.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('Create a workspace'),
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
          const SizedBox(height: 12),
          TextField(
            controller: newConversationController,
            decoration: const InputDecoration(labelText: 'New conversation title'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _createConversation(),
            child: const Text('New conversation'),
          ),
          const SizedBox(height: 12),
          const Text('Conversations'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
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
                      setState(() => selectedConversationId = conversationId);
                      await _loadTurns(conversationId);
                    },
                  ),
                );
              },
            ),
          ),
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

    return Column(
      children: [
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
                onPressed: _sendPrompt,
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
    final commandItems = items
        .map((entry) => entry.cast<String, dynamic>())
        .where((entry) => (entry['item_type'] as String? ?? '') == 'commandExecution')
        .toList();
    final fileChangeItems = items
        .map((entry) => entry.cast<String, dynamic>())
        .where((entry) => (entry['item_type'] as String? ?? '') == 'fileChange')
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
    final payload = (item['payload'] as Map?)?.cast<String, dynamic>() ?? item;
    final command = payload['command'] ?? payload['cmd'] ?? payload['text'] ?? '';
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
    final payload = (item['payload'] as Map?)?.cast<String, dynamic>() ?? item;
    final summary = payload['summary'] ?? payload['path'] ?? payload['description'] ?? jsonEncode(payload);
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
