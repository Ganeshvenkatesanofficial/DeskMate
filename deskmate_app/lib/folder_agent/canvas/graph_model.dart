// Pure data + math for the Canvas: a flat, typed-array view of a
// [GraphSnapshot] (so painting and hit-testing never walk object graphs),
// the 2D camera (pan / zoom-toward-point / fit) and the mtime histogram.
// No widgets here — everything is unit-testable.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../core/models.dart';

enum EdgeKind { similar, entity, tag, temporal }

EdgeKind? edgeKindOf(String s) => switch (s) {
  'similar' => EdgeKind.similar,
  'entity' => EdgeKind.entity,
  'tag' => EdgeKind.tag,
  'temporal' => EdgeKind.temporal,
  _ => null,
};

/// Node kinds as stored in [CanvasGraph.kind].
abstract final class NodeKind {
  static const file = 0;
  static const entity = 1;
  static const tag = 2;
}

/// Colour slots in [CanvasGraph.slot]: 0–5 are the six scoops (by cluster),
/// [muted] is a singleton file, [mint] an entity, [tag] uses the tag's colour.
abstract final class ColorSlot {
  static const muted = 6;
  static const mint = 7;
  static const tag = 8;
}

/// Screen-space node radius (logical px at the fit zoom), gently sub-linear in degree.
double nodeRadius(int kind, int degree) {
  final d = math.sqrt(math.max(0, degree));
  return switch (kind) {
    NodeKind.entity => 3.4 + math.min(3.0, d * 0.5),
    NodeKind.tag => 4.2 + math.min(4.0, d * 0.6),
    _ => 2.4 + math.min(5.0, d * 0.9),
  };
}

/// Flattened, render-ready graph. Index `i` addresses every per-node array.
class CanvasGraph {
  final List<GraphNode> nodes;
  final Map<String, int> indexOf;

  /// Final (precomputed by the backend) world positions.
  final Float32List x, y;

  /// Intro start positions: each node's cluster centre.
  final Float32List startX, startY;
  final Uint8List kind;
  final Uint8List slot;
  final Float32List radius;

  /// Seconds since epoch; NaN when unknown.
  final Float64List mtime;
  final List<String> labelLower;

  final Int32List edgeA, edgeB;
  final Uint8List edgeKind;

  /// CSR adjacency: neighbours of `i` are `adj[adjStart[i] .. adjStart[i+1])`,
  /// reached through edge `adjEdge[..]`.
  final Int32List adjStart, adj, adjEdge;

  /// Node indices by label priority: entities/tags first, then by degree.
  final Int32List priority;
  final Rect bounds;
  final double minTime, maxTime;
  final int fileCount;

  CanvasGraph._({
    required this.nodes,
    required this.indexOf,
    required this.x,
    required this.y,
    required this.startX,
    required this.startY,
    required this.kind,
    required this.slot,
    required this.radius,
    required this.mtime,
    required this.labelLower,
    required this.edgeA,
    required this.edgeB,
    required this.edgeKind,
    required this.adjStart,
    required this.adj,
    required this.adjEdge,
    required this.priority,
    required this.bounds,
    required this.minTime,
    required this.maxTime,
    required this.fileCount,
  });

  int get length => nodes.length;
  int get edgeCount => edgeA.length;

