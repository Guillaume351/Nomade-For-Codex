import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/turn.dart';
import '../models/turn_item.dart';
import '../models/turn_timeline.dart';
import '../providers/nomade_provider.dart';

class ChatTurnWidget extends StatelessWidget {
  const ChatTurnWidget({super.key, required this.turn});

  final Turn turn;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final timeline = provider.tryTimelineForTurn(turn.id);
    final markdown = _getMarkdown(timeline);
    final isUser = turn.userPrompt.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isUser) _buildUserBubble(context, turn.userPrompt),
        _buildAssistantBubble(context, markdown, timeline),
      ],
    );
  }

  String _getMarkdown(TurnTimeline? timeline) {
    if (timeline != null) {
      final fromTimeline = _markdownFromTimeline(timeline);
      if (fromTimeline.trim().isNotEmpty) {
        return fromTimeline;
      }
    }

    final isTerminal = turn.status == 'completed' ||
        turn.status == 'failed' ||
        turn.status == 'interrupted';
    if (isTerminal && turn.items.isNotEmpty) {
      final persisted = _markdownFromPersistedItems(turn.items);
      if (persisted.trim().isNotEmpty) {
        return persisted;
      }
    }

    if (turn.status == 'failed') {
      final error = turn.error?.trim();
      if (error != null && error.isNotEmpty) {
        return 'Request failed: `$error`';
      }
    }
    return '';
  }

  String _markdownFromTimeline(TurnTimeline timeline) {
    final chunks = <String>[];
    for (final item in timeline.items) {
      if (!item.isAgentMessage) {
        continue;
      }
      final timelineText = item.textDelta.trim();
      if (timelineText.isNotEmpty) {
        chunks.add(timelineText);
        continue;
      }
      final payloadText = _extractTextFromPayload(item.payload).trim();
      if (payloadText.isNotEmpty) {
        chunks.add(payloadText);
      }
    }
    return chunks.join('\n\n');
  }

  String _markdownFromPersistedItems(List<TurnItem> items) {
    final chunks = <String>[];
    for (final item in items) {
      if (item.itemType == 'agentMessage') {
        final extracted = _extractTextFromPayload(item.payload).trim();
        if (extracted.isNotEmpty) {
          chunks.add(extracted);
        }
        continue;
      }
      if (item.itemType == 'plan') {
        final text = item.payload['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          chunks.add('Plan:\n$text');
        }
        continue;
      }
      if (item.itemType == 'reasoning') {
        final reasoning = _extractReasoningSummary(item.payload);
        if (reasoning.isNotEmpty) {
          chunks.add('Reasoning:\n$reasoning');
        }
      }
    }
    return chunks.join('\n\n');
  }

  String _extractReasoningSummary(Map<String, dynamic> payload) {
    final summary = payload['summary'];
    if (summary is List) {
      final lines = <String>[];
      for (final entry in summary) {
        if (entry is String && entry.trim().isNotEmpty) {
          lines.add(entry.trim());
          continue;
        }
        if (entry is Map) {
          final text = entry['text'];
          if (text is String && text.trim().isNotEmpty) {
            lines.add(text.trim());
          }
        }
      }
      if (lines.isNotEmpty) {
        return lines.join('\n');
      }
    }
    return '';
  }

  String _extractTextFromPayload(Map<String, dynamic> payload) {
    final nested = payload['payload'];
    if (nested is Map) {
      final nestedText =
          _extractTextFromPayload(nested.cast<String, dynamic>());
      if (nestedText.trim().isNotEmpty) {
        return nestedText;
      }
    }

    final directText = payload['text'];
    if (directText is String && directText.trim().isNotEmpty) {
      return directText.trim();
    }

    final content = payload['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }

    if (content is List) {
      final parts = <String>[];
      for (final entry in content) {
        if (entry is String && entry.trim().isNotEmpty) {
          parts.add(entry.trim());
          continue;
        }
        if (entry is Map) {
          final text = entry['text'];
          if (text is String && text.trim().isNotEmpty) {
            parts.add(text.trim());
            continue;
          }
          final nestedContent = entry['content'];
          if (nestedContent is String && nestedContent.trim().isNotEmpty) {
            parts.add(nestedContent.trim());
          }
        }
      }
      if (parts.isNotEmpty) {
        return parts.join('\n');
      }
    }

    return '';
  }

  Widget _buildUserBubble(BuildContext context, String text) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, left: 42),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                scheme.tertiary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(
      BuildContext context, String markdown, TurnTimeline? timeline) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasMarkdown = markdown.trim().isNotEmpty;
    final hasError = turn.error != null && turn.error!.trim().isNotEmpty;
    final commandItems = timeline?.commandItems ?? const <TurnTimelineItem>[];
    final eventItems = timeline == null
        ? const <TurnTimelineItem>[]
        : timeline.items
            .where((item) => !item.isAgentMessage && !item.isCommandExecution)
            .toList(growable: false);
    final shouldCollapseExecution = timeline?.executionCollapsed ??
        (turn.status == 'completed' ||
            turn.status == 'failed' ||
            turn.status == 'interrupted');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Container(
        margin: const EdgeInsets.only(bottom: 18, right: 42),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTurnStatusChip(context, turn.status),
            const SizedBox(height: 10),
            if (hasMarkdown)
              MarkdownBody(
                data: markdown,
                selectable: true,
                onTapLink: (_, href, __) async {
                  if (href == null) {
                    return;
                  }
                  final uri = Uri.tryParse(href);
                  if (uri == null) {
                    return;
                  }
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                },
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  blockSpacing: 12,
                  code: TextStyle(
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.8),
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF0F131A)
                        : const Color(0xFF171C24),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  codeblockPadding: const EdgeInsets.all(12),
                  codeblockAlign: WrapAlignment.start,
                  blockquoteDecoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                        left: BorderSide(color: scheme.primary, width: 3)),
                  ),
                  blockquotePadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              )
            else
              Text(
                turn.status == 'running'
                    ? 'Codex is thinking...'
                    : hasError
                        ? 'No assistant message was produced.'
                        : 'No assistant message.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (eventItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...eventItems.map((item) => _buildLiveEventCard(context, item)),
            ],
            if (hasError) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
                ),
                child: Text(
                  'Error: ${turn.error}',
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
            if (commandItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildExecutionPanel(
                context,
                commandItems: commandItems,
                collapsed: shouldCollapseExecution,
              ),
            ],
            if (turn.status == 'completed' || turn.status == 'failed') ...[
              const Divider(height: 28),
              _buildMetrics(context, turn, markdown),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTurnStatusChip(BuildContext context, String status) {
    final theme = Theme.of(context);
    final (icon, color) = _statusVisuals(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _statusVisuals(String status) {
    switch (status) {
      case 'running':
        return (Icons.autorenew_rounded, Colors.blue);
      case 'completed':
        return (Icons.check_circle_outline_rounded, Colors.green);
      case 'failed':
        return (Icons.error_outline_rounded, Colors.red);
      case 'interrupted':
        return (Icons.pause_circle_outline_rounded, Colors.orange);
      default:
        return (Icons.circle_outlined, Colors.grey);
    }
  }

  Widget _buildLiveEventCard(BuildContext context, TurnTimelineItem item) {
    final provider = context.read<NomadeProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = switch (item.itemType) {
      'reasoning' => 'Reasoning',
      'plan' => 'Plan',
      'fileChange' => 'File changes',
      'serverRequest' => 'Approval / User input',
      _ => item.itemType,
    };
    String content = item.textDelta.trim();
    if (content.isEmpty && item.isFileChange) {
      content = item.aggregatedOutput.trim();
    }
    if (content.isEmpty && item.itemType == 'serverRequest') {
      content = item.payload['method']?.toString() ?? 'Pending request';
    }
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }

    final isServerRequest = item.itemType == 'serverRequest';
    final requestId = item.payload['requestId']?.toString() ?? '';
    final conversationId =
        item.payload['conversationId']?.toString() ?? turn.conversationId;
    final turnId = item.payload['turnId']?.toString() ?? turn.id;
    final requestMethod = item.payload['method']?.toString() ?? '';
    final requestPending = item.payload['status']?.toString() == 'inProgress';
    final canRespond = isServerRequest &&
        requestPending &&
        requestId.isNotEmpty &&
        conversationId.isNotEmpty &&
        turnId.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(11),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: item.isReasoning || item.isPlan || item.isFileChange
                  ? 'monospace'
                  : null,
              height: 1.35,
            ),
          ),
          if (canRespond) ...[
            const SizedBox(height: 8),
            _buildServerRequestActions(
              context,
              provider: provider,
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              method: requestMethod,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServerRequestActions(
    BuildContext context, {
    required NomadeProvider provider,
    required String conversationId,
    required String turnId,
    required String requestId,
    required String method,
  }) {
    if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _decisionButton(
            context,
            label: 'Accept',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'accept',
            ),
          ),
          _decisionButton(
            context,
            label: 'Accept session',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'acceptForSession',
            ),
          ),
          _decisionButton(
            context,
            label: 'Decline',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'decline',
            ),
          ),
          _decisionButton(
            context,
            label: 'Cancel',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'cancel',
            ),
          ),
        ],
      );
    }

    if (method == 'item/tool/requestUserInput') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _decisionButton(
            context,
            label: 'Reply',
            onPressed: () async {
              final input = await _promptForInput(
                context,
                title: 'Tool user input',
              );
              if (input == null) {
                return;
              }
              provider.respondToServerRequest(
                conversationId: conversationId,
                turnId: turnId,
                requestId: requestId,
                result: input,
              );
            },
          ),
          _decisionButton(
            context,
            label: 'Decline',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'decline',
            ),
          ),
        ],
      );
    }

    if (method == 'item/tool/call') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _decisionButton(
            context,
            label: 'Return empty',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: {
                'contentItems': <Map<String, dynamic>>[],
              },
            ),
          ),
          _decisionButton(
            context,
            label: 'Error',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              error: 'dynamic_tool_not_implemented',
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _decisionButton(
          context,
          label: 'Resolve',
          onPressed: () => provider.respondToServerRequest(
            conversationId: conversationId,
            turnId: turnId,
            requestId: requestId,
            result: {},
          ),
        ),
      ],
    );
  }

  Widget _decisionButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonal(
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Future<String?> _promptForInput(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter response',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Widget _buildExecutionPanel(
    BuildContext context, {
    required List<TurnTimelineItem> commandItems,
    required bool collapsed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final durationLabel = _buildExecutionDurationLabel(commandItems);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('exec-${turn.id}-${collapsed ? "closed" : "open"}'),
          initiallyExpanded: !collapsed,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Text(
            durationLabel == null
                ? 'Execution details'
                : 'A travaillé pendant $durationLabel',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '${commandItems.length} command${commandItems.length > 1 ? "s" : ""}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: commandItems
              .map((item) => _buildCommandCard(context, item))
              .toList(),
        ),
      ),
    );
  }

  String? _buildExecutionDurationLabel(List<TurnTimelineItem> commandItems) {
    final turnDuration = turn.duration;
    if (turnDuration != null) {
      return _formatDuration(turnDuration);
    }
    if (commandItems.isEmpty) {
      return null;
    }
    DateTime? startAt;
    DateTime? endAt;
    for (final item in commandItems) {
      startAt = startAt == null || item.startedAt.isBefore(startAt)
          ? item.startedAt
          : startAt;
      final completedAt = item.completedAt;
      if (completedAt != null) {
        endAt =
            endAt == null || completedAt.isAfter(endAt) ? completedAt : endAt;
      }
    }
    if (startAt == null || endAt == null) {
      return null;
    }
    final duration = endAt.difference(startAt);
    if (duration.inMilliseconds < 0) {
      return null;
    }
    return _formatDuration(duration);
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = duration.inMinutes;
    final remainingSeconds = seconds - (minutes * 60);
    return '${minutes}m ${remainingSeconds}s';
  }

  Widget _buildCommandCard(BuildContext context, TurnTimelineItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final command = item.command.trim();
    final status =
        item.statusLabel.trim().isEmpty ? 'unknown' : item.statusLabel.trim();
    final exitCode = item.exitCode;
    final cwd = item.cwd.trim();
    final output = item.aggregatedOutput;
    final durationMs = item.durationMs;
    final durationSec =
        durationMs == null ? null : (durationMs / 1000).toStringAsFixed(2);

    final commandLabel = command.isEmpty ? '(command unavailable)' : command;
    final metadata = <String>[
      'status=$status',
      if (exitCode != null) 'exit=$exitCode',
      if (durationSec != null) '${durationSec}s',
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Text(
            commandLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          subtitle: Text(
            metadata,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            if (cwd.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'cwd: $cwd',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1014),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  output.trim().isEmpty ? 'No output captured.' : output,
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
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, Turn turn, String markdown) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = turn.duration;
    final tokens = turn.totalTokens;

    return Row(
      children: [
        if (duration != null) ...[
          Icon(Icons.timer_outlined, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '${duration.inSeconds}s',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
        ],
        if (tokens > 0) ...[
          Icon(Icons.generating_tokens_outlined,
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$tokens tokens',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          icon: Icon(Icons.copy_rounded,
              size: 17, color: scheme.onSurfaceVariant),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: markdown));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          tooltip: 'Copy to clipboard',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
