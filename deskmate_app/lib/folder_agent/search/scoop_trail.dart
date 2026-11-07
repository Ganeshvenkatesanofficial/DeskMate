import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fa_theme.dart';

/// The scoop "comet" orbiting a panel's edge (FilDOS' `.scoop-trail`): a
/// 1.5px hairline ring in [base] (the border colour) with a conic gradient —
/// blueberry → mint → grape → bubblegum → mango fading to nothing — rotated
/// by [turn] on top of it. Painted as a ring only, so the panel's translucent
/// surface never washes with colour. With [comet] off (reduced motion) only
/// the still hairline remains, as in FilDOS.
class ScoopTrailPainter extends CustomPainter {
  final Animation<double> turn;
  final Color base;
  final bool comet;

  /// Outer corner radius of the ring box.
  final double radius;
  final double stroke;
  ScoopTrailPainter(this.turn, {required this.base, this.comet = true, this.radius = FaRadius.xl, this.stroke = 1.5})
    : super(repaint: comet ? turn : null);

  // conic-gradient(from a, transparent 0 200deg, #6e9bee80 240deg, mint 268deg,
  // grape 294deg, bubblegum 320deg, mango 344deg, transparent 350deg 360deg)
  static const _stops = [0.0, 200 / 360, 240 / 360, 268 / 360, 294 / 360, 320 / 360, 344 / 360, 350 / 360, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = RRect.fromRectAndRadius(rect.deflate(stroke / 2), Radius.circular(radius - stroke / 2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = base;
    canvas.drawRRect(ring, paint);
    if (!comet) return;
    final shader = SweepGradient(
      colors: [
        Scoop.blueberry.withValues(alpha: 0),
        Scoop.blueberry.withValues(alpha: 0),
        Scoop.blueberry.withValues(alpha: 0.5),
        Scoop.mint,
        Scoop.grape,
        Scoop.bubblegum,
        Scoop.mango,
        Scoop.mango.withValues(alpha: 0),
        Scoop.mango.withValues(alpha: 0),
      ],
      stops: _stops,
      // CSS conic gradients start at 12 o'clock; Flutter's sweep at 3 o'clock.
      transform: GradientRotation(turn.value * 2 * math.pi - math.pi / 2),
    ).createShader(rect);
    canvas.drawRRect(ring, paint..shader = shader);
  }

  @override
  bool shouldRepaint(covariant ScoopTrailPainter old) =>
      old.radius != radius || old.stroke != stroke || old.base != base || old.comet != comet;
}
