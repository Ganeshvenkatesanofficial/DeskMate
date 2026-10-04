import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.bgSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 1),
              ),
              child: Icon(Icons.smart_toy_outlined, color: theme.accentFg, size: 16),
            ).animate().scale(duration: 200.ms, curve: Curves.easeOut),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser ? theme.accentEmphasis : theme.bgSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isUser ? theme.accentEmphasis : theme.borderDefault,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: isUser ? Colors.white : theme.fgDefault,
                        fontSize: 14,
                        height: 1.5,
                      ),
                      code: TextStyle(
                        backgroundColor: isUser ? Colors.black.withValues(alpha: 0.2) : theme.bgInset,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: isUser ? Colors.white : theme.fgDefault,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: theme.bgInset,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.borderDefault, width: 1),
                      ),
                      codeblockPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message.formattedTime,
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white.withValues(alpha: 0.7) : theme.fgMuted,
                    ),
                  ),
                ],
              ),
            ).animate().fade(duration: 200.ms),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.bgEmphasis,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 1),
              ),
              child: Icon(Icons.person_outline, color: theme.fgDefault, size: 16),
            ).animate().scale(duration: 200.ms, curve: Curves.easeOut),
          ],
        ],
      ),
    );
  }
}
