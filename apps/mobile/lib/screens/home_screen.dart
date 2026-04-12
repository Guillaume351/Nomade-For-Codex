import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../models/workspace.dart';
import '../providers/nomade_provider.dart';
import 'secure_scan_camera_screen.dart';
import '../widgets/chat_turn_widget.dart';
import '../widgets/e2e_guide_sheet.dart';
import '../widgets/sidebar.dart';
import '../widgets/tunnel_manager_sheet.dart';

enum _TopBarMenuAction {
  turnOptions,
  copyUsefulLogs,
  toggleDiagnostics,
  e2eGuide,
  approveSecureScan,
  tunnelManager,
  serviceTerminal,
}

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
  final Set<String> _expandedWorkspaceIds = <String>{};

  bool _showDiagnostics = false;

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

    final provider = context.read<NomadeProvider>();
    String? deliveryPolicyOverride;
    final selectedAgent = provider.selectedAgent;
    final shouldPromptForOfflineChoice = provider.offlineTurnDefault == 'prompt' &&
        selectedAgent != null &&
        !selectedAgent.isOnline;
    if (shouldPromptForOfflineChoice) {
      deliveryPolicyOverride = await _askOfflineDeliveryPolicy(provider);
      if (deliveryPolicyOverride == null) {
        return;
      }
    }

    _promptController.clear();
    await provider.sendPrompt(
      text,
      deliveryPolicyOverride: deliveryPolicyOverride,
    );
    _scrollToBottom(force: true);
  }

  Future<String?> _askOfflineDeliveryPolicy(NomadeProvider provider) async {
    final allowQueue = provider.canUseDeferredTurns;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agent offline'),
          content: Text(
            allowQueue
                ? 'Send now and fail if still offline, or queue this turn until reconnect.'
                : 'Your agent is offline. Queued turns are not available on your current plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('immediate'),
              child: const Text('Send now'),
            ),
            if (allowQueue)
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop('defer_if_offline'),
                child: const Text('Queue for reconnect'),
              ),
          ],
        );
      },
    );
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

  Future<void> _startSecureScanApproval() async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await Navigator.of(context).push<SecureScanCameraResult>(
      MaterialPageRoute(
        builder: (_) => const SecureScanCameraScreen(
          title: 'Approve secure scan',
        ),
      ),
    );
    if (!mounted || result == null || !result.hasData) {
      return;
    }

    final provider = context.read<NomadeProvider>();
    try {
      await provider.stagePendingSecureScanData(
        scanPayload: result.scanPayload,
        scanShortCode: result.scanShortCode,
        serverUrl: result.serverUrl,
      );
      await provider.approveSecureScan(
        scanPayload: result.scanPayload,
        scanShortCode: result.scanShortCode,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Secure scan approved')),
      );
    } catch (error) {
      final normalizedStatus = provider.status.trim();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            normalizedStatus.isEmpty
                ? 'Secure scan failed: $error'
                : normalizedStatus,
          ),
        ),
      );
    }
  }

  Future<void> _copyUsefulLogs(NomadeProvider provider) async {
    final conversation = provider.selectedConversation;
    if (conversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionne une conversation pour copier les logs.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final report = provider.buildConversationDebugReport(conversation.id);
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs utiles copiés'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleTopBarMenuAction(
    _TopBarMenuAction action,
    NomadeProvider provider,
  ) async {
    switch (action) {
      case _TopBarMenuAction.turnOptions:
        _showOptionsBottomSheet(context);
        return;
      case _TopBarMenuAction.copyUsefulLogs:
        await _copyUsefulLogs(provider);
        return;
      case _TopBarMenuAction.toggleDiagnostics:
        setState(() {
          _showDiagnostics = !_showDiagnostics;
        });
        return;
      case _TopBarMenuAction.e2eGuide:
        showE2eGuideSheet(context);
        return;
      case _TopBarMenuAction.approveSecureScan:
        await _startSecureScanApproval();
        return;
      case _TopBarMenuAction.tunnelManager:
        showTunnelManagerSheet(context);
        return;
      case _TopBarMenuAction.serviceTerminal:
        _showTerminalSheet(context);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final isWideLayout =
        MediaQuery.of(context).size.width >= _conversationRailBreakpoint;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    _ensureWorkspaceExpansion(provider);
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
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
                                      width: 356,
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
    final topBarWidth = MediaQuery.of(context).size.width;
    final isCompactTopBar = topBarWidth < 1220;
    final isUltraCompactTopBar = topBarWidth < 860;
    final conversation = provider.selectedConversation;
    final hasRunningTurn =
        provider.activeTurnId != null || conversation?.status == 'running';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                  if (!isUltraCompactTopBar) ...[
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
                ],
              ),
            ),
            if (hasRunningTurn)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: isUltraCompactTopBar
                    ? _buildRunningDotBadge(theme, scheme)
                    : _buildRunningBadge(
                        theme,
                        scheme,
                        compact: isCompactTopBar,
                      ),
              ),
            if (_hasCodexRateLimit(provider))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: isUltraCompactTopBar
                    ? _buildCompactQuotaBadge(provider, theme, scheme)
                    : _buildCodexQuotaBadge(
                        provider,
                        theme,
                        scheme,
                        compact: isCompactTopBar,
                      ),
              ),
            if (!isCompactTopBar) ...[
              _buildTopAction(
                icon: Icons.menu_book_outlined,
                tooltip: 'Guide E2E',
                onPressed: () => showE2eGuideSheet(context),
              ),
              _buildTopAction(
                icon: Icons.qr_code_scanner_rounded,
                tooltip: 'Approve secure scan',
                onPressed: _startSecureScanApproval,
              ),
              if (provider.selectedWorkspace != null)
                _buildTopAction(
                  icon: Icons.wifi_tethering_rounded,
                  tooltip: 'Tunnel management',
                  onPressed: () => showTunnelManagerSheet(context),
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
                icon: Icons.copy_all_rounded,
                tooltip: 'Copier logs utiles',
                onPressed: () => _copyUsefulLogs(provider),
              ),
            ],
            _buildTopAction(
              icon: _showDiagnostics
                  ? Icons.bug_report_outlined
                  : Icons.bug_report_rounded,
              tooltip: 'Diagnostics & logs',
              onPressed: () {
                setState(() {
                  _showDiagnostics = !_showDiagnostics;
                });
              },
            ),
            if (isCompactTopBar)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: PopupMenuButton<_TopBarMenuAction>(
                  tooltip: 'Actions',
                  icon: const Icon(Icons.more_horiz_rounded),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _TopBarMenuAction.copyUsefulLogs,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.copy_all_rounded),
                        title: Text('Copier logs utiles'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _TopBarMenuAction.toggleDiagnostics,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.bug_report_outlined),
                        title: Text(
                          _showDiagnostics
                              ? 'Masquer diagnostics'
                              : 'Afficher diagnostics',
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _TopBarMenuAction.turnOptions,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Turn options'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _TopBarMenuAction.e2eGuide,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.menu_book_outlined),
                        title: Text('Guide E2E'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _TopBarMenuAction.approveSecureScan,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.qr_code_scanner_rounded),
                        title: Text('Approve secure scan'),
                      ),
                    ),
                    if (provider.selectedWorkspace != null)
                      const PopupMenuItem(
                        value: _TopBarMenuAction.tunnelManager,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.wifi_tethering_rounded),
                          title: Text('Tunnel management'),
                        ),
                      ),
                    if (provider.selectedService != null)
                      const PopupMenuItem(
                        value: _TopBarMenuAction.serviceTerminal,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.terminal_rounded),
                          title: Text('Service terminal'),
                        ),
                      ),
                  ],
                  onSelected: (value) =>
                      _handleTopBarMenuAction(value, provider),
                ),
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
    final socket =
        provider.realtimeConnected ? 'Realtime connected' : 'Realtime offline';
    return '$agent • $socket';
  }

  Widget _buildRunningBadge(
    ThemeData theme,
    ColorScheme scheme, {
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 6),
            Text(
              'running',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRunningDotBadge(ThemeData theme, ColorScheme scheme) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 9,
        height: 9,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: scheme.primary,
        ),
      ),
    );
  }

  bool _hasCodexRateLimit(NomadeProvider provider) {
    return provider.activeCodexRateLimitSnapshot != null;
  }

  int? _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic>? _extractRateWindow(
    Map<String, dynamic>? snapshot,
    String key,
  ) {
    if (snapshot == null) {
      return null;
    }
    final value = snapshot[key];
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return null;
  }

  List<Map<String, dynamic>> _collectRateWindows(
      Map<String, dynamic>? snapshot) {
    final windows = <Map<String, dynamic>>[];
    final primary = _extractRateWindow(snapshot, 'primary');
    final secondary = _extractRateWindow(snapshot, 'secondary');
    if (primary != null) {
      windows.add(primary);
    }
    if (secondary != null) {
      windows.add(secondary);
    }
    windows.sort((a, b) {
      final left =
          _toInt(a['windowDurationMins'] ?? a['window_minutes']) ?? 999999;
      final right =
          _toInt(b['windowDurationMins'] ?? b['window_minutes']) ?? 999999;
      return left.compareTo(right);
    });
    return windows;
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatDateTimeExact(DateTime dateTime) {
    final yyyy = dateTime.year.toString().padLeft(4, '0');
    final mm = _twoDigits(dateTime.month);
    final dd = _twoDigits(dateTime.day);
    final hh = _twoDigits(dateTime.hour);
    final mi = _twoDigits(dateTime.minute);
    final ss = _twoDigits(dateTime.second);
    return '$yyyy-$mm-$dd $hh:$mi:$ss';
  }

  String _activeRateLimitId(NomadeProvider provider) {
    if (provider.codexRateLimitsByLimitId.containsKey('codex')) {
      return 'codex';
    }
    if (provider.codexRateLimitsByLimitId.isNotEmpty) {
      return provider.codexRateLimitsByLimitId.keys.first;
    }
    return '-';
  }

  String _formatResetExact(Map<String, dynamic> window) {
    final resetsAt =
        _toInt(window['resetsAt'] ?? window['resets_at'] ?? window['resetAt']);
    if (resetsAt == null || resetsAt <= 0) {
      return '-';
    }
    final utc =
        DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000, isUtc: true);
    final local = utc.toLocal();
    return '${_formatDateTimeExact(local)} local (${_formatDateTimeExact(utc)} UTC)';
  }

  void _showCodexQuotaDetails(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final snapshot = provider.activeCodexRateLimitSnapshot;
    if (snapshot == null) {
      return;
    }
    final windows = _collectRateWindows(snapshot);
    if (windows.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Codex usage windows',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Limit id: ${_activeRateLimitId(provider)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < windows.length && i < 2; i++) ...[
                  _buildQuotaWindowDetailRow(theme, scheme, windows[i], i),
                  if (i < windows.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuotaWindowDetailRow(
    ThemeData theme,
    ColorScheme scheme,
    Map<String, dynamic> window,
    int index,
  ) {
    final used = (_toInt(window['usedPercent'] ?? window['used_percent']) ?? 0)
        .clamp(0, 100);
    final remaining = (100 - used).clamp(0, 100);
    final label = _formatWindowLabel(window, index);
    final windowMins =
        _toInt(window['windowDurationMins'] ?? window['window_minutes']) ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label window',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Used: $used%  •  Remaining: $remaining%  •  Duration: ${windowMins}m',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Reset: ${_formatResetExact(window)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _formatWindowLabel(Map<String, dynamic> window, int fallbackIndex) {
    final durationMins =
        _toInt(window['windowDurationMins'] ?? window['window_minutes']);
    if (durationMins == null || durationMins <= 0) {
      return fallbackIndex == 0 ? 'fenêtre 1' : 'fenêtre 2';
    }
    if (durationMins % (24 * 60) == 0) {
      final days = durationMins ~/ (24 * 60);
      return '${days}j';
    }
    if (durationMins % 60 == 0) {
      final hours = durationMins ~/ 60;
      return '${hours}h';
    }
    return '${durationMins}m';
  }

  String _formatResetShort(Map<String, dynamic> window) {
    final resetsAt =
        _toInt(window['resetsAt'] ?? window['resets_at'] ?? window['resetAt']);
    if (resetsAt == null || resetsAt <= 0) {
      return '';
    }
    final dateTime =
        DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000, isUtc: true)
            .toLocal();
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return ' reset $hh:$mm';
  }

  Widget _buildCodexQuotaBadge(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme, {
    bool compact = false,
  }) {
    final snapshot = provider.activeCodexRateLimitSnapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final windows = _collectRateWindows(snapshot);
    if (windows.isEmpty) {
      return const SizedBox.shrink();
    }
    final pieces = <String>[];
    final compactPieces = <String>[];
    var minRemaining = 100;
    for (var i = 0; i < windows.length && i < 2; i++) {
      final window = windows[i];
      final used =
          (_toInt(window['usedPercent'] ?? window['used_percent']) ?? 0)
              .clamp(0, 100);
      final remaining = (100 - used).clamp(0, 100);
      if (remaining < minRemaining) {
        minRemaining = remaining;
      }
      final label = _formatWindowLabel(window, i);
      final resetSuffix = _formatResetShort(window);
      pieces.add('$label $remaining%$resetSuffix');
      compactPieces.add('$label:$remaining%');
    }

    final badgeColor = minRemaining <= 5
        ? scheme.error
        : minRemaining <= 20
            ? scheme.tertiary
            : scheme.primary;
    return Tooltip(
      message: 'Show exact reset times',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _showCodexQuotaDetails(provider, theme, scheme),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              compact
                  ? compactPieces.join(' ')
                  : 'Codex restant ${pieces.join(' · ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactQuotaBadge(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final snapshot = provider.activeCodexRateLimitSnapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final windows = _collectRateWindows(snapshot);
    if (windows.isEmpty) {
      return const SizedBox.shrink();
    }
    var minRemaining = 100;
    for (final window in windows) {
      final used =
          (_toInt(window['usedPercent'] ?? window['used_percent']) ?? 0)
              .clamp(0, 100);
      final remaining = (100 - used).clamp(0, 100);
      if (remaining < minRemaining) {
        minRemaining = remaining;
      }
    }
    final badgeColor = minRemaining <= 5
        ? scheme.error
        : minRemaining <= 20
            ? scheme.tertiary
            : scheme.primary;
    return Tooltip(
      message: 'Show exact reset times',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _showCodexQuotaDetails(provider, theme, scheme),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Q $minRemaining%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
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
              TextButton.icon(
                onPressed: () => _copyUsefulLogs(provider),
                icon: const Icon(Icons.copy_all_rounded, size: 17),
                label: const Text('Copier logs utiles'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Inclut runtime/events/E2E/turns pour debug.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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

  void _ensureWorkspaceExpansion(NomadeProvider provider) {
    final selectedWorkspaceId = provider.selectedWorkspace?.id;
    if (selectedWorkspaceId == null || selectedWorkspaceId.isEmpty) {
      _expandedWorkspaceIds.clear();
      return;
    }
    if (_expandedWorkspaceIds.contains(selectedWorkspaceId)) {
      return;
    }
    _expandedWorkspaceIds
      ..clear()
      ..add(selectedWorkspaceId);
  }

  void _handleWorkspaceExpansion({
    required NomadeProvider provider,
    required Workspace workspace,
    required bool expanded,
  }) {
    setState(() {
      if (expanded) {
        _expandedWorkspaceIds
          ..clear()
          ..add(workspace.id);
      } else {
        _expandedWorkspaceIds.remove(workspace.id);
      }
    });

    if (expanded && provider.selectedWorkspace?.id != workspace.id) {
      provider.onWorkspaceSelected(workspace);
    }
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
                    'Projects',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh data',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: provider.loadingData
                      ? null
                      : () async {
                          await provider.refreshAll();
                        },
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
            child: provider.workspaces.isEmpty
                ? _buildRailPlaceholder(
                    icon: Icons.folder_open_rounded,
                    title: 'No workspace',
                    subtitle:
                        'Open the workspace panel to pair an agent and create or import workspaces.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                    children: provider.workspaces
                        .map((workspace) =>
                            _buildWorkspaceNode(provider, workspace))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceNode(NomadeProvider provider, Workspace workspace) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedWorkspace = provider.selectedWorkspace?.id == workspace.id;
    final expanded = _expandedWorkspaceIds.contains(workspace.id);
    final workspaceConversations =
        selectedWorkspace ? provider.conversations : const <Conversation>[];
    final workspaceIsRunning = _workspaceIsRunning(
      provider,
      workspaceId: workspace.id,
      conversations: workspaceConversations,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selectedWorkspace
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selectedWorkspace
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.66),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(
              'workspace-${workspace.id}-${expanded ? "open" : "closed"}'),
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          onExpansionChanged: (value) => _handleWorkspaceExpansion(
            provider: provider,
            workspace: workspace,
            expanded: value,
          ),
          leading: Icon(
            selectedWorkspace
                ? Icons.folder_open_rounded
                : Icons.folder_copy_outlined,
            size: 20,
            color: selectedWorkspace ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  workspace.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        selectedWorkspace ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (workspaceIsRunning)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          subtitle: Text(
            selectedWorkspace
                ? '${workspaceConversations.length} conversation${workspaceConversations.length > 1 ? "s" : ""}'
                : workspace.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            if (!selectedWorkspace)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await provider.onWorkspaceSelected(workspace);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open workspace'),
                  ),
                ),
              ),
            if (selectedWorkspace) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await provider.createConversation();
                  },
                  icon: const Icon(Icons.add_comment_outlined, size: 16),
                  label: const Text('New conversation'),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => showTunnelManagerSheet(context),
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                  label: Text('Tunnels (${provider.tunnels.length})'),
                ),
              ),
              const SizedBox(height: 8),
              if (workspaceConversations.isEmpty)
                Text(
                  'No conversation yet in this workspace.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                ...workspaceConversations.map((conversation) =>
                    _buildConversationNode(provider, conversation)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConversationNode(
      NomadeProvider provider, Conversation conversation) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = provider.selectedConversation?.id == conversation.id;
    final isRunning = _conversationIsRunning(provider, conversation);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.36)
              : scheme.outlineVariant.withValues(alpha: 0.56),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: Icon(
          isRunning ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline,
          size: 18,
          color: isRunning
              ? scheme.primary
              : selected
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
        ),
        title: Text(
          conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          isRunning ? 'running' : conversation.status,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: isRunning
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
            : null,
        onTap: () async {
          provider.selectedConversation = conversation;
          await provider.loadTurns(conversation.id);
        },
      ),
    );
  }

  bool _workspaceIsRunning(
    NomadeProvider provider, {
    required String workspaceId,
    required List<Conversation> conversations,
  }) {
    final selectedWorkspaceId = provider.selectedWorkspace?.id;
    if (selectedWorkspaceId != workspaceId) {
      return false;
    }
    if (provider.activeTurnId != null) {
      return true;
    }
    return conversations.any((entry) => entry.status == 'running');
  }

  bool _conversationIsRunning(
      NomadeProvider provider, Conversation conversation) {
    if (conversation.status == 'running') {
      return true;
    }
    return provider.activeTurnId != null &&
        provider.selectedConversation?.id == conversation.id;
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
            if (provider.status.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                provider.status.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (provider.selectedConversation != null) ...[
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showDiagnostics = true;
                      });
                    },
                    icon: const Icon(Icons.bug_report_outlined, size: 16),
                    label: const Text('Afficher diagnostics'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _copyUsefulLogs(provider),
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('Copier logs utiles'),
                  ),
                ],
              ),
            ],
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
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Offline agent behavior',
              value: provider.offlineTurnDefault,
              items: const ['prompt', 'defer', 'fail'],
              onChanged: (val) {
                if (val == null) {
                  return;
                }
                provider.offlineTurnDefault = val;
              },
            ),
            if (!provider.canUseDeferredTurns) ...[
              const SizedBox(height: 8),
              Text(
                'Queued execution is unavailable on your current plan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
          initialValue: currentValue,
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
