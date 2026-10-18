import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'telemetry_accordion.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final int? index;
  final bool isSending;
  final VoidCallback? onEdit;

  const ChatBubble({
    super.key,
    required this.message,
    this.index,
    this.isSending = false,
    this.onEdit,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isCopied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  void _copyToClipboard() {
    final text = widget.message.content;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _isCopied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _isCopied = false);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.message.role == MessageRole.user
              ? 'Query copied to clipboard'
              : 'Response copied to clipboard',
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        width: 220,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
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
              constraints: const BoxConstraints(minWidth: 130, maxWidth: 820),
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
                    if (!isUser && widget.message.telemetry.isNotEmpty)
                      TelemetryAccordion(steps: widget.message.telemetry),
                    if (isUser)
                      SelectionArea(
                        child: Text(
                          widget.message.content.isNotEmpty
                              ? widget.message.content
                              : '...',
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
                          data: widget.message.content.isNotEmpty
                              ? widget.message.content
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.message.formattedTime,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.isDark
                                ? AppTheme.darkFgMuted
                                : AppTheme.lightFgMuted,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isUser) ...[
                              _buildActionButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit query in chat box',
                                onTap: widget.isSending ? null : widget.onEdit,
                                theme: theme,
                              ),
                              const SizedBox(width: 4),
                            ],
                            _buildActionButton(
                              icon: _isCopied
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                              tooltip: _isCopied
                                  ? 'Copied'
                                  : (isUser ? 'Copy query' : 'Copy response'),
                              color: _isCopied ? const Color(0xFF2DA44E) : null,
                              onTap: _copyToClipboard,
                              theme: theme,
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required ThemeData theme,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        hoverColor: theme.isDark
            ? const Color(0x26FFFFFF)
            : const Color(0x1A000000),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(
            icon,
            size: 13,
            color:
                color ??
                (theme.isDark ? AppTheme.darkFgMuted : AppTheme.lightFgMuted),
          ),
        ),
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
