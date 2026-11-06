// Canvas scene state + painter.
//
// Performance model: the snapshot is flattened once ([CanvasGraph]). A
// [_RenderPlan] (world-space Float32List batches: edge lines per kind, node
// points per colour/size bucket) is rebuilt only when what's *shown* changes
// (filters, hover/selection, time range, intro frames) — never on pan/zoom,
// which only changes the canvas transform. Edges go out as one
// `drawRawPoints(PointMode.lines)` per kind/state, nodes as round-capped
// `drawRawPoints(PointMode.points)` per bucket: ~a few dozen draw calls for
// 4k nodes / 20k edges. Nothing animates unless the user (or the intro /
// replay) is driving it.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/fa_theme.dart';
import 'graph_model.dart';

const edgeColors = {
  EdgeKind.similar: Scoop.blueberry,
  EdgeKind.entity: Scoop.mint,
  EdgeKind.tag: Scoop.grape,
  EdgeKind.temporal: Scoop.mango,
};

class CanvasScene extends ChangeNotifier {
  CanvasGraph? graph;
  GraphCamera camera = GraphCamera.identity;
  GraphCamera fitCamera = GraphCamera.identity;
  Size viewport = Size.zero;
  bool _needsFit = false;

  /// Fired for everything except camera moves (hover, selection, filters).
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
  Uint8List _visible = Uint8List(0);
  Uint8List _lit = Uint8List(0);
  int _matches = 0;
  _RenderPlan? _plan;
  Float32List? _px, _py;

