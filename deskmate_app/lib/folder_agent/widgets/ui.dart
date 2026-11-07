import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fa_theme.dart';

/// Shared Folder Agent UI primitives, ported from FilDOS's `ui/*` components
/// (button, kbd, input, dialog, dropdown-menu) value for value: quiet neutral
/// chrome, hairline borders, Cloud/Ink hover washes, scoop accents only as dots.

/// A pointer-aware region: reports hover to [builder], fires [onTap] on the
/// first click (no double-tap delay — the second click of a double-click also
/// fires [onTap], then [onDoubleTap], like DOM click/dblclick), and optionally
/// scales its child while pressed (FilDOS buttons: `active:scale-[0.97]`).
class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final MouseCursor cursor;

  /// Scale applied while the primary button is held (1 = none).
  final double pressScale;
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.cursor = SystemMouseCursors.click,
    this.pressScale = 1,
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  /// macOS's default double-click interval (browsers follow the OS setting).
  static const _doubleClick = Duration(milliseconds: 500);
  bool _hover = false;
  bool _pressed = false;
  DateTime? _lastTap;

  bool get _interactive => widget.onTap != null || widget.onDoubleTap != null;

  void _setHover(bool v) {
    if (!mounted || _hover == v) return;
    setState(() => _hover = v);
  }

  void _setPressed(bool v) {
    if (!mounted || _pressed == v || widget.pressScale == 1) return;
    setState(() => _pressed = v);
  }

  void _tap() {
    widget.onTap?.call();
    if (widget.onDoubleTap == null) return;
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) <= _doubleClick) {
      _lastTap = null;
      widget.onDoubleTap!();
    } else {
      _lastTap = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.builder(context, _hover);
    if (widget.pressScale != 1) {
      child = AnimatedScale(
        scale: _pressed && _interactive ? widget.pressScale : 1,
        duration: FaMotion.fast,
        curve: FaMotion.snappy,
        child: child,
      );
    }
    return MouseRegion(
      cursor: _interactive ? widget.cursor : MouseCursor.defer,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Listener(
        onPointerDown: (e) => _setPressed(_interactive && e.buttons == kPrimaryButton),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _interactive ? _tap : null,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: child,
        ),
      ),
    );
  }
}

enum FaIconButtonVariant { ghost, secondary }

