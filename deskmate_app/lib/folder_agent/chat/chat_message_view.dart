import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import 'messages.dart';
import 'agent_log.dart';
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

/// FilDOS user bubble: right-aligned `max-w-[88%] rounded-2xl rounded-br-md
/// bg-primary/10 px-3.5 py-2`, `text-sm`; a leading known `/command` becomes
/// the mint mono badge; mention chips sit `gap-1` below.
class _UserBubble extends StatelessWidget {
  final String text;
  final List<ChatMention> mentions;
  const _UserBubble({required this.text, required this.mentions});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final style = FaText.sans(size: 14, color: c.foreground, height: 20 / 14);
    final cmd = RegExp(r'^/(\S+)\s*').firstMatch(text);
    final known = cmd != null && chatCommands.any((x) => x.id == cmd.group(1)!.toLowerCase());
    final body = known ? text.substring(cmd.end) : text;
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.88),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: SelectionArea(
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children: [
                      if (known)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Scoop.mint.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '/${cmd.group(1)!.toLowerCase()}',
                              style: FaText.mono(size: 11, weight: FontWeight.w500, color: Scoop.mint, height: 1.5),
                            ),
                          ),
                        ),
                      for (final (t, k) in highlightSegments(body, mentions))
                        TextSpan(
                          text: t,
                          style: k == null ? null : TextStyle(color: highlightColor(k)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (mentions.isNotEmpty) ...[
            const SizedBox(height: 4),
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

/// FilDOS assistant message: agent activity above the answer, the answer in
/// `text-sm leading-relaxed`, the strawberry error note, and a copy button that
/// fades in on hover (`mt-0.5 opacity-0 group-hover:opacity-100`).
class _AssistantMessage extends StatefulWidget {
  final ChatMessage message;
  const _AssistantMessage({required this.message});
  @override
  State<_AssistantMessage> createState() => _AssistantMessageState();
}

class _AssistantMessageState extends State<_AssistantMessage> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final isError = m.content.startsWith('⚠️');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.telemetry.isNotEmpty) AgentLog(key: ValueKey('fa_log_${m.id}'), steps: m.telemetry),
          if (isError) _ErrorNote(text: m.content.replaceFirst('⚠️', '').trim()) else AnswerMarkdown(text: m.content),
          if (!isError && m.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hover ? 1 : 0,
                child: _CopyButton(text: m.content),
              ),
            ),
        ],
      ),
    );
  }
}

/// FilDOS `CopyButton`: `size-6 rounded-md`, 12px copy icon → mint tick for 1.5s.
class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});
  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: 'Copy answer',
      child: Hoverable(
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.text));
          setState(() => _copied = true);
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _copied = false);
          });
        },
        builder: (context, hover) => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: hover ? c.accent : c.accent.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(FaRadius.md),
          ),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 12,
            color: _copied ? Scoop.mint : (hover ? c.foreground : c.mutedForeground),
          ),
        ),
      ),
    );
  }
}

