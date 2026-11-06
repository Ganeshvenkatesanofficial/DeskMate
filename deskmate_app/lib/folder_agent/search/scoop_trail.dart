import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fa_theme.dart';

/// The scoop "comet" orbiting a panel's edge (FilDOS' `.scoop-trail`): a
/// sweep gradient — blueberry → mint → grape → bubblegum → mango fading to
/// nothing — rotated by [turn], painted as a hairline ring only so the
/// panel's surface never washes with colour.
class ScoopTrailPainter extends CustomPainter {
  final Animation<double> turn;
  final double radius;
  final double stroke;
  ScoopTrailPainter(this.turn, {this.radius = FaRadius.xl, this.stroke = 1.5}) : super(repaint: turn);

  static const _stops = [0.0, 200 / 360, 240 / 360, 268 / 360, 294 / 360, 320 / 360, 344 / 360, 350 / 360, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = RRect.fromRectAndRadius(rect.deflate(stroke / 2), Radius.circular(radius));
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
      transform: GradientRotation(turn.value * 2 * math.pi),
    ).createShader(rect);
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant ScoopTrailPainter old) => old.radius != radius || old.stroke != stroke;
}
