typedef NomadeSlashCommandResolution = ({
  String prompt,
  bool commandDetected,
  String? collaborationModeKind,
});

class NomadeCodexUtils {
  static String? normalizeString(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? normalizeMode(dynamic value) {
    final mode = normalizeString(value);
    if (mode == 'default' || mode == 'plan') {
      return mode;
    }
    return null;
  }

  static String? normalizeReasoningEffort(dynamic value) {
    final effort = normalizeString(value);
    switch (effort) {
      case 'none':
      case 'minimal':
      case 'low':
      case 'medium':
      case 'high':
      case 'xhigh':
        return effort;
      default:
        return null;
    }
  }

  static bool isSupportedListSortMode(String value) {
    return value == 'latest' || value == 'oldest' || value == 'name';
  }

  static NomadeSlashCommandResolution resolvePromptSlashCommand(String prompt) {
    final trimmedInput = prompt.trim();
    if (trimmedInput.isEmpty || !trimmedInput.startsWith('/')) {
      return (
        prompt: trimmedInput,
        commandDetected: false,
        collaborationModeKind: null,
      );
    }

    final lines = trimmedInput.split('\n');
    final firstLine = lines.first.trim();
    String? collaborationModeKind;
    String trailingFirstLine = '';

    if (firstLine == '/plan' ||
        firstLine.startsWith('/plan ') ||
        firstLine == '/plan-mode' ||
        firstLine.startsWith('/plan-mode ')) {
      collaborationModeKind = 'plan';
      if (firstLine == '/plan-mode') {
        trailingFirstLine = '';
      } else if (firstLine.startsWith('/plan-mode ')) {
        trailingFirstLine = firstLine.substring('/plan-mode '.length);
      } else {
        trailingFirstLine = firstLine.length > 5 ? firstLine.substring(6) : '';
      }
    } else if (firstLine == '/default' || firstLine.startsWith('/default ')) {
      collaborationModeKind = 'default';
      trailingFirstLine = firstLine.length > 8 ? firstLine.substring(9) : '';
    } else if (firstLine.startsWith('/mode ')) {
      final values = firstLine
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (values.length >= 2) {
        final requestedMode = normalizeMode(values[1]);
        if (requestedMode != null) {
          collaborationModeKind = requestedMode;
          if (values.length > 2) {
            trailingFirstLine = values.sublist(2).join(' ');
          }
        }
      }
    }

    if (collaborationModeKind == null) {
      return (
        prompt: trimmedInput,
        commandDetected: false,
        collaborationModeKind: null,
      );
    }

    final remaining = <String>[];
    if (trailingFirstLine.trim().isNotEmpty) {
      remaining.add(trailingFirstLine.trim());
    }
    if (lines.length > 1) {
      remaining.addAll(lines.skip(1));
    }
    final normalizedPrompt = remaining.join('\n').trim();
    return (
      prompt: normalizedPrompt,
      commandDetected: true,
      collaborationModeKind: collaborationModeKind,
    );
  }

  static List<Map<String, dynamic>> normalizeCodexCollaborationModesPayload(
    dynamic rawModes,
  ) {
    final source = (rawModes as List?)
            ?.whereType<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    final bySlug = <String, Map<String, dynamic>>{};

    for (final modeEntry in source) {
      final modeKind = normalizeMode(modeEntry['mode']);
      final name = normalizeString(modeEntry['name']);
      if (modeKind == null || name == null) {
        continue;
      }
      final slug = modeKind;
      final model = normalizeString(modeEntry['model']);
      final reasoningEffort =
          normalizeReasoningEffort(modeEntry['reasoningEffort']) ??
              normalizeReasoningEffort(modeEntry['reasoning_effort']);
      final turnStartCollaborationMode = <String, dynamic>{
        'mode': modeKind,
        'settings': <String, dynamic>{
          'developer_instructions': null,
        },
      };
      final modeMask = <String, dynamic>{
        'name': name,
        'mode': modeKind,
        'model': model,
        'reasoning_effort': reasoningEffort,
      };

      bySlug[slug] = {
        ...modeEntry,
        'slug': slug,
        'name': name,
        'mode': modeKind,
        'model': model,
        'reasoningEffort': reasoningEffort,
        'modeMask': modeMask,
        'turnStartCollaborationMode': turnStartCollaborationMode,
      };
    }

    return bySlug.values.toList(growable: false);
  }

  static List<Map<String, dynamic>> normalizeCodexSkillsPayload(
    dynamic rawSkills,
  ) {
    final rows = (rawSkills as List?)
            ?.whereType<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    final byPath = <String, Map<String, dynamic>>{};

    Map<String, dynamic>? parseSkill(
      Map<String, dynamic> raw, {
      String? cwd,
    }) {
      final path = normalizeString(raw['path']);
      if (path == null) {
        return null;
      }
      final interfaceRaw = raw['interface'] is Map
          ? (raw['interface'] as Map).cast<String, dynamic>()
          : null;
      final shortDescription = normalizeString(raw['shortDescription']) ??
          normalizeString(interfaceRaw?['shortDescription']);
      final rawName = normalizeString(raw['name']);
      final pathSegments = path
          .replaceAll('\\', '/')
          .split('/')
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);
      final fallbackName = pathSegments.isEmpty ? null : pathSegments.last;
      final description = normalizeString(raw['description']);
      final scope = normalizeString(raw['scope']);
      return {
        ...raw,
        'name': rawName ?? fallbackName ?? path,
        'path': path,
        if (description != null) 'description': description,
        if (shortDescription != null) 'shortDescription': shortDescription,
        if (scope != null) 'scope': scope,
        if (raw['enabled'] is bool) 'enabled': raw['enabled'],
        if (cwd != null) 'cwd': cwd,
      };
    }

    for (final row in rows) {
      final cwd = normalizeString(row['cwd']);
      final nested = row['skills'] is List
          ? (row['skills'] as List)
              .whereType<Map>()
              .map((entry) => entry.cast<String, dynamic>())
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      for (final skill in nested) {
        final parsed = parseSkill(skill, cwd: cwd);
        if (parsed != null) {
          byPath[parsed['path']!.toString()] = parsed;
        }
      }
    }

    return byPath.values.toList(growable: false);
  }

