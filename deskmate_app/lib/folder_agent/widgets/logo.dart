import 'package:flutter/material.dart';

import '../core/fa_theme.dart';

/// The DeskMate mark (the star + D app icon), sized like the FilDOS tile mark.
class DeskMateMark extends StatelessWidget {
  final double size;
  const DeskMateMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        c.isDark ? 'assets/app_icon.png' : 'assets/app_icon_light.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
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
            style: FaText.sans(size: size, weight: FontWeight.w300, color: fg, letterSpacing: -0.2),
          ),
          TextSpan(text: 'Mate', style: FaText.mono(size: size * 0.94, color: fg)),
        ],
      ),
    );
  }
}

/// Mark + wordmark, the horizontal lockup used in the sidebar header.
class DeskMateLogo extends StatelessWidget {
  final double size;
  const DeskMateLogo({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DeskMateMark(size: size + 2),
      SizedBox(width: size * 0.5),
      DeskMateWordmark(size: size),
    ],
  );
}
