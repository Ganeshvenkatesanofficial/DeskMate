import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_settings.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';

/// Building blocks shared by Settings and the onboarding tour — straight ports
/// of the FilDOS SettingsView / Onboarding idioms (Section cards with a framed
/// icon tile, Ink switches, hairline row boxes, scoop colour only as accent).
///
/// FilDOS type scale used throughout: text-sm 14, text-xs 12, text-2xs 11,
/// text-3xs 10, text-4xs 8; spacing unit 4px.

String formatCount(int n) => NumberFormat.decimalPattern().format(n);

/// Tailwind's default `transition` timing (150ms, ease-in-out-ish).
const _twEase = Cubic(0.4, 0, 0.2, 1);
const _twFast = Duration(milliseconds: 150);

/// FilDOS `Toggle` / onboarding `Switch`: h-5 w-9 track (`bg-primary` on,
/// `bg-muted` off), a white size-4 thumb inset 2px that slides 16px.
class FaSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const FaSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: Hoverable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        builder: (context, _) => AnimatedContainer(
          duration: _twFast,
          curve: _twEase,
          width: 36,
          height: 20,
          decoration: BoxDecoration(color: value ? c.primary : c.muted, borderRadius: BorderRadius.circular(999)),
          child: AnimatedAlign(
            duration: _twFast,
            curve: _twEase,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// FilDOS `Section`: `rounded-xl border bg-card p-5`, a size-9 `bg-muted`
/// tile (ring-border/60, rounded-lg) with a 17px icon, title text-sm medium,
/// subtitle text-2xs, an optional action on the right, then `mt-4 space-y-4`.
class SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool mint;
  final bool disabled;
  final List<Widget> children;
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.mint = false,
    this.disabled = false,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    Widget card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.xl),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c.muted,
                        borderRadius: BorderRadius.circular(FaRadius.lg),
                        border: Border.all(color: c.border.withValues(alpha: 0.6)),
                      ),
                      child: Icon(icon, size: 17, color: mint ? Scoop.mint : c.foreground),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                          ),
                          Text(subtitle, style: FaText.sans(size: 11, color: c.mutedForeground)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 16), action!],
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 16), children[i]],
          ],
        ],
      ),
    );
    if (disabled) card = IgnorePointer(child: Opacity(opacity: 0.5, child: card));
    return card;
  }
}

/// FilDOS `SubLabel`: text-2xs, medium, tracking-wider, uppercase, mb-2.
class SubLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SubLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text.toUpperCase(),
          style: FaText.sans(size: 11, weight: FontWeight.w500, color: context.fa.mutedForeground, letterSpacing: 0.55),
        ),
      ),
      ?trailing,
    ],
  );
}

/// The `rounded-lg border px-3 py-2.5` row box every Settings control lives
/// in (Rescan every, Skip file types, This machine…).
class RowBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool dashed;
  const RowBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.dashed = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaRadius.lg),
        border: dashed ? null : Border.all(color: c.border),
      ),
      child: child,
    );
    if (!dashed) return box;
    return CustomPaint(painter: _DashedRRect(c.border), child: box);
  }
}

class _DashedRRect extends CustomPainter {
  final Color color;
  _DashedRRect(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), const Radius.circular(FaRadius.lg));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
        d += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}

/// A label + description on the left and a control on the right, inside a
/// [RowBox] (FilDOS "Rescan every" / "Continue in the background" rows).
/// With [boxed] false it is the bare `border-t pt-4` row used inside a card.
class SettingRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;
  final bool boxed;
  const SettingRow({super.key, required this.title, this.description, required this.trailing, this.boxed = true});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: FaText.sans(size: 14, color: c.foreground)),
              if (description != null) Text(description!, style: FaText.sans(size: 11, color: c.mutedForeground)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
    if (boxed) return RowBox(child: row);
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: row,
    );
  }
}

/// A small pill: `bg-muted text-muted-foreground rounded-full px-1.5 py-0.5
/// text-3xs font-medium`, or the scoop variant (`bg-mint/15 text-mint`).
class FaBadge extends StatelessWidget {
  final String text;
  final Color? accent;
  final bool wide;
  const FaBadge(this.text, {super.key, this.accent, this.wide = false});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 8 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent?.withValues(alpha: 0.15) ?? c.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: FaText.sans(size: 10, weight: FontWeight.w500, color: accent ?? c.mutedForeground, height: 1.4),
      ),
    );
  }
}

