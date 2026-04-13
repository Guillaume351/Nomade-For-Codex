part of 'home_screen.dart';

extension HomeScreenComposerMethods on _HomeScreenState {
  Future<void> _handleSend() async {
    final rawInput = _promptController.text.trim();
    if (rawInput.isEmpty) {
      return;
    }

    final provider = context.read<NomadeProvider>();
    final slashResolution = await _handleComposerSlashCommand(
      provider: provider,
      rawInput: rawInput,
    );
    if (!mounted) {
      return;
    }
    if (slashResolution.consumeOnly) {
      _promptController.clear();
      setState(() {});
      return;
    }
    final text = slashResolution.promptToSend?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }

    String? deliveryPolicyOverride;
    final selectedAgent = provider.selectedAgent;
    final shouldPromptForOfflineChoice =
        provider.offlineTurnDefault == 'prompt' &&
            selectedAgent != null &&
            !selectedAgent.isOnline;
    if (shouldPromptForOfflineChoice) {
      deliveryPolicyOverride = await _askOfflineDeliveryPolicy(provider);
      if (deliveryPolicyOverride == null) {
        return;
      }
    }

    final extraInputItems = _pendingAttachments
        .map((attachment) => attachment.toInputItem())
        .toList(growable: false);
    _promptController.clear();
    setState(() {
      _pendingAttachments.clear();
    });
    await provider.sendPrompt(
      text,
      deliveryPolicyOverride: deliveryPolicyOverride,
      extraInputItems: extraInputItems,
    );
    _scrollToBottom(force: true);
  }

  Future<({bool consumeOnly, String? promptToSend})>
      _handleComposerSlashCommand({
    required NomadeProvider provider,
    required String rawInput,
  }) async {
    final parsed = _parseSlashCommandInput(rawInput);
    if (parsed == null) {
      return (consumeOnly: false, promptToSend: rawInput);
    }

    final command = parsed.command;
    final commandPrompt = parsed.prompt;

    switch (command) {
      case '/feedback':
        await _copyUsefulLogs(provider);
        return (consumeOnly: true, promptToSend: null);
      case '/status':
        _showSlashStatusSheet(provider);
        return (consumeOnly: true, promptToSend: null);
      case '/mcp':
        _showSlashMcpSheet();
        return (consumeOnly: true, promptToSend: null);
      case '/plan-mode':
        final wasPlan = provider.isPlanModeSelected();
        provider.selectCollaborationModeByKind(wasPlan ? 'default' : 'plan');
        if (!mounted) {
          return (consumeOnly: true, promptToSend: null);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasPlan
                  ? 'Plan mode disabled (default mode active).'
                  : 'Plan mode enabled.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        if (commandPrompt.isEmpty) {
          return (consumeOnly: true, promptToSend: null);
        }
        return (consumeOnly: false, promptToSend: commandPrompt);
      case '/review':
        if (commandPrompt.isEmpty) {
          return (
            consumeOnly: false,
            promptToSend:
                'Review the current workspace changes and list findings by severity with file references.',
          );
        }
        return (
          consumeOnly: false,
          promptToSend:
              'Review the current workspace changes. Focus especially on: $commandPrompt',
        );
      default:
        break;
    }

    final skillMatch = _skillSlashCommandMap(provider)[command];
    if (skillMatch != null) {
      final path = (skillMatch['path']?.toString() ?? '').trim();
      final name = (skillMatch['name']?.toString() ?? path).trim();
      if (path.isNotEmpty) {
        provider.toggleSkillPath(path);
        if (mounted) {
          final enabled = provider.selectedSkillPaths.contains(path);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                enabled ? 'Skill enabled: $name' : 'Skill disabled: $name',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        if (commandPrompt.isEmpty) {
          return (consumeOnly: true, promptToSend: null);
        }
        return (consumeOnly: false, promptToSend: commandPrompt);
      }
    }

    return (consumeOnly: false, promptToSend: rawInput);
  }

  ({String command, String prompt})? _parseSlashCommandInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('/')) {
      return null;
    }
    final lines = trimmed.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.isEmpty || !firstLine.startsWith('/')) {
      return null;
    }
    final pieces = firstLine
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (pieces.isEmpty) {
      return null;
    }
    final command = pieces.first.toLowerCase();
    final trailingFirstLine = firstLine.length > command.length
        ? firstLine.substring(command.length).trim()
        : '';
    final promptParts = <String>[];
    if (trailingFirstLine.isNotEmpty) {
      promptParts.add(trailingFirstLine);
    }
    if (lines.length > 1) {
      promptParts.addAll(lines.skip(1));
    }
    return (
      command: command,
      prompt: promptParts.join('\n').trim(),
    );
  }

  String _skillCommandSlug(Map<String, dynamic> skill) {
    final name = (skill['name']?.toString() ?? '').trim();
    final path = (skill['path']?.toString() ?? '').trim();
    final source = name.isNotEmpty ? name : path;
    if (source.isEmpty) {
      return '';
    }
    final normalized = source
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll('.md', '')
        .replaceAll('.MD', '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized;
  }

  Map<String, Map<String, dynamic>> _skillSlashCommandMap(
    NomadeProvider provider,
  ) {
    final values = <String, Map<String, dynamic>>{};
    for (final skill in provider.codexSkills) {
      final path = (skill['path']?.toString() ?? '').trim();
      if (path.isEmpty) {
        continue;
      }
      final slug = _skillCommandSlug(skill);
      if (slug.isEmpty) {
        continue;
      }
      values['/$slug'] = skill;
    }
    return values;
  }

  List<_ComposerSlashCommand> _composerSlashCommands(NomadeProvider provider) {
    final values = <_ComposerSlashCommand>[
      ..._HomeScreenState._baseSlashCommands,
    ];
    final skillMap = _skillSlashCommandMap(provider);
    final skillCommands = skillMap.entries.map((entry) {
      final skill = entry.value;
      final description = (skill['shortDescription']?.toString() ??
              skill['description']?.toString() ??
              'Toggle this skill for upcoming prompts.')
          .trim();
      return _ComposerSlashCommand(
        command: entry.key,
        description: description.isEmpty
            ? 'Toggle this skill for upcoming prompts.'
            : description,
      );
    }).toList()
      ..sort((a, b) => a.command.compareTo(b.command));
    values.addAll(skillCommands);
    return values;
  }

  List<_ComposerSlashCommand> _filteredSlashCommands(NomadeProvider provider) {
    final raw = _promptController.text.trimLeft();
    if (raw.isEmpty || !raw.startsWith('/')) {
      return const [];
    }
    final firstLine = raw.split('\n').first.trimRight();
    if (firstLine.isEmpty || firstLine.contains(RegExp(r'\s'))) {
      return const [];
    }
    final typed = firstLine.toLowerCase();
    final allCommands = _composerSlashCommands(provider);
    if (typed == '/') {
      return allCommands;
    }
    return allCommands
        .where((command) => command.command.startsWith(typed))
        .toList(growable: false);
  }

  void _applySlashCommand(_ComposerSlashCommand command) {
    final nextText = '${command.command} ';
    _promptController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    setState(() {});
  }

  Future<void> _handleComposerAction(
    _ComposerAction action,
    NomadeProvider provider,
  ) async {
    switch (action) {
      case _ComposerAction.addFiles:
        await _pickComposerFiles();
        return;
      case _ComposerAction.togglePlanMode:
        final wasPlan = provider.isPlanModeSelected();
        provider.selectCollaborationModeByKind(wasPlan ? 'default' : 'plan');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasPlan
                  ? 'Plan mode disabled (default mode active).'
                  : 'Plan mode enabled.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
    }
  }

  Future<void> _pickComposerFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
      type: FileType.any,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    var added = 0;
    setState(() {
      for (final file in result.files) {
        final path = (file.path ?? '').trim();
        if (path.isEmpty) {
          continue;
        }
        final exists = _pendingAttachments.any((entry) => entry.path == path);
        if (exists) {
          continue;
        }
        _pendingAttachments.add(
          _PendingAttachment(
            path: path,
            type: _attachmentInputType(path),
          ),
        );
        added += 1;
      }
    });
    if (added <= 0) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$added file${added > 1 ? "s" : ""} attached'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _attachmentInputType(String path) {
    final normalized = path.trim().toLowerCase();
    for (final extension in _HomeScreenState._imageExtensions) {
      if (normalized.endsWith(extension)) {
        return 'local_image';
      }
    }
    return 'mention';
  }

  void _removePendingAttachment(String path) {
    setState(() {
      _pendingAttachments.removeWhere((entry) => entry.path == path);
    });
  }

  void _showSlashStatusSheet(NomadeProvider provider) {
    final mode = provider.isPlanModeSelected() ? 'plan' : 'default';
    final selectedConversationId = provider.selectedConversation?.id ?? '-';
    final threadId = provider.selectedConversation?.codexThreadId ?? '-';
    final model = provider.selectedModel ?? '-';
    final effort = provider.selectedEffort ?? '-';
    final approval = provider.selectedApprovalPolicy ?? '-';
    final sandbox = provider.selectedSandboxMode ?? '-';
    final statusLine =
        provider.status.trim().isEmpty ? 'Idle' : provider.status.trim();
    final contextUsage = provider.turns.length;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thread status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _statusRow('Conversation', selectedConversationId),
                _statusRow('Thread', threadId),
                _statusRow('Mode', mode),
                _statusRow('Model', model),
                _statusRow('Effort', effort),
                _statusRow('Approval', approval),
                _statusRow('Sandbox', sandbox),
                _statusRow('Turns in memory', '$contextUsage'),
                _statusRow(
                  'Realtime',
                  provider.realtimeConnected ? 'connected' : 'disconnected',
                ),
                _statusRow('Status', statusLine),
                const SizedBox(height: 8),
                Text(
                  'Rate-limit details are shown in the quota badge when available.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusRow(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _showSlashMcpSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MCP status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This mobile build does not yet expose live connected MCP server details.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use Codex desktop/CLI for detailed MCP server status right now.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                onPressed: () => Navigator.of(context).pop('defer_if_offline'),
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
}
