import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/turn.dart';
import '../models/turn_timeline.dart';
import '../providers/nomade_provider.dart';
import 'app_motion.dart';

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

class _PlanStepData {
  _PlanStepData({
    required this.step,
    required this.status,
  });

  final String step;
  final String status;
}

class _RequestUserInputOptionData {
  _RequestUserInputOptionData({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

class _RequestUserInputQuestionData {
  _RequestUserInputQuestionData({
    required this.id,
    required this.header,
    required this.question,
    required this.isOther,
    required this.isSecret,
    required this.options,
  });

  final String id;
  final String header;
  final String question;
  final bool isOther;
  final bool isSecret;
  final List<_RequestUserInputOptionData> options;
}

class ChatTurnWidget extends StatelessWidget {
  const ChatTurnWidget({super.key, required this.turn});

  static const double _messageCornerRadius = 20;
  static const double _iphoneBottomCornerRadius = 18;

  final Turn turn;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final timeline = provider.tryTimelineForTurn(turn.id);
    final markdownForCopy = _getMarkdownForCopy(timeline);
    final isUser = turn.userPrompt.isNotEmpty;

    return FadeSlideIn(
      key: ValueKey('turn-${turn.id}'),
      duration: AppMotion.medium,
      beginOffset: const Offset(0, 0.018),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isUser) _buildUserBubble(context, turn.userPrompt),
          _buildAssistantBubble(
            context,
            timeline: timeline,
            markdownForCopy: markdownForCopy,
          ),
        ],
      ),
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
              topLeft: Radius.circular(_messageCornerRadius),
              topRight: Radius.circular(_messageCornerRadius),
              bottomLeft: Radius.circular(_messageCornerRadius),
              bottomRight: Radius.circular(_iphoneBottomCornerRadius),
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
          child: SelectableText(
            _normalizeInlineDirectiveText(text),
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
            topLeft: Radius.circular(_messageCornerRadius),
            topRight: Radius.circular(_messageCornerRadius),
            bottomLeft: Radius.circular(_iphoneBottomCornerRadius),
            bottomRight: Radius.circular(_messageCornerRadius),
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
    final normalizedMarkdown = _normalizeInlineDirectiveMarkdown(markdown);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MarkdownBody(
        data: normalizedMarkdown,
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
          if (status == 'running')
            PulseDot(color: color, size: 7)
          else
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
    if (item.isPlan) {
      return _buildPlanEventCard(context, item);
    }

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
    final requestParams =
        (item.payload['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    String content = item.textDelta.trim();
    if (content.isEmpty && item.isFileChange) {
      content = item.aggregatedOutput.trim();
    }
    if (content.isEmpty && item.itemType == 'serverRequest') {
      content = _buildServerRequestSummary(
        method: item.payload['method']?.toString() ?? '',
        params: requestParams,
      );
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
              params: requestParams,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanEventCard(BuildContext context, TurnTimelineItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final explanation = _extractPlanExplanation(item.payload);
    final steps = _extractPlanSteps(item.payload);
    final delta = item.textDelta.trim();

    if (explanation.isEmpty && steps.isEmpty && delta.isEmpty) {
      return const SizedBox.shrink();
    }

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
            'Plan',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              explanation,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...steps.map((step) {
              final status = _normalizePlanStepStatus(step.status);
              final (icon, color, label) = _planStepVisual(status, scheme);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(icon, size: 15, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.step,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (delta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              delta,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _extractPlanExplanation(Map<String, dynamic> payload) {
    final explanation = payload['explanation'];
    if (explanation is String && explanation.trim().isNotEmpty) {
      return explanation.trim();
    }
    return '';
  }

  List<_PlanStepData> _extractPlanSteps(Map<String, dynamic> payload) {
    final payloadPlan = payload['plan'];
    final rawSteps = payloadPlan is List ? payloadPlan : const <dynamic>[];

    return rawSteps
        .whereType<Map>()
        .map((entry) {
          final map = entry.cast<String, dynamic>();
          final step = map['step']?.toString().trim() ?? '';
          if (step.isEmpty) {
            return null;
          }
          final status = map['status']?.toString().trim() ?? 'pending';
          return _PlanStepData(step: step, status: status);
        })
        .whereType<_PlanStepData>()
        .toList(growable: false);
  }

  String _normalizePlanStepStatus(String raw) {
    final value = raw.trim();
    if (value == 'in_progress') {
      return 'inProgress';
    }
    if (value == 'completed' || value == 'pending' || value == 'inProgress') {
      return value;
    }
    return 'pending';
  }

  (IconData, Color, String) _planStepVisual(String status, ColorScheme scheme) {
    switch (status) {
      case 'completed':
        return (Icons.check_circle_rounded, Colors.green, 'completed');
      case 'inProgress':
        return (Icons.autorenew_rounded, Colors.blue, 'in progress');
      default:
        return (
          Icons.radio_button_unchecked_rounded,
          scheme.onSurfaceVariant,
          'pending'
        );
    }
  }

  String _buildServerRequestSummary({
    required String method,
    required Map<String, dynamic> params,
  }) {
    if (method.isEmpty) {
      return 'Pending request';
    }
    if (method == 'item/tool/requestUserInput') {
      final questions = _extractRequestUserInputQuestions(params);
      if (questions.isEmpty) {
        return '$method • invalid payload';
      }
      return '$method • ${questions.length} question${questions.length > 1 ? "s" : ""}';
    }
    if (method == 'item/tool/call') {
      final tool = params['tool']?.toString().trim();
      final arguments = params['arguments'];
      if (tool == null || tool.isEmpty) {
        return method;
      }
      final argsSummary = arguments == null ? '' : _compactJson(arguments);
      if (argsSummary.isEmpty) {
        return '$method • tool=$tool';
      }
      return '$method • tool=$tool\n$argsSummary';
    }
    return method;
  }

  Widget _buildServerRequestActions(
    BuildContext context, {
    required NomadeProvider provider,
    required String conversationId,
    required String turnId,
    required String requestId,
    required String method,
    required Map<String, dynamic> params,
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
      final questions = _extractRequestUserInputQuestions(params);
      if (questions.isEmpty) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Invalid request payload: missing questions.',
              style: Theme.of(context).textTheme.bodySmall,
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
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _decisionButton(
            label: 'Answer questions',
            onPressed: () async {
              final answers = await _promptForRequestUserInput(
                context,
                questions: questions,
              );
              if (answers == null) {
                return;
              }
              provider.respondToServerRequest(
                conversationId: conversationId,
                turnId: turnId,
                requestId: requestId,
                result: answers,
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
                'content_items': <Map<String, dynamic>>[],
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

  List<_RequestUserInputQuestionData> _extractRequestUserInputQuestions(
    Map<String, dynamic> params,
  ) {
    final raw = params['questions'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((entry) {
          final map = entry.cast<String, dynamic>();
          final id = map['id']?.toString().trim() ?? '';
          final header = map['header']?.toString().trim() ?? '';
          final question = map['question']?.toString().trim() ?? '';
          final optionsRaw = map['options'];
          final options = optionsRaw is List
              ? optionsRaw
                  .whereType<Map>()
                  .map((optionEntry) {
                    final option = optionEntry.cast<String, dynamic>();
                    return _RequestUserInputOptionData(
                      label: option['label']?.toString().trim() ?? '',
                      description:
                          option['description']?.toString().trim() ?? '',
                    );
                  })
                  .where((option) => option.label.isNotEmpty)
                  .toList()
              : const <_RequestUserInputOptionData>[];
          return _RequestUserInputQuestionData(
            id: id,
            header: header,
            question: question,
            isOther: map['isOther'] == true,
            isSecret: map['isSecret'] == true,
            options: options,
          );
        })
        .where((question) => question.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _promptForRequestUserInput(
    BuildContext context, {
    required List<_RequestUserInputQuestionData> questions,
  }) async {
    final selectionByQuestion = <String, String>{};
    final freeTextControllers = <String, TextEditingController>{};
    String? validationError;

    for (final question in questions) {
      freeTextControllers[question.id] = TextEditingController();
      if (question.options.isNotEmpty) {
        selectionByQuestion[question.id] = question.options.first.label;
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Tool user input'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final question in questions) ...[
                    if (question.header.isNotEmpty)
                      Text(
                        question.header,
                        style: Theme.of(dialogContext)
                            .textTheme
                            .labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    const SizedBox(height: 4),
                    Text(question.question),
                    const SizedBox(height: 8),
                    if (question.options.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...question.options.map((option) => ChoiceChip(
                                label: Text(option.label),
                                selected: selectionByQuestion[question.id] ==
                                    option.label,
                                onSelected: (_) => setState(() {
                                  selectionByQuestion[question.id] =
                                      option.label;
                                  validationError = null;
                                }),
                              )),
                          if (question.isOther)
                            ChoiceChip(
                              label: const Text('Other'),
                              selected: selectionByQuestion[question.id] ==
                                  '__other__',
                              onSelected: (_) => setState(() {
                                selectionByQuestion[question.id] = '__other__';
                                validationError = null;
                              }),
                            ),
                        ],
                      ),
                    if (question.options.isEmpty ||
                        selectionByQuestion[question.id] == '__other__') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: freeTextControllers[question.id],
                        decoration: const InputDecoration(
                          hintText: 'Enter response',
                        ),
                        obscureText: question.isSecret,
                        onChanged: (_) {
                          if (validationError != null) {
                            setState(() {
                              validationError = null;
                            });
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                  if (validationError != null)
                    Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final answers = <String, Map<String, dynamic>>{};
                for (final question in questions) {
                  var answer = selectionByQuestion[question.id] ?? '';
                  if (question.options.isEmpty || answer == '__other__') {
                    answer =
                        freeTextControllers[question.id]?.text.trim() ?? '';
                  }
                  if (answer.isEmpty) {
                    setState(() {
                      validationError = 'Please answer every question.';
                    });
                    return;
                  }
                  answers[question.id] = {
                    'answers': [answer],
                  };
                }
                Navigator.of(dialogContext).pop({
                  'answers': answers,
                });
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );

    for (final controller in freeTextControllers.values) {
      controller.dispose();
    }
    return result;
  }

  String _compactJson(dynamic value) {
    try {
      final encoded = jsonEncode(value);
      if (encoded.length <= 360) {
        return encoded;
      }
      return '${encoded.substring(0, 357)}...';
    } catch (_) {
      return value?.toString() ?? '';
    }
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
    final hasDiff = turn.diff.trim().isNotEmpty;

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
        if (hasDiff)
          IconButton(
            icon: Icon(Icons.difference_rounded,
                size: 17, color: scheme.onSurfaceVariant),
            onPressed: () => _showTurnDiffSheet(context, turn),
            tooltip: 'View diff',
            visualDensity: VisualDensity.compact,
          ),
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

  void _showTurnDiffSheet(BuildContext context, Turn turn) {
    final diff = turn.diff.trim();
    if (diff.isEmpty) {
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
                Text(
                  'Turn diff',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  turn.userPrompt.trim().isEmpty
                      ? 'Prompt unavailable'
                      : turn.userPrompt.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 440),
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
          ),
        );
      },
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

  String _normalizeInlineDirectiveText(String value) {
    return value.replaceAllMapped(
      RegExp(r'::([a-zA-Z0-9_-]+)\{([^{}]*)\}'),
      (match) {
        final rendered = _renderInlineDirective(
          command: match[1] ?? '',
          argsBody: match[2] ?? '',
        );
        return rendered ?? match[0] ?? '';
      },
    );
  }

  String _normalizeInlineDirectiveMarkdown(String value) {
    return value.replaceAllMapped(
      RegExp(r'::([a-zA-Z0-9_-]+)\{([^{}]*)\}'),
      (match) {
        final rendered = _renderInlineDirective(
          command: match[1] ?? '',
          argsBody: match[2] ?? '',
        );
        if (rendered == null) {
          return match[0] ?? '';
        }
        return '`$rendered`';
      },
    );
  }

  String? _renderInlineDirective({
    required String command,
    required String argsBody,
  }) {
    if (command.trim().isEmpty) {
      return null;
    }
    final args = _parseDirectiveArgs(argsBody);
    final cwd = args['cwd'];
    final branch = args['branch'];
    switch (command.trim().toLowerCase()) {
      case 'git-stage':
        return cwd == null ? 'git stage' : 'git stage ($cwd)';
      case 'git-commit':
        return cwd == null ? 'git commit' : 'git commit ($cwd)';
      case 'git-push':
        if (cwd != null && branch != null) {
          return 'git push ($cwd, $branch)';
        }
        if (cwd != null) {
          return 'git push ($cwd)';
        }
        if (branch != null) {
          return 'git push ($branch)';
        }
        return 'git push';
      default:
        if (args.isEmpty) {
          return command.trim();
        }
        final details = args.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(', ');
        return '${command.trim()} ($details)';
    }
  }

  Map<String, String> _parseDirectiveArgs(String argsBody) {
    final values = <String, String>{};
    for (final match
        in RegExp(r'([a-zA-Z0-9_]+)\s*=\s*"([^"]*)"').allMatches(argsBody)) {
      final key = match.group(1)?.trim();
      final value = match.group(2);
      if (key == null || key.isEmpty || value == null) {
        continue;
      }
      values[key] = value;
    }
    return values;
  }
}
