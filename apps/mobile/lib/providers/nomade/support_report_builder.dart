import '../../models/agent.dart';
import '../../models/conversation.dart';
import '../../models/turn.dart';
import '../../models/turn_timeline.dart';
import '../../models/workspace.dart';
import 'diagnostics_models.dart';

class NomadeSupportReportContext {
  const NomadeSupportReportContext({
    required this.generatedAtUtc,
    required this.apiBaseUrl,
    required this.status,
    required this.realtimeConnected,
    required this.selectedAgent,
    required this.selectedWorkspace,
    required this.trustedDevMode,
    required this.conversation,
    required this.targetConversationId,
    required this.selectedModel,
    required this.selectedApprovalPolicy,
    required this.selectedSandboxMode,
    required this.selectedEffort,
    required this.selectedCollaborationModeSlug,
    required this.selectedSkillPaths,
    required this.nativeNotificationsBridgeEnabled,
    required this.canUsePushNotifications,
    required this.pushProviderReady,
    required this.pushRegistrationError,
    required this.rateSnapshot,
    required this.primaryWindow,
    required this.secondaryWindow,
    required this.e2eReady,
    required this.securityError,
    required this.pendingScanPayload,
    required this.pendingScanShortCode,
    required this.runtime,
    required this.events,
    required this.turnsSnapshot,
    required this.timelineTurn,
    required this.timeline,
  });

  final DateTime generatedAtUtc;
  final String apiBaseUrl;
  final String status;
  final bool realtimeConnected;
  final Agent? selectedAgent;
  final Workspace? selectedWorkspace;
  final bool trustedDevMode;
  final Conversation? conversation;
  final String targetConversationId;
  final String? selectedModel;
  final String? selectedApprovalPolicy;
  final String? selectedSandboxMode;
  final String? selectedEffort;
  final String? selectedCollaborationModeSlug;
  final List<String> selectedSkillPaths;
  final bool nativeNotificationsBridgeEnabled;
  final bool canUsePushNotifications;
  final bool pushProviderReady;
  final String? pushRegistrationError;
  final Map<String, dynamic>? rateSnapshot;
  final Map<String, dynamic>? primaryWindow;
  final Map<String, dynamic>? secondaryWindow;
  final bool e2eReady;
  final String? securityError;
  final String? pendingScanPayload;
  final String? pendingScanShortCode;
  final ConversationRuntimeTrace? runtime;
  final List<ConversationDebugEvent> events;
  final List<Turn> turnsSnapshot;
  final Turn? timelineTurn;
  final TurnTimeline? timeline;
}

class NomadeSupportReportBuilder {
  static const _redactedValue = '[REDACTED]';
  static const _sensitiveKeyMarkers = <String>[
    'token',
    'secret',
    'key',
    'sig',
    'ciphertext',
    'nonce',
    'aad',
    'authorization',
    'envelope',
  ];
  static final RegExp _jwtRegex = RegExp(
    r'\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
  );
  static final RegExp _bearerRegex = RegExp(
    r'\bbearer\s+[A-Za-z0-9._~+/\-=]{10,}\b',
    caseSensitive: false,
  );
  static final RegExp _basicRegex = RegExp(
    r'\bbasic\s+[A-Za-z0-9+/=]{8,}\b',
    caseSensitive: false,
  );
  static final RegExp _secretAssignmentRegex = RegExp(
    r'\b([a-z0-9_.-]*(?:token|secret|key|sig|ciphertext|nonce|aad|authorization|envelope)[a-z0-9_.-]*)\b(\s*[:=]\s*)([^\s,;]+)',
    caseSensitive: false,
  );

