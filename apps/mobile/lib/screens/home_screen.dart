import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nomade_provider.dart';
import '../widgets/chat_turn_widget.dart';
import '../widgets/e2e_guide_sheet.dart';
import '../widgets/sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _conversationRailBreakpoint = 980.0;
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;

    _promptController.clear();
    final provider = context.read<NomadeProvider>();
    await provider.sendPrompt(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final conversation = provider.selectedConversation;
    final isWideLayout =
        MediaQuery.of(context).size.width >= _conversationRailBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation?.title ?? 'Nomade'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Guide E2E',
            onPressed: () => showE2eGuideSheet(context),
          ),
          if (provider.selectedService != null)
            IconButton(
              icon: const Icon(Icons.terminal_outlined),
              onPressed: () => _showTerminalSheet(context),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // Show settings/options
              _showOptionsBottomSheet(context);
            },
          ),
        ],
      ),
      drawer: const Sidebar(),
      body: isWideLayout
          ? Row(
              children: [
                SizedBox(
                  width: 320,
                  child: _buildConversationRail(provider),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildChatPane(provider)),
              ],
            )
          : _buildChatPane(provider),
    );
  }

  Widget _buildChatPane(NomadeProvider provider) {
    return Column(
      children: [
        Expanded(
          child: provider.turns.isEmpty
              ? _buildEmptyState(provider)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.turns.length,
                  itemBuilder: (context, index) {
                    return ChatTurnWidget(turn: provider.turns[index]);
                  },
                ),
        ),
        _buildInputArea(provider),
      ],
    );
  }

  Widget _buildConversationRail(NomadeProvider provider) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Conversations',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'New conversation',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: provider.selectedWorkspace == null
                      ? null
                      : () async {
                          await provider.createConversation();
                        },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: provider.selectedWorkspace == null
                ? Center(
                    child: Text(
                      'Select a workspace first.',
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  )
                : provider.conversations.isEmpty
                    ? Center(
                        child: Text(
                          'No conversation yet.\nCreate one or import history.',
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: provider.conversations.length,
                        itemBuilder: (context, index) {
                          final conv = provider.conversations[index];
                          final selected =
                              provider.selectedConversation?.id == conv.id;
                          return ListTile(
                            leading: const Icon(Icons.chat_outlined, size: 20),
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              conv.status,
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: selected,
                            onTap: () async {
                              provider.selectedConversation = conv;
                              await provider.loadTurns(conv.id);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(NomadeProvider provider) {
    String message = 'Start a conversation with Codex';
    if (provider.selectedAgent == null) {
      message = 'Select or pair an agent in the sidebar';
    } else if (provider.selectedWorkspace == null) {
      message = 'Import history or create a workspace from the sidebar';
    } else if (provider.selectedConversation == null) {
      message = 'Create or select a conversation from the sidebar';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(NomadeProvider provider) {
    final isRunning = provider.activeTurnId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promptController,
                maxLines: 5,
                minLines: 1,
                decoration: InputDecoration(
                  hintText:
                      isRunning ? 'Codex is thinking...' : 'Ask something...',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                enabled: !isRunning,
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              onPressed: isRunning ? null : _handleSend,
              icon: isRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const _OptionsSheet();
      },
    );
  }

  void _showTerminalSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const _ServiceTerminalSheet();
      },
    );
  }
}

class _ServiceTerminalSheet extends StatefulWidget {
  const _ServiceTerminalSheet();

  @override
  State<_ServiceTerminalSheet> createState() => _ServiceTerminalSheetState();
}

class _ServiceTerminalSheetState extends State<_ServiceTerminalSheet> {
  final _inputController = TextEditingController();
  final _logsController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _logsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final service = provider.selectedService;
    if (service == null) {
      return const SizedBox.shrink();
    }

    final sessionId = service.session?.id;
    final logs = provider.serviceLogs(service.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logsController.hasClients) {
        _logsController.jumpTo(_logsController.position.maxScrollExtent);
      }
    });

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Terminal • ${service.name}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            sessionId == null ? 'No active session' : 'Session: $sessionId',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Container(
            height: 260,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              controller: _logsController,
              child: SelectableText(
                logs.isEmpty ? 'No output yet.' : logs,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(
                    hintText: 'Send command input...',
                  ),
                  onSubmitted: (_) => _send(provider, sessionId),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed:
                    sessionId == null ? null : () => _send(provider, sessionId),
                icon: const Icon(Icons.send_rounded),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: sessionId == null
                    ? null
                    : () => provider.terminateSession(
                          sessionId,
                          agentId: service.agentId,
                        ),
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _send(NomadeProvider provider, String? sessionId) {
    if (sessionId == null) return;
    final value = _inputController.text.trim();
    if (value.isEmpty) return;
    provider.sendSessionInput(sessionId, '$value\n');
    _inputController.clear();
  }
}

class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Turn Options',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildDropdown(
            label: 'Model',
            value: provider.selectedModel,
            items:
                provider.codexModels.map((m) => m['model'] as String).toList(),
            onChanged: (val) => provider.selectedModel = val,
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Approval Policy',
            value: provider.selectedApprovalPolicy,
            items: provider.codexApprovalPolicies,
            onChanged: (val) => provider.selectedApprovalPolicy = val,
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Sandbox Mode',
            value: provider.selectedSandboxMode,
            items: provider.codexSandboxModes,
            onChanged: (val) => provider.selectedSandboxMode = val,
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Reasoning Effort',
            value: provider.selectedEffort,
            items: provider.codexReasoningEfforts,
            onChanged: (val) => provider.selectedEffort = val,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12)),
        ),
      ],
    );
  }
}