  static List<Map<String, dynamic>> normalizeCodexMcpServersPayload(
    dynamic rawServers,
  ) {
    final rows = (rawServers as List?)
            ?.whereType<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    final byName = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final name = normalizeString(row['name'] ?? row['serverName'] ?? row['id']);
      if (name == null) {
        continue;
      }
      final authRaw =
          row['auth'] is Map ? (row['auth'] as Map).cast<String, dynamic>() : null;
      final authStatus = normalizeString(row['authStatus']) ??
          normalizeString(authRaw?['status']) ??
          normalizeString(authRaw?['state']);
      final authRequiredRaw = authRaw == null ? null : authRaw['required'];
      final authRequired = row['authRequired'] is bool
          ? row['authRequired'] as bool
          : authRequiredRaw is bool
              ? authRequiredRaw
              : null;
      final toolCount =
          row['toolCount'] is num ? (row['toolCount'] as num).toInt() : null;
      final resourceCount = row['resourceCount'] is num
          ? (row['resourceCount'] as num).toInt()
          : null;
      byName[name] = {
        ...row,
        'name': name,
        if (row['enabled'] is bool) 'enabled': row['enabled'],
        if (row['required'] is bool) 'required': row['required'],
        if (authStatus != null) 'authStatus': authStatus,
        if (authRequired != null) 'authRequired': authRequired,
        if (toolCount != null && toolCount >= 0) 'toolCount': toolCount,
        if (resourceCount != null && resourceCount >= 0)
          'resourceCount': resourceCount,
      };
    }

