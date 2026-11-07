import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/model_logo.dart';
import '../widgets/ui.dart';
import 'chat_widgets.dart';
import 'composer_logic.dart';
import 'folder_chat_controller.dart';
import 'messages.dart';

class _Option {
  final String key;
  final String label;
  final String? detail;
  final String complete;
  final String? path;
  final bool isDir;
  final String ext;
  const _Option({
    required this.key,
    required this.label,
    required this.complete,
    this.detail,
    this.path,
    this.isDir = false,
    this.ext = '',
  });
}

/// The Ask AI composer: multi-line field with `@file` / `#folder` / `/command`
/// autocomplete, mention chips, model chip, trigger keycaps and Send / Stop.
class AskAiComposer extends StatefulWidget {
  final FolderChatController chat;
  const AskAiComposer({super.key, required this.chat});

  @override
  State<AskAiComposer> createState() => AskAiComposerState();
}

class AskAiComposerState extends State<AskAiComposer> {
  late final AskAiSession _session = AskAiSession.of(widget.chat);
  late final HighlightingController _text = HighlightingController(text: _session.draft);
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _popup = OverlayPortalController();
  final _link = LayerLink();

  ComposerToken? _token;
  List<_Option> _options = const [];
  int _ix = 0;
  int? _dismissedStart;
  Timer? _debounce;
  int _gen = 0;
  int _shown = 0; // bumps each time the popover opens, replaying its entrance
  double _width = 600;
  ChatMessage? _editing; // the edit last loaded into the field

  FaController get _app => widget.chat.app;
  List<ChatMention> get _mentions => _session.mentions;

