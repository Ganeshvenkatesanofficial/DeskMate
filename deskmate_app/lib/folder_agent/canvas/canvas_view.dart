import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../shell/pane_header.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'canvas_scene.dart';
import 'graph_model.dart';
import 'time_scrubber.dart';

/// The Canvas: the knowledge graph of the user's indexed files, painted from
/// the backend's precomputed layout. File dots are scoop-coloured by
/// community, entities are Mint diamonds, tags are rings in their own colour;
/// edge kinds match the legend chips. Hover for a file's story, click to pin
/// it, and scrub / replay the timeline below to watch the map grow.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

const _kindLabels = {
  EdgeKind.similar: 'Similar',
  EdgeKind.entity: 'Entities',
  EdgeKind.tag: 'Tags',
  EdgeKind.temporal: 'Sessions',
};
const _phases = ['similarity', 'entities', 'assemble'];

String _phaseText(String? p) => switch (p) {
  'similarity' => 'Connecting files that belong together',
  'entities' => 'Reading who and what is inside your files',
  _ => 'Assembling the map',
};

class _CanvasViewState extends State<CanvasView> with TickerProviderStateMixin {
  late final FaController _app;
  final _scene = CanvasScene();
  final _query = TextEditingController();
  final _canvasFocus = FocusNode(debugLabel: 'canvas');
  final _pointer = ValueNotifier<Offset?>(null);
  final _hoverCursor = ValueNotifier<bool>(false);

  GraphSnapshot? _snapshot;
  CanvasGraph? _graph;
  List<int> _histogram = const [];
  bool _loading = true;
  bool _loadInFlight = false;
  bool _reloadPending = false;
  FaError? _loadError;

  Map<String, dynamic> _status = const {};
  Map<String, dynamic>? _lastAppStatus;
  bool _buildRequested = false;
  bool _wasBuilding = false;
  bool _autoBuilt = false;
  Timer? _poll;

  late final AnimationController _intro;
  late final AnimationController _replay;
  late final AnimationController _camAnim;
  GraphCamera _camFrom = GraphCamera.identity, _camTo = GraphCamera.identity;

