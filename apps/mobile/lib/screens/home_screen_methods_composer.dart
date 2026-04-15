part of 'home_screen.dart';

extension _HomeScreenComposerMethods on _HomeScreenState {
  Future<void> _confirmAndCancelActiveTurn(NomadeProvider provider) async {
    if (_cancelTurnInProgress) {
      return;
    }
    final turnId = provider.activeTurnId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel running turn?'),
        content: Text(
          turnId == null || turnId.trim().isEmpty
              ? 'Codex is currently running a request. Do you want to cancel it?'
              : 'Codex is currently running turn $turnId.\n\nDo you want to cancel it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep running'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel turn'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    _setStateSafe(() {
      _cancelTurnInProgress = true;
    });
    try {
      final interrupted = await provider.interruptActiveTurn();
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final message = interrupted
          ? 'Cancellation requested.'
          : (provider.status.trim().isNotEmpty
              ? provider.status.trim()
              : 'Unable to cancel the running turn.');
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      _setStateSafe(() {
        _cancelTurnInProgress = false;
      });
    }
  }

  Future<void> _handleSend() async {
    final rawInput = _promptController.text.trim();
    if (rawInput.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }

    final provider = context.read<NomadeProvider>();
    var text = rawInput;
    if (rawInput.isNotEmpty) {
      final slashResolution = await _handleComposerSlashCommand(
        provider: provider,
        rawInput: rawInput,
      );
      if (!mounted) {
        return;
      }
      if (slashResolution.consumeOnly) {
        _promptController.clear();
        _setStateSafe(() {});
        return;
      }
      text = slashResolution.promptToSend?.trim() ?? '';
    }
    if (text.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }

    String? deliveryPolicyOverride;
    final selectedAgent = provider.selectedAgent;
    final shouldPromptForOfflineChoice =
        provider.offlineTurnDefault == 'prompt' &&
            selectedAgent != null &&
            !selectedAgent.isOnline;
    if (shouldPromptForOfflineChoice) {
      deliveryPolicyOverride = await _askOfflineDeliveryPolicy(provider);
      if (deliveryPolicyOverride == null) {
        return;
      }
    }

    final extraInputItems = _pendingAttachments
        .map((attachment) => attachment.toInputItem())
        .toList(growable: false);
    HapticFeedback.lightImpact();
    _promptController.clear();
    _setStateSafe(() {
      _pendingAttachments.clear();
    });
    await provider.sendPrompt(
      text,
      deliveryPolicyOverride: deliveryPolicyOverride,
      extraInputItems: extraInputItems,
    );
    _scrollToBottom(force: true);
  }

  Future<({bool consumeOnly, String? promptToSend})>
      _handleComposerSlashCommand({
    required NomadeProvider provider,
    required String rawInput,
  }) async {
    final parsed = _parseSlashCommandInput(rawInput);
    if (parsed == null) {
      return (consumeOnly: false, promptToSend: rawInput);
    }

    final command = parsed.command;
    final commandPrompt = parsed.prompt;

    switch (command) {
      case '/feedback':
        await _copyUsefulLogs(provider);
        return (consumeOnly: true, promptToSend: null);
      case '/status':
        _showSlashStatusSheet(provider);
        return (consumeOnly: true, promptToSend: null);
      case '/mcp':
        _showSlashMcpSheet();
        return (consumeOnly: true, promptToSend: null);
      case '/plan-mode':
        final wasPlan = provider.isPlanModeSelected();
        provider.selectCollaborationModeByKind(wasPlan ? 'default' : 'plan');
        if (!mounted) {
          return (consumeOnly: true, promptToSend: null);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasPlan
                  ? 'Plan mode disabled (default mode active).'
                  : 'Plan mode enabled.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        if (commandPrompt.isEmpty) {
          return (consumeOnly: true, promptToSend: null);
        }
        return (consumeOnly: false, promptToSend: commandPrompt);
      case '/review':
        if (commandPrompt.isEmpty) {
          return (
            consumeOnly: false,
            promptToSend:
                'Review the current workspace changes and list findings by severity with file references.',
          );
        }
        return (
          consumeOnly: false,
          promptToSend:
              'Review the current workspace changes. Focus especially on: $commandPrompt',
        );
      default:
        break;
    }

    final skillMatch = _skillSlashCommandMap(provider)[command];
    if (skillMatch != null) {
      final path = (skillMatch['path']?.toString() ?? '').trim();
      final name = (skillMatch['name']?.toString() ?? path).trim();
      if (path.isNotEmpty) {
        provider.toggleSkillPath(path);
        if (mounted) {
          final enabled = provider.selectedSkillPaths.contains(path);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                enabled ? 'Skill enabled: $name' : 'Skill disabled: $name',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        if (commandPrompt.isEmpty) {
          return (consumeOnly: true, promptToSend: null);
        }
        return (consumeOnly: false, promptToSend: commandPrompt);
      }
    }

    return (consumeOnly: false, promptToSend: rawInput);
  }

  ({String command, String prompt})? _parseSlashCommandInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('/')) {
      return null;
    }
    final lines = trimmed.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.isEmpty || !firstLine.startsWith('/')) {
      return null;
    }
    final pieces = firstLine
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (pieces.isEmpty) {
      return null;
    }
    final command = pieces.first.toLowerCase();
    final trailingFirstLine = firstLine.length > command.length
        ? firstLine.substring(command.length).trim()
        : '';
    final promptParts = <String>[];
    if (trailingFirstLine.isNotEmpty) {
      promptParts.add(trailingFirstLine);
    }
    if (lines.length > 1) {
      promptParts.addAll(lines.skip(1));
    }
    return (
      command: command,
      prompt: promptParts.join('\n').trim(),
    );
  }

  String _skillCommandSlug(Map<String, dynamic> skill) {
    final name = (skill['name']?.toString() ?? '').trim();
    final path = (skill['path']?.toString() ?? '').trim();
    final source = name.isNotEmpty ? name : path;
    if (source.isEmpty) {
      return '';
    }
    final normalized = source
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll('.md', '')
        .replaceAll('.MD', '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized;
  }

  Map<String, Map<String, dynamic>> _skillSlashCommandMap(
    NomadeProvider provider,
  ) {
    final values = <String, Map<String, dynamic>>{};
    for (final skill in provider.codexSkills) {
      final path = (skill['path']?.toString() ?? '').trim();
      if (path.isEmpty) {
        continue;
      }
      final slug = _skillCommandSlug(skill);
      if (slug.isEmpty) {
        continue;
      }
      values['/$slug'] = skill;
    }
    return values;
  }

  List<_ComposerSlashCommand> _composerSlashCommands(NomadeProvider provider) {
    final values = <_ComposerSlashCommand>[
      ..._HomeScreenState._baseSlashCommands,
    ];
    final skillMap = _skillSlashCommandMap(provider);
    final skillCommands = skillMap.entries.map((entry) {
      final skill = entry.value;
      final description = (skill['shortDescription']?.toString() ??
              skill['description']?.toString() ??
              'Toggle this skill for upcoming prompts.')
          .trim();
      return _ComposerSlashCommand(
        command: entry.key,
        description: description.isEmpty
            ? 'Toggle this skill for upcoming prompts.'
            : description,
      );
    }).toList()
      ..sort((a, b) => a.command.compareTo(b.command));
    values.addAll(skillCommands);
    return values;
  }

  List<_ComposerSlashCommand> _filteredSlashCommands(NomadeProvider provider) {
    final raw = _promptController.text.trimLeft();
    if (raw.isEmpty || !raw.startsWith('/')) {
      return const [];
    }
    final firstLine = raw.split('\n').first.trimRight();
    if (firstLine.isEmpty || firstLine.contains(RegExp(r'\s'))) {
      return const [];
    }
    final typed = firstLine.toLowerCase();
    final allCommands = _composerSlashCommands(provider);
    if (typed == '/') {
      return allCommands;
    }
    return allCommands
        .where((command) => command.command.startsWith(typed))
        .toList(growable: false);
  }

  void _applySlashCommand(_ComposerSlashCommand command) {
    HapticFeedback.selectionClick();
    final nextText = '${command.command} ';
    _promptController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    _setStateSafe(() {});
  }

  KeyEventResult _handleComposerKeyEvent({
    required KeyEvent event,
    required bool isRunning,
  }) {
    if (isRunning || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isPasteKey = event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPasteKey) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final isShortcutPressed =
        keyboard.isMetaPressed || keyboard.isControlPressed;
    if (!isShortcutPressed) {
      return KeyEventResult.ignored;
    }
    unawaited(
      _pasteImageAttachmentFromClipboard(
        showFailureSnackBar: false,
      ),
    );
    return KeyEventResult.ignored;
  }

  Future<void> _handleComposerAction(
    _ComposerAction action,
    NomadeProvider provider,
  ) async {
    HapticFeedback.selectionClick();
    switch (action) {
      case _ComposerAction.addPhotos:
        await _pickComposerPhotos();
        return;
      case _ComposerAction.addFiles:
        await _pickComposerFiles();
        return;
      case _ComposerAction.pasteImage:
        await _pasteImageAttachmentFromClipboard();
        return;
      case _ComposerAction.togglePlanMode:
        final wasPlan = provider.isPlanModeSelected();
        provider.selectCollaborationModeByKind(wasPlan ? 'default' : 'plan');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasPlan
                  ? 'Plan mode disabled (default mode active).'
                  : 'Plan mode enabled.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
    }
  }

  Future<void> _pickComposerFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      withReadStream: false,
      type: FileType.any,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    var added = 0;
    _setStateSafe(() {
      for (final file in result.files) {
        final path = (file.path ?? '').trim();
        final rawName = file.name.trim();
        final attachmentName = rawName.isNotEmpty
            ? rawName
            : (path.isNotEmpty
                ? path.replaceAll('\\', '/').split('/').last
                : 'attachment');
        final normalizedTarget = path.isNotEmpty ? path : attachmentName;
        final isImage = _isImageAttachmentPath(normalizedTarget);
        final bytes = file.bytes;

        if (isImage && bytes != null && bytes.isNotEmpty) {
          final attachment = _createImageAttachment(
            bytes: bytes,
            target: normalizedTarget,
            name: attachmentName,
            path: path.isEmpty ? null : path,
          );
          final exists = _pendingAttachments.any(
            (entry) => entry.imageUrl == attachment.imageUrl,
          );
          if (exists) {
            continue;
          }
          _pendingAttachments.add(attachment);
          added += 1;
          continue;
        }

        if (path.isEmpty) {
          continue;
        }
        final id = 'path:$path';
        final exists = _pendingAttachments.any((entry) => entry.id == id);
        if (exists) {
          continue;
        }
        _pendingAttachments.add(
          _PendingAttachment(
            id: id,
            name: attachmentName,
            path: path,
            type: _attachmentInputType(path),
          ),
        );
        added += 1;
      }
    });
    if (added <= 0) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$added file${added > 1 ? "s" : ""} attached'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickComposerPhotos() async {
    final picker = ImagePicker();
    List<XFile> picked;
    try {
      picked = await picker.pickMultiImage();
    } catch (_) {
      picked = const <XFile>[];
    }
    if (picked.isEmpty) {
      try {
        final single = await picker.pickImage(source: ImageSource.gallery);
        if (single != null) {
          picked = [single];
        }
      } catch (_) {
        picked = const <XFile>[];
      }
    }
    if (!mounted || picked.isEmpty) {
      return;
    }

    final pending = <_PendingAttachment>[];
    for (final image in picked) {
      try {
        final bytes = await image.readAsBytes();
        if (bytes.isEmpty) {
          continue;
        }
        final path = image.path.trim();
        final name = image.name.trim().isNotEmpty
            ? image.name.trim()
            : (path.isNotEmpty
                ? path.replaceAll('\\', '/').split('/').last
                : 'Photo');
        final attachment = _createImageAttachment(
          bytes: bytes,
          name: name.isEmpty ? 'Photo' : name,
          path: path.isEmpty ? null : path,
          target: path.isNotEmpty ? path : name,
        );
        pending.add(attachment);
      } catch (_) {
        continue;
      }
    }
    if (pending.isEmpty) {
      return;
    }

    var added = 0;
    _setStateSafe(() {
      for (final attachment in pending) {
        final duplicate = _pendingAttachments.any(
          (entry) => entry.imageUrl == attachment.imageUrl,
        );
        if (duplicate) {
          continue;
        }
        _pendingAttachments.add(attachment);
        added += 1;
      }
    });
    if (!mounted || added <= 0) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$added photo${added > 1 ? "s" : ""} attached'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  _PendingAttachment _createImageAttachment({
    required List<int> bytes,
    required String name,
    required String target,
    String? path,
  }) {
    final imageUrl = _buildImageDataUrl(bytes, target: target);
    return _PendingAttachment(
      id: 'image:${imageUrl.hashCode}',
      type: 'image',
      name: name,
      path: path,
      imageUrl: imageUrl,
    );
  }

  Future<void> _pasteImageAttachmentFromClipboard({
    bool showFailureSnackBar = true,
  }) async {
    final binaryAttached = await _tryAttachBinaryImageFromSystemClipboard();
    if (binaryAttached) {
      return;
    }

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clipboard?.text?.trim() ?? '';
    if (!mounted || raw.isEmpty) {
      if (showFailureSnackBar) {
        _showClipboardImageFailureSnackBar();
      }
      return;
    }

    final uri = Uri.tryParse(raw);
    final isDataImage = raw.startsWith('data:image/');
    final isRemoteImage = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        _isImageAttachmentPath(uri.path);

    if (isDataImage || isRemoteImage) {
      final id = 'image:${raw.hashCode}';
      final exists = _pendingAttachments.any((entry) => entry.imageUrl == raw);
      if (exists) {
        return;
      }
      _setStateSafe(() {
        _pendingAttachments.add(
          _PendingAttachment(
            id: id,
            type: 'image',
            name: isDataImage
                ? 'Pasted image'
                : (uri?.pathSegments.last ?? 'Pasted image'),
            imageUrl: raw,
          ),
        );
      });
      return;
    }

    final normalizedPath =
        uri != null && uri.scheme == 'file' ? uri.toFilePath() : raw;
    if (_isImageAttachmentPath(normalizedPath)) {
      final id = 'path:$normalizedPath';
      final exists = _pendingAttachments.any((entry) => entry.id == id);
      if (exists) {
        return;
      }
      final name = normalizedPath.replaceAll('\\', '/').split('/').last;
      _setStateSafe(() {
        _pendingAttachments.add(
          _PendingAttachment(
            id: id,
            type: 'localImage',
            name: name.isEmpty ? 'Pasted image' : name,
            path: normalizedPath,
          ),
        );
      });
      return;
    }

    if (showFailureSnackBar) {
      _showClipboardImageFailureSnackBar();
    }
  }

  Future<bool> _tryAttachBinaryImageFromSystemClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return false;
    }
    try {
      final reader = await clipboard.read();
      if (!reader.canProvide(Formats.png)) {
        return false;
      }

      final completer = Completer<({List<int> bytes, String? fileName})?>();
      final progress = reader.getFile(
        Formats.png,
        (file) async {
          try {
            final bytes = await file.readAll();
            if (!completer.isCompleted) {
              completer.complete(
                bytes.isEmpty ? null : (bytes: bytes, fileName: file.fileName),
              );
            }
          } catch (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );
      if (progress == null) {
        return false;
      }
      final image = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (image == null || image.bytes.isEmpty || !mounted) {
        return false;
      }
      final fileName = (image.fileName ?? '').trim();
      final target = fileName.isEmpty ? 'pasted-image.png' : fileName;
      final attachment = _createImageAttachment(
        bytes: image.bytes,
        name: fileName.isEmpty ? 'Pasted image' : fileName,
        target: target,
      );
      var added = false;
      _setStateSafe(() {
        final exists = _pendingAttachments.any(
          (entry) => entry.imageUrl == attachment.imageUrl,
        );
        if (!exists) {
          _pendingAttachments.add(attachment);
          added = true;
        }
      });
      return added;
    } catch (_) {
      return false;
    }
  }

  void _showClipboardImageFailureSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Clipboard does not contain an image.',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _attachmentInputType(String path) {
    final normalized = path.trim().toLowerCase();
    for (final extension in _HomeScreenState._imageExtensions) {
      if (normalized.endsWith(extension)) {
        return 'localImage';
      }
    }
    return 'mention';
  }

  bool _isImageAttachmentPath(String target) {
    final normalized = target.trim().toLowerCase();
    for (final extension in _HomeScreenState._imageExtensions) {
      if (normalized.endsWith(extension)) {
        return true;
      }
    }
    return false;
  }

  String _buildImageDataUrl(
    List<int> bytes, {
    required String target,
  }) {
    final mimeType = _imageMimeType(target);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  String _imageMimeType(String target) {
    final normalized = target.trim().toLowerCase();
    if (normalized.endsWith('.png')) {
      return 'image/png';
    }
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.webp')) {
      return 'image/webp';
    }
    if (normalized.endsWith('.gif')) {
      return 'image/gif';
    }
    if (normalized.endsWith('.bmp')) {
      return 'image/bmp';
    }
    if (normalized.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    if (normalized.endsWith('.heic') || normalized.endsWith('.heif')) {
      return 'image/heic';
    }
    if (normalized.endsWith('.tif') || normalized.endsWith('.tiff')) {
      return 'image/tiff';
    }
    return 'image/png';
  }

  void _removePendingAttachment(String id) {
    _setStateSafe(() {
      _pendingAttachments.removeWhere((entry) => entry.id == id);
    });
  }

  void _showSlashStatusSheet(NomadeProvider provider) {
    final mode = provider.isPlanModeSelected() ? 'plan' : 'default';
    final selectedConversationId = provider.selectedConversation?.id ?? '-';
    final threadId = provider.selectedConversation?.codexThreadId ?? '-';
    final model = provider.selectedModel ?? '-';
    final effort = provider.selectedEffort ?? '-';
    final approval = provider.selectedApprovalPolicy ?? '-';
    final sandbox = provider.selectedSandboxMode ?? '-';
    final statusLine =
        provider.status.trim().isEmpty ? 'Idle' : provider.status.trim();
    final contextUsage = provider.turns.length;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thread status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _statusRow('Conversation', selectedConversationId),
                _statusRow('Thread', threadId),
                _statusRow('Mode', mode),
                _statusRow('Model', model),
                _statusRow('Effort', effort),
                _statusRow('Approval', approval),
                _statusRow('Sandbox', sandbox),
                _statusRow('Turns in memory', '$contextUsage'),
                _statusRow(
                  'Realtime',
                  provider.realtimeConnected ? 'connected' : 'disconnected',
                ),
                _statusRow('Status', statusLine),
                const SizedBox(height: 8),
                Text(
                  'Rate-limit details are shown in the quota badge when available.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusRow(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _showSlashMcpSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MCP status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This mobile build does not yet expose live connected MCP server details.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use Codex desktop/CLI for detailed MCP server status right now.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _askOfflineDeliveryPolicy(NomadeProvider provider) async {
    final allowQueue = provider.canUseDeferredTurns;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agent offline'),
          content: Text(
            allowQueue
                ? 'Send now and fail if still offline, or queue this turn until reconnect.'
                : 'Your agent is offline. Queued turns are not available on your current plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('immediate'),
              child: const Text('Send now'),
            ),
            if (allowQueue)
              FilledButton(
                onPressed: () => Navigator.of(context).pop('defer_if_offline'),
                child: const Text('Queue for reconnect'),
              ),
          ],
        );
      },
    );
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    const threshold = 140.0;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= threshold;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isNearBottom()) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppMotion.medium,
        curve: AppMotion.standardCurve,
      );
    });
  }

  Future<void> _startSecureScanApproval() async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await Navigator.of(context).push<SecureScanCameraResult>(
      buildAppPageRoute(
        context,
        const SecureScanCameraScreen(
          title: 'Approve secure scan',
        ),
      ),
    );
    if (!mounted || result == null || !result.hasData) {
      return;
    }

    final provider = context.read<NomadeProvider>();
    try {
      await provider.stagePendingSecureScanData(
        scanPayload: result.scanPayload,
        scanShortCode: result.scanShortCode,
        serverUrl: result.serverUrl,
      );
      await provider.approveSecureScan(
        scanPayload: result.scanPayload,
        scanShortCode: result.scanShortCode,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Secure scan approved')),
      );
    } catch (error) {
      final normalizedStatus = provider.status.trim();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            normalizedStatus.isEmpty
                ? 'Secure scan failed: $error'
                : normalizedStatus,
          ),
        ),
      );
    }
  }

  Future<void> _copyUsefulLogs(NomadeProvider provider) async {
    final conversation = provider.selectedConversation;
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
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs utiles copiés'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleTopBarMenuAction(
    _TopBarMenuAction action,
    NomadeProvider provider,
  ) async {
    switch (action) {
      case _TopBarMenuAction.conversationDiff:
        _showConversationDiffBottomSheet(provider);
        return;
      case _TopBarMenuAction.turnOptions:
        _showOptionsBottomSheet(context);
        return;
      case _TopBarMenuAction.copyUsefulLogs:
        await _copyUsefulLogs(provider);
        return;
      case _TopBarMenuAction.toggleDiagnostics:
        _setStateSafe(() {
          _showDiagnostics = !_showDiagnostics;
        });
        return;
      case _TopBarMenuAction.e2eGuide:
        showE2eGuideSheet(context);
        return;
      case _TopBarMenuAction.approveSecureScan:
        await _startSecureScanApproval();
        return;
      case _TopBarMenuAction.tunnelManager:
        showTunnelManagerSheet(context);
        return;
      case _TopBarMenuAction.serviceTerminal:
        _showTerminalSheet(context);
        return;
    }
  }
}
