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
import '../widgets/logo.dart';
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

String _phaseText(String? p) => switch (p) {
  'similarity' => 'Connecting files that belong together',
  'entities' => 'Reading who and what is inside your files',
  _ => 'Assembling',
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
    _replay = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..addListener(_onReplayTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() => _playing = false);
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
    _histogram = g == null ? const [] : timeHistogram(g.fileTimes, g.minTime, g.maxTime, 48);
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
  /// FilDOS replay: the right edge sweeps from just past the left edge to the
  /// end over 8s (ease-out quad); the left edge stays where the user put it.
  double _replayFrom = 0;
  void _onReplayTick() {
    final t = _replay.value;
    final eased = 1 - (1 - t) * (1 - t);
    final f = _replayFrom;
    _scene.setRange(RangeValues(f, math.min(1, f + 0.02 + (1 - f - 0.02) * eased)));
  }

  void _togglePlay() {
    if (_playing) {
      _replay.stop();
      setState(() => _playing = false);
    } else {
      _replayFrom = _scene.range.value?.start ?? 0;
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
    // FilDOS: clicking a node toggles it; clicking empty space clears.
    _scene.setSelected(hit != null && hit == _scene.selected ? null : hit);
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

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    // FilDOS: Escape clears the selection first, then leaves the page.
    if (_scene.selected != null) {
      _scene.setSelected(null);
    } else {
      _app.showSection(FaSection.browse);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    // Only what this view shows — index-progress ticks for other fields must
    // not rebuild (and so re-layout) the canvas stack.
    final (aiEnabled, indexed, busy, done, total) = context.select<FaController, (bool, int, bool, int, int)>(
      (a) => (a.aiEnabled, a.index.indexed, a.index.busy, a.index.done, a.index.total),
    );
    final g = _graph;
    return Focus(
      focusNode: _canvasFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: c.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneHeader.simple(
              icon: Icons.psychology_outlined,
              label: 'Canvas',
              actions: [
                Tooltip(
                  message: 'Recompute similarity edges and entities from scratch',
                  child: _ChromeButton(
                    icon: Icons.refresh_rounded,
                    label: 'Rebuild',
                    onTap: aiEnabled && indexed > 0 ? _rebuild : null,
                  ),
                ),
              ],
            ),
            Expanded(
              child: _body(c, aiEnabled: aiEnabled, indexed: indexed, busy: busy, done: done, total: total),
            ),
            if (aiEnabled && g != null && g.maxTime > g.minTime)
              TimeScrubber(
                counts: _histogram,
                min: g.minTime,
                max: g.maxTime,
                range: _scene.range,
                onChanged: _setRange,
                playing: _playing,
                onTogglePlay: _togglePlay,
              ),
          ],
        ),
      ),
    );
  }

  double? get _phaseFraction {
    final done = (_status['done'] as num?)?.toDouble() ?? 0;
    final total = (_status['total'] as num?)?.toDouble() ?? 0;
    return total > 0 ? (done / total).clamp(0.0, 1.0) : null;
  }

  /// FilDOS BuildProgress: "phase · NN%".
  String get _buildText {
    final pct = _phaseFraction;
    return '${_phaseText(_status['phase'] as String?)}${pct == null ? '' : ' · ${(pct * 100).round()}%'}';
  }

  Widget _body(
    FaColors c, {
    required bool aiEnabled,
    required int indexed,
    required bool busy,
    required int done,
    required int total,
  }) {
    final g = _graph;
    if (g != null && aiEnabled) return _stage(c);
    if (aiEnabled && _building) {
      return _EmptyState(
        pulse: true,
        title: 'Mapping your storage…',
        child: Text(
          _buildText,
          textAlign: TextAlign.center,
          style: FaText.sans(size: 11, color: c.mutedForeground),
        ),
      );
    }
    if (!aiEnabled || indexed == 0) {
      return _EmptyState(
        title: 'The Canvas needs an index',
        body: busy
            ? 'Indexing is under way ($done of $total). The Canvas appears once files are indexed.'
            : 'Turn on indexing and DeskMate will map how your files relate — by meaning, by the people and '
                  'projects inside them, and by when you worked on them.',
        action: _PrimaryPill(label: 'Open Settings', onTap: () => _app.showSection(FaSection.settings)),
      );
    }
    if (_state == 'error') {
      return _EmptyState(
        title: 'Couldn\'t build the Canvas',
        body: (_status['error'] as String?) ?? 'Something went wrong while mapping your files.',
        action: _PrimaryPill(label: 'Try again', onTap: _rebuild),
      );
    }
    if (_loading) return const SizedBox.shrink();
    if (_loadError != null) {
      return _EmptyState(
        title: 'Couldn\'t load the Canvas',
        body: _loadError!.message,
        action: _PrimaryPill(
          label: 'Retry',
          onTap: () {
            setState(() => _loadError = null);
            _load();
          },
        ),
      );
    }
    return const _EmptyState(
      title: 'Nothing to map yet',
      body: 'The index is still young. Come back once a few files are indexed, or rebuild now.',
    );
  }

  Widget _stage(FaColors c) {
    final snap = _snapshot!;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: _canvas(c)),
            // HUD: search + edge-kind chips (left), stats (right).
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
            Positioned(right: 12, top: 12, child: _StatsPill(stats: snap.stats)),
            // Bottom-centre: build progress / error / first-open hint.
            Positioned(left: 0, right: 0, bottom: 12, child: Center(child: _bottomPill(c))),
            // Hover card at the pointer (+14px).
            ListenableBuilder(
              listenable: Listenable.merge([_pointer, _scene.overlay]),
              builder: (context, _) {
                final i = _scene.hovered, p = _pointer.value;
                if (i == null || p == null) return const SizedBox.shrink();
                const w = 320.0;
                final left = (p.dx + 14 + w > size.width) ? p.dx - 14 - w : p.dx + 14;
                return Positioned(
                  left: math.max(8, left),
                  top: math.min(p.dy + 14, size.height - 48),
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: w),
                      child: _HoverCard(node: _graph!.nodes[i]),
                    ),
                  ),
                );
              },
            ),
            // Zoom cluster + detail panel (steps aside when a node is selected).
            ListenableBuilder(
              listenable: _scene.overlay,
              builder: (context, _) {
                final i = _scene.selected;
                return Stack(
                  children: [
                    Positioned(
                      right: i == null ? 12 : 312,
                      bottom: 12,
                      child: _ZoomControls(onIn: () => _zoomBy(1.5), onOut: () => _zoomBy(1 / 1.5), onFit: _fit),
                    ),
                    if (i != null)
                      Positioned(
                        right: 12,
                        top: 12,
                        bottom: 12,
                        width: 288,
                        child: _DetailPanel(
                          key: ValueKey(i),
                          graph: _graph!,
                          scene: _scene,
                          index: i,
                          onClose: () => _scene.setSelected(null),
                          onOpen: _openFile,
                          onShowInFolder: _showInFolder,
                          onAskAi: (paths) => _app.askAiAbout(paths),
                          onSelect: _scene.setSelected,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _canvas(FaColors c) {
    return Listener(
      onPointerSignal: _onScroll,
      onPointerDown: (_) {
        _canvasFocus.requestFocus();
        _dismissHint(); // FilDOS: the hint goes at the first touch
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _hoverCursor,
        builder: (context, onNode, child) => MouseRegion(
          cursor: onNode
              ? SystemMouseCursors.click
              : (_dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab),
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
    );
  }

  Widget _bottomPill(FaColors c) {
    if (_building) {
      return _Glass(
        radius: 999,
        alpha: 0.9,
        shadow: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Pulse(child: DeskMateMark(size: 14)),
            const SizedBox(width: 8),
            Text(_buildText, style: FaText.sans(size: 11, color: c.mutedForeground)),
          ],
        ),
      );
    }
    if (_state == 'error') {
      return _Glass(
        radius: 999,
        alpha: 0.9,
        shadow: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                'Rebuild failed: ${(_status['error'] as String?) ?? 'unknown error'}',
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 11, color: c.mutedForeground),
              ),
            ),
            const SizedBox(width: 8),
            Hoverable(
              onTap: _rebuild,
              builder: (context, h) => Text(
                'Retry',
                style: FaText.sans(size: 11, weight: FontWeight.w500, color: h ? c.foreground : Scoop.mint),
              ),
            ),
          ],
        ),
      );
    }
    return ListenableBuilder(
      listenable: _scene.overlay,
      builder: (context, _) {
        if (_hintDismissed || _scene.selected != null) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: false,
          child: _Glass(
            radius: 999,
            alpha: 0.9,
            shadow: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Drag to explore · Scroll to zoom · Click any dot for its story',
                  style: FaText.sans(size: 11, color: c.mutedForeground),
                ),
                const SizedBox(width: 4),
                Hoverable(
                  onTap: _dismissHint,
                  builder: (context, h) =>
                      Icon(Icons.close_rounded, size: 11, color: h ? c.foreground : c.mutedForeground),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── overlay widgets ─────────────────────────────────────────────────────────

/// `bg-card/85 border backdrop-blur` HUD surface (rounded-lg unless [radius]).
class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double alpha;
  final bool shadow;
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.radius = FaRadius.lg,
    this.alpha = 0.85,
    this.shadow = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.border),
        boxShadow: shadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))]
            : null,
      ),
      child: child,
    );
  }
}