  factory CanvasGraph.fromSnapshot(GraphSnapshot s) {
    final nodes = s.nodes;
    final n = nodes.length;
    final indexOf = <String, int>{};
    final x = Float32List(n), y = Float32List(n);
    final kind = Uint8List(n), slot = Uint8List(n);
    final radius = Float32List(n);
    final mtime = Float64List(n);
    final labels = List<String>.filled(n, '');
    final clusterSize = <int, int>{};
    for (final node in nodes) {
      if (node.clusterId >= 0) clusterSize[node.clusterId] = (clusterSize[node.clusterId] ?? 0) + 1;
    }
    final sumX = <int, double>{}, sumY = <int, double>{};
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    var tMin = double.infinity, tMax = -double.infinity, files = 0;
    for (var i = 0; i < n; i++) {
      final node = nodes[i];
      indexOf[node.id] = i;
      x[i] = node.x;
      y[i] = node.y;
      minX = math.min(minX, node.x);
      maxX = math.max(maxX, node.x);
      minY = math.min(minY, node.y);
      maxY = math.max(maxY, node.y);
      final k = switch (node.kind) {
        'entity' => NodeKind.entity,
        'tag' => NodeKind.tag,
        _ => NodeKind.file,
      };
      kind[i] = k;
      final clustered = node.clusterId >= 0 && (clusterSize[node.clusterId] ?? 0) > 1;
      slot[i] = switch (k) {
        NodeKind.entity => ColorSlot.mint,
        NodeKind.tag => ColorSlot.tag,
        _ => clustered ? node.clusterId % 6 : ColorSlot.muted,
      };
      radius[i] = nodeRadius(k, node.degree);
      labels[i] = node.label.toLowerCase();
      final t = node.mtime == null ? double.nan : node.mtime!.millisecondsSinceEpoch / 1000.0;
      mtime[i] = t;
      if (k == NodeKind.file) {
        files++;
        if (!t.isNaN) {
          tMin = math.min(tMin, t);
          tMax = math.max(tMax, t);
        }
      }
      if (clustered) {
        sumX[node.clusterId] = (sumX[node.clusterId] ?? 0) + node.x;
        sumY[node.clusterId] = (sumY[node.clusterId] ?? 0) + node.y;
      }
    }
    final startX = Float32List(n), startY = Float32List(n);
    for (var i = 0; i < n; i++) {
      final cid = nodes[i].clusterId;
      final size = clusterSize[cid] ?? 0;
      if (cid >= 0 && size > 1) {
        startX[i] = sumX[cid]! / size;
        startY[i] = sumY[cid]! / size;
      } else {
        startX[i] = x[i] * 0.9;
        startY[i] = y[i] * 0.9;
      }
    }

    // Edges (dropping ones whose endpoints aren't in the snapshot).
    final ea = <int>[], eb = <int>[], ek = <int>[];
    for (final e in s.edges) {
      final a = indexOf[e.source], b = indexOf[e.target], k = edgeKindOf(e.kind);
      if (a == null || b == null || k == null || a == b) continue;
      ea.add(a);
      eb.add(b);
      ek.add(k.index);
    }
    final m = ea.length;
    final edgeA = Int32List.fromList(ea), edgeB = Int32List.fromList(eb);
    final edgeKind = Uint8List.fromList(ek);

    final deg = Int32List(n + 1);
    for (var e = 0; e < m; e++) {
      deg[edgeA[e] + 1]++;
      deg[edgeB[e] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      deg[i + 1] += deg[i];
    }
    final adjStart = deg;
    final fill = Int32List.fromList(adjStart);
    final adj = Int32List(2 * m), adjEdge = Int32List(2 * m);
    for (var e = 0; e < m; e++) {
      final a = edgeA[e], b = edgeB[e];
      adj[fill[a]] = b;
      adjEdge[fill[a]++] = e;
      adj[fill[b]] = a;
      adjEdge[fill[b]++] = e;
    }

    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final fa = kind[a] == NodeKind.file ? 1 : 0, fb = kind[b] == NodeKind.file ? 1 : 0;
        if (fa != fb) return fa - fb;
        return nodes[b].degree - nodes[a].degree;
      });

