import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/dev_service.dart';
import '../models/tunnel.dart';
import '../models/workspace.dart';
import '../providers/nomade_provider.dart';

void showTunnelManagerSheet(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) {
      return;
    }
    showDialog<void>(
      context: navigator.context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) => const _TunnelManagerDialog(),
    );
  });
}

class _TunnelManagerDialog extends StatefulWidget {
  const _TunnelManagerDialog();

  @override
  State<_TunnelManagerDialog> createState() => _TunnelManagerDialogState();
}

class _TunnelManagerDialogState extends State<_TunnelManagerDialog> {
  final _portController = TextEditingController();
  bool _creatingCustomTunnel = false;
  bool _didInitialRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialRefresh) {
      return;
    }
    _didInitialRefresh = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final provider = context.read<NomadeProvider>();
      if (provider.selectedWorkspace != null) {
        await provider.loadServices();
        await provider.loadTunnels();
      }
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final workspace = provider.selectedWorkspace;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 980,
          minWidth: 720,
          maxHeight: 760,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, provider, theme, scheme, workspace),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                children: [
                  if (workspace == null)
                    _buildWorkspacePicker(provider, theme, scheme)
                  else ...[
                    _buildHowToCreate(theme, scheme),
                    const SizedBox(height: 10),
                    _buildActiveDiagnosticBanner(provider, theme, scheme),
                    const SizedBox(height: 12),
                    _buildQuickCreate(provider, theme, scheme),
                    const SizedBox(height: 14),
                    _buildCreateFromServices(provider, theme, scheme),
                    const SizedBox(height: 14),
                    _buildManualCreate(provider, theme, scheme),
                    const SizedBox(height: 16),
                    _buildExistingTunnels(provider, theme, scheme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
    Workspace? workspace,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tunnel management',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  workspace == null
                      ? 'Select a workspace to create/open/rotate tunnels'
                      : '${workspace.name} • ${workspace.path}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh tunnels',
            onPressed: workspace == null
                ? null
                : () async {
                    await provider.loadServices();
                    await provider.loadTunnels();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspacePicker(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No workspace selected',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (provider.workspaces.isEmpty)
            Text(
              'No workspace available. Open the workspace panel to import or create one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              'Choose a workspace:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.workspaces.map((workspace) {
                return OutlinedButton.icon(
                  onPressed: () async {
                    await provider.onWorkspaceSelected(workspace);
                    await provider.loadServices();
                    await provider.loadTunnels();
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text(workspace.name),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateFromServices(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'From services',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (provider.services.isEmpty)
            Text(
              'No services configured in this workspace yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            ...provider.services.map(
              (service) => _buildServiceRow(
                provider: provider,
                service: service,
                theme: theme,
                scheme: scheme,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHowToCreate(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to create a tunnel',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '1) Start a local service (for example :3000).\n'
            '2) Click "Create tunnel" from the service row, or use a quick/manual port below.\n'
            '3) Open the generated preview URL.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDiagnosticBanner(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final active = provider.tunnels
        .where((tunnel) => tunnel.diagnostic != null)
        .toList(growable: false);
    if (active.isEmpty) {
      return const SizedBox.shrink();
    }

    active.sort((left, right) {
      final leftScope = left.diagnostic?.scope == 'transport' ? 0 : 1;
      final rightScope = right.diagnostic?.scope == 'transport' ? 0 : 1;
      return leftScope.compareTo(rightScope);
    });

    final tunnel = active.first;
    final diagnostic = tunnel.diagnostic!;
    final isTransport = diagnostic.scope == 'transport';
    final icon = isTransport ? Icons.warning_amber_rounded : Icons.bug_report;
    final title = isTransport
        ? 'Tunnel transport issue detected'
        : 'Proxied app runtime issue detected';
    final helper = isTransport
        ? 'The tunnel transport failed. Check gateway/control-api/agent logs.'
        : 'The tunnel is reachable but the proxied app is failing at runtime.';
    final borderColor = isTransport
        ? scheme.error.withValues(alpha: 0.4)
        : scheme.tertiary.withValues(alpha: 0.4);
    final bgColor = isTransport
        ? scheme.errorContainer.withValues(alpha: 0.3)
        : scheme.tertiaryContainer.withValues(alpha: 0.3);

    final workspacePath = provider.selectedWorkspace?.path ?? '.';
    final backendLogsCommand =
        'cd "$workspacePath" && npm run dev:logs -- control-api tunnel-gateway';
    final agentLogsCommand =
        'cd "$workspacePath" && tail -f .nomade-dev/agent.log';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${diagnostic.code}: ${diagnostic.message}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _openTunnel(provider, tunnel),
                child: const Text('Open URL'),
              ),
              OutlinedButton(
                onPressed: () => _copyTunnelUrl(provider, tunnel),
                child: const Text('Copy URL'),
              ),
              OutlinedButton(
                onPressed: () => _copyRawText(
                  backendLogsCommand,
                  feedback: 'Backend logs command copied',
                ),
                child: const Text('Copy backend logs cmd'),
              ),
              OutlinedButton(
                onPressed: () => _copyRawText(
                  agentLogsCommand,
                  feedback: 'Agent logs command copied',
                ),
                child: const Text('Copy agent logs cmd'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCreate(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    const quickPorts = <int>[3000, 5173, 8080, 4200];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick create',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quickPorts
                .map(
                  (port) => OutlinedButton.icon(
                    onPressed: () => provider.createTunnel(targetPort: port),
                    icon: const Icon(Icons.add_link_rounded, size: 16),
                    label: Text('Create :$port'),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceRow({
    required NomadeProvider provider,
    required DevService service,
    required ThemeData theme,
    required ColorScheme scheme,
  }) {
    final serviceTunnel = _findTunnelForService(provider, service.id);
    final serviceIsRunning = service.runtimeStatus == 'running' ||
        service.state == 'healthy' ||
        service.state == 'starting';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${service.name} (:${service.port})',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'state=${service.state} • runtime=${service.runtimeStatus}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (serviceTunnel == null)
                OutlinedButton.icon(
                  onPressed: () async {
                    await provider.createTunnel(
                      targetPort: service.port,
                      serviceId: service.id,
                    );
                  },
                  icon: const Icon(Icons.add_link_rounded, size: 16),
                  label: const Text('Create tunnel'),
                )
              else ...[
                OutlinedButton(
                  onPressed: () => _openTunnel(provider, serviceTunnel),
                  child: const Text('Open'),
                ),
                OutlinedButton(
                  onPressed: () => _copyTunnelUrl(provider, serviceTunnel),
                  child: const Text('Copy URL'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await provider.closeTunnel(serviceTunnel.id);
                    await provider.loadTunnels();
                  },
                  child: const Text('Close'),
                ),
              ],
              if (!serviceIsRunning)
                OutlinedButton(
                  onPressed: () async {
                    await provider.startService(service.id);
                    await provider.loadTunnels();
                  },
                  child: const Text('Start service'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualCreate(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manual port',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target port',
                    hintText: '3000',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 46),
                    maximumSize: const Size(112, 46),
                    fixedSize: const Size(112, 46),
                  ),
                  onPressed: _creatingCustomTunnel
                      ? null
                      : () => _createManualTunnel(provider),
                  child: _creatingCustomTunnel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExistingTunnels(
    NomadeProvider provider,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Existing tunnels',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (provider.loadingTunnels) const LinearProgressIndicator(),
          if (!provider.loadingTunnels && provider.tunnels.isEmpty)
            Text(
              'No active tunnel for this workspace.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (provider.tunnels.isNotEmpty)
            ...provider.tunnels.map(
              (tunnel) => _buildTunnelRow(
                provider: provider,
                tunnel: tunnel,
                theme: theme,
                scheme: scheme,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTunnelRow({
    required NomadeProvider provider,
    required TunnelPreview tunnel,
    required ThemeData theme,
    required ColorScheme scheme,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${tunnel.slug} (:${tunnel.targetPort})',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${tunnel.status} • ${tunnel.tokenRequired ? "protected" : "trusted"}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          if (tunnel.diagnostic != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: tunnel.diagnostic!.scope == 'transport'
                    ? scheme.errorContainer.withValues(alpha: 0.35)
                    : scheme.tertiaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${tunnel.diagnostic!.code}: ${tunnel.diagnostic!.message}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _openTunnel(provider, tunnel),
                child: const Text('Open'),
              ),
              OutlinedButton(
                onPressed: () => _copyTunnelUrl(provider, tunnel),
                child: const Text('Copy URL'),
              ),
              OutlinedButton(
                onPressed: () => _rotateAndOpenTunnel(provider, tunnel),
                child: const Text('Rotate token'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await provider.closeTunnel(tunnel.id);
                  await provider.loadTunnels();
                },
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TunnelPreview? _findTunnelForService(
      NomadeProvider provider, String serviceId) {
    for (final tunnel in provider.tunnels) {
      if (tunnel.serviceId == serviceId) {
        return tunnel;
      }
    }
    return null;
  }

  Future<void> _createManualTunnel(NomadeProvider provider) async {
    final parsedPort = int.tryParse(_portController.text.trim());
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      return;
    }
    setState(() {
      _creatingCustomTunnel = true;
    });
    try {
      final created = await provider.createTunnel(targetPort: parsedPort);
      if (created) {
        _portController.clear();
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingCustomTunnel = false;
        });
      }
    }
  }

  Future<void> _openTunnel(
      NomadeProvider provider, TunnelPreview tunnel) async {
    final url = await _resolveTunnelUrl(provider, tunnel);
    if (url == null || url.trim().isEmpty) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _rotateAndOpenTunnel(
    NomadeProvider provider,
    TunnelPreview tunnel,
  ) async {
    final url = await _resolveTunnelUrl(
      provider,
      tunnel,
      rotate: true,
    );
    if (url == null || url.trim().isEmpty) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyTunnelUrl(
    NomadeProvider provider,
    TunnelPreview tunnel, {
    bool rotate = false,
  }) async {
    final url = await _resolveTunnelUrl(provider, tunnel, rotate: rotate);
    if (url == null || url.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _showSnackBar('Tunnel URL copied');
  }

  Future<void> _copyRawText(
    String value, {
    required String feedback,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnackBar(feedback);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<String?> _resolveTunnelUrl(
    NomadeProvider provider,
    TunnelPreview tunnel, {
    bool rotate = false,
  }) async {
    if (rotate) {
      return provider.rotateTunnelLink(tunnel.id);
    }
    if (tunnel.tokenRequired) {
      return provider.issueTunnelLink(tunnel.id);
    }
    return tunnel.previewUrl;
  }
}