/// `mt-1.5 rounded-md border border-strawberry/30 bg-strawberry/5 px-2 py-1 text-xs text-strawberry`.
class _ErrorNote extends StatelessWidget {
  final String text;
  const _ErrorNote({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Scoop.strawberry.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(FaRadius.md),
          border: Border.all(color: Scoop.strawberry.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline_rounded, size: 12, color: Scoop.strawberry),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: SelectableText(
                text,
                style: FaText.sans(size: 12, color: Scoop.strawberry, height: 16 / 12),
              ),
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

/// The answer body — FilDOS `MarkdownLite` rhythm: `space-y-2` blocks,
/// `text-sm leading-relaxed`, headings just go semibold at body size, `·`
/// bullets in muted, `bg-muted` inline code, and fenced code in a bordered
/// card with a language + Copy header. Backticked paths that exist become links.
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
    final body = FaText.sans(size: 14, color: c.foreground, height: 1.625);
    final heading = body.copyWith(fontWeight: FontWeight.w600);
    final mono = FaText.mono(size: 12, color: c.foreground, height: 1.625);
    final theme = Theme.of(context);
    return Listener(
      onPointerDown: (e) => _lastPointer = e.position,
      child: SelectionArea(
        child: MarkdownBody(
          data: linkifyPaths(text, home),
          selectable: false,
          builders: {'pre': _CodeBlockBuilder(c)},
          bulletBuilder: (p) => Text(
            p.style == BulletStyle.orderedList ? '${p.index + 1}.' : '·',
            textAlign: TextAlign.left,
            style: body.copyWith(color: c.mutedForeground),
          ),
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
            del: body.copyWith(decoration: TextDecoration.lineThrough),
            listBullet: body.copyWith(color: c.mutedForeground),
            listIndent: 14,
            listBulletPadding: const EdgeInsets.only(right: 6),
            h1: heading,
            h2: heading,
            h3: heading,
            h4: heading,
            h5: heading,
            h6: heading,
            blockSpacing: 8,
            code: mono.copyWith(backgroundColor: c.muted, fontSize: 11.9),
            codeblockDecoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(FaRadius.lg),
              border: Border.all(color: c.border),
            ),
            codeblockPadding: EdgeInsets.zero,
            blockquote: body.copyWith(color: c.mutedForeground),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: c.border, width: 2)),
            ),
            blockquotePadding: const EdgeInsets.only(left: 12),
            tableHead: FaText.sans(size: 12, weight: FontWeight.w600, color: c.foreground, height: 1.5),
            tableBody: FaText.sans(size: 12, color: c.foreground, height: 1.5),
            tableBorder: TableBorder.all(color: c.border),
            tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fenced code: FilDOS `CodeBlock` — header `border-b px-3 py-1` with the
/// language (`font-mono text-3xs uppercase tracking-wider`) and Copy; body
/// `px-3 py-2.5 text-xs leading-relaxed` mono, scrolling sideways.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final FaColors c;
  _CodeBlockBuilder(this.c);

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    // `md.Element` (package:markdown is only a transitive dependency).
    Object element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final dynamic el = element;
    var text = (el.textContent as String?) ?? '';
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    var lang = '';
    final children = el.children as List?;
    if (children != null && children.isNotEmpty) {
      final dynamic first = children.first;
      try {
        final cls = (first.attributes as Map)['class']?.toString() ?? '';
        if (cls.startsWith('language-')) lang = cls.substring('language-'.length);
      } catch (_) {}
    }
    return _CodeBlock(lang: lang, text: text, c: c);
  }
}

class _CodeBlock extends StatelessWidget {
  final String lang;
  final String text;
  final FaColors c;
  const _CodeBlock({required this.lang, required this.text, required this.c});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            Text(
              (lang.isEmpty ? 'code' : lang).toUpperCase(),
              style: FaText.mono(size: 10, color: c.mutedForeground).copyWith(letterSpacing: 0.5),
            ),
            const Spacer(),
            _CodeCopy(text: text, c: c),
          ],
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text, style: FaText.mono(size: 12, color: c.foreground, height: 1.625)),
      ),
    ],
  );
}

class _CodeCopy extends StatefulWidget {
  final String text;
  final FaColors c;
  const _CodeCopy({required this.text, required this.c});
  @override
  State<_CodeCopy> createState() => _CodeCopyState();
}

class _CodeCopyState extends State<_CodeCopy> {
  bool _copied = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Tooltip(
      message: 'Copy code',
      child: Hoverable(
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.text));
          setState(() => _copied = true);
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _copied = false);
          });
        },
        builder: (context, hover) {
          final fg = hover ? c.foreground : c.mutedForeground;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 11, color: _copied ? Scoop.mint : fg),
              const SizedBox(width: 4),
              Text(_copied ? 'Copied' : 'Copy', style: FaText.sans(size: 10, color: fg, height: 1.5)),
            ],
          );
        },
      ),
    );
  }
}

/// The live agent log for the turn in flight (chips + thinking dots).
class LiveTelemetry extends StatelessWidget {
  final List<AgentStepTelemetry> steps;
  final String title;
  const LiveTelemetry({super.key, required this.steps, required this.title});

  @override
  Widget build(BuildContext context) => AgentLog(
    key: const ValueKey('fa_live_log'),
    steps: List.of(steps),
    active: true,
    activeTitle: title.isEmpty ? 'Thinking…' : title,
  );
}
