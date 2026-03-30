import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/turn.dart';
import '../providers/nomade_provider.dart';

class ChatTurnWidget extends StatelessWidget {
  const ChatTurnWidget({super.key, required this.turn});

  final Turn turn;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final isUser = turn.userPrompt.isNotEmpty;
    final markdown = _getMarkdown(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isUser) _buildUserBubble(context, turn.userPrompt),
        _buildAssistantBubble(context, markdown, turn),
      ],
    );
  }

  String _getMarkdown(NomadeProvider provider) {
    final buffer = provider.streamByTurn[turn.id];
    if (buffer != null) return buffer.toString();

    // Fallback to turn items if no buffer
    final agentMessages = turn.items.where((i) => i.itemType == 'agentMessage');
    if (agentMessages.isNotEmpty) {
      return agentMessages.map((i) => i.payload['content'] ?? '').join('\n');
    }
    return '';
  }

  Widget _buildUserBubble(BuildContext context, String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, left: 48),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(
      BuildContext context, String markdown, Turn turn) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24, right: 48),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: markdown,
            selectable: true,
            onTapLink: (text, href, title) {
              // Handle links
            },
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 15, height: 1.5),
              code: TextStyle(
                backgroundColor: Colors.grey[200],
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              codeblockDecoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              codeblockPadding: const EdgeInsets.all(12),
            ),
          ),
          if (turn.status == 'completed' || turn.status == 'failed') ...[
            const Divider(height: 32),
            _buildMetrics(context, turn, markdown),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, Turn turn, String markdown) {
    final duration = turn.duration;
    final tokens = turn.totalTokens;

    return Row(
      children: [
        if (duration != null) ...[
          const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            '${duration.inSeconds}s',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(width: 16),
        ],
        if (tokens > 0) ...[
          const Icon(Icons.generating_tokens_outlined,
              size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            '$tokens tokens',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.grey),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: markdown));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1)),
            );
          },
          tooltip: 'Copy to clipboard',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
