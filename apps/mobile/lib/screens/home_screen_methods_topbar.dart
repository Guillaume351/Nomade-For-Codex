part of 'home_screen.dart';

extension _HomeScreenTopBarMethods on _HomeScreenState {
  Uri _publicUrlForApiBase(String apiBaseUrl, String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      path: normalizedPath,
      queryParameters: null,
      fragment: null,
    );
  }

  String _endpointSummary(String apiBaseUrl) {
    final uri = Uri.parse(apiBaseUrl);
    final host = uri.host.trim();
    if (host.isEmpty) {
      return apiBaseUrl;
    }
    if (uri.hasPort) {
      return '$host:${uri.port}';
    }
    return host;
  }

  Future<void> _applyServerEndpointChange(
    NomadeProvider provider, {
    required String normalizedUrl,
    required bool isReset,
  }) async {
    final current = provider.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    if (normalizedUrl == current) {
      return;
    }

    var shouldProceed = true;
    if (provider.isAuthenticated) {
      shouldProceed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                isReset ? 'Reset endpoint and sign out?' : 'Switch endpoint and sign out?',
              ),
              content: Text(
                isReset
                    ? 'Resetting the server endpoint signs you out to protect session tokens. Continue?'
                    : 'Changing the server endpoint signs you out to protect session tokens. Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!shouldProceed) {
      return;
    }

    if (isReset) {
      await provider.resetApiBaseUrl(clearSession: provider.isAuthenticated);
    } else {
      await provider.setApiBaseUrl(
        normalizedUrl,
        clearSession: provider.isAuthenticated,
      );
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isReset
              ? 'Server endpoint reset to ${provider.apiBaseUrl}'
              : 'Server endpoint set to ${provider.apiBaseUrl}',
        ),
      ),
    );
  }

  Future<void> _editServerEndpointQuick(NomadeProvider provider) async {
    final result = await showServerEndpointDialog(
      context,
      currentUrl: provider.apiBaseUrl,
      defaultUrl: provider.defaultApiBaseUrl,
      helperText:
          'Use your self-host endpoint to run without Nomade cloud subscription limits.',
    );
    if (result == null) {
      return;
    }
    await _applyServerEndpointChange(
      provider,
      normalizedUrl: result.normalizedUrl,
      isReset: result.isReset,
    );
  }

  Future<void> _resetServerEndpointQuick(NomadeProvider provider) async {
    if (provider.isUsingDefaultApiBaseUrl) {
      return;
    }
    await _applyServerEndpointChange(
      provider,
      normalizedUrl: provider.defaultApiBaseUrl,
      isReset: true,
    );
  }

  Future<void> _openBillingEntryPoint(
    NomadeProvider provider, {
    required String sourceLabel,
  }) async {
    if (provider.isSelfHostedEndpoint) {
      await provider.refreshBillingState();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Self-host endpoint detected. Nomade billing is disabled here.'),
        ),
      );
      return;
    }

    final canOpenNativePaywall =
        provider.billingUiSupported && provider.billingConfigured;
    if (canOpenNativePaywall) {
      await showProPaywallSheet(
        context,
        sourceLabel: sourceLabel,
      );
      return;
    }

    final launched = await launchUrl(
      _publicUrlForApiBase(provider.apiBaseUrl, '/pricing'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'Opened pricing page in browser.'
              : 'Unable to open pricing page.',
        ),
      ),
    );
  }

  void _showConnectionAndBillingSheet(NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connection & billing',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Server endpoint and subscription controls stay here, out of the main chat view.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildConnectionBillingPanel(provider),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _onChatScrollNotification(
    ScrollNotification notification,
    NomadeProvider provider,
  ) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollEndNotification) {
      _chatBottomOverscrollPx = 0;
      return false;
    }

    if (notification is! OverscrollNotification) {
      return false;
    }

    final metrics = notification.metrics;
    final atBottom = metrics.pixels >= (metrics.maxScrollExtent - 1);
    if (!atBottom || notification.overscroll <= 0) {
      return false;
    }

    _chatBottomOverscrollPx += notification.overscroll;
    if (_chatBottomOverscrollPx < 72) {
      return false;
    }
    _chatBottomOverscrollPx = 0;
    unawaited(_refreshFromBottomOverscroll(provider));
    return false;
  }

  Future<void> _refreshFromBottomOverscroll(NomadeProvider provider) async {
    if (_chatBottomRefreshInProgress) {
      return;
    }
    final conversation = provider.selectedConversation;
    if (conversation == null) {
      return;
    }

    final lastAt = _chatBottomRefreshLastAt;
    if (lastAt != null &&
        DateTime.now().difference(lastAt).inMilliseconds < 1200) {
      return;
    }

    _setStateSafe(() {
      _chatBottomRefreshInProgress = true;
    });
    _chatBottomRefreshLastAt = DateTime.now();
    try {
      await provider.refreshSelectedConversationFromDesktop();
    } finally {
      _setStateSafe(() {
        _chatBottomRefreshInProgress = false;
      });
    }
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
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.standardCurve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: hasRunningTurn
              ? scheme.surface.withValues(alpha: 0.9)
              : scheme.surface.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
          boxShadow: [
            BoxShadow(
              color: hasRunningTurn
                  ? scheme.primary.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: hasRunningTurn ? 20 : 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            if (!isWideLayout)
              Builder(
                builder: (scaffoldContext) => IconButton(
                  tooltip: 'Open workspace panel',
                  onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
                  icon: const Icon(Icons.space_dashboard_rounded),
                ),
              ),
            if (!isWideLayout) const SizedBox(width: 4),
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
              child: AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: AppMotion.standardCurve,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Column(
                  key: ValueKey(
                    '${conversation?.id ?? "none"}-${provider.realtimeConnected}',
                  ),
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
            ),
            if (hasRunningTurn)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: isUltraCompactTopBar
                    ? _buildRunningDotBadge(scheme)
                    : _buildRunningBadge(
                        theme,
                        scheme,
                        compact: isCompactTopBar,
                      ),
              ),
            if (_chatBottomRefreshInProgress)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: isUltraCompactTopBar
                    ? _buildSyncDotBadge(scheme)
                    : _buildSyncBadge(theme, scheme),
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
                icon: Icons.cloud_outlined,
                tooltip: 'Server endpoint & subscription',
                onPressed: () => _showConnectionAndBillingSheet(provider),
              ),
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
              if (provider.selectedConversation != null)
                _buildTopAction(
                  icon: Icons.difference_rounded,
                  tooltip: 'Conversation diff',
                  onPressed: () => _showConversationDiffBottomSheet(provider),
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
                _setStateSafe(() {
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
                      value: _TopBarMenuAction.connectionBilling,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.cloud_outlined),
                        title: Text('Connection & billing'),
                      ),
                    ),
                    if (provider.selectedConversation != null)
                      const PopupMenuItem(
                        value: _TopBarMenuAction.conversationDiff,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.difference_rounded),
                          title: Text('Conversation diff'),
                        ),
                      ),
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
        onPressed: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
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

  void _showConversationDiffBottomSheet(NomadeProvider provider) {
    final conversation = provider.selectedConversation;
    if (conversation == null) {
      return;
    }
    final diffTurns = provider.turns
        .where((turn) =>
            turn.conversationId == conversation.id &&
            turn.diff.trim().isNotEmpty)
        .toList(growable: false);
    if (diffTurns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No diff available in this conversation yet.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              6,
              16,
              MediaQuery.of(sheetContext).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Conversation diff',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final merged = _buildConversationDiffText(diffTurns);
                        await Clipboard.setData(ClipboardData(text: merged));
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Conversation diff copied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('Copy all'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${diffTurns.length} turn${diffTurns.length > 1 ? "s" : ""} with diffs',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: diffTurns.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (itemContext, index) {
                      final turn = diffTurns[index];
                      final prompt = _previewPrompt(turn.userPrompt);
                      final diff = turn.diff.trim();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.68),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Turn ${index + 1} • ${turn.status}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              prompt,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 260),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E1014),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  diff,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _previewPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return 'Prompt unavailable';
    }
    final singleLine = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.length <= 140) {
      return singleLine;
    }
    return '${singleLine.substring(0, 137)}...';
  }

  String _buildConversationDiffText(List<Turn> turnsWithDiff) {
    final buffer = StringBuffer();
    for (var index = 0; index < turnsWithDiff.length; index += 1) {
      final turn = turnsWithDiff[index];
      if (index > 0) {
        buffer.writeln();
      }
      buffer.writeln('=== Turn ${index + 1} (${turn.status}) ===');
      buffer.writeln('Prompt: ${_previewPrompt(turn.userPrompt)}');
      buffer.writeln(turn.diff.trim());
    }
    return buffer.toString().trim();
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
          PulseDot(color: scheme.primary, size: 7),
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

  Widget _buildRunningDotBadge(ColorScheme scheme) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: PulseDot(color: scheme.primary, size: 8),
    );
  }

  Widget _buildSyncBadge(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: scheme.secondary, size: 7),
          const SizedBox(width: 6),
          Text(
            'syncing',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncDotBadge(ColorScheme scheme) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: scheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: PulseDot(color: scheme.secondary, size: 8),
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
    final conversationId = provider.selectedConversation?.id ?? 'none';

    return Column(
      children: [
        if (provider.shouldShowUpgradePrompt) _buildUpgradeBanner(provider),
        if (showDiagnostics) _buildConversationDiagnostics(provider),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.standardCurve,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.012),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: provider.turns.isEmpty
                ? KeyedSubtree(
                    key: ValueKey('empty-$conversationId'),
                    child: _buildEmptyState(provider),
                  )
                : NotificationListener<ScrollNotification>(
                    key: ValueKey(
                        'turns-$conversationId-${provider.turns.length}'),
                    onNotification: (notification) =>
                        _onChatScrollNotification(notification, provider),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: provider.turns.length,
                        itemBuilder: (context, index) {
                          final turn = provider.turns[index];
                          return ChatTurnWidget(
                            key: ValueKey(turn.id),
                            turn: turn,
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ),
        _buildInputArea(provider),
      ],
    );
  }

  Widget _buildConnectionBillingPanel(NomadeProvider provider) {
    final isSelfHost = provider.isSelfHostedEndpoint;
    final planHeadline = isSelfHost
        ? 'Self-hosted'
        : provider.hasCloudProAccess
            ? 'Pro active'
            : 'Free plan';
    final planSupporting = isSelfHost
        ? 'No Nomade subscription on this endpoint.'
        : provider.billingUiSupported && provider.billingConfigured
            ? 'Open the in-app subscription sheet.'
            : 'Open pricing in the browser.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final cardWidth =
            isWide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildQuickAccessCard(
                icon: Icons.cloud_outlined,
                title: 'Server endpoint',
                headline: _endpointSummary(provider.apiBaseUrl),
                supportingText: provider.isUsingDefaultApiBaseUrl
                    ? 'Default endpoint: ${provider.apiBaseUrl}'
                    : 'Custom endpoint: ${provider.apiBaseUrl}',
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () => _editServerEndpointQuick(provider),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Change'),
                  ),
                  if (!provider.isUsingDefaultApiBaseUrl)
                    TextButton.icon(
                      onPressed: () => _resetServerEndpointQuick(provider),
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('Reset'),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildQuickAccessCard(
                icon: isSelfHost
                    ? Icons.dns_outlined
                    : provider.hasCloudProAccess
                        ? Icons.workspace_premium_outlined
                        : Icons.sell_outlined,
                title: 'Subscription',
                headline: planHeadline,
                supportingText: planSupporting,
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () => _openBillingEntryPoint(
                      provider,
                      sourceLabel: 'Connection & billing',
                    ),
                    icon: Icon(
                      isSelfHost
                          ? Icons.refresh_rounded
                          : provider.hasCloudProAccess
                              ? Icons.manage_accounts_outlined
                              : Icons.workspace_premium_outlined,
                      size: 16,
                    ),
                    label: Text(
                      isSelfHost
                          ? 'Refresh status'
                          : provider.hasCloudProAccess
                              ? 'Manage'
                              : 'Upgrade',
                    ),
                  ),
                  if (!isSelfHost)
                    TextButton(
                      onPressed: () async {
                        await provider.refreshBillingState();
                      },
                      child: const Text('Refresh'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickAccessCard({
    required IconData icon,
    required String title,
    required String headline,
    required String supportingText,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.62),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            supportingText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeBanner(NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reason = provider.upgradePromptReason;
    final isDeferredTurns =
        reason == NomadeProvider.upgradePromptReasonDeferredTurns;
    final isDeviceLimit =
        reason == NomadeProvider.upgradePromptReasonDeviceLimit;
    final isConcurrentLimit =
        reason == NomadeProvider.upgradePromptReasonConcurrentConversations;
    final quotaKnown =
        provider.currentAgents != null && provider.maxAgents != null;
    final quotaLabel = quotaKnown
        ? '${provider.currentAgents}/${provider.maxAgents} paired devices used'
        : 'Free tier limits still apply on this account';
    final title = isDeferredTurns
        ? 'Queued turns require Pro'
        : isDeviceLimit
            ? 'Device limit reached'
            : isConcurrentLimit
                ? 'One active conversation on Free'
            : 'Upgrade available';
    final message = isDeferredTurns
        ? 'Queue-for-reconnect is a paid cloud feature. Upgrade if you want turns to wait for an offline agent instead of failing immediately.'
        : isDeviceLimit
            ? 'Upgrade to Pro to keep pairing additional devices and unlock paid cloud limits.'
            : isConcurrentLimit
                ? 'Free tier can only run one conversation at a time. Upgrade if you want to work across multiple conversations in parallel.'
            : 'Upgrade to Pro to unlock additional cloud features.';
    final supporting = isDeferredTurns
        ? 'This prompt stays dismissed until you try a gated feature again.'
        : isConcurrentLimit
            ? 'This prompt stays dismissed until you try to start work in another conversation while one is still active.'
        : 'Use the connection icon in the top bar to manage billing or switch endpoint.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: provider.dismissUpgradePrompt,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          if (isDeviceLimit) ...[
            const SizedBox(height: 6),
            Text(
              quotaLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            supporting,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _openBillingEntryPoint(
                  provider,
                  sourceLabel: 'Upgrade banner',
                ),
                icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                label: const Text('Upgrade'),
              ),
              TextButton(
                onPressed: provider.dismissUpgradePrompt,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
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
            'received=${runtime?.eventsReceived ?? 0} • rendered=${runtime?.eventsRendered ?? 0} • turnsApi=${runtime?.turnsReloadApiCalls ?? 0} • throttle=${runtime?.turnsReloadThrottled ?? 0} • inflightSkip=${runtime?.turnsReloadSkippedInFlight ?? 0}',
          ),
          _debugLine(
            'Socket stats',
            'attempts=${runtime?.socketConnectAttempts ?? 0} • success=${runtime?.socketConnectSuccess ?? 0} • skips=${runtime?.socketConnectSkips ?? 0} • disconnects=${runtime?.socketDisconnects ?? 0} • reconnects=${runtime?.socketReconnectScheduled ?? 0}',
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
}
