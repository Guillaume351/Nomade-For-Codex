import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../models/workspace.dart';
import '../providers/nomade_provider.dart';
import 'secure_scan_camera_screen.dart';
import '../widgets/chat_turn_widget.dart';
import '../widgets/e2e_guide_sheet.dart';
import '../widgets/home/service_terminal_sheet.dart';
import '../widgets/home/turn_options_sheet.dart';
import '../widgets/sidebar.dart';
import '../widgets/tunnel_manager_sheet.dart';

part 'home_screen_methods_composer.dart';
part 'home_screen_methods_topbar.dart';
part 'home_screen_methods_layout.dart';

enum _TopBarMenuAction {
  turnOptions,
  copyUsefulLogs,
  toggleDiagnostics,
  e2eGuide,
  approveSecureScan,
  tunnelManager,
  serviceTerminal,
}

enum _ComposerAction {
  addFiles,
  togglePlanMode,
}

class _ComposerSlashCommand {
  const _ComposerSlashCommand({
    required this.command,
    required this.description,
    this.inlineHelp,
  });

  final String command;
  final String description;
  final String? inlineHelp;
}

class _PendingAttachment {
  const _PendingAttachment({
    required this.path,
    required this.type,
  });

  final String path;
  final String type;

  String get name {
    final normalized = path.replaceAll('\\', '/');
    final pieces = normalized.split('/');
    if (pieces.isEmpty) {
      return path;
    }
    final candidate = pieces.last.trim();
    return candidate.isEmpty ? path : candidate;
  }

  Map<String, dynamic> toInputItem() {
    return {
      'type': type,
      'path': path,
      'name': name,
    };
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _conversationRailBreakpoint = 980.0;
  static const _maxLayoutWidth = 1540.0;
  static const _imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
    '.svg',
  };
  static const _baseSlashCommands = <_ComposerSlashCommand>[
    _ComposerSlashCommand(
      command: '/feedback',
      description: 'Copy useful logs for feedback/debugging.',
    ),
    _ComposerSlashCommand(
      command: '/mcp',
      description: 'Show MCP status support.',
    ),
    _ComposerSlashCommand(
      command: '/plan-mode',
      description: 'Toggle plan mode.',
    ),
    _ComposerSlashCommand(
      command: '/review',
      description: 'Start a review-oriented prompt.',
      inlineHelp: 'Optional: /review <focus>',
    ),
    _ComposerSlashCommand(
      command: '/status',
      description: 'Show thread/model/runtime status.',
    ),
    _ComposerSlashCommand(
      command: '/plan',
      description: 'Switch to plan mode (alias).',
      inlineHelp: 'Optional: /plan <prompt>',
    ),
    _ComposerSlashCommand(
      command: '/default',
      description: 'Switch back to default mode.',
      inlineHelp: 'Optional: /default <prompt>',
    ),
    _ComposerSlashCommand(
      command: '/mode',
      description: 'Set collaboration mode explicitly.',
      inlineHelp: 'Usage: /mode <plan|default> [prompt]',
    ),
  ];

  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _expandedWorkspaceIds = <String>{};
  final List<_PendingAttachment> _pendingAttachments = <_PendingAttachment>[];

  bool _showDiagnostics = false;
  bool _chatBottomRefreshInProgress = false;
  double _chatBottomOverscrollPx = 0;
  DateTime? _chatBottomRefreshLastAt;

  void _setStateSafe(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    setState(fn);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final isWideLayout =
        MediaQuery.of(context).size.width >= _conversationRailBreakpoint;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    _ensureWorkspaceExpansion(provider);
    _scrollToBottom();

    return Scaffold(
      drawer: isWideLayout ? null : const Sidebar(),
      drawerEnableOpenDragGesture: !isWideLayout,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.16 : 0.07,
              ),
              theme.scaffoldBackgroundColor,
              scheme.tertiary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.11 : 0.05,
              ),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxLayoutWidth),
              child: Column(
                children: [
                  _buildTopBar(provider, isWideLayout),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.88),
                            border: Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.66),
                            ),
                          ),
                          child: isWideLayout
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 356,
                                      child: _buildConversationRail(provider),
                                    ),
                                    Expanded(child: _buildChatPane(provider)),
                                  ],
                                )
                              : _buildChatPane(provider),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
