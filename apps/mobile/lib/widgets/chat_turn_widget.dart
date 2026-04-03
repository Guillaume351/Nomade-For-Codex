import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/turn.dart';
import '../models/turn_timeline.dart';
import '../providers/nomade_provider.dart';

enum _TimelineSegmentKind {
  agentMessage,
  commandGroup,
  event,
}

class _TimelineSegment {
  _TimelineSegment.agentMessage({
    required this.text,
  })  : kind = _TimelineSegmentKind.agentMessage,
        item = null,
        commandItems = const [];

  _TimelineSegment.commandGroup({
    required this.commandItems,
  })  : kind = _TimelineSegmentKind.commandGroup,
        text = null,
        item = null;

  _TimelineSegment.event({
    required this.item,
  })  : kind = _TimelineSegmentKind.event,
        text = null,
        commandItems = const [];

  final _TimelineSegmentKind kind;
  final String? text;
  final TurnTimelineItem? item;
  final List<TurnTimelineItem> commandItems;
}

class ChatTurnWidget extends StatelessWidget {
  const ChatTurnWidget({super.key, required this.turn});

  final Turn turn;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final timeline = provider.tryTimelineForTurn(turn.id);
    final markdownForCopy = _getMarkdownForCopy(timeline);
    final isUser = turn.userPrompt.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isUser) _buildUserBubble(context, turn.userPrompt),
        _buildAssistantBubble(
          context,
          timeline: timeline,
          markdownForCopy: markdownForCopy,
        ),
      ],
    );
  }

  String _getMarkdownForCopy(TurnTimeline? timeline) {
    if (timeline != null) {
      final chunks = <String>[];
      for (final item in timeline.items) {
        if (!item.isAgentMessage) {
          continue;
        }
        final text = _extractAgentMessageText(item);
        if (text.isNotEmpty) {
          chunks.add(text);
        }
      }
      if (chunks.isNotEmpty) {
        return chunks.join('\n\n');
      }
    }

    final chunks = <String>[];
    for (final item in turn.items) {
      if (item.itemType != 'agentMessage') {
        continue;
      }
      final extracted = _extractTextFromPayload(item.payload).trim();
      if (extracted.isNotEmpty) {
        chunks.add(extracted);
      }
    }
    if (chunks.isNotEmpty) {
      return chunks.join('\n\n');
    }

    if (turn.status == 'failed') {
      final error = turn.error?.trim();
      if (error != null && error.isNotEmpty) {
        return 'Request failed: `$error`';
      }
    }
    return '';
  }

  List<_TimelineSegment> _buildSegments(TurnTimeline timeline) {
    final segments = <_TimelineSegment>[];
    final commandBuffer = <TurnTimelineItem>[];
    final timelineItems = List<TurnTimelineItem>.from(timeline.items);
    final indexByItemId = <String, int>{};
    for (var index = 0; index < timelineItems.length; index += 1) {
      indexByItemId[timelineItems[index].itemId] = index;
    }
    timelineItems.sort((a, b) {
      final timeCompare =
          _timelineSortInstant(a).compareTo(_timelineSortInstant(b));
      if (timeCompare != 0) {
        return timeCompare;
      }
      final typeCompare =
          _timelineTypeSortWeight(a).compareTo(_timelineTypeSortWeight(b));
      if (typeCompare != 0) {
        return typeCompare;
      }
      return (indexByItemId[a.itemId] ?? 0).compareTo(
        indexByItemId[b.itemId] ?? 0,
      );
    });

    void flushCommands() {
      if (commandBuffer.isEmpty) {
        return;
      }
      segments.add(_TimelineSegment.commandGroup(
        commandItems: List<TurnTimelineItem>.from(commandBuffer),
      ));
      commandBuffer.clear();
    }

    for (final item in timelineItems) {
      if (item.isCommandExecution) {
        commandBuffer.add(item);
        continue;
      }

      flushCommands();
      if (item.isAgentMessage) {
        final text = _extractAgentMessageText(item);
        if (text.isEmpty) {
          continue;
        }
        segments.add(_TimelineSegment.agentMessage(text: text));
      } else {
        segments.add(_TimelineSegment.event(item: item));
      }
    }
    flushCommands();

    return segments;
  }

  DateTime _timelineSortInstant(TurnTimelineItem item) {
    var instant = item.completedAt ?? item.startedAt;
    final phase = item.payload['phase']?.toString().toLowerCase();
    if (item.isAgentMessage && phase == 'final_answer') {
      instant = instant.add(const Duration(milliseconds: 1));
    }
    return instant;
  }

  int _timelineTypeSortWeight(TurnTimelineItem item) {
    if (item.isCommandExecution) {
      return 0;
    }
    if (item.isAgentMessage) {
      return 2;
    }
    return 1;
  }

  String _extractAgentMessageText(TurnTimelineItem item) {
    final timelineText = item.textDelta.trim();
    if (timelineText.isNotEmpty) {
      return timelineText;
    }
    return _extractTextFromPayload(item.payload).trim();
  }

  Widget _buildUserBubble(BuildContext context, String text) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1260),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 16),
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
    BuildContext context, {
    required TurnTimeline? timeline,
    required String markdownForCopy,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasError = turn.error != null && turn.error!.trim().isNotEmpty;
    final segments = timeline == null
        ? const <_TimelineSegment>[]
        : _buildSegments(timeline);
    final hasTimeline = segments.isNotEmpty;
    final shouldCollapseExecution = timeline?.executionCollapsed ??
        (turn.status == 'completed' ||
            turn.status == 'failed' ||
            turn.status == 'interrupted');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1360),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 6),
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
            if (hasTimeline)
              ...segments.map((segment) {
                return switch (segment.kind) {
                  _TimelineSegmentKind.agentMessage =>
                    _buildAgentMessageCard(context, segment.text ?? ''),
                  _TimelineSegmentKind.commandGroup => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildExecutionPanel(
                        context,
                        commandItems: segment.commandItems,
                        collapsed: shouldCollapseExecution,
                      ),
                    ),
                  _TimelineSegmentKind.event =>
                    _buildLiveEventCard(context, segment.item!),
                };
              })
            else
              _buildAgentMessageFallback(context, markdownForCopy, hasError),
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
            if (turn.status == 'completed' || turn.status == 'failed') ...[
              const Divider(height: 28),
              _buildMetrics(context, turn, markdownForCopy),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAgentMessageFallback(
    BuildContext context,
    String markdown,
    bool hasError,
  ) {
    if (markdown.trim().isEmpty) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return Text(
        turn.status == 'running'
            ? 'Codex is thinking...'
            : hasError
                ? 'No assistant message was produced.'
                : 'No assistant message.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return _buildAgentMessageCard(context, markdown);
  }

  Widget _buildAgentMessageCard(BuildContext context, String markdown) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MarkdownBody(
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
        styleSheet: _markdownStyle(context),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
      blockSpacing: 12,
      code: TextStyle(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF0F131A)
            : const Color(0xFF171C24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockAlign: WrapAlignment.start,
      blockquoteDecoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            label: 'Accept',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'accept',
            ),
          ),
          _decisionButton(
            label: 'Accept session',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'acceptForSession',
            ),
          ),
          _decisionButton(
            label: 'Decline',
            onPressed: () => provider.respondToServerRequest(
              conversationId: conversationId,
              turnId: turnId,
              requestId: requestId,
              result: 'decline',
            ),
          ),
          _decisionButton(
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

    return _decisionButton(
      label: 'Resolve',
      onPressed: () => provider.respondToServerRequest(
        conversationId: conversationId,
        turnId: turnId,
        requestId: requestId,
        result: {},
      ),
    );
  }

  Widget _decisionButton({
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
          key: ValueKey(
            'exec-${turn.id}-${commandItems.first.itemId}-${commandItems.length}-${collapsed ? "closed" : "open"}',
          ),
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
}