/// Square icon button — FilDOS `<Button size="icon">`: `rounded-sm` (6px), a
/// 16px glyph, ghost = Mist glyph on a `foreground/9%` hover wash, secondary =
/// Cloud fill (`bg-secondary hover:bg-secondary/80`). Disabled = 50% opacity.
class FaIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double? iconSize;
  final bool active;
  final Color? color;
  final FaIconButtonVariant variant;

  /// Corner radius: `rounded-sm` (6) by default; pass [FaRadius.md] where
  /// FilDOS overrides with `rounded-md`.
  final double radius;
  const FaIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 28,
    this.iconSize,
    this.active = false,
    this.color,
    this.variant = FaIconButtonVariant.ghost,
    this.radius = FaRadius.sm,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final enabled = onPressed != null;
    final glyph = iconSize ?? (size >= 28 ? 16.0 : (size * 0.62).roundToDouble());
    final btn = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Hoverable(
        onTap: onPressed,
        pressScale: 0.97,
        builder: (context, hover) {
          final hot = enabled && hover;
          final Color bg;
          final Color fg;
          switch (variant) {
            case FaIconButtonVariant.ghost:
              bg = active || hot ? c.wash : c.wash.withValues(alpha: 0);
              fg = color ?? (active || hot ? c.foreground : c.mutedForeground);
            case FaIconButtonVariant.secondary:
              bg = hot ? c.muted.withValues(alpha: 0.8) : c.muted;
              fg = color ?? c.foreground;
          }
          return AnimatedContainer(
            duration: FaMotion.fast,
            curve: FaMotion.snappy,
            width: size,
            height: size,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
            child: Icon(icon, size: glyph, color: fg),
          );
        },
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

enum FaButtonVariant { primary, secondary, ghost, outline, destructive }

/// FilDOS `<Button>`: `rounded-sm` (6px), `text-sm` (14px, regular weight),
/// 16px icons; default size h-9 / px-4 (px-3 with an icon), [dense] = `sm`
/// h-8 / px-3 (px-2.5 with an icon) / gap-1.5. Colour transitions take 150ms
/// and the button presses down to 97%.
class FaButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final FaButtonVariant variant;
  final bool dense;
  final bool expand;
  const FaButton({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.onPressed,
    this.variant = FaButtonVariant.secondary,
    this.dense = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final enabled = onPressed != null;
    final hasGlyph = icon != null || leading != null;
    final gap = dense ? 6.0 : 8.0;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Hoverable(
        onTap: onPressed,
        pressScale: 0.97,
        builder: (context, hover) {
          final hot = enabled && hover;
          final (Color bg, Color fg, Color border, List<BoxShadow>? shadow) = switch (variant) {
            FaButtonVariant.primary => (
              hot ? c.primary.withValues(alpha: 0.9) : c.primary,
              c.primaryForeground,
              Colors.transparent,
              FaShadow.xs,
            ),
            FaButtonVariant.secondary => (
              hot ? c.muted.withValues(alpha: 0.8) : c.muted,
              c.foreground,
              Colors.transparent,
              null,
            ),
            FaButtonVariant.ghost => (
              hot ? c.wash : c.wash.withValues(alpha: 0),
              hot ? c.foreground : c.mutedForeground,
              Colors.transparent,
              null,
            ),
            FaButtonVariant.outline => (
              c.isDark ? c.input.withValues(alpha: hot ? 0.5 : 0.3) : (hot ? c.accent : c.background),
              c.foreground,
              c.isDark ? c.input : c.border,
              FaShadow.xs,
            ),
            FaButtonVariant.destructive => (
              c.destructive.withValues(alpha: (c.isDark ? 0.6 : 1) * (hot ? 0.9 : 1)),
              Colors.white,
              Colors.transparent,
              FaShadow.xs,
            ),
          };
          return AnimatedContainer(
            duration: FaMotion.fast,
            curve: FaMotion.snappy,
            height: dense ? 32 : 36,
            padding: EdgeInsets.symmetric(horizontal: dense ? (hasGlyph ? 10 : 12) : (hasGlyph ? 12 : 16)),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(FaRadius.sm),
              border: Border.all(color: border),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, SizedBox(width: gap)],
                if (icon != null) ...[Icon(icon, size: 16, color: fg), SizedBox(width: gap)],
                Text(
                  label,
                  style: FaText.sans(size: 14, color: fg, height: 20 / 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A coloured dot (tags, scoop legend) — FilDOS `TagDot`.
class ScoopDot extends StatelessWidget {
  final Color color;
  final double size;
  const ScoopDot(this.color, {super.key, this.size = 9});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Pill chip used for filters (search kinds, canvas edge types).
class FaChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? dot;
  final IconData? icon;
  const FaChip({super.key, required this.label, this.selected = false, this.onTap, this.dot, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? c.accent : (hover ? c.accent.withValues(alpha: 0.6) : Colors.transparent),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.mutedForeground.withValues(alpha: 0.35) : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[ScoopDot(dot!, size: 7), const SizedBox(width: 6)],
            if (icon != null) ...[Icon(icon, size: 13, color: c.mutedForeground), const SizedBox(width: 5)],
            Text(
              label,
              style: FaText.sans(
                size: 12,
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? c.foreground : c.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum KbdVariant {
  /// Bordered muted keycap (menus, lists).
  normal,

  /// Keycap with the printed-key bottom shadow.
  raised,

  /// Borderless, for keys tucked inside another tinted control.
  ghost,

  /// The title-bar search pill's keycap: `border-border/70 bg-transparent px-1`.
  outline,
}

/// Keyboard hint ("⌘K", "esc") — FilDOS `<Kbd>`: Space Mono 10px, leading-none,
/// `rounded` (4px), `px-1.5 py-0.5`; a leading ⌘ renders as the 10px command glyph.
class Kbd extends StatelessWidget {
  final String text;
  final KbdVariant variant;
  const Kbd(this.text, {super.key, this.variant = KbdVariant.normal});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final style = FaText.mono(size: 10, color: c.mutedForeground, height: 1);
    final cmd = text.startsWith('⌘') && text.length > 1;
    final label = cmd
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_command_key, size: 10, color: c.mutedForeground),
              const SizedBox(width: 2),
              Text(text.substring(1), style: style),
            ],
          )
        : Text(text, style: style);
    if (variant == KbdVariant.ghost) return label;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: variant == KbdVariant.outline ? 4 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: switch (variant) {
          KbdVariant.normal => c.muted,
          KbdVariant.raised => c.background,
          _ => Colors.transparent,
        },
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: variant == KbdVariant.outline ? c.border.withValues(alpha: 0.7) : c.border),
        boxShadow: variant == KbdVariant.raised ? [BoxShadow(color: c.border, offset: const Offset(0, 1))] : null,
      ),
      child: label,
    );
  }
}

/// Hairline card surface (popovers, panels, dialogs).
class FaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool shadow;
  const FaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = FaRadius.lg,
    this.color,
    this.shadow = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.border),
        boxShadow: shadow ? FaShadow.lg : null,
      ),
      child: child,
    );
  }
}