  @override
  void initState() {
    super.initState();
    _text.mentions = _mentions;
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _text.addListener(_onTextChanged);
    _focus.addListener(_onFocus);
    _app.addListener(_consumePending);
    widget.chat.addListener(_onChatChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _consumePending();
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _app.removeListener(_consumePending);
    widget.chat.removeListener(_onChatChanged);
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── public API (empty-state suggestions) ─────────────────────────────────
  void applySuggestion(String id) {
    switch (id) {
      case 'summarize':
        _prefill('/summarize ');
      case 'find':
        _prefill('/find ');
      case 'explain':
        _prefill('Explain @');
      case 'action':
        _prefill('Create a file called ');
    }
  }

  /// "Edit and resend": load the question (with its @/# mentions) into the field;
  /// cancelling the edit empties it again.
  void _onChatChanged() {
    final next = widget.chat.editing;
    if (identical(next, _editing)) return;
    final cancelled = _editing != null && next == null;
    _editing = next;
    if (next != null) {
      _session.mentions = List.of(_session.sentMentions[next.content.trim()] ?? const <ChatMention>[]);
      _text.mentions = _session.mentions;
      _prefill(next.content);
    } else if (cancelled) {
      _clear();
    }
  }

  void _prefill(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  void _addMention(ChatMention m) {
    if (_mentions.any((x) => x.path == m.path)) return;
    _session.mentions = [..._mentions, m];
    _text.mentions = _session.mentions;
  }

  /// Paths queued by "Ask AI about this" become @file / #folder tokens.
  void _consumePending() {
    if (_app.pendingAskAiFiles.isEmpty) return;
    final paths = List.of(_app.pendingAskAiFiles);
    _app.pendingAskAiFiles.clear();
    final tokens = <String>[];
    for (final p in paths) {
      bool isDir;
      try {
        isDir = FileSystemEntity.isDirectorySync(p);
      } catch (_) {
        isDir = false;
      }
      final m = ChatMention.forPath(p, isDir: isDir);
      _addMention(m);
      if (!_text.text.contains(m.token)) tokens.add(m.token);
    }
    final base = _text.text.trimRight();
    final next = '${base.isEmpty ? '' : '$base '}${tokens.join(' ')} ';
    _prefill(next.trimLeft());
    if (mounted) setState(() {});
  }

  // ── text / token tracking ────────────────────────────────────────────────
  void _onFocus() => _syncPopup();

  void _onTextChanged() {
    _session.draft = _text.text;
    final caret = _text.selection.isCollapsed ? _text.selection.baseOffset : -1;
    final t = caret < 0 ? null : activeToken(_text.text, caret);
    final changed = t?.trigger != _token?.trigger || t?.start != _token?.start || t?.query != _token?.query;
    _token = t;
    if (t == null) {
      _dismissedStart = null;
      _setOptions(const []);
    } else if (changed) {
      if (_dismissedStart != t.start) _dismissedStart = null;
      _loadOptions(t);
    }
    setState(() {});
  }

  void _setOptions(List<_Option> opts) {
    _options = opts;
    _ix = 0;
    _syncPopup();
  }

  bool get _popupOpen => _token != null && _options.isNotEmpty && _dismissedStart != _token!.start && _focus.hasFocus;

  void _syncPopup() {
    if (_popupOpen) {
      if (!_popup.isShowing) {
        _shown++;
        _popup.show();
      }
    } else if (_popup.isShowing) {
      _popup.hide();
    }
    if (mounted) setState(() {});
  }

  void _loadOptions(ComposerToken t) {
    _debounce?.cancel();
    final gen = ++_gen;
    final q = t.query.toLowerCase();
    if (t.trigger == '/') {
      _setOptions([
        for (final cmd in chatCommands)
          if (cmd.id.startsWith(q))
            _Option(key: cmd.id, label: '/${cmd.id}', detail: cmd.description, complete: cmd.id),
      ]);
      return;
    }
    final wantDirs = t.trigger == '#';
    final root = _app.currentFolder.isNotEmpty ? _app.currentFolder : _app.home;
    _debounce = Timer(Duration(milliseconds: q.isEmpty ? 0 : 140), () async {
      List<FsEntry> found = const [];
      if (q.isEmpty) {
        final r = await _app.api.list(root, hidden: false);
        if (r.ok) found = r.value!.entries;
      } else {
        final r = await _app.api.nameSearch(t.query, root);
        if (r.ok) found = r.value!;
      }
      if (!mounted || gen != _gen) return;
      final opts = <_Option>[
        if (wantDirs && root.isNotEmpty && (q.isEmpty || baseName(root).toLowerCase().contains(q)))
          _Option(
            key: root,
            label: baseName(root),
            detail: 'This folder',
            complete: baseName(root),
            path: root,
            isDir: true,
          ),
        for (final e in found.where((e) => e.isDir == wantDirs && !e.hidden).take(8))
          _Option(
            key: e.path,
            label: e.name,
            detail: q.isEmpty ? null : compactDir(parentDir(e.path), _app.home),
            complete: e.name,
            path: e.path,
            isDir: e.isDir,
            ext: e.ext,
          ),
      ];
      _setOptions(opts);
    });
  }

  void _pick(int ix) {
    final t = _token;
    if (t == null || ix >= _options.length) return;
    final opt = _options[ix];
    final caret = _text.selection.baseOffset;
    if (opt.path != null) _addMention(ChatMention.forPath(opt.path!, isDir: t.trigger == '#'));
    final (next, at) = completeToken(_text.text, caret, t, opt.complete);
    _dismissedStart = null;
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at),
    );
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_text.value.composing.isValid) return KeyEventResult.ignored; // IME composition
    final key = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (_popupOpen) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _ix = (_ix + 1) % _options.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _ix = (_ix - 1 + _options.length) % _options.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
        _pick(_ix);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _dismissedStart = _token?.start;
        _syncPopup();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape && widget.chat.editing != null) {
      widget.chat.cancelEdit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && !shift && _text.selection.isCollapsed) {
      final del = tokenBeforeCaret(_text.text, _text.selection.baseOffset, _mentions);
      if (del != null) {
        final (start, end, mention) = del;
        if (mention != null) {
          _session.mentions = _mentions.where((m) => m.path != mention.path).toList();
          _text.mentions = _session.mentions;
        }
        _text.value = TextEditingValue(
          text: _text.text.substring(0, start) + _text.text.substring(end),
          selection: TextSelection.collapsed(offset: start),
        );
        return KeyEventResult.handled;
      }
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && !shift) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insertTrigger(String trigger) {
    if (trigger == '/') {
      if (_text.text.trim().isNotEmpty) return;
      return _prefill('/');
    }
    final sel = _text.selection;
    final pos = sel.isValid ? sel.baseOffset.clamp(0, _text.text.length) : _text.text.length;
    final before = _text.text.substring(0, pos);
    final insert = (before.isNotEmpty && before.trimRight() == before ? ' ' : '') + trigger;
    final next = before + insert + _text.text.substring(pos);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
    _focus.requestFocus();
  }

