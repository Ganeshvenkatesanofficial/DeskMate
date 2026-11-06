import 'package:flutter/material.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import 'folder_chat_controller.dart';

/// Pure text logic behind the Ask AI composer (port of FilDOS `chatComposer.ts`):
/// which `@` / `#` / `/` token the caret sits in, completing it, pruning
/// mentions whose token was deleted, and atomic token deletion on Backspace.

enum MentionKind { file, folder }

@immutable
class ChatMention {
  final MentionKind kind;
  final String path;
  final String name;
  const ChatMention(this.kind, this.path, this.name);

  factory ChatMention.forPath(String path, {required bool isDir}) =>
      ChatMention(isDir ? MentionKind.folder : MentionKind.file, path, baseName(path));

  bool get isFolder => kind == MentionKind.folder;
  String get token => '${isFolder ? '#' : '@'}$name';

  @override
  bool operator ==(Object other) => other is ChatMention && other.path == path && other.kind == kind;
  @override
  int get hashCode => Object.hash(path, kind);
}

class ComposerToken {
  final String trigger; // '@' | '#' | '/'
  final int start;
  final String query;
  const ComposerToken(this.trigger, this.start, this.query);
}

const _maxQuery = 64;

/// The mention/command token the caret currently sits in, or null.
/// `@`/`#` open a token after start-of-text or whitespace; `/` only at the very start.
ComposerToken? activeToken(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final upto = text.substring(0, caret);
  for (var i = upto.length - 1; i >= 0; i--) {
    final ch = upto[i];
    if (ch == '\n') return null;
    if (ch == '@' || ch == '#' || ch == '/') {
      final before = i == 0 ? '' : upto[i - 1];
      if (ch == '/' && i != 0) continue;
      if (before.isNotEmpty && before.trim().isNotEmpty) continue;
      final query = upto.substring(i + 1);
      if (query.length > _maxQuery) return null;
      return ComposerToken(ch, i, query);
    }
  }
  return null;
}

/// Replace the active token with [completion]; returns the new text and caret.
(String, int) completeToken(String text, int caret, ComposerToken token, String completion) {
  final inserted = '${token.trigger}$completion ';
  final next = text.substring(0, token.start) + inserted + text.substring(caret);
  return (next, token.start + inserted.length);
}

/// Mentions still present in [text] (deduplicated) — what actually gets sent.
List<ChatMention> pruneMentions(String text, List<ChatMention> mentions) {
  final seen = <String>{};
  return [
    for (final m in mentions)
      if (text.contains(m.token) && seen.add(m.path)) m,
  ];
}

/// When the caret sits right after a completed mention (or a leading
/// `/command`), the whole span to delete on Backspace — plus its mention.
(int, int, ChatMention?)? tokenBeforeCaret(String text, int caret, List<ChatMention> mentions) {
  if (caret <= 0 || caret > text.length) return null;
  final before = text.substring(0, caret);
  (int, int, ChatMention?)? best;
  for (final m in mentions) {
    int? start;
    if (before.endsWith('${m.token} ')) {
      start = caret - m.token.length - 1;
    } else if (before.endsWith(m.token)) {
      start = caret - m.token.length;
    }
    if (start != null && (best == null || start < best.$1)) best = (start, caret, m);
  }
  if (best != null) return best;
  if (RegExp(r'^/\S+ ?$').hasMatch(before)) return (0, caret, null);
  return null;
}

// ── commands ───────────────────────────────────────────────────────────────

class ChatCommand {
  final String id;
  final String description;
  const ChatCommand(this.id, this.description);
}

const chatCommands = [
  ChatCommand('find', 'Search your files by name and meaning'),
  ChatCommand('summarize', 'Summarize the folder in view'),
  ChatCommand('clear', 'Start a new conversation'),
];

// ── highlighting ───────────────────────────────────────────────────────────

enum HighlightKind { command, file, folder }

Color highlightColor(HighlightKind k) => switch (k) {
  HighlightKind.command => Scoop.mint,
  HighlightKind.file => Scoop.blueberry,
  HighlightKind.folder => Scoop.grape,
};

/// Splits [text] into plain and coloured runs: a leading `/command` (mint),
/// `@file` (blueberry) and `#folder` (grape) — known mentions match their
/// literal token (names may contain spaces), bare triggers colour their word.
List<(String, HighlightKind?)> highlightSegments(String text, List<ChatMention> mentions) {
  final ranges = <(int, int, HighlightKind)>[];
  final cmd = RegExp(r'^/(\S+)').firstMatch(text);
  if (cmd != null) ranges.add((0, cmd.end, HighlightKind.command));
  for (final m in mentions) {
    var from = 0;
    while (true) {
      final ix = text.indexOf(m.token, from);
      if (ix < 0) break;
      ranges.add((ix, ix + m.token.length, m.isFolder ? HighlightKind.folder : HighlightKind.file));
      from = ix + m.token.length;
    }
  }
  for (final match in RegExp(r'(^|\s)([@#])(\S*)').allMatches(text)) {
    final start = match.start + match.group(1)!.length;
    final end = start + 1 + match.group(3)!.length;
    ranges.add((start, end, match.group(2) == '@' ? HighlightKind.file : HighlightKind.folder));
  }
  ranges.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
  final out = <(String, HighlightKind?)>[];
  var cursor = 0;
  for (final r in ranges) {
    if (r.$1 < cursor) continue;
    if (r.$1 > cursor) out.add((text.substring(cursor, r.$1), null));
    out.add((text.substring(r.$1, r.$2), r.$3));
    cursor = r.$2;
  }
  if (cursor < text.length) out.add((text.substring(cursor), null));
  return out;
}

/// A text controller that paints mentions/commands in their scoop colour
/// (colour only — never a metric change, so the caret stays aligned).
class HighlightingController extends TextEditingController {
  List<ChatMention> mentions = const [];
  HighlightingController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (value.composing.isValid && withComposing) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return TextSpan(
      style: style,
      children: [
        for (final (t, k) in highlightSegments(text, mentions))
          TextSpan(
            text: t,
            style: k == null ? null : TextStyle(color: highlightColor(k)),
          ),
      ],
    );
  }
}

// ── per-controller session state (survives leaving the Ask AI view) ───────

/// Composer draft + recorded mentions, and the mentions each sent message
/// carried (for the chips under user bubbles). Kept per [FolderChatController]
/// so switching sections doesn't lose them.
class AskAiSession {
  String draft = '';
  List<ChatMention> mentions = [];
  bool indexHintDismissed = false;
  bool showHistory = false;
  final Map<String, List<ChatMention>> sentMentions = {};

  static final _store = Expando<AskAiSession>('askAiSession');
  static AskAiSession of(FolderChatController chat) => _store[chat] ??= AskAiSession();
}
