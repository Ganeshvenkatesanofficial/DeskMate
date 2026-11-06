import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../models/chat_message.dart';
import '../../widgets/telemetry_accordion.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'chat_widgets.dart';
import 'composer_logic.dart';

/// One rendered turn: the user's right-aligned bubble (with its mention chips)
/// or the assistant's answer — agent logs (the shared DeskMate telemetry
/// accordion) above markdown, with existing absolute paths made clickable.
class ChatMessageView extends StatelessWidget {
  final ChatMessage message;
  final List<ChatMention> mentions;
  const ChatMessageView({super.key, required this.message, this.mentions = const []});

  @override
  Widget build(BuildContext context) {
    return message.role == MessageRole.user
        ? _UserBubble(text: message.content, mentions: mentions)
        : _AssistantMessage(message: message);
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  final List<ChatMention> mentions;
  const _UserBubble({required this.text, required this.mentions});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final style = FaText.sans(size: 13.5, color: c.foreground, height: 1.45);
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.88),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: c.isDark ? 0.10 : 0.07),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: SelectableText.rich(
                TextSpan(
                  style: style,
                  children: [
                    for (final (t, k) in highlightSegments(text, mentions))
                      TextSpan(
                        text: t,
                        style: k == null ? null : TextStyle(color: highlightColor(k)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (mentions.isNotEmpty) ...[
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.88),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final m in mentions) MentionChip(mention: m, onTap: () => openPathInExplorer(context, m.path)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantMessage extends StatefulWidget {
  final ChatMessage message;
  const _AssistantMessage({required this.message});
  @override
  State<_AssistantMessage> createState() => _AssistantMessageState();
}

class _AssistantMessageState extends State<_AssistantMessage> {
  bool _hover = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final m = widget.message;
    final isError = m.content.startsWith('⚠️');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.telemetry.isNotEmpty) TelemetryAccordion(key: ValueKey('fa_telemetry_${m.id}'), steps: m.telemetry),
          if (isError) _ErrorNote(text: m.content.replaceFirst('⚠️', '').trim()) else AnswerMarkdown(text: m.content),
          if (!isError && m.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AnimatedOpacity(
                duration: FaMotion.fast,
                opacity: _hover ? 1 : 0,
                child: Row(
                  children: [
                    FaIconButton(
                      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 24,
                      tooltip: 'Copy answer',
                      color: _copied ? Scoop.mint : null,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: m.content));
                        setState(() => _copied = true);
                        Future.delayed(const Duration(milliseconds: 1500), () {
                          if (mounted) setState(() => _copied = false);
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    Text(formatAgo(m.timestamp), style: FaText.sans(size: 10.5, color: c.mutedForeground)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String text;
  const _ErrorNote({required this.text});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.destructive.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(FaRadius.md),
          border: Border.all(color: c.destructive.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.error_outline_rounded, size: 14, color: c.destructive),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: SelectableText(text, style: FaText.sans(size: 12.5, color: c.destructive, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── markdown ───────────────────────────────────────────────────────────────

const _pathScheme = 'fa-path:';
final _existsCache = <String, FileSystemEntityType>{};

FileSystemEntityType _typeOf(String path) => _existsCache.putIfAbsent(path, () {
  try {
    return FileSystemEntity.typeSync(path);
  } catch (_) {
    return FileSystemEntityType.notFound;
  }
});

/// Turns backticked absolute paths that exist on disk (`/…` or `~/…`) into
/// links outside fenced code blocks, so they render as clickable code.
String linkifyPaths(String markdown, String home) {
  final inline = RegExp(r'(?<![`\[])`((?:/|~/)[^`\n]+)`(?!`)');
  final out = StringBuffer();
  var fenced = false;
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```') || line.trimLeft().startsWith('~~~')) fenced = !fenced;
    if (fenced || !line.contains('`')) {
      out.write(line);
    } else {
      out.write(
        line.replaceAllMapped(inline, (m) {
          final raw = m.group(1)!.trim();
          final path = raw.startsWith('~/') && home.isNotEmpty ? '$home${raw.substring(1)}' : raw;
          if (_typeOf(path) == FileSystemEntityType.notFound) return m.group(0)!;
          return '[`$raw`]($_pathScheme${Uri.encodeComponent(path)})';
        }),
      );
    }
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

/// Opens a path in the explorer: a folder opens, a file opens its parent with
/// the file selected. Switches back to Browse.
Future<void> openPathInExplorer(BuildContext context, String path) async {
  final app = context.read<FaController>();
  final ex = context.read<ExplorerController>();
  final isDir = _typeOf(path) == FileSystemEntityType.directory;
  app.showSection(FaSection.browse);
  await ex.open(isDir ? path : parentDir(path));
  if (!isDir) {
    for (final e in ex.entries) {
      if (e.path == path) {
        ex.select(e);
        break;
      }
    }
  }
}

class AnswerMarkdown extends StatelessWidget {
  final String text;
  const AnswerMarkdown({super.key, required this.text});

  void _pathMenu(BuildContext context, String path) {
    final ex = context.read<ExplorerController>();
    final pos = _lastPointer ?? Offset.zero;
    showFaMenu(context, pos, [
      FaMenuItem(
        'Show in Folder Agent',
        icon: Icons.folder_open_rounded,
        onTap: () => openPathInExplorer(context, path),
      ),
      FaMenuItem(
        Platform.isMacOS ? 'Reveal in Finder' : 'Reveal in file manager',
        icon: Icons.open_in_new_rounded,
        onTap: () => ex.reveal(path),
      ),
      FaMenuItem(
        'Copy path',
        icon: Icons.content_copy_rounded,
        onTap: () => Clipboard.setData(ClipboardData(text: path)),
      ),
    ]);
  }

  static Offset? _lastPointer;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final home = context.select<FaController, String>((a) => a.home);
    final body = FaText.sans(size: 13.5, color: c.foreground, height: 1.55);
    final mono = FaText.mono(size: 12, color: c.foreground);
    final theme = Theme.of(context);
    return Listener(
      onPointerDown: (e) => _lastPointer = e.position,
      child: SelectionArea(
        child: MarkdownBody(
          data: linkifyPaths(text, home),
          selectable: false,
          onTapLink: (label, href, title) {
            if (href == null) return;
            if (href.startsWith(_pathScheme)) {
              final path = Uri.decodeComponent(href.substring(_pathScheme.length));
              if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
                _pathMenu(context, path);
              } else {
                openPathInExplorer(context, path);
              }
            }
          },
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: body,
            a: body.copyWith(color: Scoop.blueberry, decoration: TextDecoration.underline),
            strong: body.copyWith(fontWeight: FontWeight.w600),
            em: body.copyWith(fontStyle: FontStyle.italic),
            listBullet: body,
            h1: FaText.sans(size: 18, weight: FontWeight.w600, color: c.foreground, height: 1.4),
            h2: FaText.sans(size: 16, weight: FontWeight.w600, color: c.foreground, height: 1.4),
            h3: FaText.sans(size: 14.5, weight: FontWeight.w600, color: c.foreground, height: 1.4),
            h4: FaText.sans(size: 13.5, weight: FontWeight.w600, color: c.foreground, height: 1.4),
            h5: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
            h6: FaText.sans(size: 12.5, weight: FontWeight.w600, color: c.mutedForeground),
            blockSpacing: 10,
            code: mono.copyWith(backgroundColor: c.muted, fontSize: 11.5),
            codeblockDecoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(FaRadius.md),
              border: Border.all(color: c.border),
            ),
            codeblockPadding: const EdgeInsets.all(12),
            blockquote: body.copyWith(color: c.mutedForeground),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: Scoop.mint.withValues(alpha: 0.6), width: 3)),
            ),
            blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            tableHead: body.copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
            tableBody: body.copyWith(fontSize: 12.5),
            tableBorder: TableBorder.all(color: c.border),
            tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The live agent-log accordion for the turn in flight.
class LiveTelemetry extends StatelessWidget {
  final List<AgentStepTelemetry> steps;
  final String title;
  const LiveTelemetry({super.key, required this.steps, required this.title});

  @override
  Widget build(BuildContext context) => TelemetryAccordion(
    key: const ValueKey('fa_live_telemetry'),
    steps: List.of(steps),
    isActive: true,
    activeTitle: title.isEmpty ? 'Thinking…' : title,
    initiallyExpanded: true,
  );
}
