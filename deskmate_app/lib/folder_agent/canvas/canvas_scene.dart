// Canvas scene state + painter.
//
// Paint semantics follow FilDOS graphViz.buildPaint exactly:
//  - every node is always drawn; the edge-kind chips only remove links;
//  - a node is "active" when it matches the search, its file mtime is inside
//    the scrubber window, and (with a selection) it is the selected node or
//    one of its neighbours. Active nodes draw at alpha 0.96, the rest at 0.08;
//  - a link is lit when both ends are active — Blueberry similar links at
//    0.12 + 0.3·weight (width 0.6 + weight), other kinds at 0.22 (width 0.8)
//    — otherwise 0.02;
//  - hovering never repaints the graph: it only adds the Ink hover ring (the
//    cosmos `renderHoveredPointRing`) and the hover card.
//
// Performance model: the snapshot is flattened once ([CanvasGraph]). A
// [_RenderPlan] (world-space Float32List batches: link lines per kind ×
// weight bucket, node points per colour/size bucket) is rebuilt only when
// what's *lit* changes (filters, selection, search, time range, intro
// frames) — never on pan/zoom or hover, which only change the transform or
// the ring. Edges go out as one `drawRawPoints(PointMode.lines)` per batch,
// nodes as round-capped `drawRawPoints(PointMode.points)` per bucket.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/fa_theme.dart';
import 'graph_model.dart';

/// Edge kind → scoop, matching the filter chips (one scoop, one meaning).
const edgeColors = {
  EdgeKind.similar: Scoop.blueberry,
  EdgeKind.entity: Scoop.mint,
  EdgeKind.tag: Scoop.grape,
  EdgeKind.temporal: Scoop.mango,
};

const _activeAlpha = 0.96;
const _dimAlpha = 0.08;
const _dimLinkAlpha = 0.02;

/// Similar-link weight buckets (alpha / width vary with weight).
const _weightBuckets = 4;

class CanvasScene extends ChangeNotifier {
  CanvasGraph? graph;
  GraphCamera camera = GraphCamera.identity;
  GraphCamera fitCamera = GraphCamera.identity;
  Size viewport = Size.zero;
  bool _needsFit = false;

  /// Fired for interaction-state changes the overlays care about (hover,
  /// selection, filters) — not for camera moves.
  final ChangeNotifier _overlay = ChangeNotifier();
  Listenable get overlay => _overlay;

  /// Time-range filter as fractions of [minTime, maxTime]; null = everything.
  final ValueNotifier<RangeValues?> range = ValueNotifier(null);

  final Set<EdgeKind> kinds = {...EdgeKind.values};
  String query = '';
  int? hovered;
  int? selected;

  /// Intro progress 0..1 (already eased).
  double intro = 1;

  // derived state
  Uint8List _active = Uint8List(0);
  _RenderPlan? _plan;
  Float32List? _px, _py;

  double get minScale => fitCamera.scale * 0.25;
  double get maxScale => math.max(fitCamera.scale * 40, 6);

  /// Node size multiplier: nodes grow gently as you zoom in.
  double get zoomK => math.sqrt(camera.scale / fitCamera.scale).clamp(0.7, 3.2);

  void setGraph(CanvasGraph? g) {
    graph = g;
    _px = _py = null;
    hovered = null;
    selected = null;
    range.value = null;
    _clearLabels();
    _needsFit = true;
    _fitIfReady();
    _invalidate();
  }

  // ── camera ────────────────────────────────────────────────────────────────
  void setCamera(GraphCamera c) {
    if (c == camera) return;
    camera = c;
    notifyListeners();
  }

  GraphCamera computeFit() {
    final g = graph;
    if (g == null || viewport.isEmpty) return camera;
    return GraphCamera.fit(g.bounds.inflate(20), viewport, maxScale: 1.6);
  }