  bool _playing = false;
  bool _dragging = false;
  bool _hintDismissed = false;
  double _lastScale = 1;
  int? _lastTapNode;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _app = context.read<FaController>();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..addListener(() => _scene.setIntro(FaMotion.snappy.transform(_intro.value)));
    _replay = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(_onReplayTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _playing = false);
          _scene.setRange(null);
        }
      });
    _camAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() {
        final t = FaMotion.snappy.transform(_camAnim.value);
        _scene.setCamera(GraphCamera.lerp(_camFrom, _camTo, _scene.viewport, t));
      });
    _app.addListener(_onApp);
    _lastAppStatus = _app.graphStatus;
    if (_app.graphStatus.isNotEmpty) _applyStatus(_app.graphStatus, initial: true);
    _load();
    _fetchStatus();
  }

  @override
  void dispose() {
    _app.removeListener(_onApp);
    _poll?.cancel();
    _intro.dispose();
    _replay.dispose();
    _camAnim.dispose();
    _scene.dispose();
    _query.dispose();
    _canvasFocus.dispose();
    _pointer.dispose();
    _hoverCursor.dispose();
    super.dispose();
  }

  // ── data / build status ───────────────────────────────────────────────────
  Future<void> _load() async {
    if (_loadInFlight) {
      _reloadPending = true;
      return;
    }
    _loadInFlight = true;
    final r = await _app.api.graph();
    _loadInFlight = false;
    if (!mounted) return;
    if (r.ok) {
      _setSnapshot(r.value);
      _loadError = null;
    } else {
      _loadError = r.error;
    }
    setState(() => _loading = false);
    if (_reloadPending) {
      _reloadPending = false;
      unawaited(_load());
      return;
    }
    _maybeAutoBuild();
  }

  void _setSnapshot(GraphSnapshot? snap) {
    _snapshot = snap;
    final g = snap == null || snap.nodes.isEmpty ? null : CanvasGraph.fromSnapshot(snap);
    _graph = g;
    _histogram = g == null ? const [] : timeHistogram(g.fileTimes, g.minTime, g.maxTime, 60);
    _replay.stop();
    _playing = false;
    _scene.setGraph(g);
    if (g != null) {
      _scene.setIntro(0);
      _intro.forward(from: 0);
    }
  }

  Future<void> _fetchStatus() async {
    final r = await _app.api.graphStatus();
    if (!mounted || !r.ok) return;
    _applyStatus(r.value!);
  }

  void _onApp() {
    final s = _app.graphStatus;
    if (!identical(s, _lastAppStatus)) {
      _lastAppStatus = s;
      _applyStatus(s);
    }
    _maybeAutoBuild();
  }

  String get _state => _status['type'] == 'graph.ready' ? 'idle' : (_status['state'] as String? ?? 'idle');
  bool get _building => _buildRequested || _state == 'building';

  void _applyStatus(Map<String, dynamic> s, {bool initial = false}) {
    final ready = s['type'] == 'graph.ready';
    final state = ready ? 'idle' : (s['state'] as String? ?? 'idle');
    void update() => _status = s;
    if (initial) {
      update();
    } else if (mounted) {
      setState(update);
    }
    if (state == 'building') {
      _buildRequested = false;
      _wasBuilding = true;
      _startPoll();
    } else if (state == 'error') {
      _buildRequested = false;
      _wasBuilding = false;
      _stopPoll();
    } else {
      final builtAt = (s['builtAt'] as num?)?.toDouble();
      final current = _snapshot?.builtAt.millisecondsSinceEpoch;
      final newer = ready && builtAt != null && (current == null || (builtAt * 1000 - current).abs() > 1000);
      if (_wasBuilding || newer) {
        _wasBuilding = false;
        _buildRequested = false;
        if (!initial) unawaited(_load());
      }
      if (!_buildRequested) _stopPoll();
    }
  }

  // Event stream is primary; this light poll only covers missed events while building.
  void _startPoll() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 1500), (_) => _fetchStatus());
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _rebuild() async {
    setState(() {
      _buildRequested = true;
      _wasBuilding = true;
      _status = {..._status, 'state': 'building', 'phase': null, 'done': 0, 'total': 0, 'type': 'graph.progress'};
    });
    _startPoll();
    final r = await _app.api.buildGraph();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _buildRequested = false;
        _wasBuilding = false;
        _status = {'state': 'error', 'error': r.error?.message};
      });
      _stopPoll();
      _app.toastError(r.error);
    } else if (r.value!['state'] == 'building') {
      _applyStatus(r.value!);
    }
  }

  void _maybeAutoBuild() {
    if (_autoBuilt || _loading || _loadError != null || _snapshot != null) return;
    if (!_app.aiEnabled || _app.index.indexed == 0 || _building || _state == 'error') return;
    _autoBuilt = true;
    unawaited(_rebuild());
  }

  // ── camera ────────────────────────────────────────────────────────────────
  void _animateCamera(GraphCamera to) {
    _camFrom = _scene.camera;
    _camTo = to;
    _camAnim.forward(from: 0);
  }

  void _zoomBy(double f) {
    final base = _camAnim.isAnimating ? _camTo : _scene.camera;
    final c = _scene.viewport.center(Offset.zero);
    _animateCamera(base.zoomAt(c, f, minScale: _scene.minScale, maxScale: _scene.maxScale));
  }

  void _fit() => _animateCamera(_scene.computeFit());

  void _centreOn(int i, {bool zoomIn = true}) {
    final g = _graph;
    if (g == null) return;
    final scale = zoomIn ? math.max(_scene.camera.scale, _scene.fitCamera.scale * 2.5) : _scene.camera.scale;
    _animateCamera(GraphCamera.centredOn(Offset(g.x[i], g.y[i]), _scene.viewport, scale));
  }

  // ── replay ────────────────────────────────────────────────────────────────
  void _onReplayTick() {
    final t = _replay.value;
    final eased = 1 - (1 - t) * (1 - t);
    _scene.setRange(RangeValues(0, 0.02 + 0.98 * eased));
  }

  void _togglePlay() {
    if (_playing) {
      _replay.stop();
      setState(() => _playing = false);
    } else {
      _scene.setSelected(null);
      setState(() => _playing = true);
      _replay.forward(from: 0);
    }
  }

  void _setRange(RangeValues? r) {
    if (_playing) {
      _replay.stop();
      setState(() => _playing = false);
    }
    _scene.setRange(r);
  }

  // ── pointer interaction ───────────────────────────────────────────────────
  void _onHover(PointerHoverEvent e) {
    if (_dragging) return;
    final hit = _scene.hitTest(e.localPosition);
    _scene.setHover(hit);
    _hoverCursor.value = hit != null;
    _pointer.value = hit == null ? null : e.localPosition;
  }

  void _onExit(PointerExitEvent _) {
    _scene.setHover(null);
    _hoverCursor.value = false;
    _pointer.value = null;
  }

  void _onScroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      _camAnim.stop();
      final factor = math.exp(-s.scrollDelta.dy / 360);
      _scene.setCamera(
        _scene.camera.zoomAt(s.localPosition, factor, minScale: _scene.minScale, maxScale: _scene.maxScale),
      );
      _dismissHint();
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _camAnim.stop();
    _lastScale = 1;
    _dragging = true;
    _scene.setHover(null);
    _pointer.value = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    var cam = _scene.camera.panBy(d.focalPointDelta);
    if (d.scale != _lastScale && d.scale > 0) {
      cam = cam.zoomAt(d.localFocalPoint, d.scale / _lastScale, minScale: _scene.minScale, maxScale: _scene.maxScale);
      _lastScale = d.scale;
    }
    _scene.setCamera(cam);
    _dismissHint();
  }

  void _onScaleEnd(ScaleEndDetails d) => _dragging = false;

  void _onTapUp(TapUpDetails d) {
    _dismissHint();
    final hit = _scene.hitTest(d.localPosition);
    final now = DateTime.now();
    if (hit != null && hit == _lastTapNode && now.difference(_lastTapAt) < const Duration(milliseconds: 350)) {
      _lastTapNode = null;
      final path = _graph?.nodes[hit].path;
      if (path != null) _openFile(path);
      return;
    }
    _lastTapNode = hit;
    _lastTapAt = now;
    _scene.setSelected(hit);
  }

  void _dismissHint() {
    if (!_hintDismissed) setState(() => _hintDismissed = true);
  }

  // ── actions ───────────────────────────────────────────────────────────────
  Future<void> _openFile(String path) async {
    final r = await _app.api.open(path);
    if (!r.ok) _app.toastError(r.error);
  }

  Future<void> _showInFolder(String path) async {
    final ex = context.read<ExplorerController>();
    await ex.open(parentDir(path));
    for (final e in ex.entries) {
      if (e.path == path) {
        ex.select(e);
        break;
      }
    }
  }

  void _findFirst() {
    final i = _scene.firstMatch();
    if (i == null) return;
    _scene.setSelected(i);
    _centreOn(i);
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    return ColoredBox(
      color: c.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneHeader.simple(icon: Icons.hub_outlined, label: 'Canvas', actions: [_headerAction(c, app)]),
          Expanded(child: _body(c, app)),
          if (app.aiEnabled && _graph != null && _graph!.maxTime > _graph!.minTime)
            TimeScrubber(
              counts: _histogram,
              min: _graph!.minTime,
              max: _graph!.maxTime,
              range: _scene.range,
              onChanged: _setRange,
              playing: _playing,
              onTogglePlay: _togglePlay,
            ),
        ],
      ),
    );
  }

  (int, int) get _phaseStep {
    final p = _status['phase'] as String?;
    final i = _phases.indexOf(p ?? '');
    return (i < 0 ? 1 : i + 1, _phases.length);
  }

  double? get _phaseFraction {
    final done = (_status['done'] as num?)?.toDouble() ?? 0;
    final total = (_status['total'] as num?)?.toDouble() ?? 0;
    return total > 0 ? (done / total).clamp(0.0, 1.0) : null;
  }

  Widget _headerAction(FaColors c, FaController app) {
    if (_building) {
      final (n, m) = _phaseStep;
      return Tooltip(
        message: _phaseText(_status['phase'] as String?),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Scoop.mint),
              ),
              const SizedBox(width: 8),
              Text('Building… $n/$m', style: FaText.sans(size: 12, color: c.mutedForeground)),
            ],
          ),
        ),
      );
    }
    return Tooltip(
      message: 'Recompute similarity, entities and clusters from the index',
      child: FaButton(
        label: 'Rebuild',
        icon: Icons.refresh_rounded,
        variant: FaButtonVariant.ghost,
        dense: true,
        onPressed: app.aiEnabled && app.index.indexed > 0 ? _rebuild : null,
      ),
    );
  }

  Widget _body(FaColors c, FaController app) {
    if (!app.aiEnabled) {
      return _EmptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'The Canvas needs on-device AI',
        body:
            'Turn on DeskMate\'s on-device AI and index a few folders. The Canvas then maps how your files '
            'relate: by meaning, by the people and projects inside them, and by when you worked on them.',
        action: FaButton(
          label: 'Open Settings',
          variant: FaButtonVariant.primary,
          dense: true,
          onPressed: () => app.showSection(FaSection.settings),
        ),
      );
    }
    final g = _graph;
    if (g == null) {
      if (_building) return _buildingState(c);
      if (_state == 'error') {
        return _EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn\'t build the Canvas',
          body: (_status['error'] as String?) ?? 'Something went wrong while mapping your files.',
          action: FaButton(label: 'Try again', icon: Icons.refresh_rounded, dense: true, onPressed: _rebuild),
        );
      }
      if (app.index.indexed == 0) {
        return _EmptyState(
          icon: Icons.hub_outlined,
          title: 'Index some folders first',
          body: app.index.busy
              ? 'Indexing is under way (${app.index.done} of ${app.index.total}). The Canvas appears once files are indexed.'
              : 'The Canvas is drawn from your semantic index. Choose folders to index in Settings and come back.',
          action: FaButton(
            label: 'Open Settings',
            variant: FaButtonVariant.primary,
            dense: true,
            onPressed: () => app.showSection(FaSection.settings),
          ),
        );
      }
      if (_loading) return const SizedBox.shrink();
      if (_loadError != null) {
        return _EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn\'t load the Canvas',
          body: _loadError!.message,
          action: FaButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            dense: true,
            onPressed: () {
              setState(() => _loadError = null);
              _load();
            },
          ),
        );
      }
      if (_snapshot != null) {
        return _EmptyState(
          icon: Icons.hub_outlined,
          title: 'Nothing to map yet',
          body: 'The index is still young. Come back once a few more files are indexed, or rebuild now.',
          action: FaButton(label: 'Rebuild', icon: Icons.refresh_rounded, dense: true, onPressed: _rebuild),
        );
      }
      return _buildingState(c);
    }
    return _stage(c, app);
  }

  Widget _buildingState(FaColors c) {
    final (n, m) = _phaseStep;
    final pct = _phaseFraction;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub_outlined, size: 30, color: Scoop.mint),
            const SizedBox(height: 14),
            Text(
              'Mapping your files…',
              style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
            ),
            const SizedBox(height: 6),
            Text(
              '${_phaseText(_status['phase'] as String?)} · step $n of $m'
              '${pct == null ? '' : ' · ${(pct * 100).round()}%'}',
              textAlign: TextAlign.center,
              style: FaText.sans(size: 12, color: c.mutedForeground),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 220,
              child: FaProgressBar(value: pct == null ? null : ((n - 1) + pct) / m, color: Scoop.mint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(FaColors c, FaController app) {
    final snap = _snapshot!;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: _canvas(c)),
            // Top-left: search + legend/filter chips.
            Positioned(
              left: 12,
              top: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SearchBox(controller: _query, scene: _scene, onSubmit: _findFirst),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: _scene.overlay,
                    builder: (context, _) => Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final k in EdgeKind.values)
                          _KindChip(
                            label: _kindLabels[k]!,
                            color: edgeColors[k]!,
                            on: _scene.kinds.contains(k),
                            onTap: () => _scene.toggleKind(k),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Top-right: stats pill.
            Positioned(right: 12, top: 12, child: _StatsPill(stats: snap.stats)),
            // Bottom-right: zoom controls.
            Positioned(
              right: 12,
              bottom: 12,
              child: _ZoomControls(onIn: () => _zoomBy(1.5), onOut: () => _zoomBy(1 / 1.5), onFit: _fit),
            ),
            // Bottom-centre: build progress over an existing graph / error / first-use hint.
            Positioned(left: 0, right: 0, bottom: 14, child: Center(child: _bottomPill(c))),
            // Hover tooltip.
            ListenableBuilder(
              listenable: Listenable.merge([_pointer, _scene.overlay]),
              builder: (context, _) {
                final i = _scene.hovered, p = _pointer.value;
                if (i == null || p == null || i == _scene.selected) return const SizedBox.shrink();
                const w = 280.0;
                final left = (p.dx + 16 + w > size.width) ? p.dx - 16 - w : p.dx + 16;
                final top = math.min(p.dy + 16, size.height - 110);
                return Positioned(
                  left: math.max(8, left),
                  top: math.max(8, top),
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: w),
                      child: _HoverCard(node: _graph!.nodes[i], home: app.home, scene: _scene, index: i),
                    ),
                  ),
                );
              },
            ),
            // Selection card, anchored beside the selected node.
            ListenableBuilder(
              listenable: _scene,
              builder: (context, _) {
                final i = _scene.selected;
                if (i == null || !_scene.isVisible(i)) return const SizedBox.shrink();
                const w = 272.0;
                final p = _scene.screenOf(i);
                final r = _scene.screenRadius(i) + 14;
                var left = p.dx + r;
                if (left + w > size.width - 60) left = p.dx - r - w;
                left = left.clamp(8.0, math.max(8.0, size.width - w - 8)).toDouble();
                final top = (p.dy - 40).clamp(96.0, math.max(96.0, size.height - 250)).toDouble();
                return Positioned(
                  left: left,
                  top: top,
                  width: w,
                  child: _SelectionCard(
                    key: ValueKey(i),
                    graph: _graph!,
                    scene: _scene,
                    index: i,
                    home: app.home,
                    onClose: () => _scene.setSelected(null),
                    onOpen: _openFile,
                    onShowInFolder: _showInFolder,
                    onAskAi: (paths) => app.askAiAbout(paths),
                    onSelect: (j) {
                      _scene.setSelected(j);
                      _centreOn(j, zoomIn: false);
                    },
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _canvas(FaColors c) {
    return Focus(
      focusNode: _canvasFocus,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && _scene.selected != null) {
          _scene.setSelected(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerSignal: _onScroll,
        onPointerDown: (_) => _canvasFocus.requestFocus(),
        child: ValueListenableBuilder<bool>(
          valueListenable: _hoverCursor,
          builder: (context, onNode, child) => MouseRegion(
            cursor: onNode ? SystemMouseCursors.click : SystemMouseCursors.grab,
            onHover: _onHover,
            onExit: _onExit,
            child: child,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: RepaintBoundary(
              child: CustomPaint(painter: CanvasPainter(_scene, c), size: Size.infinite),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomPill(FaColors c) {
    if (_building) {
      final (n, m) = _phaseStep;
      final pct = _phaseFraction;
      return _Glass(
        radius: 999,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: Scoop.mint),
            ),
            const SizedBox(width: 8),
            Text(
              '${_phaseText(_status['phase'] as String?)} · $n/$m${pct == null ? '' : ' · ${(pct * 100).round()}%'}',
              style: FaText.sans(size: 11.5, color: c.mutedForeground),
            ),
          ],
        ),
      );
    }
    if (_state == 'error') {
      return _Glass(
        radius: 999,
        padding: const EdgeInsets.only(left: 12, right: 4, top: 3, bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 14, color: c.destructive),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                'Rebuild failed: ${(_status['error'] as String?) ?? 'unknown error'}',
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 11.5, color: c.mutedForeground),
              ),
            ),
            const SizedBox(width: 6),
            FaButton(label: 'Retry', variant: FaButtonVariant.ghost, dense: true, onPressed: _rebuild),
          ],
        ),
      );
    }
    if (_hintDismissed) return const SizedBox.shrink();
    return _Glass(
      radius: 999,
      padding: const EdgeInsets.only(left: 12, right: 4, top: 3, bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Drag to explore · Scroll to zoom · Click any dot for its story',
            style: FaText.sans(size: 11.5, color: c.mutedForeground),
          ),
          FaIconButton(icon: Icons.close_rounded, size: 22, onPressed: _dismissHint),
        ],
      ),
    );
  }
}

