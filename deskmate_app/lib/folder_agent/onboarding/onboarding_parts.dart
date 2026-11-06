import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/fa_theme.dart';
import '../widgets/ui.dart';
import '../settings/settings_widgets.dart';

/// Pieces of the onboarding tour: the "rise into focus" entrance, step
/// headings, choice cards and the three flat feature vignettes on the AI step
/// (monochrome mockups; the Canvas one borrows scoop cluster colours).

/// A block that rises into focus (opacity + 16px lift + 8px blur, 600ms,
/// snappy); [order] staggers siblings by 75ms. Plays once per mount — each
/// step is keyed, so every screen animates in fresh.
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

/// The step's headline + supporting line, consistently staggered.
class StepHeading extends StatelessWidget {
  final String title;
  final String sub;
  final bool center;
  const StepHeading({super.key, required this.title, required this.sub, this.center = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Reveal(
          order: 0,
          child: Text(
            title,
            textAlign: align,
            style: FaText.sans(size: 24, weight: FontWeight.w500, color: c.foreground, letterSpacing: -0.4),
          ),
        ),
        const SizedBox(height: 8),
        Reveal(
          order: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              sub,
              textAlign: align,
              style: FaText.sans(size: 13.5, color: c.mutedForeground, height: 1.55),
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the radio-style choice cards (AI opt-in).
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
          color: active ? c.primary.withValues(alpha: 0.08) : (hover ? c.accent.withValues(alpha: 0.6) : c.card),
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
                  style: FaText.sans(size: 13.5, weight: FontWeight.w500, color: c.foreground),
                ),
                if (badge != null) ...[const SizedBox(width: 8), FaBadge(badge!, accent: Scoop.mint)],
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

/// A square checkbox with a label (welcome terms, folder checklist).
class FaCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const FaCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: () => onChanged(!value),
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: value ? c.foreground : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? c.foreground : (hover ? c.mutedForeground : c.border), width: 1.3),
        ),
        child: value ? Icon(Icons.check_rounded, size: 12, color: c.background) : null,
      ),
    );
  }
}

/// A feature vignette: mockup on top, title + description below.
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
              color: c.muted.withValues(alpha: 0.5),
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
                  style: FaText.sans(size: 13, weight: FontWeight.w500, color: c.foreground),
                ),
                const SizedBox(height: 3),
                Text(desc, style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.45)),
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
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 11, color: c.mutedForeground),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'receipts from tax season',
                  style: FaText.sans(size: 10, color: c.foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        for (final (name, score) in hits) ...[
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 10, color: c.mutedForeground),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    name,
                    style: FaText.mono(size: 8.5, color: c.foreground.withValues(alpha: 0.8)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 2,
                  alignment: Alignment.centerLeft,
                  color: c.border,
                  child: FractionallySizedBox(
                    widthFactor: score,
                    child: Container(color: c.foreground.withValues(alpha: 0.6)),
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
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(2),
              ),
            ),
            child: Text(
              'What changed across my lease drafts?',
              style: FaText.sans(size: 9.5, color: c.primaryForeground),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: c.border),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(2),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ScoopDot(Scoop.mint, size: 5),
                    const SizedBox(width: 4),
                    Text('read_file · 2 files', style: FaText.mono(size: 8, color: c.mutedForeground)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'The rent clause changed twice; v3 removed the break fee.',
                  style: FaText.sans(size: 9.5, color: c.foreground.withValues(alpha: 0.8), height: 1.35),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in const ['lease-v2.docx', 'lease-v3.docx']) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(3)),
                        child: Text(f, style: FaText.mono(size: 7.5, color: c.mutedForeground)),
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
    // viewBox 160×92, fitted and centred.
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

/// Label + key caps ("Search everything  ⌘ K").
class ShortcutRow extends StatelessWidget {
  final String label;
  final List<String> keys;
  final bool divider;
  const ShortcutRow({super.key, required this.label, required this.keys, this.divider = true});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: divider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: FaText.sans(size: 13, color: c.foreground)),
          ),
          for (var i = 0; i < keys.length; i++) ...[if (i > 0) const SizedBox(width: 3), Kbd(keys[i])],
        ],
      ),
    );
  }
}
