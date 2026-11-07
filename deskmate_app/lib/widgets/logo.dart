import 'package:flutter/material.dart';

import '../core/fa_theme.dart';

/// The DeskMate mark — the purple star + D glyph on transparent, used the
/// way FilDOS uses its tile mark (sidebar, Ask AI, onboarding).
class DeskMateMark extends StatelessWidget {
  final double size;
  const DeskMateMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/deskmate_mark.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    isAntiAlias: true,
  );
}

/// "Desk" (Inter Light) + "Mate" (Space Mono) — the FilDOS wordmark recipe,
/// in DeskMate's name. Both halves follow the current text colour.
class DeskMateWordmark extends StatelessWidget {
  final double size;
  final Color? color;
  const DeskMateWordmark({super.key, this.size = 17, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.fa.foreground;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Desk',
            // `font-light tracking-tight` (-0.025em), leading-none.
            style: FaText.sans(size: size, weight: FontWeight.w300, color: fg, letterSpacing: -0.025 * size, height: 1),
          ),
          TextSpan(
            text: 'Mate',
            style: FaText.mono(size: size, color: fg, height: 1),
          ),
        ],
      ),
    );
  }
}

/// Mark + wordmark, the horizontal lockup used in the sidebar header — FilDOS
/// `Logo`: the mark at 1.1em, `gap-2`.
class DeskMateLogo extends StatelessWidget {
  final double size;
  const DeskMateLogo({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DeskMateMark(size: (size * 1.1).roundToDouble()),
      const SizedBox(width: 8),
      DeskMateWordmark(size: size),
    ],
  );
}
