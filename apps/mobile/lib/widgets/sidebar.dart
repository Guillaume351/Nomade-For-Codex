import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/conversation.dart';
import '../models/workspace.dart';
import '../providers/nomade_provider.dart';
import '../screens/onboarding_screen.dart';
import 'app_motion.dart';
import 'e2e_guide_sheet.dart';
import 'tunnel_manager_sheet.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  static const _accountDeletionConfirmCode = 'DELETE';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedWorkspaceIds = <String>{};
  final Set<String> _loadingWorkspaceIds = <String>{};
  final Map<String, List<Conversation>> _workspaceConversationCache =
      <String, List<Conversation>>{};

  String _prefetchSignature = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _copyUsefulLogs(
    BuildContext context,
    NomadeProvider provider,
  ) async {
    final conversation = provider.selectedConversation ??
        (provider.conversations.isNotEmpty
            ? provider.conversations.first
            : null);
    if (conversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a conversation to copy logs.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final report = provider.buildConversationDebugReport(conversation.id);
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Useful logs copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Color _serviceColor(String state) {
    switch (state) {
      case 'healthy':
        return Colors.green;
      case 'unhealthy':
        return Colors.orange;
      case 'crashed':
        return Colors.red;
      case 'starting':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _sortModeLabel(String value) {
    switch (value) {
      case 'oldest':
        return 'Oldest first';
      case 'name':
        return 'Name (A-Z)';
      case 'latest':
      default:
        return 'Latest first';
    }
  }

  Uri _publicUrlForApiBase(String apiBaseUrl, String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      path: normalizedPath,
      queryParameters: null,
      fragment: null,
    );
  }

  Future<void> _openExternalUrl(
    BuildContext context,
    Uri uri, {
    String? failureMessage,
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failureMessage ??
                'Unable to open ${uri.toString()}. Check your browser setup.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    NomadeProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete account and data?'),
            content: const Text(
              'This permanently deletes your account and associated app data that Nomade is not legally required to retain. If you have active subscriptions, cancel billing before deletion. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete account'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    try {
      await provider.deleteAccountAndData(
        confirmationCode: _accountDeletionConfirmCode,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion request completed.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        buildAppPageRoute(context, const OnboardingScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      final message = error.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Account deletion failed. Please retry.' : message,
          ),
        ),
      );
    }
  }

  void _syncWorkspaceCache(NomadeProvider provider) {
    final validWorkspaceIds = provider.workspaces
        .map((workspace) => workspace.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    _workspaceConversationCache.removeWhere(
      (workspaceId, _) => !validWorkspaceIds.contains(workspaceId),
    );
    _loadingWorkspaceIds.removeWhere(
      (workspaceId) => !validWorkspaceIds.contains(workspaceId),
    );
    _expandedWorkspaceIds.removeWhere(
      (workspaceId) => !validWorkspaceIds.contains(workspaceId),
    );

    final selectedWorkspaceId = provider.selectedWorkspace?.id;
    if (selectedWorkspaceId != null &&
        selectedWorkspaceId.isNotEmpty &&
        provider.conversationsWorkspaceId == selectedWorkspaceId) {
      _workspaceConversationCache[selectedWorkspaceId] =
          provider.sortConversationsForDisplay(provider.conversations);
    }
  }

  String _workspacePrefetchSignatureFor(NomadeProvider provider) {
    final ids = provider.workspaces
        .map((workspace) => workspace.id)
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false)
      ..sort();
    final agentId = provider.selectedAgent?.id ?? '';
    final authPart = provider.accessToken == null ? 'no-auth' : 'auth';
    return '$agentId|$authPart|${ids.join(",")}';
  }

  void _ensureWorkspacePrefetch(NomadeProvider provider) {
    final nextSignature = _workspacePrefetchSignatureFor(provider);
    if (nextSignature == _prefetchSignature) {
      return;
    }
    _prefetchSignature = nextSignature;

    if (provider.accessToken == null) {
      return;
    }
    unawaited(_prefetchWorkspaceConversations(provider));
  }

  Future<void> _prefetchWorkspaceConversations(NomadeProvider provider) async {
    final tasks = <Future<void>>[];
    for (final workspace in provider.workspaces) {
      final workspaceId = workspace.id;
      if (workspaceId.isEmpty) {
        continue;
      }
      if (provider.selectedWorkspace?.id == workspaceId) {
        continue;
      }
      if (_workspaceConversationCache.containsKey(workspaceId) ||
          _loadingWorkspaceIds.contains(workspaceId)) {
        continue;
      }
      tasks.add(
        _loadWorkspaceConversations(
          provider,
          workspaceId: workspaceId,
          notifyListeners: false,
        ),
      );
    }

    if (tasks.isEmpty) {
      return;
    }

    await Future.wait(tasks);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _loadWorkspaceConversations(
    NomadeProvider provider, {
    required String workspaceId,
    bool notifyListeners = true,
    bool forceRefresh = false,
  }) async {
    if (workspaceId.isEmpty) {
      return;
    }
    final token = provider.accessToken;
    if (token == null) {
      return;
    }
    if (_loadingWorkspaceIds.contains(workspaceId)) {
      return;
    }
    if (!forceRefresh &&
        provider.selectedWorkspace?.id != workspaceId &&
        _workspaceConversationCache.containsKey(workspaceId)) {
      return;
    }

    void markLoadingStart() {
      _loadingWorkspaceIds.add(workspaceId);
    }

    void markLoadingDone() {
      _loadingWorkspaceIds.remove(workspaceId);
    }

    if (notifyListeners && mounted) {
      setState(markLoadingStart);
    } else {
      markLoadingStart();
    }

    try {
      List<Conversation> values;
      if (provider.selectedWorkspace?.id == workspaceId) {
        values =
            List<Conversation>.from(provider.conversations, growable: false);
      } else {
        final raw = await provider.api.listConversations(
          accessToken: token,
          workspaceId: workspaceId,
        );
        values = raw
            .map((entry) => Conversation.fromJson(entry))
            .toList(growable: false);
      }

      final sorted = provider.sortConversationsForDisplay(values);
      if (!mounted) {
        _workspaceConversationCache[workspaceId] = sorted;
        markLoadingDone();
        return;
      }

      if (notifyListeners) {
        setState(() {
          _workspaceConversationCache[workspaceId] = sorted;
          markLoadingDone();
        });
      } else {
        _workspaceConversationCache[workspaceId] = sorted;
        markLoadingDone();
      }
    } catch (_) {
      if (!mounted) {
        markLoadingDone();
        return;
      }
      if (notifyListeners) {
        setState(markLoadingDone);
      } else {
        markLoadingDone();
      }
    }
  }

  List<Conversation> _workspaceConversationsForDisplay(
    NomadeProvider provider,
    Workspace workspace,
  ) {
    final workspaceId = workspace.id;
    if (workspaceId.isEmpty) {
      return const <Conversation>[];
    }

    if (provider.selectedWorkspace?.id == workspaceId) {
      if (provider.conversationsWorkspaceId == workspaceId) {
        final sorted =
            provider.sortConversationsForDisplay(provider.conversations);
        _workspaceConversationCache[workspaceId] = sorted;
        return sorted;
      }
      final cachedSelected = _workspaceConversationCache[workspaceId];
      if (cachedSelected != null) {
        return provider.sortConversationsForDisplay(cachedSelected);
      }
      return const <Conversation>[];
    }

    final cached = _workspaceConversationCache[workspaceId];
    if (cached == null) {
      return const <Conversation>[];
    }
    return provider.sortConversationsForDisplay(cached);
  }

  DateTime _workspaceActivityAt(
    NomadeProvider provider,
    Workspace workspace,
  ) {
    final conversations =
        _workspaceConversationsForDisplay(provider, workspace);
    if (conversations.isEmpty) {
      return workspace.createdAt;
    }

    var latest = workspace.createdAt;
    for (final conversation in conversations) {
      final candidate = conversation.updatedAt.isAfter(conversation.createdAt)
          ? conversation.updatedAt
          : conversation.createdAt;
      if (candidate.isAfter(latest)) {
        latest = candidate;
      }
    }
    return latest;
  }

  List<Workspace> _sortedWorkspaces(NomadeProvider provider) {
    final values = List<Workspace>.from(provider.workspaces, growable: false);
    final activityByWorkspaceId = <String, DateTime>{
      for (final workspace in values)
        workspace.id: _workspaceActivityAt(provider, workspace),
    };
    values.sort((a, b) {
      switch (provider.listSortMode) {
        case 'oldest':
          final oldestComparison = activityByWorkspaceId[a.id]!
              .compareTo(activityByWorkspaceId[b.id]!);
          if (oldestComparison != 0) {
            return oldestComparison;
          }
          break;
        case 'name':
          break;
        case 'latest':
        default:
          final latestComparison = activityByWorkspaceId[b.id]!
              .compareTo(activityByWorkspaceId[a.id]!);
          if (latestComparison != 0) {
            return latestComparison;
          }
          break;
      }

      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) {
        return byName;
      }
      return a.id.compareTo(b.id);
    });
    return values;
  }

  bool _workspaceIsRunning(
    NomadeProvider provider, {
    required String workspaceId,
    required List<Conversation> conversations,
  }) {
    if (workspaceId.isEmpty) {
      return false;
    }
    if (provider.selectedWorkspace?.id == workspaceId &&
        provider.activeTurnId != null) {
      return true;
    }
    return conversations
        .any((conversation) => conversation.status == 'running');
  }

  String _normalizeQuery(String value) {
    return value.trim().toLowerCase();
  }

  bool _workspaceMatchesQuery(Workspace workspace, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final name = workspace.name.toLowerCase();
    final path = workspace.path.toLowerCase();
    return name.contains(normalizedQuery) || path.contains(normalizedQuery);
  }

  List<Conversation> _filterConversations(
    List<Conversation> source,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) {
      return source;
    }
    return source
        .where(
          (conversation) =>
              conversation.title.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
  }

  Future<void> _onWorkspaceExpansionChanged({
    required NomadeProvider provider,
    required Workspace workspace,
    required bool expanded,
  }) async {
    HapticFeedback.selectionClick();
    if (!expanded) {
      if (!mounted) {
        return;
      }
      setState(() {
        _expandedWorkspaceIds.remove(workspace.id);
      });
      return;
    }

    if (mounted) {
      setState(() {
        _expandedWorkspaceIds
          ..clear()
          ..add(workspace.id);
      });
    }

    if (provider.selectedWorkspace?.id != workspace.id) {
      if (mounted) {
        setState(() {
          _loadingWorkspaceIds.add(workspace.id);
        });
      } else {
        _loadingWorkspaceIds.add(workspace.id);
      }
      try {
        await provider.onWorkspaceSelected(workspace);
      } finally {
        if (!mounted) {
          _loadingWorkspaceIds.remove(workspace.id);
        } else {
          setState(() {
            _loadingWorkspaceIds.remove(workspace.id);
          });
        }
      }
      return;
    }

    if (!_workspaceConversationCache.containsKey(workspace.id)) {
      await _loadWorkspaceConversations(
        provider,
        workspaceId: workspace.id,
      );
    }
  }

  Future<void> _openConversation(
    BuildContext context,
    NomadeProvider provider, {
    required Workspace workspace,
    required Conversation conversation,
  }) async {
    if (provider.selectedWorkspace?.id != workspace.id) {
      await provider.onWorkspaceSelected(workspace);
    }

    var targetConversation = conversation;
    for (final candidate in provider.conversations) {
      if (candidate.id == conversation.id) {
        targetConversation = candidate;
        break;
      }
    }

    provider.selectedConversation = targetConversation;
    await provider.loadTurns(targetConversation.id);

    if (!context.mounted) {
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _createConversationInWorkspace(
    BuildContext context,
    NomadeProvider provider, {
    required Workspace workspace,
  }) async {
    if (provider.selectedWorkspace?.id != workspace.id) {
      await provider.onWorkspaceSelected(workspace);
    }
    final created = await provider.createConversation();
    await _loadWorkspaceConversations(
      provider,
      workspaceId: workspace.id,
      forceRefresh: true,
    );
    if (created && context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    _syncWorkspaceCache(provider);
    _ensureWorkspacePrefetch(provider);

    final normalizedQuery = _normalizeQuery(_searchController.text);
    final sortedWorkspaces = _sortedWorkspaces(provider);
    final visibleWorkspaces = sortedWorkspaces.where((workspace) {
      final allConversations =
          _workspaceConversationsForDisplay(provider, workspace);
      final matchesWorkspace =
          _workspaceMatchesQuery(workspace, normalizedQuery);
      final matchingConversations =
          _filterConversations(allConversations, normalizedQuery);
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return matchesWorkspace || matchingConversations.isNotEmpty;
    }).toList(growable: false);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, provider),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search projects or conversations',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: normalizedQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                ),
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.72),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.72),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: scheme.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Sort projects and conversations',
                    initialValue: provider.listSortMode,
                    icon: const Icon(Icons.sort_rounded),
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
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  _buildSectionHeader(context, 'Projects'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      _sortModeLabel(provider.listSortMode),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (sortedWorkspaces.isEmpty &&
                      provider.selectedAgent != null)
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(Icons.add_box_outlined, size: 20),
                      title: const Text('Create default workspace'),
                      subtitle: const Text(
                        'Creates "Local workspace" at path "."',
                        style: TextStyle(fontSize: 11),
                      ),
                      onTap: () async {
                        await provider.createDefaultWorkspace();
                      },
                    ),
                  if (sortedWorkspaces.isEmpty &&
                      provider.selectedAgent == null)
                    _buildInfoLine(
                      context,
                      'Pair or select an online agent to see projects.',
                    ),
                  if (visibleWorkspaces.isEmpty &&
                      sortedWorkspaces.isNotEmpty &&
                      normalizedQuery.isNotEmpty)
                    _buildInfoLine(
                      context,
                      'No project or conversation matches your search.',
                    ),
                  ...visibleWorkspaces.asMap().entries.map((entry) {
                    final index = entry.key;
                    final workspace = entry.value;
                    final delayMs = (index * 22).clamp(0, 190).toInt();
                    return FadeSlideIn(
                      delay: Duration(milliseconds: delayMs),
                      beginOffset: const Offset(0, 0.015),
                      child: _buildWorkspaceNode(
                        context,
                        provider,
                        workspace: workspace,
                        normalizedQuery: normalizedQuery,
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  _buildToolsSection(context, provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final workspaceLabel =
        provider.selectedWorkspace?.name ?? 'No project open';
    final agentLabel = provider.selectedAgent?.displayName ?? 'No agent';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.standardCurve,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: scheme.surfaceContainerLow,
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nomade for Codex',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$agentLabel • $workspaceLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (provider.loadingData)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceNode(
    BuildContext context,
    NomadeProvider provider, {
    required Workspace workspace,
    required String normalizedQuery,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final workspaceConversations =
        _workspaceConversationsForDisplay(provider, workspace);
    final matchingConversations =
        _filterConversations(workspaceConversations, normalizedQuery);
    final selectedWorkspace = provider.selectedWorkspace?.id == workspace.id;
    final hasConversationQueryMatch =
        normalizedQuery.isNotEmpty && matchingConversations.isNotEmpty;
    final expanded = _expandedWorkspaceIds.contains(workspace.id) ||
        selectedWorkspace ||
        hasConversationQueryMatch;
    final workspaceIsRunning = _workspaceIsRunning(
      provider,
      workspaceId: workspace.id,
      conversations: workspaceConversations,
    );
    final loading = _loadingWorkspaceIds.contains(workspace.id);
    final visibleConversations = normalizedQuery.isEmpty
        ? workspaceConversations
        : matchingConversations;

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standardCurve,
      key: ValueKey('workspace-node-${workspace.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selectedWorkspace
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selectedWorkspace
              ? scheme.primary.withValues(alpha: 0.34)
              : scheme.outlineVariant.withValues(alpha: 0.62),
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
          visualDensity: VisualDensity.compact,
          onExpansionChanged: (value) {
            unawaited(
              _onWorkspaceExpansionChanged(
                provider: provider,
                workspace: workspace,
                expanded: value,
              ),
            );
          },
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
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: PulseDot(color: scheme.primary, size: 7),
                    ),
                  ),
                ),
            ],
          ),
          subtitle: AnimatedSwitcher(
            duration: AppMotion.medium,
            child: Text(
              loading
                  ? 'Loading conversations...'
                  : '${workspaceConversations.length} conversation${workspaceConversations.length > 1 ? "s" : ""}',
              key: ValueKey(
                '${workspace.id}-${loading ? "loading" : workspaceConversations.length}',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await _createConversationInWorkspace(
                    context,
                    provider,
                    workspace: workspace,
                  );
                },
                icon: const Icon(Icons.add_comment_outlined, size: 16),
                label: const Text('New conversation'),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (!loading && visibleConversations.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: Text(
                  normalizedQuery.isEmpty
                      ? 'No conversations yet in this project.'
                      : 'No matching conversations.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!loading)
              ...visibleConversations.asMap().entries.map((entry) {
                final index = entry.key;
                final conversation = entry.value;
                final delayMs = (index * 16).clamp(0, 140).toInt();
                return FadeSlideIn(
                  delay: Duration(milliseconds: delayMs),
                  beginOffset: const Offset(0, 0.01),
                  child: _buildConversationNode(
                    context,
                    provider,
                    workspace: workspace,
                    conversation: conversation,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationNode(
    BuildContext context,
    NomadeProvider provider, {
    required Workspace workspace,
    required Conversation conversation,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = provider.selectedConversation?.id == conversation.id;
    final isRunning = conversation.status == 'running' ||
        (provider.activeTurnId != null && selected);

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
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Icon(
          isRunning ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline,
          size: 17,
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
          await _openConversation(
            context,
            provider,
            workspace: workspace,
            conversation: conversation,
          );
        },
      ),
    );
  }

  Widget _buildToolsSection(BuildContext context, NomadeProvider provider) {
    final theme = Theme.of(context);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      leading: const Icon(Icons.tune_rounded, size: 20),
      title: const Text('Tools & account'),
      subtitle: Text(
        'Collapsed by default to save space',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        _buildSectionHeader(context, 'Agents'),
        if (provider.agents.isEmpty)
          _buildInfoLine(
            context,
            'No paired agent found for this account.',
          ),
        ...provider.agents.map(
          (agent) => ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(
              Icons.circle,
              size: 11,
              color: agent.isOnline ? Colors.green : Colors.grey,
            ),
            title: Text(agent.displayName),
            selected: provider.selectedAgent?.id == agent.id,
            onTap: () async {
              await provider.onAgentSelected(agent);
            },
          ),
        ),
        const SizedBox(height: 6),
        _buildSectionHeader(context, 'Services'),
        if (provider.selectedWorkspace == null)
          _buildInfoLine(context, 'Select a project to manage services.')
        else ...[
          ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.settings_ethernet, size: 20),
            title: const Text('Manage tunnels'),
            subtitle: const Text(
              'Create, open, rotate, or close',
              style: TextStyle(fontSize: 11),
            ),
            onTap: () {
              final rootContext =
                  Navigator.of(context, rootNavigator: true).context;
              Navigator.of(context).pop();
              showTunnelManagerSheet(rootContext);
            },
          ),
          SwitchListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            title: const Text('Trusted dev mode'),
            subtitle: const Text(
              'Disable token requirement for local previews',
              style: TextStyle(fontSize: 11),
            ),
            value: provider.trustedDevMode,
            onChanged: (value) async {
              if (value && !provider.trustedDevMode) {
                final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Enable trusted dev mode?'),
                        content: const Text(
                          'Tunnel URLs in this workspace become accessible without token. Use only on trusted networks/devices.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Enable'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (!confirmed) {
                  return;
                }
              }
              await provider.setTrustedDevMode(value);
            },
          ),
          if (provider.loadingServices)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: LinearProgressIndicator(),
            ),
          if (!provider.loadingServices && provider.services.isEmpty)
            _buildInfoLine(context, 'No services configured yet.'),
          ...provider.services.map(
            (service) => ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                Icons.circle,
                size: 11,
                color: _serviceColor(service.state),
              ),
              title: Text(service.name),
              subtitle: Text(
                service.dependsOn.isEmpty
                    ? '${service.state} • :${service.port}'
                    : '${service.state} • :${service.port} • deps: ${service.dependsOn.join(', ')}',
                style: const TextStyle(fontSize: 11),
              ),
              selected: provider.selectedServiceId == service.id,
              onTap: () {
                provider.selectService(service.id);
              },
              trailing: IconButton(
                iconSize: 20,
                icon: Icon(
                  service.state == 'healthy' ||
                          service.state == 'starting' ||
                          service.runtimeStatus == 'running'
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                onPressed: () async {
                  if (service.state == 'healthy' ||
                      service.state == 'starting' ||
                      service.runtimeStatus == 'running') {
                    await provider.stopService(service.id);
                  } else {
                    await provider.startService(service.id);
                  }
                },
              ),
            ),
          ),
          if (provider.loadingTunnels)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: LinearProgressIndicator(),
            ),
          if (!provider.loadingTunnels && provider.tunnels.isEmpty)
            _buildInfoLine(context, 'No active tunnel for this workspace.'),
          ...provider.tunnels.map(
            (tunnel) => ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                tunnel.isReachable
                    ? Icons.wifi_tethering
                    : Icons.wifi_tethering_off,
                size: 18,
                color: tunnel.isReachable ? Colors.green : Colors.grey,
              ),
              title: Text('${tunnel.slug} (:${tunnel.targetPort})'),
              subtitle: Text(
                '${tunnel.status} • ${tunnel.tokenRequired ? 'Protected' : 'Trusted'}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'open') {
                    final link = await provider.issueTunnelLink(tunnel.id);
                    if (link == null) {
                      return;
                    }
                    await launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    );
                    return;
                  }

                  if (value == 'rotate') {
                    final link = await provider.rotateTunnelLink(tunnel.id);
                    if (link == null) {
                      return;
                    }
                    await launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    );
                    return;
                  }

                  if (value == 'copy') {
                    final link = tunnel.tokenRequired
                        ? await provider.issueTunnelLink(tunnel.id)
                        : tunnel.previewUrl;
                    if (link == null || link.trim().isEmpty) {
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: link));
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tunnel URL copied'),
                      ),
                    );
                    return;
                  }

                  if (value == 'close') {
                    await provider.closeTunnel(tunnel.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'open',
                    child: Text('Open preview'),
                  ),
                  PopupMenuItem(
                    value: 'rotate',
                    child: Text('Rotate token'),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy URL'),
                  ),
                  PopupMenuItem(
                    value: 'close',
                    child: Text('Close tunnel'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        _buildSectionHeader(context, 'Legal & privacy'),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          onTap: () async {
            await _openExternalUrl(
              context,
              _publicUrlForApiBase(provider.api.baseUrl, '/legal/privacy'),
              failureMessage: 'Unable to open privacy policy.',
            );
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Terms of service'),
          onTap: () async {
            await _openExternalUrl(
              context,
              _publicUrlForApiBase(provider.api.baseUrl, '/legal/terms'),
              failureMessage: 'Unable to open terms of service.',
            );
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.language_rounded),
          title: const Text('Account deletion (web)'),
          subtitle: const Text(
            'Outside-app deletion link for store policies',
            style: TextStyle(fontSize: 11),
          ),
          onTap: () async {
            await _openExternalUrl(
              context,
              _publicUrlForApiBase(
                provider.api.baseUrl,
                '/legal/account-deletion',
              ),
              failureMessage: 'Unable to open account deletion page.',
            );
          },
        ),
        const SizedBox(height: 6),
        _buildSectionHeader(context, 'Session'),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Icon(
            Icons.delete_forever_outlined,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Delete account & data',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text(
            'Permanently remove account data',
            style: TextStyle(fontSize: 11),
          ),
          onTap: () async {
            await _confirmDeleteAccount(context, provider);
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Guide E2E dev'),
          onTap: () async {
            await showE2eGuideSheet(context);
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.copy_all_rounded),
          title: const Text('Copy useful logs'),
          onTap: () async {
            await _copyUsefulLogs(context, provider);
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.refresh_rounded),
          title: const Text('Refresh data'),
          onTap: () async {
            HapticFeedback.selectionClick();
            await provider.refreshAll();
          },
        ),
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Icon(
            Icons.logout_rounded,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Logout',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          onTap: () async {
            await provider.logout();
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pushAndRemoveUntil(
              buildAppPageRoute(context, const OnboardingScreen()),
              (route) => false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
      ),
    );
  }

  Widget _buildInfoLine(BuildContext context, String text) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }
}
