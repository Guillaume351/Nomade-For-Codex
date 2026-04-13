import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/nomade_provider.dart';
import '../screens/onboarding_screen.dart';
import 'e2e_guide_sheet.dart';
import 'tunnel_manager_sheet.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

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
          content: Text('Sélectionne une conversation pour copier les logs.'),
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
        content: Text('Logs utiles copiés'),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final sortedWorkspaces =
        provider.sortWorkspacesForDisplay(provider.workspaces);
    final sortedConversations =
        provider.sortConversationsForDisplay(provider.conversations);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: _buildStatusCard(context, provider.status),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.tune_rounded, size: 20),
                    title: const Text('Sort lists'),
                    subtitle: Text(_sortModeLabel(provider.listSortMode)),
                    trailing: PopupMenuButton<String>(
                      initialValue: provider.listSortMode,
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
                  ),
                  const SizedBox(height: 8),
                  _buildSectionHeader(context, 'Agents'),
                  if (provider.agents.isEmpty)
                    _buildInfoLine(
                      context,
                      'No paired agent found for this account.',
                    ),
                  ...provider.agents.map(
                    (agent) => ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: agent.isOnline ? Colors.green : Colors.grey,
                      ),
                      title: Text(agent.displayName),
                      selected: provider.selectedAgent?.id == agent.id,
                      onTap: () async {
                        await provider.onAgentSelected(agent);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSectionHeader(context, 'Workspaces'),
                  if (provider.selectedAgent != null &&
                      provider.selectedAgent!.isOnline)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: provider.importingHistory
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 20),
                      title: const Text('Import Codex history'),
                      enabled: !provider.importingHistory,
                      onTap: provider.importingHistory
                          ? null
                          : () async {
                              await provider.importCodexHistory();
                            },
                    ),
                  if (sortedWorkspaces.isEmpty &&
                      provider.selectedAgent != null)
                    ListTile(
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
                  ...sortedWorkspaces.map(
                    (workspace) => ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(Icons.folder_open_outlined, size: 20),
                      title: Text(workspace.name),
                      subtitle: Text(workspace.path,
                          style: const TextStyle(fontSize: 10)),
                      selected: provider.selectedWorkspace?.id == workspace.id,
                      onTap: () async {
                        await provider.onWorkspaceSelected(workspace);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSectionHeader(context, 'Conversations'),
                  if (provider.selectedWorkspace != null)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(Icons.add_comment_outlined, size: 20),
                      title: const Text('New conversation'),
                      onTap: () async {
                        final created = await provider.createConversation();
                        if (created && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  if (provider.selectedWorkspace != null &&
                      sortedConversations.isEmpty)
                    _buildInfoLine(
                      context,
                      'No conversations yet. Import history or create one.',
                    ),
                  ...sortedConversations.map(
                    (conv) => ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(Icons.chat_outlined, size: 20),
                      title: Text(conv.title),
                      selected: provider.selectedConversation?.id == conv.id,
                      onTap: () {
                        provider.selectedConversation = conv;
                        provider.loadTurns(conv.id);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    leading: const Icon(Icons.developer_mode_rounded, size: 20),
                    title: const Text('Services & tunnels'),
                    subtitle: const Text(
                      'Advanced tools',
                      style: TextStyle(fontSize: 11),
                    ),
                    children: [
                      _buildSectionHeader(context, 'Dev Services'),
                      if (provider.selectedWorkspace != null)
                        SwitchListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          title: const Text('Trusted dev mode'),
                          subtitle: const Text(
                            'Disable token requirement for local dev previews',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: provider.trustedDevMode,
                          onChanged: (value) async {
                            if (value && !provider.trustedDevMode) {
                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text(
                                          'Enable trusted dev mode?'),
                                      content: const Text(
                                        'Tunnel URLs in this workspace will become accessible without token. Use only on trusted networks/devices.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(true),
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
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: LinearProgressIndicator(),
                        ),
                      if (provider.selectedWorkspace != null &&
                          provider.services.isEmpty)
                        _buildInfoLine(context, 'No services configured yet.'),
                      ...provider.services.map(
                        (service) => ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(
                            Icons.circle,
                            size: 12,
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
                      const SizedBox(height: 8),
                      _buildSectionHeader(context, 'Tunnels'),
                      if (provider.selectedWorkspace != null)
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading:
                              const Icon(Icons.settings_ethernet, size: 20),
                          title: const Text('Manage tunnels'),
                          subtitle: const Text(
                            'Create, open, rotate, or close',
                            style: TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            final rootContext =
                                Navigator.of(context, rootNavigator: true)
                                    .context;
                            Navigator.of(context).pop();
                            showTunnelManagerSheet(rootContext);
                          },
                        ),
                      if (provider.loadingTunnels)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: LinearProgressIndicator(),
                        ),
                      if (provider.selectedWorkspace != null &&
                          provider.tunnels.isEmpty)
                        _buildInfoLine(
                            context, 'No active tunnel for this workspace.'),
                      ...provider.tunnels.map(
                        (tunnel) => ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(
                            tunnel.isReachable
                                ? Icons.wifi_tethering
                                : Icons.wifi_tethering_off,
                            size: 18,
                            color:
                                tunnel.isReachable ? Colors.green : Colors.grey,
                          ),
                          title: Text('${tunnel.slug} (:${tunnel.targetPort})'),
                          subtitle: Text(
                            '${tunnel.status} • ${tunnel.tokenRequired ? 'Protected' : 'Trusted'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'open') {
                                final link =
                                    await provider.issueTunnelLink(tunnel.id);
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
                                final link =
                                    await provider.rotateTunnelLink(tunnel.id);
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
                                await Clipboard.setData(
                                    ClipboardData(text: link));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Tunnel URL copied'),
                                    ),
                                  );
                                }
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
                  ),
                ],
              ),
            ),
            _buildFooter(context, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              scheme.tertiary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nomade',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'for Codex',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.86),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, String status) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_rounded, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildFooter(BuildContext context, NomadeProvider provider) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        children: [
          ListTile(
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.copy_all_rounded),
            title: const Text('Copier logs utiles'),
            onTap: () async {
              await _copyUsefulLogs(context, provider);
            },
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Refresh data'),
            onTap: () async {
              await provider.refreshAll();
            },
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
            title: Text(
              'Logout',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () async {
              await provider.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
