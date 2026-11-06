import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fa_theme.dart';

/// Shared Folder Agent UI primitives (FilDOS look: quiet neutral chrome,
/// hairline borders, Cloud/Ink hover washes, scoop accents only as dots).

class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final MouseCursor cursor;
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null && widget.onDoubleTap == null ? MouseCursor.defer : widget.cursor,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      child: widget.builder(context, _hover),
    ),
  );
}

/// Square icon button used in the title bar and toolbars.
class FaIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool active;
  final Color? color;
  const FaIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 28,
    this.active = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final enabled = onPressed != null;
    final btn = Hoverable(
      onTap: onPressed,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? c.accent : (hover && enabled ? c.accent : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.sm),
        ),
        child: Icon(
          icon,
          size: size * 0.55,
          color: !enabled
              ? c.mutedForeground.withValues(alpha: 0.4)
              : (color ?? (active || hover ? c.foreground : c.mutedForeground)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

enum FaButtonVariant { primary, secondary, ghost, outline, destructive }

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
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Hoverable(
        onTap: onPressed,
        builder: (context, hover) {
          final (bg, fg, border) = switch (variant) {
            FaButtonVariant.primary => (
              hover ? c.primary.withValues(alpha: 0.88) : c.primary,
              c.primaryForeground,
              Colors.transparent,
            ),
            FaButtonVariant.secondary => (hover ? c.border : c.muted, c.foreground, Colors.transparent),
            FaButtonVariant.ghost => (hover ? c.accent : Colors.transparent, c.foreground, Colors.transparent),
            FaButtonVariant.outline => (hover ? c.accent : Colors.transparent, c.foreground, c.border),
            FaButtonVariant.destructive => (
              hover ? c.destructive.withValues(alpha: 0.9) : c.destructive,
              Colors.white,
              Colors.transparent,
            ),
          };
          return AnimatedContainer(
            duration: FaMotion.fast,
            height: dense ? 28 : 34,
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(FaRadius.md),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 7)],
                if (icon != null) ...[Icon(icon, size: dense ? 14 : 15, color: fg), const SizedBox(width: 7)],
                Text(label, style: FaText.sans(size: dense ? 12 : 13, weight: FontWeight.w500, color: fg)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A coloured dot (tags, scoop legend).
class ScoopDot extends StatelessWidget {
  final Color color;
  final double size;
  const ScoopDot(this.color, {super.key, this.size = 8});
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

/// Keyboard hint ("⌘K", "esc").
class Kbd extends StatelessWidget {
  final String text;
  const Kbd(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: FaText.mono(size: 10, color: c.mutedForeground)),
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
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isDark ? 0.5 : 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Section label ("QUICK ACCESS").
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 8, 6),
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
  final double height;
  const FaProgressBar({super.key, this.value, this.color, this.height = 3});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: c.border,
        valueColor: AlwaysStoppedAnimation(color ?? c.mutedForeground),
      ),
    );
  }
}

// ── Context menus ──────────────────────────────────────────────────────────

class FaMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool destructive;
  final bool divider;
  final Widget? leading;
  final List<FaMenuItem>? submenu;
  const FaMenuItem(
    this.label, {
    this.icon,
    this.onTap,
    this.shortcut,
    this.destructive = false,
    this.leading,
    this.submenu,
  }) : divider = false;
  const FaMenuItem.divider() : label = '', icon = null, onTap = null, shortcut = null, destructive = false, divider = true, leading = null, submenu = null;
}

/// Shows a FilDOS-style context menu at [position] (global coordinates).
Future<void> showFaMenu(BuildContext context, Offset position, List<FaMenuItem> items) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(position);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, _, _) => _MenuLayer(position: local, items: items, theme: Theme.of(context)),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

class _MenuLayer extends StatelessWidget {
  final Offset position;
  final List<FaMenuItem> items;
  final ThemeData theme;
  const _MenuLayer({required this.position, required this.items, required this.theme});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const width = 232.0;
    final estHeight = items.fold<double>(8, (h, i) => h + (i.divider ? 9 : 30));
    final left = (position.dx + width > size.width - 8) ? size.width - width - 8 : position.dx;
    final top = (position.dy + estHeight > size.height - 8) ? (size.height - estHeight - 8).clamp(8.0, size.height) : position.dy;
    return Theme(
      data: theme,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Builder(builder: (context) => _MenuPanel(items: items)),
          ),
        ],
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  final List<FaMenuItem> items;
  const _MenuPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Material(
      color: Colors.transparent,
      child: FaCard(
        shadow: true,
        padding: const EdgeInsets.all(4),
        color: c.popover,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              if (item.divider)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1, thickness: 1, color: c.border),
                )
              else
                _MenuRow(item: item),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final FaMenuItem item;
  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final enabled = item.onTap != null || item.submenu != null;
    final fg = !enabled
        ? c.mutedForeground.withValues(alpha: 0.5)
        : (item.destructive ? c.destructive : c.foreground);
    return Hoverable(
      onTap: !enabled
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox;
              final at = box.localToGlobal(Offset(box.size.width - 4, 0));
              if (item.submenu != null) {
                showFaMenu(context, at, item.submenu!);
                return;
              }
              Navigator.of(context).pop();
              item.onTap!();
            },
      builder: (context, hover) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hover && enabled ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(FaRadius.sm),
        ),
        child: Row(
          children: [
            if (item.leading != null)
              SizedBox(width: 22, child: Align(alignment: Alignment.centerLeft, child: item.leading))
            else if (item.icon != null)
              SizedBox(width: 22, child: Icon(item.icon, size: 15, color: item.destructive ? c.destructive : c.mutedForeground)),
            Expanded(child: Text(item.label, style: FaText.sans(size: 12.5, color: fg), overflow: TextOverflow.ellipsis)),
            if (item.shortcut != null) Text(item.shortcut!, style: FaText.sans(size: 11.5, color: c.mutedForeground)),
            if (item.submenu != null) Icon(Icons.chevron_right_rounded, size: 15, color: c.mutedForeground),
          ],
        ),
      ),
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

/// Simple single-line text prompt dialog.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirm = 'OK',
  String? hint,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: context.fa.overlay,
    builder: (ctx) {
      final c = ctx.fa;
      return Dialog(
        backgroundColor: c.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FaRadius.xl),
          side: BorderSide(color: c.border),
        ),
        child: SizedBox(
          width: 360,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FaText.sans(size: 15, weight: FontWeight.w600, color: c.foreground)),
                const SizedBox(height: 12),
                FaTextField(
                  controller: controller,
                  hint: hint,
                  autofocus: true,
                  onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FaButton(label: 'Cancel', variant: FaButtonVariant.ghost, onPressed: () => Navigator.pop(ctx)),
                    const SizedBox(width: 8),
                    FaButton(
                      label: confirm,
                      variant: FaButtonVariant.primary,
                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class FaTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = context.fa;
    final style = mono ? FaText.mono(size: 12, color: c.foreground) : FaText.sans(size: 13, color: c.foreground);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: style,
      cursorColor: c.foreground,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: style.copyWith(color: c.mutedForeground),
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(minWidth: 32),
        filled: true,
        fillColor: c.muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 8 : 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(FaRadius.md), borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(FaRadius.md), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FaRadius.md),
          borderSide: BorderSide(color: c.mutedForeground.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

/// Text with «marked» spans highlighted in Mint (search snippets).
class MarkedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  const MarkedText(this.text, {super.key, required this.style, this.maxLines = 1});

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
          style: style.copyWith(color: Scoop.mint, fontWeight: FontWeight.w600),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}
