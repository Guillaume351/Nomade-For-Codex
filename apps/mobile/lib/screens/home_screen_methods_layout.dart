part of 'home_screen.dart';

extension _HomeScreenLayoutMethods on _HomeScreenState {
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
    HapticFeedback.selectionClick();
    _setStateSafe(() {
      if (expanded) {
        _expandedWorkspaceIds
          ..clear()
          ..add(workspace.id);
      } else {
        _expandedWorkspaceIds.remove(workspace.id);
      }
    });

    if (expanded && provider.selectedWorkspace?.id != workspace.id) {
      unawaited(provider.onWorkspaceSelected(workspace));
    }
  }

  Widget _buildConversationRail(NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sortedWorkspaces = _sortedWorkspaces(
      provider.workspaces,
      provider.listSortMode,
    );

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
                PopupMenuButton<String>(
                  tooltip: 'Sort projects and conversations',
                  initialValue: provider.listSortMode,
                  icon: const Icon(Icons.tune_rounded),
                  onSelected: (value) {
                    provider.listSortMode = value;
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'latest',
                      child: Text('Latest first'),
                    ),
                    PopupMenuItem(
                      value: 'oldest',
                      child: Text('Oldest first'),
                    ),
                    PopupMenuItem(
                      value: 'name',
                      child: Text('Name (A-Z)'),
                    ),
                  ],
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
                    children: sortedWorkspaces.asMap().entries.map((entry) {
                      final index = entry.key;
                      final workspace = entry.value;
                      final delayMs = (index * 22).clamp(0, 190).toInt();
                      return FadeSlideIn(
                        delay: Duration(milliseconds: delayMs),
                        beginOffset: const Offset(0, 0.015),
                        child: _buildWorkspaceNode(provider, workspace),
                      );
                    }).toList(),
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
    final workspaceConversations = selectedWorkspace
        ? _sortedConversations(provider.conversations, provider.listSortMode)
        : const <Conversation>[];
    final workspaceIsRunning = _workspaceIsRunning(
      provider,
      workspaceId: workspace.id,
      conversations: workspaceConversations,
    );

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standardCurve,
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
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(left: 6),
                  alignment: Alignment.center,
                  child: PulseDot(color: scheme.primary, size: 7),
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
                      HapticFeedback.selectionClick();
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
                    HapticFeedback.selectionClick();
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
                ...workspaceConversations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final conversation = entry.value;
                  final delayMs = (index * 16).clamp(0, 140).toInt();
                  return FadeSlideIn(
                    delay: Duration(milliseconds: delayMs),
                    beginOffset: const Offset(0, 0.01),
                    child: _buildConversationNode(provider, conversation),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  List<Workspace> _sortedWorkspaces(List<Workspace> source, String sortMode) {
    final values = List<Workspace>.from(source);
    values.sort((a, b) {
      switch (sortMode) {
        case 'oldest':
          return a.createdAt.compareTo(b.createdAt);
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'latest':
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });
    return values;
  }

  List<Conversation> _sortedConversations(
    List<Conversation> source,
    String sortMode,
  ) {
    final values = List<Conversation>.from(source);
    values.sort((a, b) {
      switch (sortMode) {
        case 'oldest':
          final byUpdated = a.updatedAt.compareTo(b.updatedAt);
          if (byUpdated != 0) {
            return byUpdated;
          }
          return a.createdAt.compareTo(b.createdAt);
        case 'name':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'latest':
        default:
          final byUpdated = b.updatedAt.compareTo(a.updatedAt);
          if (byUpdated != 0) {
            return byUpdated;
          }
          return b.createdAt.compareTo(a.createdAt);
      }
    });
    return values;
  }

  Widget _buildConversationNode(
      NomadeProvider provider, Conversation conversation) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = provider.selectedConversation?.id == conversation.id;
    final isRunning = _conversationIsRunning(provider, conversation);

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standardCurve,
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
                width: 18,
                height: 18,
                child: Center(
                  child: PulseDot(color: scheme.primary, size: 7),
                ),
              )
            : null,
        onTap: () async {
          HapticFeedback.selectionClick();
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
                      _setStateSafe(() {
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
    final isCanceling = _cancelTurnInProgress;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final slashSuggestions = _filteredSlashCommands(provider);
    final dollarSuggestions = _filteredDollarSuggestions(provider);
    final isPlanMode = provider.isPlanModeSelected();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.standardCurve,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_pendingAttachments.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _pendingAttachments.map((attachment) {
                    final normalizedType = attachment.type.toLowerCase();
                    final isImage = normalizedType == 'image' ||
                        normalizedType == 'localimage' ||
                        normalizedType == 'local_image';
                    return InputChip(
                      avatar: Icon(
                        isImage
                            ? Icons.image_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 16,
                      ),
                      label: Text(
                        attachment.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      tooltip: attachment.tooltip,
                      onDeleted: isRunning
                          ? null
                          : () => _removePendingAttachment(attachment.id),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
              AnimatedSize(
                duration: AppMotion.medium,
                curve: AppMotion.standardCurve,
                child: slashSuggestions.isEmpty && dollarSuggestions.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow
                                  .withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.56),
                              ),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              children: slashSuggestions.isNotEmpty
                                  ? slashSuggestions.map((command) {
                                      return ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        title: Text(
                                          command.command,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          command.inlineHelp == null
                                              ? command.description
                                              : '${command.description} • ${command.inlineHelp}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: isRunning
                                            ? null
                                            : () => _applySlashCommand(command),
                                      );
                                    }).toList(growable: false)
                                  : dollarSuggestions.map((suggestion) {
                                      final kindLabel =
                                          suggestion.kind ==
                                                  _ComposerDollarSuggestionKind
                                                      .skill
                                              ? 'skill'
                                              : 'MCP';
                                      final subtitle = suggestion.description
                                              .trim()
                                              .isEmpty
                                          ? kindLabel
                                          : '$kindLabel • ${suggestion.description}';
                                      return ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        title: Text(
                                          suggestion.token,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: Icon(
                                          suggestion.enabled
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          size: 18,
                                          color: suggestion.enabled
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                        onTap: isRunning
                                            ? null
                                            : () => _applyDollarSuggestion(
                                                  suggestion,
                                                  provider,
                                                ),
                                      );
                                    }).toList(growable: false),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<_ComposerAction>(
                    tooltip: 'Composer actions',
                    enabled: !isRunning,
                    onSelected: (action) =>
                        _handleComposerAction(action, provider),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _ComposerAction.addPhotos,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.photo_library_outlined),
                          title: Text('Add photos'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ComposerAction.addFiles,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.attach_file_rounded),
                          title: Text('Add files'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ComposerAction.pasteImage,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.content_paste_rounded),
                          title: Text('Paste image'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ComposerAction.togglePlanMode,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isPlanMode
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                          ),
                          title: Text(
                            isPlanMode
                                ? 'Disable plan mode'
                                : 'Enable plan mode',
                          ),
                        ),
                      ),
                    ],
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.66),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (node, event) => _handleComposerKeyEvent(
                        event: event,
                        isRunning: isRunning,
                      ),
                      child: TextField(
                        controller: _promptController,
                        maxLines: 6,
                        minLines: 1,
                        enabled: !isRunning,
                        onChanged: (_) => _setStateSafe(() {}),
                        onSubmitted: (_) => isRunning ? null : _handleSend(),
                        decoration: InputDecoration(
                          hintText: isRunning
                              ? 'Codex is working on your request...'
                              : 'Ask Codex to inspect, edit, or run something...',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                        ),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isRunning) ...[
                    IconButton.filledTonal(
                      tooltip: 'Cancel running turn',
                      onPressed: isCanceling
                          ? null
                          : () => _confirmAndCancelActiveTurn(provider),
                      icon: isCanceling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.stop_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton.filled(
                    tooltip: isRunning ? 'Turn is running' : 'Send prompt',
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
              AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: AppMotion.standardCurve,
                switchOutCurve: Curves.easeInCubic,
                child: !isPlanMode
                    ? const SizedBox.shrink()
                    : Padding(
                        key: const ValueKey('plan-mode-row'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.checklist_rtl_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Plan mode enabled',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
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
      builder: (context) => const TurnOptionsSheet(),
    );
  }

  void _showTerminalSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const ServiceTerminalSheet(),
    );
  }
}
