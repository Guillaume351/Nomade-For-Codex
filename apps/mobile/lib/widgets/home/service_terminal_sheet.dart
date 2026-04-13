import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/nomade_provider.dart';

class ServiceTerminalSheet extends StatefulWidget {
  const ServiceTerminalSheet({super.key});

  @override
  State<ServiceTerminalSheet> createState() => _ServiceTerminalSheetState();
}

class _ServiceTerminalSheetState extends State<ServiceTerminalSheet> {
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