  void _removeMention(ChatMention m) {
    _session.mentions = _mentions.where((x) => x.path != m.path).toList();
    _text.mentions = _session.mentions;
    final t = _text.text.replaceFirst('${m.token} ', '').replaceFirst(m.token, '');
    _text.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  // ── send ─────────────────────────────────────────────────────────────────
  bool get _canSend {
    final raw = _text.text.trim();
    if (raw.isEmpty || widget.chat.sending) return false;
    if (raw.startsWith('/find') || raw == '/clear') return true;
    return widget.chat.hasModel;
  }

  void _submit() {
    if (!_canSend) return;
    final message = _text.text.trim();
    final live = pruneMentions(message, _mentions);
    final files = [
      for (final m in live)
        if (!m.isFolder) m.path,
    ];
    final folders = [
      for (final m in live)
        if (m.isFolder) m.path,
    ];

    // `/clear` is a UI action; every other command (/find, /summarize) is the engine's.
    if (RegExp(r'^/clear\b', caseSensitive: false).hasMatch(message)) {
      widget.chat.newChat();
      _clear();
      return;
    }
    _session.sentMentions[message] = live;
    widget.chat.send(message, files: files, folders: folders);
    _clear();
  }

  void _clear() {
    _session.mentions = [];
    _text.mentions = const [];
    _text.clear();
    _focus.requestFocus();
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final chat = widget.chat;
    final focused = _focus.hasFocus;
    final live = pruneMentions(_text.text, _mentions);
    // FilDOS FIELD_BOX: `px-3 py-2.5 text-sm leading-5`.
    final style = FaText.sans(size: 14, color: c.foreground, height: 20 / 14);

    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth - 24;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: OverlayPortal(
            controller: _popup,
            overlayChildBuilder: _buildPopup,
            child: CompositedTransformTarget(
              link: _link,
              child: AnimatedContainer(
                duration: FaMotion.fast,
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(FaRadius.xl),
                  border: Border.all(color: focused ? Scoop.mint.withValues(alpha: 0.5) : c.border),
                  // `focus-within:ring-2 ring-mint/30` — kept as a transparent ring when
                  // unfocused so the shadow animates instead of popping.
                  boxShadow: [
                    BoxShadow(color: Scoop.mint.withValues(alpha: focused ? 0.30 : 0), blurRadius: 0, spreadRadius: 2),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (chat.editing != null) _EditingStrip(onCancel: chat.cancelEdit),
                    if (live.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [for (final m in live) MentionChip(mention: m, onRemove: () => _removeMention(m))],
                        ),
                      ),
                    TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 9, // `max-h-50`: 200px less the 20px padding
                      keyboardType: TextInputType.multiline,
                      style: style,
                      cursorColor: c.foreground,
                      cursorWidth: 1.5,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Ask to research across your files…',
                        hintStyle: style.copyWith(color: c.mutedForeground),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), // `px-2 pb-2`, `gap-1`
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _ModelChip(chat: chat),
                            ),
                          ),
                          for (final (t, tint, tip) in const [
                            ('@', Scoop.blueberry, 'Mention a file'),
                            ('#', Scoop.grape, 'Mention a folder'),
                            ('/', Scoop.mint, 'Run a command'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: _TriggerButton(
                                text: t,
                                tint: tint,
                                tooltip: tip,
                                onTap: t == '/' && _text.text.trim().isNotEmpty ? null : () => _insertTrigger(t),
                              ),
                            ),
                          const SizedBox(width: 8),
                          if (chat.sending)
                            _RoundButton(
                              tooltip: 'Stop generating',
                              filled: false,
                              onTap: chat.stop,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: c.foreground, borderRadius: BorderRadius.circular(2)),
                              ),
                            )
                          else
                            _RoundButton(
                              tooltip: 'Send',
                              filled: true,
                              onTap: _canSend ? _submit : null,
                              child: Icon(Icons.arrow_upward_rounded, size: 14, color: c.primaryForeground),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPopup(BuildContext context) {
    final c = context.fa;
    final t = _token;
    if (t == null || _options.isEmpty) return const SizedBox.shrink();
    final heading = t.trigger == '/' ? 'Commands' : (t.trigger == '#' ? 'Folders' : 'Files');
    return Positioned(
      width: _width,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -6),
        child: TextFieldTapRegion(
          // `animate-in fade-in-0 slide-in-from-bottom-1 duration-150 ease-snappy`.
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_shown),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 150),
            curve: FaMotion.snappy,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, 4 * (1 - t)), child: child),
            ),
            child: Material(
              color: Colors.transparent,
              child: FaCard(
                shadow: true,
                color: c.popover,
                padding: EdgeInsets.zero,
                radius: FaRadius.xl,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FaRadius.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.border)),
                        ),
                        child: Text(
                          heading.toUpperCase(),
                          style: FaText.sans(
                            size: 10,
                            weight: FontWeight.w500,
                            color: c.mutedForeground,
                            height: 1.5,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      for (var i = 0; i < _options.length; i++) _optionRow(context, i, t.trigger),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionRow(BuildContext context, int i, String trigger) {
    final c = context.fa;
    final o = _options[i];
    final active = i == _ix;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _ix = i),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(i),
        child: Container(
          height: 28, // `px-3 py-1.5 text-xs`
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: active ? c.accent : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: o.path != null
                    ? FileIcon(name: o.label, isDir: o.isDir, ext: o.ext, size: 16)
                    : Text(
                        '/',
                        textAlign: TextAlign.center,
                        style: FaText.mono(size: 12, weight: FontWeight.w700, color: Scoop.mint),
                      ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 0,
                child: Text(
                  o.label,
                  style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (o.detail != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    o.detail!,
                    style: (o.path != null ? FaText.mono(size: 11) : FaText.sans(size: 12)).copyWith(
                      color: c.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              if (active) ...[
                const SizedBox(width: 8),
                // `Kbd` with `bg-transparent px-1 py-px` (text-3xs).
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border),
                  ),
                  child: Text('⏎', style: FaText.mono(size: 10, color: c.mutedForeground, height: 1)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown above the field while a sent question is being edited.
class _EditingStrip extends StatelessWidget {
  final VoidCallback onCancel;
  const _EditingStrip({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 12, color: Scoop.mint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Editing — sending replaces this question and its answer',
              overflow: TextOverflow.ellipsis,
              style: FaText.sans(size: 12, color: c.mutedForeground),
            ),
          ),
          Tooltip(
            message: 'Cancel editing (Esc)',
            child: Hoverable(
              onTap: onCancel,
              builder: (context, hover) => Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: hover ? c.accent : c.accent.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(FaRadius.sm),
                ),
                child: Icon(Icons.close_rounded, size: 12, color: hover ? c.foreground : c.mutedForeground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TriggerButton extends StatelessWidget {
  final String text;
  final Color tint;
  final String tooltip;
  final VoidCallback? onTap;
  const _TriggerButton({required this.text, required this.tint, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1,
        child: Hoverable(
          onTap: onTap,
          // `rounded border px-1.5 py-0.5 font-mono text-2xs hover:bg-accent`.
          builder: (context, hover) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: hover && onTap != null ? c.accent : c.accent.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.border),
            ),
            child: Text(text, style: FaText.mono(size: 11, color: tint, height: 1.5)),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final String tooltip;
  final bool filled;
  final VoidCallback? onTap;
  final Widget child;
  const _RoundButton({required this.tooltip, required this.filled, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Hoverable(
          onTap: onTap,
          builder: (context, hover) => AnimatedContainer(
            duration: FaMotion.fast,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? c.primary : (hover ? c.accent : c.accent.withValues(alpha: 0)),
              border: filled ? null : Border.all(color: c.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The model chip — a drop-up of DeskMate's local models (+ Gemini when a key is saved).
class _ModelChip extends StatelessWidget {
  final FolderChatController chat;
  const _ModelChip({required this.chat});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final config = context.select<FaController, AiConfig>((a) => a.aiConfig);
    final cloud = config.usesGemini;
    final label = chat.modelLabel;
    final currentId = cloud ? '' : (config.effectiveModel ?? '');
    return Tooltip(
      message: 'Choose the chat model',
      child: Hoverable(
        onTap: () => _open(context, config),
        // `gap-1.5 rounded-md px-1.5 py-1 text-2xs font-medium`, muted → foreground.
        builder: (context, hover) => AnimatedContainer(
          duration: FaMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: hover ? c.accent : c.accent.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(FaRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chat.hasModel)
                ModelLogo(currentId, cloud: cloud, size: 14)
              else
                ScoopDot(c.mutedForeground.withValues(alpha: 0.4), size: 6),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: FaText.sans(
                    size: 11,
                    weight: FontWeight.w500,
                    color: hover ? c.foreground : c.mutedForeground,
                    height: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.expand_less_rounded,
                size: 12,
                color: (hover ? c.foreground : c.mutedForeground).withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, AiConfig config) {
    final app = chat.app;
    final items = <FaMenuItem>[
      if (config.installedModels.isEmpty && !config.hasGeminiKey) const FaMenuItem('No models on this device yet'),
      for (final m in config.installedModels)
        FaMenuItem(
          m,
          leading: ModelLogo(m, size: 15),
          shortcut: !config.usesGemini && m == config.effectiveModel ? '✓' : null,
          onTap: () => app.setChatModel(m),
        ),
      if (config.hasGeminiKey)
        FaMenuItem(
          config.geminiLabel,
          leading: const ModelLogo('', cloud: true, size: 15),
          shortcut: config.usesGemini ? '✓' : null,
          onTap: () => app.setChatModel(config.geminiChoice),
        ),
      const FaMenuItem.divider(),
      FaMenuItem(
        'Manage models in Settings…',
        icon: Icons.settings_outlined,
        onTap: () => chat.app.showSection(FaSection.settings),
      ),
    ];
    final box = context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    final est = items.fold<double>(8, (h, i) => h + (i.divider ? 9 : 30));
    showFaMenu(context, Offset(topLeft.dx, topLeft.dy - est - 6), items);
  }
}