// ── overlay widgets ─────────────────────────────────────────────────────────

/// Translucent card surface for HUD elements floating over the graph.
class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const _Glass({required this.child, this.padding = const EdgeInsets.all(10), this.radius = FaRadius.md});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final CanvasScene scene;
  final VoidCallback onSubmit;
  const _SearchBox({required this.controller, required this.scene, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SizedBox(
        width: 236,
        height: 32,
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 15, color: c.mutedForeground),
            const SizedBox(width: 7),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    controller.clear();
                    scene.setQuery('');
                  },
                },
                child: TextField(
                  controller: controller,
                  onChanged: scene.setQuery,
                  onSubmitted: (_) => onSubmit(),
                  style: FaText.sans(size: 12.5, color: c.foreground),
                  cursorColor: c.foreground,
                  cursorHeight: 14,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Find in graph…',
                    hintStyle: FaText.sans(size: 12.5, color: c.mutedForeground),
                  ),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: scene.overlay,
              builder: (context, _) {
                if (scene.query.isEmpty) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${scene.matchCount}',
                      style: FaText.mono(size: 10.5, color: scene.matchCount == 0 ? c.destructive : c.mutedForeground),
                    ),
                    const SizedBox(width: 2),
                    FaIconButton(
                      icon: Icons.close_rounded,
                      size: 22,
                      tooltip: 'Clear',
                      onPressed: () {
                        controller.clear();
                        scene.setQuery('');
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool on;
  final VoidCallback onTap;
  const _KindChip({required this.label, required this.color, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: '${on ? 'Hide' : 'Show'} ${label.toLowerCase()} connections',
      child: Hoverable(
        onTap: onTap,
        builder: (context, hover) => AnimatedContainer(
          duration: FaMotion.fast,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hover ? c.accent : c.card.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScoopDot(on ? color : color.withValues(alpha: 0.3), size: 7),
              const SizedBox(width: 6),
              Text(
                label,
                style: FaText.sans(
                  size: 11.5,
                  color: on ? c.foreground : c.mutedForeground.withValues(alpha: 0.7),
                ).copyWith(decoration: on ? null : TextDecoration.lineThrough, decorationColor: c.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsPill extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsPill({required this.stats});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final f = NumberFormat.decimalPattern();
    String n(String k) => f.format((stats[k] as num?)?.toInt() ?? 0);
    final text =
        '${n('files')} files · ${n('entities')} entities · ${n('edges')} links'
        '${stats['truncated'] == true ? ' · most-connected shown' : ''}';
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(text, style: FaText.sans(size: 11.5, color: c.mutedForeground)),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final VoidCallback onIn, onOut, onFit;
  const _ZoomControls({required this.onIn, required this.onOut, required this.onFit});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    Widget sep() => Container(height: 1, width: 30, color: c.border);
    return _Glass(
      padding: const EdgeInsets.all(1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIconButton(icon: Icons.add_rounded, size: 30, tooltip: 'Zoom in', onPressed: onIn),
          sep(),
          FaIconButton(icon: Icons.remove_rounded, size: 30, tooltip: 'Zoom out', onPressed: onOut),
          sep(),
          FaIconButton(
            icon: Icons.fit_screen_outlined,
            size: 30,
            tooltip: 'Fit the whole graph in view',
            onPressed: onFit,
          ),
        ],
      ),
    );
  }
}

Color _nodeColor(CanvasGraph g, int i, FaColors c) {
  final s = g.slot[i];
  if (s < 6) return Scoop.all[s];
  if (s == ColorSlot.mint) return Scoop.mint;
  if (s == ColorSlot.tag) return Scoop.parse(g.nodes[i].color, Scoop.grape);
  return c.mutedForeground;
}

String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

class _HoverCard extends StatelessWidget {
  final GraphNode node;
  final String home;
  final CanvasScene scene;
  final int index;
  const _HoverCard({required this.node, required this.home, required this.scene, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final g = scene.graph!;
    final muted = FaText.sans(size: 11, color: c.mutedForeground);
    final isFile = node.kind == 'file';
    return FaCard(
      shadow: true,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScoopDot(_nodeColor(g, index, c), size: 7),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FaText.sans(size: 12.5, weight: FontWeight.w600, color: c.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (isFile && node.path != null)
            Text(
              compactDir(parentDir(node.path!), home),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FaText.mono(size: 10, color: c.mutedForeground),
            ),
          const SizedBox(height: 3),
          Text(
            [
              if (isFile)
                kindLabel(node.fileKind ?? 'file', node.ext ?? '')
              else
                (node.kind == 'tag' ? 'Tag' : 'Entity'),
              if (isFile && node.mtime != null) formatDate(node.mtime!),
              _plural(node.degree, 'connection'),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final CanvasGraph graph;
  final CanvasScene scene;
  final int index;
  final String home;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onShowInFolder;
  final ValueChanged<List<String>> onAskAi;
  final ValueChanged<int> onSelect;

  const _SelectionCard({
    super.key,
    required this.graph,
    required this.scene,
    required this.index,
    required this.home,
    required this.onClose,
    required this.onOpen,
    required this.onShowInFolder,
    required this.onAskAi,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final node = graph.nodes[index];
    final isFile = node.kind == 'file';
    final neighbours = scene.neighboursOf(index)..sort((a, b) => graph.nodes[b].degree - graph.nodes[a].degree);
    final linkedFiles = neighbours.where((j) => graph.kind[j] == NodeKind.file).toList();

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isFile)
          Padding(
            padding: const EdgeInsets.only(right: 9, top: 1),
            child: FileIcon(name: node.label, isDir: false, ext: node.ext ?? '', size: 28),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 9, top: 5),
            child: ScoopDot(_nodeColor(graph, index, c), size: 9),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
              ),
              const SizedBox(height: 2),
              Text(
                isFile
                    ? compactDir(parentDir(node.path ?? ''), home)
                    : '${node.kind == 'tag' ? 'Tag' : 'Entity'} · ${_plural(linkedFiles.length, 'linked file')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isFile
                    ? FaText.mono(size: 10, color: c.mutedForeground)
                    : FaText.sans(size: 11, color: c.mutedForeground),
              ),
            ],
          ),
        ),
        FaIconButton(icon: Icons.close_rounded, size: 22, tooltip: 'Close', onPressed: onClose),
      ],
    );

    return FaCard(
      shadow: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (isFile) ...[
            const SizedBox(height: 6),
            Text(
              [
                kindLabel(node.fileKind ?? 'file', node.ext ?? ''),
                if (node.mtime != null) 'Modified ${formatDate(node.mtime!)}',
                _plural(neighbours.length, 'connection'),
              ].join(' · '),
              style: FaText.sans(size: 11, color: c.mutedForeground),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FaButton(
                    label: 'Open',
                    variant: FaButtonVariant.primary,
                    dense: true,
                    expand: true,
                    onPressed: node.path == null ? null : () => onOpen(node.path!),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FaButton(
                    label: 'Show in Folder',
                    variant: FaButtonVariant.outline,
                    dense: true,
                    expand: true,
                    onPressed: node.path == null ? null : () => onShowInFolder(node.path!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FaButton(
              label: 'Ask AI about it',
              leading: const Icon(Icons.auto_awesome_outlined, size: 14, color: Scoop.mint),
              variant: FaButtonVariant.ghost,
              dense: true,
              expand: true,
              onPressed: node.path == null ? null : () => onAskAi([node.path!]),
            ),
          ] else ...[
            const SizedBox(height: 8),
            for (final j in linkedFiles.take(6))
              Hoverable(
                onTap: () => onSelect(j),
                builder: (context, hover) => Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: hover ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(FaRadius.sm),
                  ),
                  child: Row(
                    children: [
                      ScoopDot(_nodeColor(graph, j, c), size: 6),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          graph.nodes[j].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FaText.sans(size: 12, color: c.foreground),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (linkedFiles.length > 6)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Text(
                  '+ ${linkedFiles.length - 6} more highlighted',
                  style: FaText.sans(size: 11, color: c.mutedForeground),
                ),
              ),
            if (linkedFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              FaButton(
                label: 'Ask AI about these files',
                leading: const Icon(Icons.auto_awesome_outlined, size: 14, color: Scoop.mint),
                variant: FaButtonVariant.ghost,
                dense: true,
                expand: true,
                onPressed: () => onAskAi([
                  for (final j in linkedFiles.take(10))
                    if (graph.nodes[j].path != null) graph.nodes[j].path!,
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const _EmptyState({required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(FaRadius.xl),
                  border: Border.all(color: c.border),
                ),
                child: Icon(icon, size: 22, color: Scoop.mint),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: FaText.sans(size: 12.5, color: c.mutedForeground, height: 1.5),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