  /// Called at paint time with the real canvas size (silently — no notifications mid-paint).
  void syncViewport(Size size) {
    if (size == viewport) return;
    final old = viewport;
    viewport = size;
    if (!old.isEmpty && !_needsFit) {
      // Keep the world point at the centre stable across resizes.
      final c = camera.toWorld(old.center(Offset.zero));
      camera = GraphCamera.centredOn(c, size, camera.scale);
      fitCamera = computeFit();
    }
    _fitIfReady();
  }

  void _fitIfReady() {
    if (!_needsFit || graph == null || viewport.isEmpty) return;
    _needsFit = false;
    fitCamera = computeFit();
    camera = fitCamera;
  }

  // ── interaction state ─────────────────────────────────────────────────────

  /// Hover only moves the ring — the plan (and so the whole graph) is untouched.
  void setHover(int? i) {
    if (i == hovered) return;
    hovered = i;
    _overlay.notifyListeners();
    notifyListeners();
  }

  void setSelected(int? i) {
    if (i == selected) return;
    selected = i;
    _invalidate();
  }

  void setQuery(String q) {
    final v = q.trim().toLowerCase();
    if (v == query) return;
    query = v;
    _invalidate();
  }

  void toggleKind(EdgeKind k) {
    kinds.contains(k) ? kinds.remove(k) : kinds.add(k);
    _invalidate();
  }

  void setRange(RangeValues? r) {
    if (r != null && r.start <= 0.001 && r.end >= 0.999) r = null;
    if (r == range.value) return;
    range.value = r;
    _invalidate();
  }

  void setIntro(double t) {
    intro = t;
    _plan = null;
    notifyListeners();
  }

  void _invalidate() {
    _plan = null;
    _masks = false;
    _overlay.notifyListeners();
    notifyListeners();
  }

  // ── active mask (FilDOS buildPaint) ───────────────────────────────────────
  bool _masks = false;

  /// Every node is drawn; kept for callers that ask.
  bool isVisible(int i) => graph != null && i < graph!.length;

  bool isActive(int i) {
    _ensureMasks();
    return i < _active.length && _active[i] == 1;
  }

  void _ensureMasks() {
    if (_masks) return;
    _masks = true;
    final g = graph;
    if (g == null) {
      _active = Uint8List(0);
      return;
    }
    final n = g.length;
    final r = range.value;
    final (t0, t1) = r == null ? (-double.infinity, double.infinity) : timeWindow(r.start, r.end, g.minTime, g.maxTime);
    final sel = selected != null && selected! < n ? selected : null;
    Uint8List? keep;
    if (sel != null) {
      keep = Uint8List(n)..[sel] = 1;
      for (var j = g.adjStart[sel]; j < g.adjStart[sel + 1]; j++) {
        if (kinds.contains(EdgeKind.values[g.edgeKind[g.adjEdge[j]]])) keep[g.adj[j]] = 1;
      }
    }
    final active = Uint8List(n);
    for (var i = 0; i < n; i++) {
      var on = query.isEmpty || g.labelLower[i].contains(query);
      if (on && r != null && g.kind[i] == NodeKind.file) {
        final t = g.mtime[i].isNaN ? 0.0 : g.mtime[i];
        on = t >= t0 && t <= t1;
      }
      if (on && keep != null) on = keep[i] == 1;
      active[i] = on ? 1 : 0;
    }
    _active = active;
  }

