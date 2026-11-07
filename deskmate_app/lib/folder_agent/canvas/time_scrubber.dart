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
  static final _fmt = DateFormat('MMM y');

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
    // FilDOS: `border-t px-3 py-2 gap-2.5`; labels w-16 text-3xs tabular.
    final label = FaText.sans(size: 10, color: c.mutedForeground);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  builder: (context, hover) {
                    final fg = hover ? c.foreground : c.mutedForeground;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hover ? c.accent : c.accent.withValues(alpha: 0),
                        borderRadius: BorderRadius.circular(FaRadius.md),
                      ),
                      child: Row(
                        children: [
                          Icon(widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 13, color: fg),
                          const SizedBox(width: 4),
                          Text(widget.playing ? 'Stop' : 'Replay', style: FaText.sans(size: 11, color: fg)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(_label(r.start), style: label, textAlign: TextAlign.right),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    double frac(Offset p) => (p.dx / math.max(1, box.maxWidth)).clamp(0.0, 1.0);
                    return Tooltip(
                      message: 'Drag to focus a period; double-click to reset',
                      waitDuration: const Duration(milliseconds: 900),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragDown: (d) => _down(frac(d.localPosition)),
                          onHorizontalDragUpdate: (d) => _move(frac(d.localPosition)),
                          onDoubleTap: () => widget.onChanged(null),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(box.maxWidth, 32),
                              painter: _HistogramPainter(counts: widget.counts, from: r.start, to: r.end, colors: c),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 64, child: Text(_label(r.end), style: label)),
            ],
          );
        },
      ),
    );
  }
}

/// Bars `gap-px`, height 6% + count/peak·88%, rounded-t 1px — `mint/70` inside
/// the window, `muted-foreground/20` outside — and the brush outline: a
/// `rounded border-x-2 border-mint/60` box spanning the window (min 0.5%).
class _HistogramPainter extends CustomPainter {
  final List<int> counts;
  final double from, to;
  final FaColors colors;
  _HistogramPainter({required this.counts, required this.from, required this.to, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty) return;
    final peak = math.max(1, counts.reduce(math.max));
    final n = counts.length;
    final bw = (size.width - (n - 1)) / n;
    final lit = Paint()..color = Scoop.mint.withValues(alpha: 0.7);
    final off = Paint()..color = colors.mutedForeground.withValues(alpha: 0.2);
    for (var i = 0; i < n; i++) {
      final h = size.height * (0.06 + (counts[i] / peak) * 0.88);
      final mid = (i + 0.5) / n;
      final rect = Rect.fromLTWH(i * (bw + 1), size.height - h, math.max(0.5, bw), h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(1), topRight: const Radius.circular(1)),
        mid >= from && mid <= to ? lit : off,
      );
    }
    final left = from * size.width;
    final width = math.max(0.005, to - from) * size.width;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, width, size.height), const Radius.circular(4));
    final edge = Paint()..color = Scoop.mint.withValues(alpha: 0.6);
    canvas.save();
    canvas.clipRRect(box);
    canvas.drawRect(Rect.fromLTWH(left, 0, 2, size.height), edge);
    canvas.drawRect(Rect.fromLTWH(left + width - 2, 0, 2, size.height), edge);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HistogramPainter o) =>
      o.from != from || o.to != to || !identical(o.counts, counts) || o.colors != colors;
}