/// FilDOS's `.material`: a floating surface (menus, toasts) painted as
/// popover at 92% over a 24px blurred, saturated backdrop.
class FaMaterial extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final List<BoxShadow> shadow;
  const FaMaterial({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = FaRadius.md,
    this.shadow = FaShadow.md,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: shadow),
      // Popovers live in overlays above the Scaffold: a transparent Material
      // gives their rows ink and text defaults.
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: c.popover.withValues(alpha: 0.92),
                borderRadius: r,
                border: Border.all(color: c.border),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Section label ("QUICK ACCESS") — FilDOS sidebar title: `px-2 pb-2
/// text-3xs font-semibold tracking-wider uppercase`, `mt-3` after the first.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final double top;
  const SectionLabel(this.text, {super.key, this.trailing, this.top = 12});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(8, top, 8, 8),
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: FaText.label(context.fa))),
        ?trailing,
      ],
    ),
  );
}

/// Thin progress bar (drive capacity, downloads, indexing).
class FaProgressBar extends StatelessWidget {
  final double? value;
  final Color? color;
  final Color? background;
  final double height;
  const FaProgressBar({super.key, this.value, this.color, this.background, this.height = 3});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: background ?? c.border,
        valueColor: AlwaysStoppedAnimation(color ?? c.mutedForeground),
      ),
    );
  }
}

// ── Menus (FilDOS dropdown-menu / ContextMenu surface) ──────────────────────

class FaMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool destructive;
  final bool divider;
  final Widget? leading;
  final Widget? trailing;
  final List<FaMenuItem>? submenu;

  /// Run [onTap] but keep the menu open (FilDOS's `preventDefault` items:
  /// sort keys, toggles inside the View menu).
  final bool keepOpen;

  /// A section caption (`DropdownMenuLabel`).
  final bool isLabel;

  /// Free-form content (e.g. the View menu's layout tiles).
  final WidgetBuilder? custom;

  const FaMenuItem(
    this.label, {
    this.icon,
    this.onTap,
    this.shortcut,
    this.destructive = false,
    this.leading,
    this.trailing,
    this.submenu,
    this.keepOpen = false,
  }) : divider = false,
       isLabel = false,
       custom = null;
  const FaMenuItem.divider()
    : label = '',
      icon = null,
      onTap = null,
      shortcut = null,
      destructive = false,
      divider = true,
      leading = null,
      trailing = null,
      submenu = null,
      keepOpen = false,
      isLabel = false,
      custom = null;
  const FaMenuItem.label(this.label)
    : icon = null,
      onTap = null,
      shortcut = null,
      destructive = false,
      divider = false,
      leading = null,
      trailing = null,
      submenu = null,
      keepOpen = false,
      isLabel = true,
      custom = null;
  const FaMenuItem.custom(WidgetBuilder this.custom)
    : label = '',
      icon = null,
      onTap = null,
      shortcut = null,
      destructive = false,
      divider = false,
      leading = null,
      trailing = null,
      submenu = null,
      keepOpen = false,
      isLabel = false;

  bool get _actionable => !divider && !isLabel && custom == null && (onTap != null || submenu != null);
}

