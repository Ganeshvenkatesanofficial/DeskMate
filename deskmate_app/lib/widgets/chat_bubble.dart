import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'telemetry_accordion.dart';

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
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(theme, isUser: false),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isUser ? theme.bgEmphasis : theme.bgSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUser ? theme.accentEmphasis : theme.borderDefault,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUser && message.telemetry.isNotEmpty)
                      TelemetryAccordion(steps: message.telemetry),
                    if (isUser)
                      SelectionArea(
                        child: Text(
                          message.content.isNotEmpty ? message.content : '...',
                          style: TextStyle(
                            color: theme.isDark
                                ? AppTheme.darkFgDefault
                                : AppTheme.lightFgDefault,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      )
                    else
                      SelectionArea(
                        child: MarkdownBody(
                          data: message.content.isNotEmpty
                              ? message.content
                              : '*(No response received)*',
                          selectable: false,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme)
                              .copyWith(
                                p: TextStyle(
                                  color: theme.isDark
                                      ? AppTheme.darkFgDefault
                                      : AppTheme.lightFgDefault,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                code: TextStyle(
                                  backgroundColor: theme.bgInset,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: theme.isDark
                                      ? AppTheme.darkFgDefault
                                      : AppTheme.lightFgDefault,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: theme.bgInset,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: theme.borderDefault,
                                    width: 1,
                                  ),
                                ),
                                codeblockPadding: const EdgeInsets.all(12),
                              ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      message.formattedTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.isDark
                            ? AppTheme.darkFgMuted
                            : AppTheme.lightFgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            _buildAvatar(theme, isUser: true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, {required bool isUser}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isUser ? theme.bgEmphasis : theme.bgSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Icon(
        isUser ? Icons.person_outline : Icons.smart_toy_outlined,
        color: isUser ? theme.fgDefault : theme.accentFg,
        size: 16,
      ),
    ).animate().scale(duration: 200.ms, curve: Curves.easeOut);
  }
}