  /// Every connection of [i] across all edge kinds, strongest first (FilDOS
  /// detail panel: `snapshot.edges` touching the node, top 24 by weight).
  List<({int node, EdgeKind kind, double weight})> connectionsOf(int i, {int cap = 24}) {
    final g = graph;
    if (g == null) return const [];
    final out = <({int node, EdgeKind kind, double weight})>[];
    for (var j = g.adjStart[i]; j < g.adjStart[i + 1]; j++) {
      final e = g.adjEdge[j];
      out.add((node: g.adj[j], kind: EdgeKind.values[g.edgeKind[e]], weight: g.edgeWeight[e]));
    }
    out.sort((a, b) => b.weight.compareTo(a.weight));
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  /// Highest-priority node whose label matches the query.
  int? firstMatch() {
    final g = graph;
    if (g == null || query.isEmpty) return null;
    for (final i in g.priority) {
      if (g.labelLower[i].contains(query)) return i;
    }
    return null;
  }

  // ── positions / hit-testing ───────────────────────────────────────────────
  void _ensurePositions() {
    final g = graph!;
    if (intro >= 1) {
      _px = g.x;
      _py = g.y;
      return;
    }
    final n = g.length;
    final px = (_px != null && _px!.length == n && !identical(_px, g.x)) ? _px! : Float32List(n);
    final py = (_py != null && _py!.length == n && !identical(_py, g.y)) ? _py! : Float32List(n);
    final t = intro;
    for (var i = 0; i < n; i++) {
      px[i] = g.startX[i] + (g.x[i] - g.startX[i]) * t;
      py[i] = g.startY[i] + (g.y[i] - g.startY[i]) * t;
    }
    _px = px;
    _py = py;
  }

  /// Screen position of node [i] (final layout).
  Offset screenOf(int i) => camera.toScreen(graph!.x[i], graph!.y[i]);

  /// Screen radius of node [i].
  double screenRadius(int i) => graph!.radius[i] * zoomK;

  /// The node under [screen], if any (nearest within its radius + slop).
  int? hitTest(Offset screen) {
    final g = graph;
    if (g == null) return null;
    final w = camera.toWorld(screen);
    final s = camera.scale;
    final k = zoomK;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < g.length; i++) {
      final dx = g.x[i] - w.dx, dy = g.y[i] - w.dy;
      final d2 = dx * dx + dy * dy;
      final r = (g.radius[i] * k + 4) / s;
      if (d2 <= r * r && d2 < bestD) {
        bestD = d2;
        best = i;
      }
    }
    return best;
  }

  // ── render plan ───────────────────────────────────────────────────────────
  _RenderPlan _ensurePlan() {
    final existing = _plan;
    if (existing != null) return existing;
    _ensureMasks();
    _ensurePositions();
    final g = graph!;
    final px = _px!, py = _py!;
    final act = _active;

    // Links: batch key = kind × weight bucket (lit) or kind (dim).
    final kc = EdgeKind.values.length;
    final litCount = List<int>.filled(kc * _weightBuckets, 0), dimCount = List<int>.filled(kc, 0);
    final key = Int16List(g.edgeCount)..fillRange(0, g.edgeCount, -1);
    for (var e = 0; e < g.edgeCount; e++) {
      final k = g.edgeKind[e];
      if (!kinds.contains(EdgeKind.values[k])) continue;
      final a = g.edgeA[e], b = g.edgeB[e];
      if (act[a] == 1 && act[b] == 1) {
        final bucket = k == EdgeKind.similar.index ? (g.edgeWeight[e].clamp(0.0, 0.999) * _weightBuckets).floor() : 0;
        key[e] = k * _weightBuckets + bucket;
        litCount[key[e]]++;
      } else {
        key[e] = 1000 + k;
        dimCount[k]++;
      }
    }
    final litPts = [for (final n in litCount) Float32List(n * 4)];
    final dimPts = [for (final n in dimCount) Float32List(n * 4)];
    final li = List<int>.filled(litPts.length, 0), di = List<int>.filled(kc, 0);
    for (var e = 0; e < g.edgeCount; e++) {
      final kk = key[e];
      if (kk < 0) continue;
      final a = g.edgeA[e], b = g.edgeB[e];
      final dim = kk >= 1000;
      final slot = dim ? kk - 1000 : kk;
      final buf = dim ? dimPts[slot] : litPts[slot];
      var o = dim ? di[slot] : li[slot];
      buf[o++] = px[a];
      buf[o++] = py[a];
      buf[o++] = px[b];
      buf[o++] = py[b];
      dim ? di[slot] = o : li[slot] = o;
    }

    // Nodes: file points bucketed by colour slot × half-pixel radius.
    final litBuckets = <int, List<double>>{}, dimBuckets = <int, List<double>>{};
    final entLit = <int>[], entDim = <int>[], tagLit = <int>[], tagDim = <int>[];
    for (var i = 0; i < g.length; i++) {
      final on = act[i] == 1;
      switch (g.kind[i]) {
        case NodeKind.entity:
          (on ? entLit : entDim).add(i);
        case NodeKind.tag:
          (on ? tagLit : tagDim).add(i);
        default:
          final k = g.slot[i] * 64 + (g.radius[i] * 2).round();
          ((on ? litBuckets : dimBuckets)[k] ??= <double>[])
            ..add(px[i])
            ..add(py[i]);
      }
    }
    List<_NodeBatch> batches(Map<int, List<double>> m) => [
      for (final e in m.entries) _NodeBatch(e.key ~/ 64, (e.key % 64) / 2, Float32List.fromList(e.value)),
    ];
    return _plan = _RenderPlan(
      litEdges: litPts,
      dimEdges: dimPts,
      litNodes: batches(litBuckets),
      dimNodes: batches(dimBuckets),
      entLit: entLit,
      entDim: entDim,
      tagLit: tagLit,
      tagDim: tagDim,
    );
  }