    final values = byName.values.toList(growable: false);
    values.sort((a, b) {
      final left = a['name']?.toString() ?? '';
      final right = b['name']?.toString() ?? '';
      return left.compareTo(right);
    });
    return values;
  }

  static String? defaultCollaborationModeSlugFor(
    List<Map<String, dynamic>> modes,
  ) {
    if (modes.isEmpty) {
      return null;
    }
    for (final mode in modes) {
      if (mode['mode']?.toString() == 'default') {
        final slug = normalizeString(mode['slug']);
        if (slug != null) {
          return slug;
        }
      }
    }
    return normalizeString(modes.first['slug']);
  }

  static Map<String, dynamic>? buildSelectedCollaborationModePayload({
    required List<Map<String, dynamic>> collaborationModes,
    required String? selectedSlug,
  }) {
    if (collaborationModes.isEmpty) {
      return null;
    }
    final normalizedSlug = normalizeString(selectedSlug);
    final selectedMode = collaborationModes.firstWhere(
      (entry) => normalizeString(entry['slug']) == normalizedSlug,
      orElse: () => collaborationModes.first,
    );
    final explicitTurnStart = selectedMode['turnStartCollaborationMode'];
    if (explicitTurnStart is Map) {
      return explicitTurnStart.cast<String, dynamic>();
    }
    final mode = normalizeMode(selectedMode['mode']);
    if (mode == null) {
      return null;
    }
    return {
      'mode': mode,
      'settings': <String, dynamic>{
        'developer_instructions': null,
      },
    };
  }

  static String? findCollaborationModeSlugByKind({
    required List<Map<String, dynamic>> collaborationModes,
    required String modeKind,
  }) {
    final normalizedKind = normalizeMode(modeKind);
    if (normalizedKind == null) {
      return null;
    }
    for (final entry in collaborationModes) {
      final mode = normalizeMode(entry['mode']);
      if (mode != normalizedKind) {
        continue;
      }
      final slug = normalizeString(entry['slug']);
      if (slug != null) {
        return slug;
      }
    }
    return null;
  }

  static bool isPlanModeSelected({
    required List<Map<String, dynamic>> collaborationModes,
    required String? selectedSlug,
  }) {
    final normalizedSelected = normalizeString(selectedSlug);
    if (normalizedSelected == null) {
      return false;
    }
    final selectedMode = collaborationModes.firstWhere(
      (entry) => normalizeString(entry['slug']) == normalizedSelected,
      orElse: () => const <String, dynamic>{},
    );
    return normalizeMode(selectedMode['mode']) == 'plan';
  }

  static Map<String, dynamic>? normalizeOutgoingInputItem(
    Map<String, dynamic> input,
  ) {
    final typeRaw = normalizeString(input['type']);
    if (typeRaw == null) {
      return null;
    }
    final type = typeRaw.toLowerCase();
    switch (type) {
      case 'text':
        final text = normalizeString(input['text']);
        if (text == null) {
          return null;
        }
        final rawElements = input['text_elements'] ?? input['textElements'];
        final textElements = rawElements is List
            ? rawElements
                .whereType<Map>()
                .map((entry) => entry.cast<String, dynamic>())
                .where((entry) {
                  final byteRange = entry['byteRange'];
                  final start = entry['start'];
                  final end = entry['end'];
                  if (byteRange is Map) {
                    final cast = byteRange.cast<String, dynamic>();
                    return cast['start'] is num && cast['end'] is num;
                  }
                  return start is num && end is num;
                })
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
        return {
          'type': 'text',
          'text': text,
          'text_elements': textElements,
        };
      case 'image':
        final imageUrl = normalizeString(
          input['url'] ?? input['imageUrl'] ?? input['image_url'],
        );
        if (imageUrl == null) {
          return null;
        }
        return {
          'type': 'image',
          'url': imageUrl,
        };
      case 'local_image':
      case 'localimage':
        final path = normalizeString(input['path']);
        if (path == null) {
          return null;
        }
        return {
          'type': 'localImage',
          'path': path,
        };
      case 'mention':
      case 'skill':
        final path = normalizeString(input['path']);
        if (path == null) {
          return null;
        }
        final name = normalizeString(input['name']);
        return {
          'type': type,
          'path': path,
          if (name != null) 'name': name,
        };
      default:
        return null;
    }
  }
}
