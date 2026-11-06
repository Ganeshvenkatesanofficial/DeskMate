import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'file_preview.dart';
import 'x_common.dart';

/// Quick Look: a look at [entry] without opening another app. Space or Esc
/// closes it; ←/→ (and ↑/↓) step through the files of the current folder and
/// the explorer selection follows.
Future<void> showQuickLook(BuildContext context, FsEntry entry) {
  final app = context.read<FaController>();
  final ex = context.read<ExplorerController>();
  final theme = Theme.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Quick Look',
    barrierColor: Colors.transparent,
    transitionDuration: FaMotion.medium,
    pageBuilder: (_, _, _) => Theme(
      data: theme,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<FaController>.value(value: app),
          ChangeNotifierProvider<ExplorerController>.value(value: ex),
        ],
        child: _QuickLook(initial: entry),
      ),
    ),
    transitionBuilder: (context, anim, _, child) {
      final t = CurvedAnimation(parent: anim, curve: FaMotion.snappy);
      return FadeTransition(
        opacity: t,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(t), child: child),
      );
    },
  );
}

class _QuickLook extends StatefulWidget {
  final FsEntry initial;
  const _QuickLook({required this.initial});

  @override
  State<_QuickLook> createState() => _QuickLookState();
}

class _QuickLookState extends State<_QuickLook> {
  late FsEntry _entry = widget.initial;
  final _focus = FocusNode(debugLabel: 'QuickLook');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<FsEntry> get _files => context.read<ExplorerController>().entries.where((e) => !e.isDir).toList();

  void _step(int delta) {
    final files = _files;
    final i = files.indexWhere((e) => e.path == _entry.path);
    if (i < 0 || files.isEmpty) return;
    final next = files[(i + delta).clamp(0, files.length - 1)];
    if (next.path == _entry.path) return;
    setState(() => _entry = next);
    context.read<ExplorerController>().select(next);
  }

  void _close() => Navigator.of(context).maybePop();

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (e is KeyDownEvent && (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.escape)) {
      _close();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp) {
      _step(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final size = MediaQuery.sizeOf(context);
    final files = context.watch<ExplorerController>().entries.where((e) => !e.isDir).toList();
    final index = files.indexWhere((e) => e.path == _entry.path);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // Blurred, dimmed backdrop; a click outside closes.
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: ColoredBox(color: c.overlay),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: (size.width * 0.8).clamp(360.0, 1400.0),
              height: (size.height * 0.8).clamp(320.0, 1100.0),
              child: Material(
                color: Colors.transparent,
                child: FaCard(
                  shadow: true,
                  radius: FaRadius.xl,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FaRadius.xl),
                    child: Column(
                      children: [
                        _TitleBar(entry: _entry, onClose: _close),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: KeyedSubtree(
                              key: ValueKey(_entry.path),
                              child: FilePreview(entry: _entry),
                            ),
                          ),
                        ),
                        _Footer(
                          position: index < 0 ? null : '${index + 1} of ${files.length}',
                          canPrev: index > 0,
                          canNext: index >= 0 && index < files.length - 1,
                          onPrev: () => _step(-1),
                          onNext: () => _step(1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  final FsEntry entry;
  final VoidCallback onClose;
  const _TitleBar({required this.entry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    final meta = entry.isDir ? formatDate(entry.mtime) : '${formatBytes(entry.size)} · ${formatDate(entry.mtime)}';
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          FileIcon.entry(entry, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.name,
                    overflow: TextOverflow.ellipsis,
                    style: FaText.sans(size: 13.5, weight: FontWeight.w600, color: c.foreground),
                  ),
                ),
                const SizedBox(width: 10),
                Text(meta, style: FaText.mono(size: 10.5, color: c.mutedForeground)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FaButton(
            label: 'Open with default app',
            icon: Icons.open_in_new_rounded,
            dense: true,
            onPressed: () async {
              final r = await app.api.open(entry.path);
              if (!r.ok) app.toastError(r.error);
            },
          ),
          const SizedBox(width: 4),
          FaIconButton(
            icon: Icons.folder_open_outlined,
            tooltip: revealLabel(app),
            onPressed: () => ex.reveal(entry.path),
          ),
          FaIconButton(icon: Icons.close_rounded, tooltip: 'Close (Esc)', onPressed: onClose),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final String? position;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _Footer({
    required this.position,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final hint = FaText.sans(size: 11.5, color: c.mutedForeground);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          const Kbd('←'),
          const SizedBox(width: 4),
          const Kbd('→'),
          const SizedBox(width: 6),
          Text('next file', style: hint),
          const SizedBox(width: 14),
          const Kbd('space'),
          const SizedBox(width: 6),
          Text('close', style: hint),
          const Spacer(),
          if (position != null) ...[
            FaIconButton(icon: Icons.chevron_left_rounded, tooltip: 'Previous', onPressed: canPrev ? onPrev : null),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(position!, style: FaText.mono(size: 10.5, color: c.mutedForeground)),
            ),
            FaIconButton(icon: Icons.chevron_right_rounded, tooltip: 'Next', onPressed: canNext ? onNext : null),
          ],
        ],
      ),
    );
  }
}