/// FilDOS page-chrome button: `text-xs px-2 py-1 rounded-md`, 14px icon.
class _ChromeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ChromeButton({required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Hoverable(
        onTap: onTap,
        builder: (context, h) {
          final fg = h && onTap != null ? c.foreground : c.mutedForeground;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: h && onTap != null ? c.accent : c.accent.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(FaRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(label, style: FaText.sans(size: 12, color: fg)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `bg-primary text-primary-foreground rounded-md px-3 py-1.5 text-xs font-medium`.
class _PrimaryPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryPill({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, h) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: h ? c.primary.withValues(alpha: 0.9) : c.primary,
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Text(
          label,
          style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.primaryForeground),
        ),
      ),
    );
  }
}

/// Tailwind `animate-pulse` (opacity 1 → 0.5 → 1 over 2s).
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _c.drive(
        TweenSequence([
          TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 0.5).chain(CurveTween(curve: const Cubic(0.4, 0, 0.6, 1))),
            weight: 1,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 0.5, end: 1.0).chain(CurveTween(curve: const Cubic(0.4, 0, 0.6, 1))),
            weight: 1,
          ),
        ]),
      ),
      child: widget.child,
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final CanvasScene scene;
  final VoidCallback onSubmit;
  const _SearchBox({required this.controller, required this.scene, required this.onSubmit});

  void _clear() {
    controller.clear();
    scene.setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return _Glass(
      shadow: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SizedBox(
        width: 202, // w-56 (224) minus padding
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 14, color: c.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
                child: TextField(
                  controller: controller,
                  onChanged: scene.setQuery,
                  onSubmitted: (_) => onSubmit(),
                  style: FaText.sans(size: 12, color: c.foreground),
                  cursorColor: c.foreground,
                  cursorHeight: 13,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Find in graph…',
                    hintStyle: FaText.sans(size: 12, color: c.mutedForeground),
                  ),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: scene.overlay,
              builder: (context, _) {
                if (scene.query.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Hoverable(
                    onTap: _clear,
                    builder: (context, h) =>
                        Icon(Icons.close_rounded, size: 12, color: h ? c.foreground : c.mutedForeground),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Edge-kind chip: `rounded-full border bg-card/85 px-2.5 py-1 text-2xs`, a
/// size-2 dot; off = muted text, whole chip at 60%, dot at 35%.
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
      message: 'Toggle ${label.toLowerCase()} connections',
      child: Hoverable(
        onTap: onTap,
        builder: (context, _) => AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: on ? 1 : 0.6,
          child: _Glass(
            radius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScoopDot(color.withValues(alpha: on ? 1 : 0.35), size: 8),
                const SizedBox(width: 6),
                Text(label, style: FaText.sans(size: 11, color: on ? c.foreground : c.mutedForeground)),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(text, style: FaText.sans(size: 11, color: c.mutedForeground)),
    );
  }
}

/// Zoom cluster: three size-7 buttons, hairline `border-y` between.
class _ZoomControls extends StatelessWidget {
  final VoidCallback onIn, onOut, onFit;
  const _ZoomControls({required this.onIn, required this.onOut, required this.onFit});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    Widget btn(String tip, VoidCallback onTap, Widget Function(Color) glyph) => Tooltip(
      message: tip,
      child: Hoverable(
        onTap: onTap,
        builder: (context, h) => Container(
          width: 28,
          height: 28,
          color: h ? c.accent : c.accent.withValues(alpha: 0),
          alignment: Alignment.center,
          child: glyph(h ? c.foreground : c.mutedForeground),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(FaRadius.lg),
      child: _Glass(
        shadow: true,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn('Zoom in', onIn, (fg) => Icon(Icons.add_rounded, size: 14, color: fg)),
            Container(height: 1, width: 28, color: c.border),
            btn(
              'Zoom out',
              onOut,
              (fg) => Text(
                '−',
                style: FaText.sans(size: 14, weight: FontWeight.w500, color: fg, height: 1),
              ),
            ),
            Container(height: 1, width: 28, color: c.border),
            btn('Fit the whole graph in view', onFit, (fg) => Icon(Icons.fullscreen_exit_rounded, size: 13, color: fg)),
          ],
        ),
      ),
    );
  }
}

Color _nodeColor(CanvasGraph g, int i, FaColors c) {
  final s = g.slot[i];
  if (s < 6) return Scoop.all[s];
  if (s == ColorSlot.mint) return Scoop.mint;
  if (s == ColorSlot.tag) return Scoop.parse(g.nodes[i].color, c.mutedForeground);
  return c.mutedForeground;
}

String _kindName(GraphNode n) => n.kind == 'tag' ? 'Tag' : 'Entity';

/// FilDOS HoverCard: label text-xs medium; path (or kind) · N connections in text-3xs.
class _HoverCard extends StatelessWidget {
  final GraphNode node;
  const _HoverCard({required this.node});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final sub = node.kind == 'file' ? (node.path ?? '') : _kindName(node);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.lg),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
          ),
          Text(
            '$sub · ${node.degree} connection${node.degree == 1 ? '' : 's'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FaText.sans(size: 10, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// FilDOS DetailPanel: a right-docked `w-72 bg-card/95 rounded-xl` panel —
/// header (dot, label, path, close), Open / Show in folder, then the node's
/// strongest connections with the "why" behind each.
class _DetailPanel extends StatelessWidget {
  final CanvasGraph graph;
  final CanvasScene scene;
  final int index;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onShowInFolder;
  final ValueChanged<List<String>> onAskAi;
  final ValueChanged<int> onSelect;

  const _DetailPanel({
    super.key,
    required this.graph,
    required this.scene,
    required this.index,
    required this.onClose,
    required this.onOpen,
    required this.onShowInFolder,
    required this.onAskAi,
    required this.onSelect,
  });

  static String _why(EdgeKind k, double w) => switch (k) {
    EdgeKind.similar => '${(w * 100).round()}% similar',
    EdgeKind.entity => 'mentions it',
    EdgeKind.tag => 'tagged',
    EdgeKind.temporal => 'same work session',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final node = graph.nodes[index];
    final isFile = node.kind == 'file';
    final connections = scene.connectionsOf(index);
    Widget action(String label, bool primary, VoidCallback? onTap) => Expanded(
      child: Hoverable(
        onTap: onTap,
        builder: (context, h) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? c.primary : (h ? c.accent : c.accent.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(FaRadius.md),
            border: primary ? null : Border.all(color: c.border),
          ),
          child: Text(
            label,
            style: FaText.sans(
              size: 11,
              weight: primary ? FontWeight.w500 : FontWeight.w400,
              color: primary ? c.primaryForeground : c.foreground,
            ),
          ),
        ),
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(FaRadius.xl),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 4), child: ScoopDot(_nodeColor(graph, index, c), size: 10)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.label,
                        style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                      ),
                      if (isFile && node.path != null)
                        Text(node.path!, style: FaText.sans(size: 10, color: c.mutedForeground))
                      else if (!isFile)
                        Text(_kindName(node), style: FaText.sans(size: 10, color: c.mutedForeground)),
                    ],
                  ),
                ),
                Hoverable(
                  onTap: onClose,
                  builder: (context, h) =>
                      Icon(Icons.close_rounded, size: 14, color: h ? c.foreground : c.mutedForeground),
                ),
              ],
            ),
          ),
          if (isFile && node.path != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  action('Open', true, () => onOpen(node.path!)),
                  const SizedBox(width: 6),
                  action('Show in folder', false, () => onShowInFolder(node.path!)),
                  const SizedBox(width: 6),
                  // DeskMate: hand the file to Ask AI.
                  Tooltip(
                    message: 'Ask AI about it',
                    child: Hoverable(
                      onTap: () => onAskAi([node.path!]),
                      builder: (context, h) => Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: h ? c.accent : c.accent.withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(FaRadius.md),
                          border: Border.all(color: c.border),
                        ),
                        child: const Icon(Icons.auto_awesome_outlined, size: 13, color: Scoop.mint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              'CONNECTED',
              style: FaText.sans(size: 10, weight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.5),
            ),
          ),
          Expanded(
            child: connections.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                    child: Text(
                      'No visible connections',
                      textAlign: TextAlign.center,
                      style: FaText.sans(size: 11, color: c.mutedForeground),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    children: [
                      for (final conn in connections)
                        Tooltip(
                          message: graph.nodes[conn.node].path ?? graph.nodes[conn.node].label,
                          waitDuration: const Duration(milliseconds: 700),
                          child: Hoverable(
                            onTap: () => onSelect(conn.node),
                            builder: (context, h) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: h ? c.accent : c.accent.withValues(alpha: 0),
                                borderRadius: BorderRadius.circular(FaRadius.md),
                              ),
                              child: Row(
                                children: [
                                  ScoopDot(edgeColors[conn.kind]!, size: 6),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      graph.nodes[conn.node].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: FaText.sans(size: 12, color: c.foreground),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _why(conn.kind, conn.weight),
                                    style: FaText.sans(size: 10, color: c.mutedForeground),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// FilDOS empty state: the mark (size-10, pulsing while building), title
/// text-sm medium, body text-xs leading-relaxed, optional action; `gap-3`.
class _EmptyState extends StatelessWidget {
  final String title;
  final String? body;
  final Widget? child;
  final Widget? action;
  final bool pulse;
  const _EmptyState({required this.title, this.body, this.child, this.action, this.pulse = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    const mark = DeskMateMark(size: 40);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 384),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pulse) const _Pulse(child: mark) else mark,
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
              ),
              if (body != null) ...[
                const SizedBox(height: 12),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: FaText.sans(size: 12, color: c.mutedForeground, height: 1.625),
                ),
              ],
              if (child != null) ...[const SizedBox(height: 12), child!],
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}