/// Shows a FilDOS-style menu anchored at [position] (global coordinates): it
/// opens 4px below the point (above it when there's no room), left-aligned —
/// or right-aligned to the point with [alignEnd] (the View menu). Submenus
/// open on hover like Radix's, the keyboard moves the highlight (↑ ↓ → ←,
/// Enter, Esc), and any click outside closes it.
///
/// For a menu that stays open and reflects live state (keepOpen items), pass
/// [builder] + [listenable] instead of [items].
Future<void> showFaMenu(
  BuildContext context,
  Offset position,
  List<FaMenuItem> items, {
  bool alignEnd = false,
  double minWidth = 208,
  List<FaMenuItem> Function()? builder,
  Listenable? listenable,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(position);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: FaMotion.fast,
    pageBuilder: (ctx, _, _) => _MenuLayer(
      anchor: local,
      alignEnd: alignEnd,
      minWidth: minWidth,
      items: builder ?? () => items,
      listenable: listenable,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: FaMotion.snappy);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(curved),
          alignment: _scaleOrigin(ctx, local, alignEnd),
          child: child,
        ),
      );
    },
  );
}

Alignment _scaleOrigin(BuildContext ctx, Offset at, bool alignEnd) {
  final size = MediaQuery.sizeOf(ctx);
  if (size.isEmpty) return Alignment.topLeft;
  return Alignment(at.dx / size.width * 2 - 1, at.dy / size.height * 2 - 1);
}

class _MenuLevel {
  final List<FaMenuItem> Function() items;
  final Rect anchor;
  final bool sub;
  final FaMenuItem? parent;
  int? highlight;
  _MenuLevel(this.items, this.anchor, {this.sub = false, this.parent});
}