/// The FilDOS radio indicator (ChoiceCard / OptionRow): size-4 circle with a
/// border; active fills with foreground and shows a 10px check.
class RadioDot extends StatelessWidget {
  final bool active;
  const RadioDot(this.active, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return AnimatedContainer(
      duration: _twFast,
      curve: _twEase,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? c.foreground : Colors.transparent,
        border: Border.all(color: active ? c.foreground : c.border),
      ),
      child: active ? Icon(Icons.check_rounded, size: 10, color: c.background) : null,
    );
  }
}

/// FilDOS `Button` — `size="sm"` (h-8 px-3) by default, or the default size
/// with [large] (h-9 px-4); rounded-sm, text-sm, 150ms colour transition.
class SmallButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final FaButtonVariant variant;
  final bool large;
  final bool expand;
  const SmallButton({
    super.key,
    required this.label,
    this.icon,
    this.iconSize = 13,
    this.onPressed,
    this.variant = FaButtonVariant.primary,
    this.large = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Hoverable(
        onTap: onPressed,
        builder: (context, hover) {
          final h = hover && enabled;
          final (bg, fg, border) = switch (variant) {
            FaButtonVariant.primary => (h ? c.primary.withValues(alpha: 0.9) : c.primary, c.primaryForeground, null),
            FaButtonVariant.secondary => (h ? c.muted.withValues(alpha: 0.8) : c.muted, c.foreground, null),
            FaButtonVariant.outline => (h ? c.accent : c.background, c.foreground, c.border),
            FaButtonVariant.ghost => (
              h ? c.foreground.withValues(alpha: 0.09) : Colors.transparent,
              h ? c.foreground : c.mutedForeground,
              null,
            ),
            FaButtonVariant.destructive => (
              h ? c.destructive.withValues(alpha: 0.9) : c.destructive,
              Colors.white,
              null,
            ),
          };
          return AnimatedContainer(
            duration: _twFast,
            height: large ? 36 : 32,
            padding: EdgeInsets.symmetric(horizontal: large ? (icon == null ? 16 : 12) : (icon == null ? 12 : 10)),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(FaRadius.sm),
              border: border == null ? null : Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: iconSize, color: fg), SizedBox(width: large ? 8 : 6)],
                Text(label, style: FaText.sans(size: 14, color: fg)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Appearance ─────────────────────────────────────────────────────────────

/// An abstract miniature of the app window in one theme's palette.
class MiniWindow extends StatelessWidget {
  final bool dark;
  const MiniWindow({super.key, required this.dark});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF16181F) : Colors.white;
    final side = dark ? const Color(0xFF0F1117) : const Color(0xFFF5F5F7);
    final line = dark ? const Color(0xFF262932) : const Color(0xFFE7E7EA);
    final bar = dark ? const Color(0xFF2E3340) : const Color(0xFFD9DADE);
    Widget pill(double f) => FractionallySizedBox(
      widthFactor: f,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 4,
        decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(4)),
      ),
    );
    return ColoredBox(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              decoration: BoxDecoration(
                color: side,
                border: Border(right: BorderSide(color: line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pill(0.75),
                  const SizedBox(height: 4),
                  pill(0.5),
                  const Spacer(),
                  const Row(
                    children: [
                      ScoopDot(Scoop.blueberry, size: 4),
                      SizedBox(width: 4),
                      ScoopDot(Scoop.mint, size: 4),
                      SizedBox(width: 4),
                      ScoopDot(Scoop.strawberry, size: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pill(1 / 3),
                  const SizedBox(height: 6),
                  Container(height: 1, color: line),
                  for (final w in const [0.9, 0.65, 0.8, 0.5]) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: pill(w)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.58, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width * 0.38, s.height)
    ..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

const themeChoices = [
  (ThemeMode.system, 'System', Icons.desktop_windows_outlined),
  (ThemeMode.light, 'Light', Icons.light_mode_outlined),
  (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
];

/// System / Light / Dark. The onboarding variant is FilDOS's `ThemeCard` grid
/// (live miniature previews, `grid-cols-3 gap-3`); [compact] is the Settings
/// variant (`grid-cols-3 gap-2` of bordered icon buttons). Selecting one
/// changes DeskMate's app-wide theme (AppSettings) — Folder Agent follows it.
class ThemePicker extends StatelessWidget {
  final bool compact;
  const ThemePicker({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppSettings, ThemeMode>((s) => s.themeMode);
    final chat = context.read<AppSettings>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < themeChoices.length; i++) ...[
          if (i > 0) SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: compact
                ? _ThemeButton(
                    label: themeChoices[i].$2,
                    icon: themeChoices[i].$3,
                    active: mode == themeChoices[i].$1,
                    onTap: () => chat.setThemeMode(themeChoices[i].$1),
                  )
                : _ThemeCard(
                    mode: themeChoices[i].$1,
                    label: themeChoices[i].$2,
                    icon: themeChoices[i].$3,
                    active: mode == themeChoices[i].$1,
                    onTap: () => chat.setThemeMode(themeChoices[i].$1),
                  ),
          ),
        ],
      ],
    );
  }
}

class _ThemeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ThemeButton({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: _twFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active ? c.primary.withValues(alpha: 0.1) : (hover ? c.accent : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: active ? c.foreground : c.mutedForeground),
            const SizedBox(height: 6),
            Text(label, style: FaText.sans(size: 14, color: c.foreground)),
          ],
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final preview = mode == ThemeMode.system
        ? Stack(
            fit: StackFit.expand,
            children: [
              const MiniWindow(dark: false),
              ClipPath(clipper: _SystemClipper(), child: const MiniWindow(dark: true)),
            ],
          )
        : MiniWindow(dark: mode == ThemeMode.dark);
    final fg = active ? c.foreground : c.mutedForeground;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? c.primary.withValues(alpha: 0.1)
              : (hover ? c.accent.withValues(alpha: 0.5) : c.background.withValues(alpha: 0)),
          borderRadius: BorderRadius.circular(FaRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 7 / 5,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FaRadius.lg),
                  border: Border.all(color: c.border),
                ),
                child: preview,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 6),
                Text(label, style: FaText.sans(size: 14, color: fg)),
                if (active) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, size: 13, color: fg)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Paths ──────────────────────────────────────────────────────────────────

/// FilDOS `HiddenPathRow`: `rounded-lg border px-3 py-2 gap-2.5`, a 15px
/// icon, name text-sm with its parent beneath (mono text-3xs), and a 14px
/// remove affordance revealed on hover.
class PathRow extends StatelessWidget {
  final String path;
  final VoidCallback? onRemove;
  final String removeTooltip;
  final IconData icon;
  const PathRow({
    super.key,
    required this.path,
    this.onRemove,
    this.removeTooltip = 'Remove',
    this.icon = Icons.folder_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final parent = parentDir(path);
    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 800),
      child: Hoverable(
        cursor: SystemMouseCursors.basic,
        builder: (context, hover) => AnimatedContainer(
          duration: _twFast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: hover ? c.accent.withValues(alpha: 0.5) : c.card.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(FaRadius.lg),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: c.mutedForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      baseName(path),
                      style: FaText.sans(size: 14, color: c.foreground),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (parent != path)
                      Text(
                        parent,
                        style: FaText.mono(size: 10, color: c.mutedForeground),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (onRemove != null)
                AnimatedOpacity(
                  duration: _twFast,
                  opacity: hover ? 1 : 0,
                  child: Tooltip(
                    message: removeTooltip,
                    child: Hoverable(
                      onTap: onRemove,
                      builder: (context, h) =>
                          Icon(Icons.close_rounded, size: 14, color: h ? c.foreground : c.mutedForeground),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder for an empty list (FilDOS dashed `rounded-lg` empty state).
class EmptyNote extends StatelessWidget {
  final String text;
  final IconData? icon;
  const EmptyNote(this.text, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return RowBox(
      dashed: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: c.mutedForeground), const SizedBox(height: 8)],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.375),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Privacy ────────────────────────────────────────────────────────────────

Future<void> pickExcludes(FaController app) async {
  final picked = await app.api.pickFolders(prompt: 'Choose folders to hide from AI');
  if (!picked.ok) return app.toastError(picked.error);
  if (picked.value!.isEmpty) return;
  final r = await app.api.addExcludes(picked.value!);
  if (!r.ok) return app.toastError(r.error);
  await app.refreshPrefs();
}

Future<void> removeExclude(FaController app, String path) async {
  final r = await app.api.removeExclude(path);
  if (!r.ok) return app.toastError(r.error);
  await app.refreshPrefs();
}

Future<void> setExcludeExtensions(FaController app, List<String> exts) async {
  final r = await app.api.setExcludeExtensions(exts);
  if (!r.ok) return app.toastError(r.error);
  await app.refreshPrefs();
}

/// "Hide from AI" body (FilDOS Settings → Privacy): the hidden paths, or the
/// dashed empty state, plus the footnote.
class HiddenPathsList extends StatelessWidget {
  const HiddenPathsList({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final excludes = app.excludes;
    if (excludes.isEmpty) {
      return const EmptyNote(
        'Nothing is hidden. Right-click any file or folder and choose Hide from AI, or add one here. '
        'Hidden items are removed from the index immediately and never re-indexed.',
        icon: Icons.visibility_off_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in excludes) ...[
          PathRow(path: p, removeTooltip: 'Show to AI again', onRemove: () => removeExclude(app, p)),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 10),
        Text(
          'Hidden items are removed from the index immediately and never re-indexed — semantic search and '
          'Ask AI can\'t see them.',
          style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.375),
        ),
      ],
    );
  }
}

/// FilDOS `SkipTypesRow`: removable extension chips plus an inline input.
/// Enter, comma or space commits what's typed; backspace on an empty input
/// removes the last chip; blur commits too.
class SkipTypesRow extends StatefulWidget {
  /// Without the row box (onboarding draws its own card).
  final bool bare;
  const SkipTypesRow({super.key, this.bare = false});
  @override
  State<SkipTypesRow> createState() => _SkipTypesRowState();
}

class _SkipTypesRowState extends State<SkipTypesRow> {
  final _draft = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    _draft.addListener(_onDraft);
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onDraft() {
    final t = _draft.text;
    if (t.endsWith(',') || t.endsWith(' ')) _commit();
  }

  void _commit() {
    final app = context.read<FaController>();
    final parts = _draft.text
        .split(RegExp(r'[\s,]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e != '.')
        .map((e) => e.startsWith('.') ? e : '.$e');
    if (_draft.text.isNotEmpty) _draft.clear();
    if (parts.isEmpty) return;
    setExcludeExtensions(app, {...app.excludeExtensions, ...parts}.toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final exts = app.excludeExtensions;
    final field = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final e in exts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(FaRadius.md)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e, style: FaText.mono(size: 11, color: c.foreground)),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Index $e files again',
                    child: Hoverable(
                      onTap: () => setExcludeExtensions(app, exts.where((x) => x != e).toList()),
                      builder: (context, h) =>
                          Icon(Icons.close_rounded, size: 10, color: h ? c.foreground : c.mutedForeground),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: 120,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, k) {
                if (k is KeyDownEvent && k.logicalKey == LogicalKeyboardKey.backspace && _draft.text.isEmpty) {
                  if (exts.isNotEmpty) setExcludeExtensions(app, exts.sublist(0, exts.length - 1));
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _draft,
                focusNode: _focus,
                onSubmitted: (_) => _commit(),
                style: FaText.sans(size: 14, color: c.foreground),
                cursorColor: c.foreground,
                cursorHeight: 15,
                decoration: InputDecoration.collapsed(
                  hintText: exts.isEmpty ? 'e.g. log, mp3, svg' : '',
                  hintStyle: FaText.sans(size: 14, color: c.mutedForeground),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.bare) return field;
    return RowBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Skip file types', style: FaText.sans(size: 14, color: c.foreground)),
          Text(
            'The index never reads these extensions; existing entries are removed',
            style: FaText.sans(size: 11, color: c.mutedForeground),
          ),
          const SizedBox(height: 8),
          field,
        ],
      ),
    );
  }
}
