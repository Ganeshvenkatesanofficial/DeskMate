import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/fa_theme.dart';
import '../widgets/ui.dart';

/// The Canvas time scrubber: a histogram of file mtimes (Mint bars) with a
/// draggable range brush, plus a Replay button that sweeps the window forward
/// so files appear in the order they were worked on. The range is a pair of
/// fractions over `[min, max]` (seconds since epoch); null means everything.
class TimeScrubber extends StatefulWidget {
  final List<int> counts;
  final double min;
  final double max;
  final ValueNotifier<RangeValues?> range;
  final ValueChanged<RangeValues?> onChanged;
  final bool playing;
  final VoidCallback onTogglePlay;

  const TimeScrubber({
    super.key,
    required this.counts,
    required this.min,
    required this.max,
    required this.range,
    required this.onChanged,
    required this.playing,
    required this.onTogglePlay,
  });

  @override
  State<TimeScrubber> createState() => _TimeScrubberState();
}

class _TimeScrubberState extends State<TimeScrubber> {
  bool _dragFrom = false;
  static final _fmt = DateFormat('MMM yyyy');

  String _label(double f) =>
      _fmt.format(DateTime.fromMillisecondsSinceEpoch(((widget.min + f * (widget.max - widget.min)) * 1000).round()));

  void _down(double f) {
    final r = widget.range.value ?? const RangeValues(0, 1);
    _dragFrom = (f - r.start).abs() <= (f - r.end).abs();
    _move(f);
  }

  void _move(double f) {
    final r = widget.range.value ?? const RangeValues(0, 1);
    widget.onChanged(_dragFrom ? RangeValues(math.min(f, r.end), r.end) : RangeValues(r.start, math.max(f, r.start)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final muted = FaText.sans(size: 11, color: c.mutedForeground);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: ValueListenableBuilder<RangeValues?>(
        valueListenable: widget.range,
        builder: (context, value, _) {
          final r = value ?? const RangeValues(0, 1);
          return Row(
            children: [
              Tooltip(
                message: widget.playing ? 'Stop the replay' : 'Watch your files appear in the order you worked on them',
                child: Hoverable(
                  onTap: widget.onTogglePlay,
                  builder: (context, hover) => Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: hover ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(FaRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.playing ? Icons.stop_rounded : Icons.play_arrow_outlined,
                          size: 15,
                          color: hover || widget.playing ? c.foreground : c.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.playing ? 'Stop' : 'Replay',
                          style: muted.copyWith(color: hover || widget.playing ? c.foreground : c.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 62,
                child: Text(_label(r.start), style: muted, textAlign: TextAlign.right),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    double frac(Offset p) => (p.dx / math.max(1, box.maxWidth)).clamp(0.0, 1.0);
                    return Tooltip(
                      message: 'Drag to focus a period · double-click to reset',
                      waitDuration: const Duration(milliseconds: 900),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragDown: (d) => _down(frac(d.localPosition)),
                          onHorizontalDragUpdate: (d) => _move(frac(d.localPosition)),
                          onDoubleTap: () => widget.onChanged(null),
                          child: CustomPaint(
                            size: Size(box.maxWidth, 30),
                            painter: _HistogramPainter(
                              counts: widget.counts,
                              from: r.start,
                              to: r.end,
                              active: value != null,
                              colors: c,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 62, child: Text(_label(r.end), style: muted)),
            ],
          );
        },
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> counts;
  final double from, to;
  final bool active;
  final FaColors colors;
  _HistogramPainter({
    required this.counts,
    required this.from,
    required this.to,
    required this.active,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty) return;
    final peak = math.max(1, counts.reduce(math.max));
    final n = counts.length;
    final bw = size.width / n;
    final lit = Paint()..color = Scoop.mint.withValues(alpha: 0.75);
    final off = Paint()..color = colors.mutedForeground.withValues(alpha: 0.22);
    for (var i = 0; i < n; i++) {
      final h = counts[i] == 0 ? 2.0 : 3 + (counts[i] / peak) * (size.height - 4);
      final mid = (i + 0.5) / n;
      final rect = Rect.fromLTWH(i * bw + 0.5, size.height - h, math.max(0.5, bw - 1), h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(1), topRight: const Radius.circular(1)),
        mid >= from && mid <= to ? lit : off,
      );
    }
    // Brush window: Mint edges (handles), always shown so they read as draggable.
    final edge = Paint()
      ..color = Scoop.mint.withValues(alpha: active ? 0.9 : 0.55)
      ..strokeWidth = 2;
    for (final f in [from, to]) {
      final x = (f * size.width).clamp(1.0, size.width - 1);
      canvas.drawLine(Offset(x, -2), Offset(x, size.height + 2), edge);
    }
    if (active) {
      final band = Paint()..color = Scoop.mint.withValues(alpha: 0.07);
      canvas.drawRect(Rect.fromLTRB(from * size.width, -2, to * size.width, size.height + 2), band);
    }
  }

  @override
  bool shouldRepaint(_HistogramPainter o) =>
      o.from != from || o.to != to || o.active != active || o.counts != counts || o.colors != colors;
}