  int? get focus => hovered ?? selected;
  bool get emphasis => query.isNotEmpty || focus != null;
  int get matchCount => _matches;

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
  void setHover(int? i) {
    if (i == hovered) return;
    hovered = i;
    _invalidate();
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
    if (r != null && r.start <= 0.0005 && r.end >= 0.9995) r = null;
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

  // ── masks ─────────────────────────────────────────────────────────────────
  bool _masks = false;

  bool isVisible(int i) {
    _ensureMasks();
    return i < _visible.length && _visible[i] == 1;
  }

  bool isLit(int i) {
    _ensureMasks();
    return i < _lit.length && _lit[i] == 1;
  }

  void _ensureMasks() {
    if (_masks) return;
    _masks = true;
    final g = graph;
    if (g == null) {
      _visible = Uint8List(0);
      _lit = Uint8List(0);
      _matches = 0;
      return;
    }
    final n = g.length;
    final vis = Uint8List(n);
    final r = range.value;
    final (t0, t1) = r == null ? (-double.infinity, double.infinity) : timeWindow(r.start, r.end, g.minTime, g.maxTime);
    final upperOpen = r == null || r.end >= 0.999;
    for (var i = 0; i < n; i++) {
      if (g.kind[i] != NodeKind.file) continue;
      final t = g.mtime[i];
      vis[i] = (t.isNaN || (t >= t0 && (upperOpen || t <= t1))) ? 1 : 0;
    }
    // Entity / tag hubs show when their kind is on and they link a visible file.
    final entOn = kinds.contains(EdgeKind.entity), tagOn = kinds.contains(EdgeKind.tag);
    for (var e = 0; e < g.edgeCount; e++) {
      final k = g.edgeKind[e];
      if (k == EdgeKind.entity.index && entOn || k == EdgeKind.tag.index && tagOn) {
        final a = g.edgeA[e], b = g.edgeB[e];
        if (g.kind[a] != NodeKind.file && g.kind[b] == NodeKind.file && vis[b] == 1) vis[a] = 1;
        if (g.kind[b] != NodeKind.file && g.kind[a] == NodeKind.file && vis[a] == 1) vis[b] = 1;
      }
    }

    final lit = Uint8List(n);
    var matches = 0;
    for (var i = 0; i < n; i++) {
      if (vis[i] == 0) continue;
      final m = query.isEmpty || g.labelLower[i].contains(query);
      if (m) {
        lit[i] = 1;
        if (query.isNotEmpty) matches++;
      }
    }
    final f = focus;
    if (f != null && f < n && vis[f] == 1) {
      final keep = Uint8List(n)..[f] = 1;
      for (var j = g.adjStart[f]; j < g.adjStart[f + 1]; j++) {
        final nb = g.adj[j];
        if (vis[nb] == 1 && kinds.contains(EdgeKind.values[g.edgeKind[g.adjEdge[j]]])) keep[nb] = 1;
      }
      for (var i = 0; i < n; i++) {
        // The focus set stays lit even when it doesn't match the search.
        lit[i] = keep[i];
      }
    }
    _visible = vis;
    _lit = lit;
    _matches = matches;
  }

  /// Number of visible neighbours of [i] (through enabled edge kinds).
  List<int> neighboursOf(int i) {
    final g = graph;
    if (g == null) return const [];
    _ensureMasks();
    final out = <int>{};
    for (var j = g.adjStart[i]; j < g.adjStart[i + 1]; j++) {
      final nb = g.adj[j];
      if (_visible[nb] == 1 && kinds.contains(EdgeKind.values[g.edgeKind[g.adjEdge[j]]])) out.add(nb);
    }
    return out.toList();
  }

  /// Highest-priority visible node whose label matches the query.
  int? firstMatch() {
    final g = graph;
    if (g == null || query.isEmpty) return null;
    _ensureMasks();
    for (final i in g.priority) {
      if (_visible[i] == 1 && g.labelLower[i].contains(query)) return i;
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

  /// The visible node under [screen], if any (nearest within its radius + slop).
  int? hitTest(Offset screen) {
    final g = graph;
    if (g == null) return null;
    _ensureMasks();
    final w = camera.toWorld(screen);
    final s = camera.scale;
    final k = zoomK;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < g.length; i++) {
      if (_visible[i] == 0) continue;
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
    final vis = _visible, lit = _lit;

    // Edges: count first so each batch is a single exact-size Float32List.
    final kc = EdgeKind.values.length;
    final litCount = List<int>.filled(kc, 0), dimCount = List<int>.filled(kc, 0);
    final state = Uint8List(g.edgeCount); // 0 hidden, 1 dim, 2 lit
    final emph = emphasis;
    for (var e = 0; e < g.edgeCount; e++) {
      final k = g.edgeKind[e];
      if (!kinds.contains(EdgeKind.values[k])) continue;
      final a = g.edgeA[e], b = g.edgeB[e];
      if (vis[a] == 0 || vis[b] == 0) continue;
      final on = !emph || (lit[a] == 1 && lit[b] == 1);
      state[e] = on ? 2 : 1;
      on ? litCount[k]++ : dimCount[k]++;
    }
    final litPts = [for (var k = 0; k < kc; k++) Float32List(litCount[k] * 4)];
    final dimPts = [for (var k = 0; k < kc; k++) Float32List(dimCount[k] * 4)];
    final li = List<int>.filled(kc, 0), di = List<int>.filled(kc, 0);
    for (var e = 0; e < g.edgeCount; e++) {
      final st = state[e];
      if (st == 0) continue;
      final k = g.edgeKind[e];
      final a = g.edgeA[e], b = g.edgeB[e];
      final buf = st == 2 ? litPts[k] : dimPts[k];
      var o = st == 2 ? li[k] : di[k];
      buf[o++] = px[a];
      buf[o++] = py[a];
      buf[o++] = px[b];
      buf[o++] = py[b];
      st == 2 ? li[k] = o : di[k] = o;
    }

    // Nodes: file points bucketed by colour slot × half-pixel radius.
    final litBuckets = <int, List<double>>{}, dimBuckets = <int, List<double>>{};
    final entLit = <int>[], entDim = <int>[], tagLit = <int>[], tagDim = <int>[];
    for (var i = 0; i < g.length; i++) {
      if (vis[i] == 0) continue;
      final on = !emph || lit[i] == 1;
      switch (g.kind[i]) {
        case NodeKind.entity:
          (on ? entLit : entDim).add(i);
        case NodeKind.tag:
          (on ? tagLit : tagDim).add(i);
        default:
          final key = g.slot[i] * 64 + (g.radius[i] * 2).round();
          ((on ? litBuckets : dimBuckets)[key] ??= <double>[])
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

  TextPainter _label(int i, Color color, {bool bold = false}) {
    if (_labelColor != color) {
      _clearLabels();
      _labelColor = color;
    }
    final key = bold ? -1 - i : i;
    return _labels[key] ??= TextPainter(
      text: TextSpan(
        text: graph!.nodes[i].label,
        style: FaText.sans(size: bold ? 11.5 : 10.5, weight: bold ? FontWeight.w600 : FontWeight.w500, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 170);
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
  final List<Float32List> litEdges, dimEdges;
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
    final dark = colors.isDark;
    final fade = scene.intro.clamp(0.0, 1.0);
    final emph = scene.emphasis;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(cam.offset.dx, cam.offset.dy);
    canvas.scale(s);

    // ── edges ──
    final edgePaint = Paint()
      ..strokeWidth = 1 / s
      ..isAntiAlias = true;
    final baseAlpha = dark ? 0.22 : 0.30;
    for (final kind in EdgeKind.values) {
      final dim = plan.dimEdges[kind.index];
      if (dim.isNotEmpty) {
        edgePaint.color = edgeColors[kind]!.withValues(alpha: (dark ? 0.035 : 0.05) * fade);
        canvas.drawRawPoints(ui.PointMode.lines, dim, edgePaint);
      }
    }
    for (final kind in EdgeKind.values) {
      final lit = plan.litEdges[kind.index];
      if (lit.isEmpty) continue;
      edgePaint
        ..color = edgeColors[kind]!.withValues(alpha: (emph ? 0.65 : baseAlpha) * fade)
        ..strokeWidth = (emph ? 1.3 : 1) / s;
      canvas.drawRawPoints(ui.PointMode.lines, lit, edgePaint);
    }

    // ── nodes ──
    final dotPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final dimA = (dark ? 0.14 : 0.18) * fade;
    void drawBatches(List<_NodeBatch> list, double alpha) {
      for (final b in list) {
        dotPaint
          ..color = _slotColor(b.slot).withValues(alpha: alpha)
          ..strokeWidth = 2 * b.radius * k / s;
        canvas.drawRawPoints(ui.PointMode.points, b.points, dotPaint);
      }
    }

    drawBatches(plan.dimNodes, dimA);
    drawBatches(plan.litNodes, 0.95 * fade);

    // Entities: Mint diamonds.
    void diamonds(List<int> ids, double alpha) {
      if (ids.isEmpty) return;
      final path = Path();
      for (final i in ids) {
        final r = g.radius[i] * k * 1.25 / s;
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
    diamonds(plan.entLit, 0.95 * fade);

    // Tags: rings in their own colour.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / s;
    void rings(List<int> ids, double alpha) {
      for (final i in ids) {
        ring.color = Scoop.parse(g.nodes[i].color, Scoop.grape).withValues(alpha: alpha);
        canvas.drawCircle(Offset(px[i], py[i]), g.radius[i] * k / s, ring);
      }
    }

    rings(plan.tagDim, dimA);
    rings(plan.tagLit, 0.95 * fade);

    // Focus / selection rings.
    final hl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / s
      ..color = colors.foreground.withValues(alpha: 0.9);
    for (final i in {?scene.selected, ?scene.hovered}) {
      if (i >= g.length || !scene.isVisible(i)) continue;
      canvas.drawCircle(Offset(px[i], py[i]), (g.radius[i] * k + 3.5) / s, hl);
    }
    canvas.restore();

    if (fade >= 0.6) _paintLabels(canvas, size, g, px, py, k);
  }

  void _paintLabels(Canvas canvas, Size size, CanvasGraph g, Float32List px, Float32List py, double k) {
    final cam = scene.camera;
    final emph = scene.emphasis;
    final cap = (22 * k * k).clamp(22, 90).round();
    final color = colors.foreground.withValues(alpha: 0.82);
    final shadow = colors.background;
    final placed = <Rect>[];
    final view = (Offset.zero & size).inflate(40);

    bool place(int i, {bool bold = false}) {
      final p = cam.toScreen(px[i], py[i]);
      if (!view.contains(p)) return false;
      final r = g.radius[i] * k;
      // Cheap estimate first so crowded areas don't lay out text they'll never show.
      final est = math.min(170.0, g.nodes[i].label.length * 5.6);
      final guess = Rect.fromLTWH(p.dx - est / 2, p.dy + r + 3, est, 13);
      for (final o in placed) {
        if (o.overlaps(guess)) return false;
      }
      final tp = scene._label(i, color, bold: bold);
      final rect = Rect.fromLTWH(p.dx - tp.width / 2, p.dy + r + 3, tp.width, tp.height);
      for (final o in placed) {
        if (o.overlaps(rect)) return false;
      }
      placed.add(rect);
      // A soft halo in the background colour keeps labels legible over edges.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(3)),
        Paint()..color = shadow.withValues(alpha: 0.55),
      );
      tp.paint(canvas, rect.topLeft);
      return true;
    }

    final f = scene.focus;
    if (f != null && scene.isVisible(f)) place(f, bold: true);
    var drawn = placed.length;
    var tries = 0;
    for (final i in g.priority) {
      if (drawn >= cap || tries > cap * 6) break;
      if (i == f || !scene.isVisible(i)) continue;
      if (emph && !scene.isLit(i)) continue;
      if (!view.contains(cam.toScreen(px[i], py[i]))) continue;
      tries++;
      if (place(i)) drawn++;
    }
  }

  @override
  bool shouldRepaint(CanvasPainter old) => old.scene != scene || old.colors != colors;
}