class _MenuLayer extends StatefulWidget {
  final Offset anchor;
  final bool alignEnd;
  final double minWidth;
  final List<FaMenuItem> Function() items;
  final Listenable? listenable;
  const _MenuLayer({
    required this.anchor,
    required this.alignEnd,
    required this.minWidth,
    required this.items,
    this.listenable,
  });

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  late final List<_MenuLevel> _levels = [_MenuLevel(widget.items, Rect.fromPoints(widget.anchor, widget.anchor))];
  final _focus = FocusNode(debugLabel: 'fa-menu');
  Timer? _closeSub;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_rebuild);
    _closeSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _hoverRow(int level, int index, Rect rect) {
    _closeSub?.cancel();
    final lv = _levels[level];
    final item = lv.items()[index];
    setState(() => lv.highlight = index);
    if (item.submenu != null) {
      if (_levels.length > level + 1 && _levels[level + 1].parent == item) return;
      setState(() {
        _levels.removeRange(level + 1, _levels.length);
        _levels.add(_MenuLevel(() => item.submenu!, rect, sub: true, parent: item));
      });
    } else if (_levels.length > level + 1) {
      // Radix's pointer grace: give a diagonal move toward the open submenu a
      // moment before it closes.
      _closeSub = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(() => _levels.removeRange(level + 1, _levels.length));
      });
    }
  }

  void _leavePanel(int level) {
    final lv = _levels[level];
    // Keep the trigger of an open submenu highlighted (`data-[state=open]:bg-accent`).
    final keep = _levels.length > level + 1 ? lv.items().indexOf(_levels[level + 1].parent!) : null;
    if (lv.highlight != keep) setState(() => lv.highlight = keep);
  }

  void _enterPanel(int level) => _closeSub?.cancel();

  void _activate(int level, int index, Rect? rect) {
    final item = _levels[level].items()[index];
    if (!item._actionable) return;
    if (item.submenu != null) {
      if (rect != null) _hoverRow(level, index, rect);
      return;
    }
    if (item.keepOpen) {
      item.onTap?.call();
      _rebuild();
      return;
    }
    _close();
    item.onTap?.call();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final level = _levels.length - 1;
    final lv = _levels[level];
    final items = lv.items();
    final key = e.logicalKey;
    int? step(int from, int dir) {
      for (var i = 1; i <= items.length; i++) {
        final j = (from + dir * i) % items.length;
        final k = j < 0 ? j + items.length : j;
        if (items[k]._actionable) return k;
      }
      return null;
    }

    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final dir = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final next = step(lv.highlight ?? (dir > 0 ? -1 : items.length), dir);
      setState(() => lv.highlight = next);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || (key == LogicalKeyboardKey.arrowLeft && lv.sub)) {
      if (lv.sub) {
        setState(() => _levels.removeLast());
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    final hi = lv.highlight;
    if (hi == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowRight && items[hi].submenu != null) {
      final rect = _rowRects[(level, hi)];
      if (rect != null) {
        _hoverRow(level, hi, rect);
        setState(() => _levels.last.highlight = step(-1, 1));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      _activate(level, hi, _rowRects[(level, hi)]);
      if (items[hi].submenu != null) setState(() => _levels.last.highlight = step(-1, 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  final Map<(int, int), Rect> _rowRects = {};

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // Radix closes on pointer-down outside — any button, not just a click.
          Positioned.fill(
            child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => _close()),
          ),
          for (var i = 0; i < _levels.length; i++)
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _MenuPosition(_levels[i].anchor, sub: _levels[i].sub, alignEnd: widget.alignEnd && i == 0),
                child: _MenuAppear(
                  key: ObjectKey(_levels[i]),
                  animate: i > 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: i == 0 ? widget.minWidth : 128,
                      maxWidth: 360,
                      maxHeight: size.height - 16,
                    ),
                    child: MouseRegion(
                      onEnter: (_) => _enterPanel(i),
                      onExit: (_) => _leavePanel(i),
                      child: _panel(context, i),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, int level) {
    final c = context.fa;
    final lv = _levels[level];
    final items = lv.items();
    return IntrinsicWidth(
      child: FaMaterial(
        shadow: lv.sub ? FaShadow.lg : FaShadow.md,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                if (items[i].divider)
                  // `-mx-1 my-1 h-px`: the separator runs edge to edge.
                  Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: c.border)
                else if (items[i].isLabel)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Text(
                      items[i].label.toUpperCase(),
                      style: FaText.sans(
                        size: 11,
                        weight: FontWeight.w600,
                        color: c.mutedForeground,
                        letterSpacing: 0.55,
                        height: 20 / 11,
                      ),
                    ),
                  )
                else if (items[i].custom != null)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: items[i].custom!(context))
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _MenuRow(
                      item: items[i],
                      highlighted: lv.highlight == i,
                      onRect: (r) => _rowRects[(level, i)] = r,
                      onHover: (r) => _hoverRow(level, i, r),
                      onTap: (r) => _activate(level, i, r),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Positions a menu panel against its anchor, flipping/shifting to stay on screen.
class _MenuPosition extends SingleChildLayoutDelegate {
  final Rect anchor;
  final bool sub;
  final bool alignEnd;
  const _MenuPosition(this.anchor, {required this.sub, required this.alignEnd});

  static const _pad = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    double left;
    double top;
    if (sub) {
      // side="right" align="start", flush against the trigger row; flip left.
      left = anchor.right;
      if (left + child.width > size.width - _pad) left = anchor.left - child.width;
      top = anchor.top - 5; // border 1 + padding 4: first row lines up with the trigger
    } else {
      left = alignEnd ? anchor.left - child.width : anchor.left;
      top = anchor.bottom + 4; // sideOffset 4
      if (top + child.height > size.height - _pad && anchor.top - 4 - child.height >= _pad) {
        top = anchor.top - 4 - child.height;
      }
    }
    left = left.clamp(_pad, (size.width - child.width - _pad).clamp(_pad, double.infinity));
    top = top.clamp(_pad, (size.height - child.height - _pad).clamp(_pad, double.infinity));
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_MenuPosition old) => old.anchor != anchor || old.sub != sub || old.alignEnd != alignEnd;
}

/// Submenus fade + zoom in from 95% over 150ms (`zoom-in-95 duration-150`).
class _MenuAppear extends StatelessWidget {
  final Widget child;
  final bool animate;
  const _MenuAppear({super.key, required this.child, required this.animate});
  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: FaMotion.fast,
      curve: FaMotion.snappy,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.scale(scale: 0.95 + 0.05 * v, alignment: Alignment.topLeft, child: child),
      ),
      child: child,
    );
  }
}

/// A menu row — `DropdownMenuItem`: `rounded-sm px-2 py-1.5 gap-2 text-sm`,
/// 16px Mist icon, `focus:bg-accent` (destructive: `bg-destructive/10`, 20% in
/// dark mode), disabled at 50%, shortcut in `text-xs tracking-widest`.
class _MenuRow extends StatelessWidget {
  final FaMenuItem item;
  final bool highlighted;
  final ValueChanged<Rect> onRect;
  final ValueChanged<Rect> onHover;
  final ValueChanged<Rect> onTap;
  const _MenuRow({
    required this.item,
    required this.highlighted,
    required this.onRect,
    required this.onHover,
    required this.onTap,
  });

  Rect _rect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final enabled = item._actionable;
    final fg = item.destructive ? c.destructive : c.foreground;
    final iconColor = item.destructive ? c.destructive : c.mutedForeground;
    final bg = !highlighted || !enabled
        ? Colors.transparent
        : item.destructive
        ? c.destructive.withValues(alpha: c.isDark ? 0.2 : 0.1)
        : c.accent;
    return Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) onRect(_rect(context));
        });
        return Opacity(
          opacity: enabled ? 1 : 0.5,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: enabled ? (_) => onHover(_rect(context)) : null,
            onHover: enabled && !highlighted ? (_) => onHover(_rect(context)) : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => onTap(_rect(context)) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(FaRadius.sm)),
                child: Row(
                  children: [
                    if (item.leading != null) ...[item.leading!, const SizedBox(width: 8)],
                    if (item.leading == null && item.icon != null) ...[
                      Icon(item.icon, size: 16, color: iconColor),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 14, color: fg, height: 20 / 14),
                      ),
                    ),
                    if (item.trailing != null) ...[const SizedBox(width: 8), item.trailing!],
                    if (item.shortcut != null) ...[
                      const SizedBox(width: 8),
                      Text(item.shortcut!, style: FaText.sans(size: 12, color: c.mutedForeground, letterSpacing: 1.2)),
                    ],
                    if (item.submenu != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, size: 16, color: c.foreground),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "⌘K" on macOS, "Ctrl+K" elsewhere.
