import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'file_preview.dart';

/// Quick Look (FilDOS `QuickLook`): a look at [entry] without opening another
/// app. Every file shows on the same fixed stage, so stepping through a folder
/// with the arrow keys never makes the window jump. Space or Esc closes it;
/// ↑/↓ (and ←/→) step through the folder's items and the selection follows.
Future<void> showQuickLook(BuildContext context, FsEntry entry) {
  final app = context.read<FaController>();
  final ex = context.read<ExplorerController>();
  final theme = Theme.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Quick Look',
    barrierColor: Colors.transparent,
    // Radix dialog: fade + zoom 95%, 200ms ease-snappy, in and out.
    transitionDuration: const Duration(milliseconds: 200),
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
        child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(t), child: child),
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

  /// Move the selection by [delta] items (Quick Look follows it), clamped at the ends.
  void _step(int delta) {
    final ex = context.read<ExplorerController>();
    final visible = ex.entries;
    final i = visible.indexWhere((e) => e.path == _entry.path);
    if (i < 0) return; // shown from elsewhere: nowhere to step
    final next = visible[(i + delta).clamp(0, visible.length - 1)];
    if (next.path == _entry.path) return;
    setState(() => _entry = next);
    ex.select(next);
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _openExternally() async {
    final app = context.read<FaController>();
    final r = await app.api.open(_entry.path);
    if (!r.ok) app.toastError(r.error);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // These keys are Quick Look's: nothing else may act on them too.
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.escape) {
      if (e is KeyDownEvent) _close();
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
    final e = _entry;
    final meta = e.isDir ? formatDate(e.mtime) : '${formatBytes(e.size)} · ${formatDate(e.mtime)}';
    final hint = FaText.sans(size: 11, color: c.mutedForeground);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // bg-black/40 + backdrop-blur-sm; a click outside closes.
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              // w-[min(880px,calc(100vw-4rem))]
              width: math.min(880.0, size.width - 64),
              child: Material(
                type: MaterialType.transparency,
                // bg-card border rounded-lg p-5 gap-4 shadow-lg.
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(FaRadius.lg),
                    border: Border.all(color: c.border),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A000000), blurRadius: 15, spreadRadius: -3, offset: Offset(0, 10)),
                      BoxShadow(color: Color(0x1A000000), blurRadius: 6, spreadRadius: -4, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 32),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(
                                    e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: FaText.sans(size: 14, color: c.foreground, height: 20 / 14),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(meta, style: FaText.mono(size: 10, color: c.mutedForeground)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            // h-[min(560px,calc(100vh-13rem))]
                            height: math.max(120.0, math.min(560.0, size.height - 208)),
                            child: FilePreview(key: ValueKey(e.path), entry: e),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 32,
                            child: Row(
                              children: [
                                const Kbd('↑'),
                                const SizedBox(width: 6),
                                const Kbd('↓'),
                                const SizedBox(width: 6),
                                Text('next file', style: hint),
                                const SizedBox(width: 14),
                                const Kbd('space'),
                                const SizedBox(width: 6),
                                Text('close', style: hint),
                                const Spacer(),
                                _SecondaryButton(label: 'Open', onTap: _openExternally),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // The dialog's close button: top-4 right-4 of the card, 16px, opacity .7 → 1.
                      Positioned(top: -4, right: -4, child: _CloseButton(onTap: _close)),
                    ],
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

/// FilDOS `Button size="sm" variant="secondary"`.
class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: FaMotion.snappy,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: hover ? 0.8 : 1),
          borderRadius: BorderRadius.circular(FaRadius.sm),
        ),
        child: Text(label, style: FaText.sans(size: 14, color: c.foreground)),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: 'Close',
      child: Hoverable(
        cursor: SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hover) => AnimatedOpacity(
          opacity: hover ? 1 : 0.7,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(width: 16, height: 16, child: Icon(Icons.close_rounded, size: 16, color: c.foreground)),
        ),
      ),
    );
  }
}
