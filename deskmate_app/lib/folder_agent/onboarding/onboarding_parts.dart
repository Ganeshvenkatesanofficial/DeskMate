import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/fa_theme.dart';
import '../settings/model_widgets.dart' show ThinBar;
import '../settings/settings_widgets.dart';
import '../widgets/ui.dart';

/// Pieces of the onboarding tour — ports of the FilDOS Onboarding.tsx
/// components: the `.onboard-item` entrance, StepHeading, ChoiceCard,
/// OptionRow, ModelProgressRow, ShortcutRow and the three flat feature
/// vignettes on the AI step (monochrome mockups; the Canvas one borrows the
/// scoop cluster colours).

/// `.onboard-item`: rises into focus (opacity 0→1, translateY 16→0, blur
/// 8→0) over 600ms on the snappy curve, `animation-fill-mode: both`; [order]
/// staggers siblings by 75ms. It plays once per mount — each step is keyed so
/// every screen animates in fresh, and rebuilds never replay it (flutter_animate
/// only restarts on a duration / controller change). Reduced motion: static.
class Reveal extends StatelessWidget {
  final int order;
  final Widget child;
  const Reveal({super.key, this.order = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    const d = Duration(milliseconds: 600);
    return child
        .animate(delay: Duration(milliseconds: order * 75))
        .fadeIn(duration: d, curve: FaMotion.snappy)
        .moveY(begin: 16, end: 0, duration: d, curve: FaMotion.snappy)
        .blurXY(begin: 8, end: 0, duration: d, curve: FaMotion.snappy);
  }
}

/// The step's headline (text-2xl medium, tracking-tight) + supporting line
/// (mt-2, max-w-lg, text-sm leading-relaxed), staggered 0 / 1.
class StepHeading extends StatelessWidget {
  final String title;
  final String sub;
  const StepHeading({super.key, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal(
          order: 0,
          child: Text(
            title,
            style: FaText.sans(
              size: 24,
              weight: FontWeight.w500,
              color: c.foreground,
              letterSpacing: -0.6,
              height: 1.33,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Reveal(
          order: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Text(sub, style: FaText.sans(size: 14, color: c.mutedForeground, height: 1.625)),
          ),
        ),
      ],
    );
  }
}

/// `border-border bg-card rounded-xl border` surface used by every step.
class OnbCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const OnbCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.xl),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

/// `divide-y` rows inside an [OnbCard] with `px-4`.
class DividedRows extends StatelessWidget {
  final List<Widget> children;
  const DividedRows({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return OnbCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++)
            Container(
              decoration: i == 0
                  ? null
                  : BoxDecoration(
                      border: Border(top: BorderSide(color: c.border)),
                    ),
              child: children[i],
            ),
        ],
      ),
    );
  }
}

/// One of the two AI opt-in choices, radio-style: `rounded-xl border p-4`,
/// `bg-primary/10` when active, else `bg-card` with an `accent/50` hover.
class ChoiceCard extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final String title;
  final String? badge;
  final List<Widget> children;
  const ChoiceCard({
    super.key,
    required this.active,
    required this.onTap,
    required this.title,
    this.badge,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? c.primary.withValues(alpha: 0.1) : (hover ? c.accent.withValues(alpha: 0.5) : c.card),
          borderRadius: BorderRadius.circular(FaRadius.xl),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                ),
                if (badge != null) ...[const SizedBox(width: 8), FaBadge(badge!)],
                const Spacer(),
                RadioDot(active),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A compact radio row (FilDOS `OptionRow`): `rounded-lg border px-3 py-2.5
/// gap-3`, radio, size-4 logo, title text-sm, optional pill, mono size on
/// the right and a text-2xs description.
class OptionRow extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final String title;
  final String? badge;
  final String? meta;
  final String? desc;
  final Widget? logo;
  final Widget? below;
  const OptionRow({
    super.key,
    required this.active,
    required this.onTap,
    required this.title,
    this.badge,
    this.meta,
    this.desc,
    this.logo,
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? c.primary.withValues(alpha: 0.1)
              : (hover ? c.accent.withValues(alpha: 0.5) : c.card.withValues(alpha: 0)),
          borderRadius: BorderRadius.circular(FaRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RadioDot(active),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (logo != null) ...[SizedBox(width: 16, height: 16, child: logo), const SizedBox(width: 8)],
                          Flexible(
                            child: Text(
                              title,
                              style: FaText.sans(size: 14, color: c.foreground),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badge != null) ...[const SizedBox(width: 8), FaBadge(badge!)],
                          const Spacer(),
                          if (meta != null) Text(meta!, style: FaText.mono(size: 10, color: c.mutedForeground)),
                        ],
                      ),
                      if (desc != null && desc!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(desc!, style: FaText.sans(size: 11, color: c.mutedForeground)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (below != null) ...[const SizedBox(height: 10), below!],
          ],
        ),
      ),
    );
  }
}

/// Live status for one model on the ready step (FilDOS `ModelProgressRow`):
/// a w-28 label, then Ready / "Will retry from Settings" / an h-1 bar with a
/// mono percentage.
class ModelProgressRow extends StatelessWidget {
  final String label;

  /// ready | downloading | error | queued | text
  final String state;
  final double progress;
  final String? text;
  const ModelProgressRow({super.key, required this.label, required this.state, this.progress = 0, this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final muted = FaText.sans(size: 11, color: c.mutedForeground);
    final pct = (progress * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FaText.sans(size: 11, color: c.foreground),
          ),
        ),
        const SizedBox(width: 12),
        if (state == 'ready')
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 12, color: c.mutedForeground),
              const SizedBox(width: 4),
              Text(text ?? 'Ready', style: muted),
            ],
          )
        else if (state == 'error')
          Text(text ?? 'Will retry from Settings', style: muted)
        else if (state == 'text')
          Expanded(
            child: Text(text ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          )
        else ...[
          Expanded(
            child: ThinBar(value: progress, color: c.foreground.withValues(alpha: 0.5)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Text(
              state == 'downloading' ? '$pct%' : '…',
              textAlign: TextAlign.right,
              style: FaText.mono(size: 10, color: c.mutedForeground),
            ),
          ),
        ],
      ],
    );
  }
}