String shortcutLabel(String key) => '${Platform.isMacOS ? '⌘' : 'Ctrl+'}$key';

/// Is the platform "primary" modifier (⌘ on macOS, Ctrl elsewhere) held?
bool isPrimaryModifierPressed() {
  final keys = HardwareKeyboard.instance;
  return keys.isMetaPressed || keys.isControlPressed;
}

// ── Dialogs (FilDOS ui/dialog + Dialog.tsx) ─────────────────────────────────

/// Shows a FilDOS dialog: a `bg-black/40 backdrop-blur-sm` scrim and a centred
/// `bg-card rounded-lg border p-5 shadow-lg` panel, max 448px wide, fading and
/// zooming in from 95% over 200ms.
Future<T?> showFaDialog<T>(BuildContext context, {required WidgetBuilder builder, double maxWidth = 448}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dialog',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            type: MaterialType.transparency,
            child: _DialogPanel(child: Builder(builder: builder)),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: FaMotion.snappy);
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: curved,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: ColoredBox(color: ctx.fa.dialogScrim),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(curved), child: child),
          ),
        ],
      );
    },
  );
}

class _DialogPanel extends StatelessWidget {
  final Widget child;
  const _DialogPanel({required this.child});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.lg),
        border: Border.all(color: c.border),
        boxShadow: FaShadow.lg,
      ),
      child: child,
    );
  }
}

/// `DialogTitle`: `text-lg leading-none font-medium`.
class FaDialogTitle extends StatelessWidget {
  final String text;
  const FaDialogTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: FaText.sans(size: 18, weight: FontWeight.w500, color: context.fa.foreground, height: 1),
  );
}

