import 'dart:ui';

import 'package:deskmate_app/folder_agent/canvas/graph_model.dart';
import 'package:deskmate_app/folder_agent/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GraphCamera', () {
    test('fit centres the world rect and respects padding', () {
      final cam = GraphCamera.fit(const Rect.fromLTRB(-1000, -500, 1000, 500), const Size(1100, 700), padding: 50);
      expect(cam.scale, closeTo(0.5, 1e-9)); // (1100-100)/2000 vs (700-100)/1000
      final centre = cam.toScreen(0, 0);
      expect(centre.dx, closeTo(550, 1e-9));
      expect(centre.dy, closeTo(350, 1e-9));
      final tl = cam.toScreen(-1000, -500);
      expect(tl.dx, closeTo(50, 1e-9));
    });

    test('fit caps scale for tiny graphs', () {
      final cam = GraphCamera.fit(const Rect.fromLTRB(0, 0, 10, 10), const Size(800, 600), maxScale: 2);
      expect(cam.scale, 2);
    });

    test('zoomAt keeps the focal world point fixed and clamps', () {
      const cam = GraphCamera(0.5, Offset(100, 40));
      const focal = Offset(320, 210);
      final before = cam.toWorld(focal);
      final z = cam.zoomAt(focal, 3);
      expect(z.scale, 1.5);
      final after = z.toWorld(focal);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
      expect(cam.zoomAt(focal, 100, maxScale: 4).scale, 4);
    });

    test('toWorld inverts toScreen and lerp hits both ends', () {
      const a = GraphCamera(0.25, Offset(10, 20));
      final w = a.toWorld(a.toScreen(123, -45));
      expect(w.dx, closeTo(123, 1e-9));
      expect(w.dy, closeTo(-45, 1e-9));
      const vp = Size(800, 600);
      final b = GraphCamera.centredOn(const Offset(500, 500), vp, 2);
      expect(GraphCamera.lerp(a, b, vp, 0).scale, closeTo(0.25, 1e-9));
      final end = GraphCamera.lerp(a, b, vp, 1);
      expect(end.scale, closeTo(2, 1e-9));
      expect(end.toWorld(vp.center(Offset.zero)).dx, closeTo(500, 1e-6));
      expect(GraphCamera.lerp(a, b, vp, 0.5).scale, closeTo(0.70710678, 1e-6)); // geometric mean
    });
  });

  group('time histogram', () {
    test('buckets into equal bins, clamps max into last bin, skips NaN', () {
      final h = timeHistogram([0, 1, 4.9, 5, 9.99, 10, double.nan], 0, 10, 2);
      expect(h, [3, 3]);
    });
    test('degenerate span puts everything in the first bin', () {
      expect(timeHistogram([5, 5, 5], 5, 5, 4), [3, 0, 0, 0]);
    });
    test('timeWindow maps fractions onto the range', () {
      expect(timeWindow(0.25, 0.75, 100, 200), (125.0, 175.0));
    });
  });

  test('CanvasGraph flattens a snapshot', () {
    GraphNode file(String id, int cluster, double x, {int deg = 1, int t = 1000}) => GraphNode(
      id: id,
      kind: 'file',
      label: id.toUpperCase(),
      path: '/tmp/$id',
      mtime: DateTime.fromMillisecondsSinceEpoch(t * 1000),
      degree: deg,
      clusterId: cluster,
      x: x,
      y: 0,
    );
    final snap = GraphSnapshot(
      [
        file('a', 0, -10, deg: 2, t: 100),
        file('b', 0, 10, t: 300),
        file('c', -1, 50, t: 200),
        const GraphNode(id: 'e:x', kind: 'entity', label: 'X', degree: 2, clusterId: 0, x: 0, y: 5),
      ],
      const [
        GraphEdge('a', 'b', 'similar', 0.9),
        GraphEdge('e:x', 'a', 'entity', 0.7),
        GraphEdge('e:x', 'b', 'entity', 0.7),
        GraphEdge('a', 'missing', 'similar', 0.9),
      ],
      DateTime(2026),
      const {'minTime': 100, 'maxTime': 300},
    );
    final g = CanvasGraph.fromSnapshot(snap);
    expect(g.length, 4);
    expect(g.edgeCount, 3); // dangling edge dropped
    expect(g.fileCount, 3);
    expect(g.slot[g.indexOf['a']!], 0);
    expect(g.slot[g.indexOf['c']!], ColorSlot.muted);
    expect(g.slot[g.indexOf['e:x']!], ColorSlot.mint);
    expect(g.bounds, const Rect.fromLTRB(-10, 0, 50, 5));
    expect(g.minTime, 100);
    expect(g.maxTime, 300);
    // CSR: 'a' touches b (similar) and e:x (entity).
    final a = g.indexOf['a']!;
    final nbrs = {for (var j = g.adjStart[a]; j < g.adjStart[a + 1]; j++) g.adj[j]};
    expect(nbrs, {g.indexOf['b']!, g.indexOf['e:x']!});
    // Priority: entity first.
    expect(g.priority.first, g.indexOf['e:x']);
    // Cluster 0 intro start = centroid of its members (a, b, e:x).
    expect(g.startX[a], closeTo(0, 1e-6));
  });
}