    final statMin = (s.stats['minTime'] as num?)?.toDouble();
    final statMax = (s.stats['maxTime'] as num?)?.toDouble();
    return CanvasGraph._(
      nodes: nodes,
      indexOf: indexOf,
      x: x,
      y: y,
      startX: startX,
      startY: startY,
      kind: kind,
      slot: slot,
      radius: radius,
      mtime: mtime,
      labelLower: labels,
      edgeA: edgeA,
      edgeB: edgeB,
      edgeKind: edgeKind,
      adjStart: adjStart,
      adj: adj,
      adjEdge: adjEdge,
      priority: Int32List.fromList(order),
      bounds: n == 0 ? Rect.zero : Rect.fromLTRB(minX, minY, maxX, maxY),
      minTime: statMin ?? (tMin.isFinite ? tMin : 0),
      maxTime: statMax ?? (tMax.isFinite ? tMax : 0),
      fileCount: files,
    );
  }

  /// Visible file timestamps for the scrubber histogram.
  Iterable<double> get fileTimes sync* {
    for (var i = 0; i < length; i++) {
      if (kind[i] == NodeKind.file && !mtime[i].isNaN) yield mtime[i];
    }
  }
}

/// World → screen transform: `screen = world * scale + offset`.
class GraphCamera {
  final double scale;
  final Offset offset;
  const GraphCamera(this.scale, this.offset);

  static const identity = GraphCamera(1, Offset.zero);

  Offset toScreen(double wx, double wy) => Offset(wx * scale + offset.dx, wy * scale + offset.dy);
  Offset toWorld(Offset screen) => Offset((screen.dx - offset.dx) / scale, (screen.dy - offset.dy) / scale);

  GraphCamera panBy(Offset delta) => GraphCamera(scale, offset + delta);

  /// Zooms by [factor] keeping the world point under [focal] fixed on screen.
  GraphCamera zoomAt(Offset focal, double factor, {double minScale = 1e-4, double maxScale = 1e4}) {
    final next = (scale * factor).clamp(minScale, maxScale);
    final world = toWorld(focal);
    return GraphCamera(next, focal - world * next);
  }

  /// A camera that fits [world] inside [viewport] with [padding] logical px on each side.
  static GraphCamera fit(Rect world, Size viewport, {double padding = 56, double maxScale = 2.0}) {
    if (viewport.isEmpty) return identity;
    final w = math.max(world.width, 1.0), h = math.max(world.height, 1.0);
    final availW = math.max(viewport.width - 2 * padding, 40.0);
    final availH = math.max(viewport.height - 2 * padding, 40.0);
    final s = math.min(math.min(availW / w, availH / h), maxScale);
    return centredOn(world.center, viewport, s);
  }

  /// A camera at [scale] with [world] point at the viewport centre.
  static GraphCamera centredOn(Offset world, Size viewport, double scale) =>
      GraphCamera(scale, viewport.center(Offset.zero) - world * scale);

  /// Smooth camera interpolation: geometric in scale, linear in the world centre.
  static GraphCamera lerp(GraphCamera a, GraphCamera b, Size viewport, double t) {
    final mid = viewport.center(Offset.zero);
    final ca = a.toWorld(mid), cb = b.toWorld(mid);
    final s = math.exp(_lerp(math.log(a.scale), math.log(b.scale), t));
    return centredOn(Offset.lerp(ca, cb, t)!, viewport, s);
  }

  @override
  bool operator ==(Object other) => other is GraphCamera && other.scale == scale && other.offset == offset;
  @override
  int get hashCode => Object.hash(scale, offset);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Counts of [times] in [bins] equal buckets over `[min, max]` (values outside are clamped in).
List<int> timeHistogram(Iterable<double> times, double min, double max, int bins) {
  final counts = List<int>.filled(bins, 0);
  if (bins <= 0) return counts;
  final span = max - min;
  for (final t in times) {
    if (t.isNaN) continue;
    final ix = span <= 0 ? 0 : (((t - min) / span) * bins).floor().clamp(0, bins - 1);
    counts[ix]++;
  }
  return counts;
}

/// The mtime window `[from, to]` (seconds) for a [fraction] range over `[min, max]`.
(double, double) timeWindow(double from, double to, double min, double max) =>
    (min + from * (max - min), min + to * (max - min));