/// Single-line text prompt — FilDOS `PromptDialog` (New Folder / New File /
/// New Tag / rename): title, an optional label over the field, Cancel
/// (outline) + confirm (primary, disabled while empty). The name part of
/// [initial] (before its extension) starts selected.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirm = 'OK',
  String? hint,
  String? label,
}) async {
  final controller = TextEditingController(text: initial);
  final dot = initial.lastIndexOf('.');
  controller.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : initial.length);
  final result = await showFaDialog<String>(
    context,
    builder: (ctx) {
      final c = ctx.fa;
      void submit() {
        final v = controller.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FaDialogTitle(title),
          const SizedBox(height: 16),
          if (label != null) ...[
            Text(
              label,
              style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground, height: 1),
            ),
            const SizedBox(height: 8),
          ],
          FaTextField(controller: controller, hint: hint, autofocus: true, onSubmitted: (_) => submit()),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FaButton(label: 'Cancel', variant: FaButtonVariant.outline, onPressed: () => Navigator.pop(ctx)),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, v, _) => FaButton(
                  label: confirm,
                  variant: FaButtonVariant.primary,
                  onPressed: v.text.trim().isEmpty ? null : submit,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  // Dispose after the exit transition has stopped using the field.
  Future.delayed(const Duration(milliseconds: 300), controller.dispose);
  return result;
}

/// FilDOS `ConfirmDialog` (Delete…): title, Mist message, Cancel (outline) and
/// the named confirm action (destructive when [danger]); Enter confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool danger = false,
}) async {
  final ok = await showFaDialog<bool>(
    context,
    builder: (ctx) {
      final c = ctx.fa;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.pop(ctx, true),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () => Navigator.pop(ctx, true),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FaDialogTitle(title),
              const SizedBox(height: 8),
              Text(
                message,
                style: FaText.sans(size: 14, color: c.mutedForeground, height: 20 / 14),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FaButton(
                    label: 'Cancel',
                    variant: FaButtonVariant.outline,
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                  const SizedBox(width: 8),
                  FaButton(
                    label: confirm,
                    variant: danger ? FaButtonVariant.destructive : FaButtonVariant.primary,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

/// FilDOS `<Input>`: h-9, `rounded-sm` (6px), `border-input`, transparent
/// (dark: `input/30`), `px-3 text-sm`, `shadow-xs`; focused: `border-ring` +
/// a 3px `ring/50` halo. [dense] trims it to 32px.
class FaTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final Widget? prefix;
  final bool dense;
  final bool mono;
  const FaTextField({
    super.key,
    this.controller,
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.prefix,
    this.dense = false,
    this.mono = false,
  });

  @override
  State<FaTextField> createState() => _FaTextFieldState();
}

class _FaTextFieldState extends State<FaTextField> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_sync);
  }

  @override
  void didUpdateWidget(FaTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_sync);
      _node.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    _node.removeListener(_sync);
    _own?.dispose();
    super.dispose();
  }

  void _sync() {
    if (mounted && _focused != _node.hasFocus) setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final style = widget.mono
        ? FaText.mono(size: 12, color: c.foreground)
        : FaText.sans(size: 14, color: c.foreground, height: 20 / 14);
    return AnimatedContainer(
      duration: FaMotion.fast,
      height: widget.dense ? 32 : 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.isDark ? c.input.withValues(alpha: 0.3) : Colors.transparent,
        borderRadius: BorderRadius.circular(FaRadius.sm),
        border: Border.all(color: _focused ? c.ring : c.input),
        boxShadow: _focused ? [BoxShadow(color: c.ring.withValues(alpha: 0.5), spreadRadius: 3)] : FaShadow.xs,
      ),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autofocus,
        focusNode: _node,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        style: style,
        cursorColor: c.foreground,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isDense: true,
          isCollapsed: widget.prefix == null,
          hintText: widget.hint,
          hintStyle: style.copyWith(color: c.mutedForeground),
          prefixIcon: widget.prefix,
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// Text with «marked» spans on a light Mint wash (search snippets).
class MarkedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;

  /// The highlight wash: Mint 25% (previews, FilDOS `bg-mint/25`) unless given
  /// (search rows use a faint ink wash, FilDOS `bg-primary/10`).
  final Color? markColor;
  const MarkedText(this.text, {super.key, required this.style, this.maxLines = 1, this.markColor});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final re = RegExp('«([^»]*)»');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          // FilDOS `<mark class="bg-mint/25 text-foreground">`.
          style: style.copyWith(
            color: markColor == null ? null : context.fa.foreground,
            background: Paint()..color = markColor ?? Scoop.mint.withValues(alpha: 0.25),
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
