import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/nomade_provider.dart';
import '../screens/onboarding_screen.dart';
import 'e2e_guide_sheet.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();

    return Drawer(
      child: Column(
        children: [
          _buildHeader(context, provider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                provider.status,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSectionHeader('Agents'),
                if (provider.agents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No paired agent found for this account.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...provider.agents.map((agent) => ListTile(
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
                    )),
                const Divider(),
                _buildSectionHeader('Workspaces'),
                if (provider.selectedAgent != null &&
                    provider.selectedAgent!.isOnline)
                  ListTile(
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
                if (provider.workspaces.isEmpty &&
                    provider.selectedAgent != null)
                  ListTile(
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
                ...provider.workspaces.map((workspace) => ListTile(
                      leading: const Icon(Icons.folder_open_outlined, size: 20),
                      title: Text(workspace.name),
                      subtitle: Text(workspace.path,
                          style: const TextStyle(fontSize: 10)),
                      selected: provider.selectedWorkspace?.id == workspace.id,
                      onTap: () async {
                        await provider.onWorkspaceSelected(workspace);
                      },
                    )),
                const Divider(),
                _buildSectionHeader('Conversations'),
                if (provider.selectedWorkspace != null)
                  ListTile(
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
                    provider.conversations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No conversations yet. Import history or create one.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...provider.conversations.map((conv) => ListTile(
                      leading: const Icon(Icons.chat_outlined, size: 20),
                      title: Text(conv.title),
                      selected: provider.selectedConversation?.id == conv.id,
                      onTap: () {
                        provider.selectedConversation = conv;
                        provider.loadTurns(conv.id);
                        Navigator.pop(context); // Close drawer
                      },
                    )),
                const Divider(),
                _buildSectionHeader('Dev Services'),
                if (provider.selectedWorkspace != null)
                  SwitchListTile(
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
                                title: const Text('Enable trusted dev mode?'),
                                content: const Text(
                                  'Tunnel URLs in this workspace will become accessible without token. Use only on trusted networks/devices.',
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
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (provider.selectedWorkspace != null &&
                    provider.services.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No services configured yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...provider.services.map((service) => ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: _serviceColor(service.state),
                      ),
                      title: Text(service.name),
                      subtitle: Text(
                        service.dependsOn.isEmpty
                            ? '${service.state} • :${service.port}'
                            : '${service.state} • :${service.port} • deps: ${service.dependsOn.join(", ")}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: provider.selectedServiceId == service.id,
                      onTap: () {
                        provider.selectService(service.id);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
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
                        ],
                      ),
                    )),
                const Divider(),
                _buildSectionHeader('Tunnels'),
                if (provider.loadingTunnels)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (provider.selectedWorkspace != null &&
                    provider.tunnels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No active tunnel for this workspace.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...provider.tunnels.map((tunnel) => ListTile(
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
                            final link =
                                await provider.issueTunnelLink(tunnel.id);
                            if (link == null) return;
                            await launchUrl(Uri.parse(link),
                                mode: LaunchMode.externalApplication);
                            return;
                          }
                          if (value == 'rotate') {
                            final link =
                                await provider.rotateTunnelLink(tunnel.id);
                            if (link == null) return;
                            await launchUrl(Uri.parse(link),
                                mode: LaunchMode.externalApplication);
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
                            value: 'close',
                            child: Text('Close tunnel'),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          _buildFooter(context, provider),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NomadeProvider provider) {
    return DrawerHeader(
      decoration: BoxDecoration(color: Theme.of(context).primaryColor),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nomade',
            style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'for Codex',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, NomadeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey, width: 0.2)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Guide E2E dev'),
            onTap: () async {
              await showE2eGuideSheet(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Refresh data'),
            onTap: () async {
              await provider.refreshAll();
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
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