/// The welcome step's terms checkbox (`accent-foreground size-3.5`).
class FaCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const FaCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: () => onChanged(!value),
      builder: (context, hover) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: value ? c.foreground : c.background,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: value ? c.foreground : (hover ? c.mutedForeground : c.border), width: 1),
        ),
        child: value ? Icon(Icons.check_rounded, size: 11, color: c.background) : null,
      ),
    );
  }
}

/// A feature vignette: `h-32 bg-muted/40 border-b p-3` mockup on top, then a
/// `p-3` title (text-sm medium) + description (text-2xs leading-relaxed).
class DemoCard extends StatelessWidget {
  final String title;
  final String desc;
  final Widget child;
  const DemoCard({super.key, required this.title, required this.desc, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.xl),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 128,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.4),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: child,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                ),
                const SizedBox(height: 2),
                Text(desc, style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SearchDemo extends StatelessWidget {
  const SearchDemo({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    const hits = [('invoice-march.pdf', 0.92), ('whole-foods-scan.jpg', 0.78), ('reimbursements.xlsx', 0.61)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 11, color: c.mutedForeground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'receipts from tax season',
                  style: FaText.sans(size: 10, color: c.foreground, height: 1.2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        for (final (name, score) in hits) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(FaRadius.md),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 10, color: c.mutedForeground),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: FaText.mono(size: 10, color: c.foreground.withValues(alpha: 0.8), height: 1.2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 32,
                  height: 2,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(999)),
                  child: FractionallySizedBox(
                    widthFactor: score,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.foreground.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class ChatDemo extends StatelessWidget {
  const ChatDemo({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(FaRadius.lg),
                topRight: Radius.circular(FaRadius.lg),
                bottomLeft: Radius.circular(FaRadius.lg),
                bottomRight: Radius.circular(FaRadius.sm),
              ),
            ),
            child: Text(
              'What changed across my lease drafts?',
              style: FaText.sans(size: 10, color: c.primaryForeground, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: c.border),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(FaRadius.lg),
                topRight: Radius.circular(FaRadius.lg),
                bottomLeft: Radius.circular(FaRadius.sm),
                bottomRight: Radius.circular(FaRadius.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The rent clause changed twice v3 removed the break fee.',
                  style: FaText.sans(size: 10, color: c.foreground.withValues(alpha: 0.8), height: 1.375),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in const ['lease-v2.docx', 'lease-v3.docx']) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.insert_drive_file_outlined, size: 8, color: c.mutedForeground),
                            const SizedBox(width: 4),
                            Text(f, style: FaText.mono(size: 8, color: c.mutedForeground, height: 1.2)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CanvasDemo extends StatelessWidget {
  const CanvasDemo({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _CanvasPainter(context.fa.foreground), size: Size.infinite);
}

class _CanvasPainter extends CustomPainter {
  final Color fg;
  _CanvasPainter(this.fg);

  static const _edges = [
    (28.0, 30.0, 46.0, 18.0),
    (28.0, 30.0, 40.0, 48.0),
    (46.0, 18.0, 40.0, 48.0),
    (40.0, 48.0, 78.0, 34.0),
    (78.0, 34.0, 96.0, 20.0),
    (78.0, 34.0, 92.0, 52.0),
    (92.0, 52.0, 122.0, 62.0),
    (122.0, 62.0, 138.0, 46.0),
    (122.0, 62.0, 130.0, 78.0),
    (138.0, 46.0, 130.0, 78.0),
  ];
  static const _nodes = [
    (28.0, 30.0, Scoop.blueberry, 4.0),
    (46.0, 18.0, Scoop.blueberry, 3.0),
    (40.0, 48.0, Scoop.blueberry, 3.0),
    (78.0, 34.0, Scoop.mango, 4.5),
    (96.0, 20.0, Scoop.mango, 3.0),
    (92.0, 52.0, Scoop.mint, 3.0),
    (122.0, 62.0, Scoop.mint, 4.0),
    (138.0, 46.0, Scoop.grape, 3.0),
    (130.0, 78.0, Scoop.grape, 3.5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 160×92, `meet`: fitted and centred.
    final s = (size.width / 160).clamp(0.0, size.height / 92);
    canvas.translate((size.width - 160 * s) / 2, (size.height - 92 * s) / 2);
    canvas.scale(s);
    final line = Paint()
      ..color = fg.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (final (x1, y1, x2, y2) in _edges) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), line);
    }
    for (final (x, y, color, r) in _nodes) {
      canvas.drawCircle(Offset(x, y), r, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => old.fg != fg;
}

/// `Kbd size="md"`: bordered muted keycap, mono text-2xs, px-1.5 py-0.5.
class KbdKey extends StatelessWidget {
  final String text;
  const KbdKey(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: FaText.mono(size: 11, color: c.mutedForeground, height: 1)),
    );
  }
}

/// Label + key caps (`flex justify-between py-2`, label text-sm).
class ShortcutRow extends StatelessWidget {
  final String label;
  final List<String> keys;
  const ShortcutRow({super.key, required this.label, required this.keys});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: FaText.sans(size: 14, color: c.foreground)),
          ),
          for (var i = 0; i < keys.length; i++) ...[if (i > 0) const SizedBox(width: 4), KbdKey(keys[i])],
        ],
      ),
    );
  }
}