  // ── labels ────────────────────────────────────────────────────────────────
  final Map<int, TextPainter> _labels = {};
  Color? _labelColor;

  TextPainter _label(int i, Color color) {
    if (_labelColor != color) {
      _clearLabels();
      _labelColor = color;
    }
    return _labels[i] ??= TextPainter(
      text: TextSpan(
        text: graph!.nodes[i].label,
        style: FaText.sans(size: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);
  }

  void _clearLabels() {
    for (final p in _labels.values) {
      p.dispose();
    }
    _labels.clear();
  }

  @override
  void dispose() {
    _clearLabels();
    range.dispose();
    _overlay.dispose();
    super.dispose();
  }
}

class _NodeBatch {
  final int slot;
  final double radius;
  final Float32List points;
  _NodeBatch(this.slot, this.radius, this.points);
}

class _RenderPlan {
  /// Indexed by `kind * _weightBuckets + bucket`.
  final List<Float32List> litEdges;

  /// Indexed by kind.
  final List<Float32List> dimEdges;
  final List<_NodeBatch> litNodes, dimNodes;
  final List<int> entLit, entDim, tagLit, tagDim;
  _RenderPlan({
    required this.litEdges,
    required this.dimEdges,
    required this.litNodes,
    required this.dimNodes,
    required this.entLit,
    required this.entDim,
    required this.tagLit,
    required this.tagDim,
  });
}

class CanvasPainter extends CustomPainter {
  final CanvasScene scene;
  final FaColors colors;
  CanvasPainter(this.scene, this.colors) : super(repaint: scene);

  Color _slotColor(int slot) => slot < 6
      ? Scoop.all[slot]
      : slot == ColorSlot.mint
      ? Scoop.mint
      : colors.mutedForeground;

  @override
  void paint(Canvas canvas, Size size) {
    scene.syncViewport(size);
    final g = scene.graph;
    if (g == null || g.length == 0) return;
    final plan = scene._ensurePlan();
    final cam = scene.camera;
    final s = cam.scale;
    final k = scene.zoomK;
    final px = scene._px!, py = scene._py!;
    final fade = scene.intro.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(cam.offset.dx, cam.offset.dy);
    canvas.scale(s);

    // ── links (screen-px widths, like cosmos) ──
    final edgePaint = Paint()..isAntiAlias = true;
    for (final kind in EdgeKind.values) {
      final dim = plan.dimEdges[kind.index];
      if (dim.isEmpty) continue;
      edgePaint
        ..color = edgeColors[kind]!.withValues(alpha: _dimLinkAlpha * fade)
        ..strokeWidth = 0.8 / s;
      canvas.drawRawPoints(ui.PointMode.lines, dim, edgePaint);
    }
    for (final kind in EdgeKind.values) {
      for (var b = 0; b < _weightBuckets; b++) {
        final lit = plan.litEdges[kind.index * _weightBuckets + b];
        if (lit.isEmpty) continue;
        final similar = kind == EdgeKind.similar;
        final w = (b + 0.5) / _weightBuckets;
        edgePaint
          ..color = edgeColors[kind]!.withValues(alpha: (similar ? 0.12 + 0.3 * w : 0.22) * fade)
          ..strokeWidth = (similar ? 0.6 + w : 0.8) / s;
        canvas.drawRawPoints(ui.PointMode.lines, lit, edgePaint);
      }
    }

    // ── nodes ──
    final dotPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final dimA = _dimAlpha * fade;
    final litA = _activeAlpha * fade;
    void drawBatches(List<_NodeBatch> list, double alpha) {
      for (final b in list) {
        dotPaint
          ..color = _slotColor(b.slot).withValues(alpha: alpha)
          ..strokeWidth = 2 * b.radius * k / s;
        canvas.drawRawPoints(ui.PointMode.points, b.points, dotPaint);
      }
    }

    drawBatches(plan.dimNodes, dimA);
    drawBatches(plan.litNodes, litA);

    // Entities: Mint diamonds.
    void diamonds(List<int> ids, double alpha) {
      if (ids.isEmpty) return;
      final path = Path();
      for (final i in ids) {
        final r = g.radius[i] * k / s;
        final x = px[i], y = py[i];
        path
          ..moveTo(x, y - r)
          ..lineTo(x + r, y)
          ..lineTo(x, y + r)
          ..lineTo(x - r, y)
          ..close();
      }
      canvas.drawPath(path, Paint()..color = Scoop.mint.withValues(alpha: alpha));
    }

    diamonds(plan.entDim, dimA);
    diamonds(plan.entLit, litA);

    // Tags: stars in their own colour.
    final star = Paint();
    void stars(List<int> ids, double alpha) {
      for (final i in ids) {
        star.color = Scoop.parse(g.nodes[i].color, colors.mutedForeground).withValues(alpha: alpha);
        canvas.drawPath(_starPath(px[i], py[i], g.radius[i] * k / s), star);
      }
    }

    stars(plan.tagDim, dimA);
    stars(plan.tagLit, litA);

    // Hover ring (cosmos `renderHoveredPointRing`, Ink).
    final h = scene.hovered;
    if (h != null && h < g.length) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / s
        ..color = colors.foreground;
      canvas.drawCircle(Offset(px[h], py[h]), (g.radius[h] * k + 2.5) / s, ring);
    }
    canvas.restore();

    if (fade >= 0.6) _paintLabels(canvas, size, g, px, py, k);
  }

  static Path _starPath(double cx, double cy, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + rr * math.cos(a), y = cy + rr * math.sin(a);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  /// FilDOS LabelsOverlay: the [kLabelCap] highest-degree nodes (entities
  /// first), text-3xs foreground/80 with a soft drop shadow, centred 8px under
  /// the node; a dimmed node keeps only a ghost (12%) of its label. The set is
  /// fixed, so labels never pop in or out while panning or zooming.
  void _paintLabels(Canvas canvas, Size size, CanvasGraph g, Float32List px, Float32List py, double k) {
    final cam = scene.camera;
    final color = colors.foreground.withValues(alpha: 0.8);
    final view = (Offset.zero & size).inflate(80);
    final shadow = Paint()
      ..color = colors.background.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final n = math.min(kLabelCap, g.length);
    for (var x = 0; x < n; x++) {
      final i = g.priority[x];
      final p = cam.toScreen(px[i], py[i]);
      if (!view.contains(p)) continue;
      final tp = scene._label(i, color);
      final at = Offset((p.dx - tp.width / 2).roundToDouble(), (p.dy + 8).roundToDouble());
      final ghost = !scene.isActive(i);
      if (ghost) {
        canvas.saveLayer(at & tp.size, Paint()..color = Colors.black.withValues(alpha: 0.12));
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius((at & tp.size).inflate(1), const Radius.circular(3)), shadow);
      }
      tp.paint(canvas, at);
      if (ghost) canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CanvasPainter old) => old.scene != scene || old.colors != colors;
}