  static String build(NomadeSupportReportContext context) {
    final lines = <String>['supportBundleVersion=1'];

    _appendSupportSectionHeader(lines, 'context');
    _appendSupportKeyValue(
      lines,
      'generatedAt',
      context.generatedAtUtc.toIso8601String(),
    );
    _appendSupportKeyValue(lines, 'apiBaseUrl', context.apiBaseUrl);
    _appendSupportKeyValue(lines, 'status', context.status);
    _appendSupportKeyValue(
      lines,
      'socket',
      context.realtimeConnected ? 'connected' : 'disconnected',
    );
    _appendSupportKeyValue(lines, 'agentId', context.selectedAgent?.id ?? '-');
    _appendSupportKeyValue(
      lines,
      'agentOnline',
      context.selectedAgent?.isOnline == true ? 'true' : 'false',
    );
    _appendSupportKeyValue(
      lines,
      'workspaceId',
      context.selectedWorkspace?.id ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'workspacePath',
      context.selectedWorkspace?.path ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'workspaceTrustedDev',
      context.trustedDevMode ? 'true' : 'false',
    );
    _appendSupportKeyValue(
        lines, 'conversationId', context.targetConversationId);
    _appendSupportKeyValue(
      lines,
      'conversationStatus',
      context.conversation?.status ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'conversationThread',
      context.conversation?.codexThreadId ?? '-',
    );
    _appendSupportKeyValue(
        lines, 'selectedModel', context.selectedModel ?? '-');
    _appendSupportKeyValue(
      lines,
      'selectedApproval',
      context.selectedApprovalPolicy ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'selectedSandbox',
      context.selectedSandboxMode ?? '-',
    );
    _appendSupportKeyValue(
        lines, 'selectedEffort', context.selectedEffort ?? '-');
    _appendSupportKeyValue(
      lines,
      'selectedCollaborationMode',
      context.selectedCollaborationModeSlug ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'selectedSkills',
      context.selectedSkillPaths.isEmpty
          ? '-'
          : context.selectedSkillPaths.join(','),
    );
    _appendSupportKeyValue(
      lines,
      'nativeNotificationsBridgeEnabled',
      context.nativeNotificationsBridgeEnabled ? 'true' : 'false',
    );
    _appendSupportKeyValue(
      lines,
      'pushFeatureEnabled',
      context.canUsePushNotifications ? 'true' : 'false',
    );
    _appendSupportKeyValue(
      lines,
      'pushProviderReady',
      context.pushProviderReady ? 'true' : 'false',
    );
    _appendSupportKeyValue(
      lines,
      'pushRegistrationError',
      context.pushRegistrationError ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'codexRateLimitId',
      context.rateSnapshot?['limitId']?.toString() ?? '-',
    );
    _appendSupportRateWindow(lines, 'codexRatePrimary', context.primaryWindow);
    _appendSupportRateWindow(
        lines, 'codexRateSecondary', context.secondaryWindow);

    _appendSupportSectionHeader(lines, 'security');
    _appendSupportKeyValue(
        lines, 'e2eReady', context.e2eReady ? 'true' : 'false');
    _appendSupportKeyValue(
        lines, 'securityError', context.securityError ?? '-');
    _appendSupportKeyValue(
      lines,
      'pendingScanPayload',
      context.pendingScanPayload ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'pendingScanShortCode',
      context.pendingScanShortCode ?? '-',
    );

    _appendSupportSectionHeader(lines, 'runtime');
    _appendSupportKeyValue(
        lines, 'runtimeTurnId', context.runtime?.turnId ?? '-');
    _appendSupportKeyValue(
      lines,
      'runtimeCodexTurnId',
      context.runtime?.codexTurnId ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeThreadId',
      context.runtime?.threadId ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeTurnStatus',
      context.runtime?.turnStatus ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeTurnError',
      context.runtime?.turnError ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeRequestedAt',
      context.runtime?.requestedAt?.toIso8601String() ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeStartedAt',
      context.runtime?.startedAt?.toIso8601String() ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeCompletedAt',
      context.runtime?.completedAt?.toIso8601String() ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeRequestedCwd',
      context.runtime?.requestedCwd ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeRequestedModel',
      context.runtime?.requestedModel ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeRequestedApproval',
      context.runtime?.requestedApprovalPolicy ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeRequestedSandbox',
      context.runtime?.requestedSandboxMode ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'runtimeRequestedEffort',
      context.runtime?.requestedEffort ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'eventsReceived',
      context.runtime?.eventsReceived ?? 0,
    );
    _appendSupportKeyValue(
      lines,
      'eventsRendered',
      context.runtime?.eventsRendered ?? 0,
    );
    _appendSupportKeyValue(
      lines,
      'eventsNotRenderedMethods',
      context.runtime == null || context.runtime!.unsupportedMethods.isEmpty
          ? '-'
          : context.runtime!.unsupportedMethods.join(','),
    );

    _appendSupportSectionHeader(lines, 'events');
    _appendSupportKeyValue(lines, 'count', context.events.length);
    for (var index = 0; index < context.events.length; index += 1) {
      final event = context.events[index];
      final compact = _formatSupportInlineFields({
        'at': event.at.toIso8601String(),
        'type': event.type,
        'message': event.message,
      });
      lines.add('event[$index]=$compact');
    }

    _appendSupportSectionHeader(lines, 'turns');
    _appendSupportKeyValue(lines, 'count', context.turnsSnapshot.length);
    for (var index = 0; index < context.turnsSnapshot.length; index += 1) {
      final turn = context.turnsSnapshot[index];
      lines.add(
        'turn[$index]=${_formatSupportInlineFields({
              'id': turn.id,
              'status': turn.status,
              'codexTurnId': turn.codexTurnId ?? '-',
              'error': turn.error ?? '-',
              'createdAt': turn.createdAt.toIso8601String(),
              'updatedAt': turn.updatedAt.toIso8601String(),
              'completedAt': turn.completedAt?.toIso8601String() ?? '-',
              'itemsCount': turn.items.length,
            })}',
      );
    }

    _appendSupportSectionHeader(lines, 'timeline');
    _appendSupportKeyValue(lines, 'turnId', context.timelineTurn?.id ?? '-');
    _appendSupportKeyValue(
      lines,
      'turnStatus',
      context.timelineTurn?.status ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      'turnCodexTurnId',
      context.timelineTurn?.codexTurnId ?? '-',
    );
    _appendSupportKeyValue(
        lines, 'itemCount', context.timeline?.items.length ?? 0);
    if (context.timeline == null && context.timelineTurn != null) {
      _appendSupportKeyValue(lines, 'note', 'timeline_not_initialized');
    }
    if (context.timeline != null) {
      final items = context.timeline!.items;
      for (var index = 0; index < items.length; index += 1) {
        final item = items[index];
        lines.add(
          'item[$index]=${_formatSupportInlineFields({
                'itemId': item.itemId,
                'itemType': item.itemType,
                'stream': item.stream ?? '-',
                'status': item.statusLabel,
                'exitCode': item.exitCode?.toString() ?? '-',
                'durationMs': item.durationMs?.toString() ?? '-',
                'startedAt': item.startedAt.toIso8601String(),
                'completedAt': item.completedAt?.toIso8601String() ?? '-',
              })}',
        );
      }
    }

    return lines.join('\n');
  }

  static void _appendSupportSectionHeader(List<String> lines, String name) {
    lines.add('');
    lines.add('[$name]');
  }

  static void _appendSupportKeyValue(
    List<String> lines,
    String key,
    Object? value,
  ) {
    lines.add('$key=${_redactSupportValue(key, _formatSupportValue(value))}');
  }

  static void _appendSupportRateWindow(
    List<String> lines,
    String prefix,
    Map<String, dynamic>? window,
  ) {
    _appendSupportKeyValue(
      lines,
      '${prefix}UsedPct',
      window?['usedPercent']?.toString() ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      '${prefix}RemainingPct',
      window?['remainingPercent']?.toString() ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      '${prefix}WindowMins',
      window?['windowDurationMins']?.toString() ?? '-',
    );
    _appendSupportKeyValue(
      lines,
      '${prefix}ResetAt',
      window?['resetAt']?.toString() ?? '-',
    );
  }

  static String _formatSupportInlineFields(Map<String, Object?> fields) {
    final parts = <String>[];
    for (final entry in fields.entries) {
      parts.add(
        '${entry.key}=${_redactSupportValue(entry.key, _formatSupportValue(entry.value))}',
      );
    }
    return parts.join(' ');
  }

  static String _formatSupportValue(Object? value) {
    if (value == null) {
      return '-';
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? '-' : trimmed;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    return value.toString();
  }

  static String _redactSupportValue(String key, String value) {
    if (value == '-') {
      return value;
    }
    if (_isSensitiveSupportKey(key)) {
      return _redactedValue;
    }
    var output = value;
    if (key == 'apiBaseUrl') {
      output = _redactUrlSensitiveParts(output);
    }
    output = _redactSensitiveFragments(output);
    return output;
  }

  static bool _isSensitiveSupportKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final marker in _sensitiveKeyMarkers) {
      if (normalized.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  static String _redactUrlSensitiveParts(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      return value;
    }
    const uriSafeRedacted = 'REDACTED';
    var changed = false;
    var updated = parsed;
    if (parsed.userInfo.isNotEmpty) {
      updated = updated.replace(userInfo: uriSafeRedacted);
      changed = true;
    }
    if (parsed.queryParameters.isNotEmpty) {
      final nextQuery = <String, String>{};
      for (final entry in parsed.queryParameters.entries) {
        final nextValue =
            _isSensitiveSupportKey(entry.key) ? uriSafeRedacted : entry.value;
        if (nextValue != entry.value) {
          changed = true;
        }
        nextQuery[entry.key] = nextValue;
      }
      if (changed) {
        updated = updated.replace(queryParameters: nextQuery);
      }
    }
    return changed ? updated.toString() : value;
  }

  static String _redactSensitiveFragments(String value) {
    var output = value;
    output =
        output.replaceAllMapped(_bearerRegex, (_) => 'Bearer $_redactedValue');
    output =
        output.replaceAllMapped(_basicRegex, (_) => 'Basic $_redactedValue');
    output = output.replaceAllMapped(_jwtRegex, (_) => _redactedValue);
    output = output.replaceAllMapped(_secretAssignmentRegex, (match) {
      final name = match.group(1) ?? 'secret';
      final sep = match.group(2) ?? '=';
      return '$name$sep$_redactedValue';
    });
    return output;
  }
}
