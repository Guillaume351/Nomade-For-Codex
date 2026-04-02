import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _maxLayoutWidth = 1540.0;

  final _promptController = TextEditingController();
  final _scrollController = ScrollController();

  bool _showDiagnostics = true;

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) {
      return;
    }

    _promptController.clear();
    final provider = context.read<NomadeProvider>();
    await provider.sendPrompt(text);
    _scrollToBottom(force: true);
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    const threshold = 140.0;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= threshold;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isNearBottom()) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final isWideLayout =
        MediaQuery.of(context).size.width >= _conversationRailBreakpoint;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    _scrollToBottom();

    return Scaffold(
      drawer: const Sidebar(),
      drawerEnableOpenDragGesture: !isWideLayout,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.16 : 0.07,
              ),
              theme.scaffoldBackgroundColor,
              scheme.tertiary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.11 : 0.05,
              ),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxLayoutWidth),
              child: Column(
                children: [
                  _buildTopBar(provider, isWideLayout),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.88),
                            border: Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.66),
                            ),
                          ),
                          child: isWideLayout
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 340,
                                      child: _buildConversationRail(provider),
                                    ),
                                    Expanded(child: _buildChatPane(provider)),
                                  ],
                                )
                              : _buildChatPane(provider),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(NomadeProvider provider, bool isWideLayout) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conversation = provider.selectedConversation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Builder(
              builder: (scaffoldContext) => IconButton(
                tooltip: 'Open workspace panel',
                onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
                icon: const Icon(Icons.space_dashboard_rounded),
              ),
            ),
            const SizedBox(width: 4),
            if (isWideLayout) ...[
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation?.title ?? 'Nomade for Codex',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _buildContextSubtitle(provider),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (provider.selectedWorkspace != null && isWideLayout)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text(
                    provider.selectedWorkspace!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  avatar: const Icon(Icons.folder_open_rounded, size: 16),
                ),
              ),
            _buildTopAction(
              icon: Icons.menu_book_outlined,
              tooltip: 'Guide E2E',
              onPressed: () => showE2eGuideSheet(context),
            ),
            if (provider.selectedService != null)
              _buildTopAction(
                icon: Icons.terminal_rounded,
                tooltip: 'Service terminal',
                onPressed: () => _showTerminalSheet(context),
              ),
            _buildTopAction(
              icon: Icons.tune_rounded,
              tooltip: 'Turn options',
              onPressed: () => _showOptionsBottomSheet(context),
            ),
            _buildTopAction(
              icon: _showDiagnostics
                  ? Icons.bug_report_outlined
                  : Icons.bug_report_rounded,
              tooltip: _showDiagnostics
                  ? 'Hide conversation diagnostics'
                  : 'Show conversation diagnostics',
              onPressed: () {
                setState(() {
                  _showDiagnostics = !_showDiagnostics;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.6),
        ),
        icon: Icon(icon, size: 19),
      ),
    );
  }

  String _buildContextSubtitle(NomadeProvider provider) {
    final agent = provider.selectedAgent?.displayName ?? 'No agent paired';
    final workspace =
        provider.selectedWorkspace?.name ?? 'No workspace selected';
    final socket =
        provider.realtimeConnected ? 'Realtime connected' : 'Realtime offline';
    return '$agent • $workspace • $socket';
  }

  Widget _buildChatPane(NomadeProvider provider) {
    final showDiagnostics =
        _showDiagnostics && provider.selectedConversation != null;

    return Column(
      children: [
        if (showDiagnostics) _buildConversationDiagnostics(provider),
        Expanded(
          child: provider.turns.isEmpty
              ? _buildEmptyState(provider)
              : Scrollbar(
                  controller: _scrollController,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: provider.turns.length,
                    itemBuilder: (context, index) {
                      return ChatTurnWidget(turn: provider.turns[index]);
                    },
                  ),
                ),
        ),
        _buildInputArea(provider),
      ],
    );
  }

  Widget _buildConversationDiagnostics(NomadeProvider provider) {
    final conversation = provider.selectedConversation;
    if (conversation == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final runtime = provider.runtimeTraceForConversation(conversation.id);
    final events =
        provider.debugEventsForConversation(conversation.id, limit: 8);
    final workspace = provider.selectedWorkspace;
    final agent = provider.selectedAgent;
    final agentOffline = agent?.isOnline != true;
    final turnRejectedOffline =
        runtime?.turnError?.toLowerCase().contains('agent_offline') == true;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined,
                  size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conversation diagnostics',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all_rounded, size: 17),
                tooltip: 'Copy debug report',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final report =
                      provider.buildConversationDebugReport(conversation.id);
                  Clipboard.setData(ClipboardData(text: report));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Debug report copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          if (agentOffline || turnRejectedOffline) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.orange.withValues(alpha: 0.32)),
              ),
              child: Text(
                turnRejectedOffline
                    ? 'Agent offline: this turn was not executed by Codex desktop, so it will not appear there.'
                    : 'Agent offline: new prompts may fail and will not sync to Codex desktop until reconnect.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInlineBadge('API', provider.api.baseUrl),
              _buildInlineBadge(
                'Socket',
                provider.realtimeConnected ? 'connected' : 'disconnected',
              ),
              _buildInlineBadge(
                'Agent',
                '${agent?.displayName ?? '-'} (${agent?.isOnline == true ? 'online' : 'offline'})',
              ),
              _buildInlineBadge('Workspace', workspace?.name ?? '-'),
            ],
          ),
          const SizedBox(height: 10),
          _debugLine('Workspace path', workspace?.path ?? '-'),
          _debugLine('Conversation',
              '${conversation.id} • status=${conversation.status}'),
          _debugLine('Thread (persisted)', conversation.codexThreadId ?? '-'),
          _debugLine(
            'Requested',
            'cwd=${runtime?.requestedCwd ?? workspace?.path ?? '-'} • model=${runtime?.requestedModel ?? provider.selectedModel ?? '-'} • approval=${runtime?.requestedApprovalPolicy ?? provider.selectedApprovalPolicy ?? '-'} • sandbox=${runtime?.requestedSandboxMode ?? provider.selectedSandboxMode ?? '-'} • effort=${runtime?.requestedEffort ?? provider.selectedEffort ?? '-'}',
          ),
          _debugLine(
            'Runtime',
            'turn=${runtime?.turnId ?? '-'} • codexTurn=${runtime?.codexTurnId ?? '-'} • thread=${runtime?.threadId ?? '-'} • status=${runtime?.turnStatus ?? '-'}',
          ),
          _debugLine(
            'Events',
            'received=${runtime?.eventsReceived ?? 0} • rendered=${runtime?.eventsRendered ?? 0}',
          ),
          if (runtime?.turnError != null && runtime!.turnError!.isNotEmpty)
            _debugLine('Error', runtime.turnError!),
          if (runtime != null && runtime.unsupportedMethods.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Text(
                'Methods not rendered in UI: ${runtime.unsupportedMethods.join(", ")}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Recent events',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          if (events.isEmpty)
            Text(
              'No events yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            ...events.map(
              (event) => Text(
                '${_formatClock(event.at)} ${event.type} ${event.message}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineBadge(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.66)),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _debugLine(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.88),
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _formatClock(DateTime dateTime) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final ss = dateTime.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Widget _buildConversationRail(NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.8),
        border: Border(
          right:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Conversations',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
          if (provider.selectedWorkspace != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  Icon(Icons.folder_open_rounded,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      provider.selectedWorkspace!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: provider.selectedWorkspace == null
                ? _buildRailPlaceholder(
                    icon: Icons.folder_open_rounded,
                    title: 'Select a workspace first',
                    subtitle:
                        'Open the workspace panel to pick or create a workspace.',
                  )
                : provider.conversations.isEmpty
                    ? _buildRailPlaceholder(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'No conversation yet',
                        subtitle:
                            'Create one from this panel or import Codex history from the drawer.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                        itemCount: provider.conversations.length,
                        itemBuilder: (context, index) {
                          final conv = provider.conversations[index];
                          final selected =
                              provider.selectedConversation?.id == conv.id;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              tileColor: selected
                                  ? scheme.primary.withValues(alpha: 0.12)
                                  : scheme.surface,
                              selectedTileColor:
                                  scheme.primary.withValues(alpha: 0.14),
                              selected: selected,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              leading: Icon(
                                Icons.chat_outlined,
                                size: 20,
                                color: selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                              title: Text(
                                conv.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                conv.status,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              onTap: () async {
                                provider.selectedConversation = conv;
                                await provider.loadTurns(conv.id);
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

  Widget _buildRailPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String message = 'Start a conversation with Codex';
    if (provider.selectedAgent == null) {
      message = 'Select or pair an agent in the workspace panel';
    } else if (provider.selectedWorkspace == null) {
      message = 'Import history or create a workspace from the workspace panel';
    } else if (provider.selectedConversation == null) {
      message = 'Create or select a conversation to start chatting';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(NomadeProvider provider) {
    final isRunning = provider.activeTurnId != null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  maxLines: 6,
                  minLines: 1,
                  enabled: !isRunning,
                  onSubmitted: (_) => isRunning ? null : _handleSend(),
                  decoration: InputDecoration(
                    hintText: isRunning
                        ? 'Codex is working on your request...'
                        : 'Ask Codex to inspect, edit, or run something...',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send prompt',
                onPressed: isRunning ? null : _handleSend,
                icon: isRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _OptionsSheet(),
    );
  }

  void _showTerminalSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _ServiceTerminalSheet(),
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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sessionId = service.session?.id;
    final logs = provider.serviceLogs(service.id);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logsController.hasClients) {
        _logsController.jumpTo(_logsController.position.maxScrollExtent);
      }
    });

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Terminal • ${service.name}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sessionId == null ? 'No active session' : 'Session: $sessionId',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 280,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1014),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: SingleChildScrollView(
                controller: _logsController,
                child: SelectableText(
                  logs.isEmpty ? 'No output yet.' : logs,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white,
                    height: 1.3,
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
                  tooltip: 'Send to session',
                  onPressed: sessionId == null
                      ? null
                      : () => _send(provider, sessionId),
                  icon: const Icon(Icons.send_rounded),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Terminate session',
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
      ),
    );
  }

  void _send(NomadeProvider provider, String? sessionId) {
    if (sessionId == null) {
      return;
    }

    final value = _inputController.text.trim();
    if (value.isEmpty) {
      return;
    }

    provider.sendSessionInput(sessionId, '$value\n');
    _inputController.clear();
  }
}

class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          10,
          24,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Turn options',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tune model and execution policies for the next prompt.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            _buildDropdown(
              label: 'Model',
              value: provider.selectedModel,
              items: provider.codexModels
                  .map((m) => m['model'] as String)
                  .toList(),
              onChanged: (val) => provider.selectedModel = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Approval policy',
              value: provider.selectedApprovalPolicy,
              items: provider.codexApprovalPolicies,
              onChanged: (val) => provider.selectedApprovalPolicy = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Sandbox mode',
              value: provider.selectedSandboxMode,
              items: provider.codexSandboxModes,
              onChanged: (val) => provider.selectedSandboxMode = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Reasoning effort',
              value: provider.selectedEffort,
              items: provider.codexReasoningEfforts,
              onChanged: (val) => provider.selectedEffort = val,
            ),
            if (provider.codexCollaborationModes.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildDropdown(
                label: 'Collaboration mode',
                value: provider.selectedCollaborationModeSlug,
                items: provider.codexCollaborationModes
                    .map((entry) => entry['slug']?.toString() ?? '')
                    .where((slug) => slug.isNotEmpty)
                    .toList(),
                onChanged: (val) =>
                    provider.selectedCollaborationModeSlug = val,
              ),
            ],
            if (provider.codexSkills.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Skills',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.codexSkills.map((skill) {
                  final path = skill['path']?.toString() ?? '';
                  final name = skill['name']?.toString() ?? path;
                  if (path.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return FilterChip(
                    label: Text(name),
                    selected: provider.selectedSkillPaths.contains(path),
                    onSelected: (_) => provider.toggleSkillPath(path),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final sanitizedItems = items
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
    final currentValue =
        value != null && sanitizedItems.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: currentValue,
          items: sanitizedItems
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
