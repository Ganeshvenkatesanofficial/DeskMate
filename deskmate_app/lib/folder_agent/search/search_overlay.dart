import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../explorer/file_preview.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'scoop_trail.dart';

/// The Spotlight-style search surface, ported from FilDOS' `SearchOverlay`
/// (MIT): one fused result list (name + meaning), filter chips, and — once
/// there are results — a split view with a live preview of the active row.
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key});

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

enum _Scope { everywhere, folder }

enum _Since {
  any('Any time', null),
  day('Past day', Duration(days: 1)),
  week('Past week', Duration(days: 7)),
  month('Past month', Duration(days: 30));

  final String label;
  final Duration? window;
  const _Since(this.label, this.window);

  DateTime? get cutoff => window == null ? null : DateTime.now().subtract(window!);
}

/// A file-type chip: the backend kind group it sends, and its scoop.
class _KindFilter {
  final String key;
  final String label;
  final Color color;
  final Set<String> kinds;
  const _KindFilter(this.key, this.label, this.color, this.kinds);
}

const _kindFilters = [
  _KindFilter('folders', 'Folders', Scoop.blueberry, {'folder'}),
  _KindFilter('docs', 'Docs', Scoop.mango, {'pdf', 'document', 'spreadsheet', 'presentation', 'ebook'}),
  _KindFilter('images', 'Images', Scoop.bubblegum, {'image'}),
  _KindFilter('audio', 'Audio', Scoop.grape, {'audio'}),
  _KindFilter('video', 'Video', Scoop.strawberry, {'video'}),
  _KindFilter('code', 'Code', Scoop.mint, {'code', 'data'}),
];

/// One result row, whatever lane it came from.
class _Row {
  final FsEntry entry;

  /// Snippet with «marked» words, or null (the subline then names the folder).
  final String? snippet;
  final int? page;
  final bool best;
  const _Row(this.entry, {this.snippet, this.page, this.best = false});
}

/// Filters stay put between openings within a session; the query starts clean.
abstract final class _Sticky {
  static _Scope scope = _Scope.everywhere;
  static final Set<String> kinds = {};
  static int? tagId;
  static _Since since = _Since.any;
}

/// How long the cursor rests on a row before the preview follows it (sweeping the list loads nothing).
const _previewDelay = Duration(milliseconds: 120);

/// FilDOS waits 250 ms after the last keystroke before searching.
const _debounce = Duration(milliseconds: 250);

/// FilDOS' `duration-150 ease-snappy` transitions.
const _quick = Duration(milliseconds: 150);

// Fixed list geometry (FilDOS: py-1.5 list, pt-2.5 pb-1 10px headers, py-2 rows
// of a 20px name over a 16.5px subline), so arrow keys can keep the active row in view.
const _listPadTop = 6.0;
const _headerH = 29.0;
const _rowH = 52.0;

class _SearchOverlayState extends State<SearchOverlay> with TickerProviderStateMixin {
  late final TextEditingController _text;
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _scroll = ScrollController();
  late final AnimationController _enter = AnimationController(vsync: this, duration: _quick)..forward();
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  Timer? _debounceTimer;
  Timer? _previewTimer;
  int _req = 0;
  bool _loading = false;
  SearchResponse? _resp;
  String _respQuery = '';
  List<FsEntry> _tagFiles = const [];
  Map<String, List<int>> _tagMap = const {};
  bool _showWeak = false;
  int _active = 0;
  _Row? _shown;

  // Rows derived from the latest response and the client-side filters.
  List<_Row> _strong = const [];
  List<_Row> _weak = const [];

  @override
  void initState() {
    super.initState();
    final app = context.read<FaController>();
    _text = TextEditingController(text: app.searchSeed);
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    if (_Sticky.tagId != null && !app.tags.any((t) => t.id == _Sticky.tagId)) _Sticky.tagId = null;
    if (app.currentFolder.isEmpty) _Sticky.scope = _Scope.everywhere;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _schedule(immediate: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _orbit.stop();
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _previewTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    _enter.dispose();
    _orbit.dispose();
    super.dispose();
  }

  FaController get _app => context.read<FaController>();
  String get _query => _text.text.trim();
  bool get _scopedToFolder => _Sticky.scope == _Scope.folder && _hasFolder(_app);

  /// "This folder" only makes sense with a folder behind the overlay.
  static bool _hasFolder(FaController app) => app.section == FaSection.browse && app.currentFolder.isNotEmpty;

  // ── search execution (debounced, stale responses dropped) ───────────────

  /// Runs the search for the current query. The previous results stay on
  /// screen (with the spinner) until the new ones arrive, so nothing blinks
  /// between keystrokes.
  void _schedule({bool immediate = false}) {
    _debounceTimer?.cancel();
    final id = ++_req;
    final q = _query;
    if (q.isEmpty) {
      setState(() {
        _resp = null;
        _respQuery = '';
        _loading = false;
        _rebuildRows(resetActive: true);
      });
      if (_Sticky.tagId != null) _loadTagFiles(id, _Sticky.tagId!);
      return;
    }
    setState(() => _loading = true);
    _debounceTimer = Timer(immediate ? Duration.zero : _debounce, () => _run(id, q));
  }

  Future<void> _loadTagFiles(int id, int tagId) async {
    final r = await _app.api.tagFiles(tagId);
    if (!mounted || id != _req) return;
    if (!r.ok) return;
    setState(() {
      _tagFiles = r.value ?? const [];
      _rebuildRows(resetActive: true);
    });
  }

  Future<void> _run(int id, String q) async {
    final app = _app;
    final r = await app.api.search(
      q,
      root: _scopedToFolder ? app.currentFolder : null,
      scope: _scopedToFolder ? 'folder' : 'everywhere',
      kinds: [
        for (final f in _kindFilters)
          if (_Sticky.kinds.contains(f.key)) f.key,
      ],
      since: _Sticky.since.cutoff,
    );
    if (!mounted || id != _req) return;
    var tagMap = const <String, List<int>>{};
    if (r.ok && _Sticky.tagId != null && r.value!.results.isNotEmpty) {
      final t = await app.api.tagsForPaths([for (final h in r.value!.results) h.entry.path]);
      if (!mounted || id != _req) return;
      tagMap = t.value ?? const {};
    }
    if (!r.ok) app.toastError(r.error);
    setState(() {
      _loading = false;
      _resp = r.value;
      _respQuery = q;
      _tagMap = tagMap;
      _showWeak = false;
      _rebuildRows(resetActive: true);
    });
  }

  /// Assemble the fused list through the client-side filters (tag; kind/time for tag browsing).
  void _rebuildRows({bool resetActive = false}) {
    final tagId = _Sticky.tagId;
    if (_query.isEmpty) {
      _weak = const [];
      if (tagId == null) {
        // Nothing typed: the panel waits for a query (no recents list).
        _strong = const [];
      } else {
        final kinds = {
          for (final f in _kindFilters)
            if (_Sticky.kinds.contains(f.key)) ...f.kinds,
        };
        final cutoff = _Sticky.since.cutoff;
        _strong = [
          for (final e in _tagFiles)
            if ((kinds.isEmpty || kinds.contains(e.kind)) && (cutoff == null || e.mtime.isAfter(cutoff))) _Row(e),
        ];
      }
    } else {
      final hits = (_resp?.results ?? const <SearchHit>[])
          .where((h) => tagId == null || (_tagMap[h.entry.path] ?? const []).contains(tagId))
          .toList();
      // A weaker meaning match stays weak unless its name matches too.
      bool weak(SearchHit h) => !h.strong && !h.lanes.contains('name');
      _Row row(SearchHit h, {bool best = false}) =>
          _Row(h.entry, snippet: (h.snippet ?? '').trim().isEmpty ? null : h.snippet, page: h.page, best: best);
      // The single strongest result — the first row, unless it is a weaker one.
      _strong = [
        for (final (i, h) in hits.indexed)
          if (!weak(h)) row(h, best: i == 0),
      ];
      _weak = [
        for (final h in hits)
          if (weak(h)) row(h),
      ];
    }
    final n = _flat.length;
    if (resetActive) {
      _active = 0;
      _shown = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    _active = n == 0 ? 0 : _active.clamp(0, n - 1);
    _syncPreview();
  }

  /// Weaker matches show (under their own heading) once expanded — or when they're all there is.
  bool get _weakShown => _showWeak || _strong.isEmpty;
  List<_Row> get _flat => _weakShown ? [..._strong, ..._weak] : _strong;
  int get _foldedWeak => _weakShown ? 0 : _weak.length;
  _Row? get _activeRow {
    final f = _flat;
    return f.isEmpty ? null : f[_active.clamp(0, f.length - 1)];
  }

  /// The preview follows the active row once the cursor rests on it; the first (best) shows at once.
  void _syncPreview() {
    _previewTimer?.cancel();
    final row = _activeRow;
    if (row == null) {
      _shown = null;
      return;
    }
    if (_shown == null) {
      _shown = row;
      return;
    }
    if (_shown!.entry.path == row.entry.path && _shown!.page == row.page) {
      _shown = row;
      return;
    }
    _previewTimer = Timer(_previewDelay, () {
      if (mounted) setState(() => _shown = _activeRow);
    });
  }

  void _setActive(int i, {bool ensureVisible = false}) {
    final n = _flat.length;
    if (n == 0) return;
    final next = i.clamp(0, n - 1);
    if (next != _active) {
      setState(() {
        _active = next;
        _syncPreview();
      });
    }
    if (ensureVisible) _ensureVisible(next);
  }

  /// `scrollIntoView({ block: 'nearest' })` for row [i].
  void _ensureVisible(int i) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (i == 0) {
      // The best match: bring its heading along too.
      if (pos.pixels > 0) _scroll.jumpTo(0);
      return;
    }
    final strongHeader = _strong.isEmpty ? 0.0 : _headerH;
    final weakHeader = _weakShown && _weak.isNotEmpty && i >= _strong.length ? _headerH : 0.0;
    final top = _listPadTop + strongHeader + weakHeader + i * _rowH;
    final bottom = top + _rowH;
    if (top < pos.pixels) {
      _scroll.jumpTo(top.clamp(0.0, pos.maxScrollExtent));
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo((bottom - pos.viewportDimension).clamp(0.0, pos.maxScrollExtent));
    }
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _open(_Row row) async {
    final app = _app;
    final ex = context.read<ExplorerController>();
    app.closeSearch();
    if (row.entry.isDir) {
      await ex.open(row.entry.path);
    } else {
      final r = await app.api.open(row.entry.path);
      if (!r.ok) app.toastError(r.error);
    }
  }

  /// Show in folder: open the parent in the explorer with the file selected.
  Future<void> _reveal(_Row row) async {
    final ex = context.read<ExplorerController>();
    _app.closeSearch();
    final path = row.entry.path;
    if (row.entry.isDir) {
      await ex.open(path);
      return;
    }
    await ex.open(parentDir(path));
    FsEntry? match;
    for (final e in ex.entries) {
      if (e.path == path) {
        match = e;
        break;
      }
    }
    if (match != null) {
      ex.select(match);
    } else {
      await ex.reveal(path); // hidden from the listing: let the OS show it.
    }
  }

  void _close() => _app.closeSearch();

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _setActive(_active + 1, ensureVisible: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _setActive(_active - 1, ensureVisible: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      final row = _activeRow;
      if (row == null) return KeyEventResult.ignored;
      isPrimaryModifierPressed() ? _reveal(row) : _open(row);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      if (_text.text.isNotEmpty) {
        _text.clear();
        _schedule();
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── filter menus ─────────────────────────────────────────────────────────

  Future<void> _menuBelow(BuildContext anchor, List<FaMenuItem> items) async {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) return;
    await showFaMenu(anchor, box.localToGlobal(Offset(0, box.size.height + 4)), items);
    if (mounted) _focus.requestFocus();
  }

  void _setFilter(VoidCallback change) {
    change();
    _schedule(immediate: true);
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = context.watch<FaController>();
    final size = MediaQuery.sizeOf(context);
    // w-[min(1040px,94vw)], mt-[8vh]; results h-[min(620px,66vh)] — one size whatever it shows.
    final width = math.min(1040.0, size.width * 0.94);
    final topGap = size.height * 0.08;
    final resultsH = math.min(620.0, size.height * 0.66);
    final fade = CurvedAnimation(parent: _enter, curve: Curves.ease);

    return Positioned.fill(
      child: Stack(
        children: [
          // bg-ink/20 + 3px blur in both themes; a press outside closes (onMouseDown).
          Positioned.fill(
            child: FadeTransition(
              opacity: fade,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _close(),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: const ColoredBox(color: Color(0x330F1117)),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: topGap),
              child: FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: Tween(begin: 0.95, end: 1.0).animate(fade),
                  child: Focus(
                    // Keys reach the panel from anywhere inside it (FilDOS' onKeyDown on the panel),
                    // e.g. after a click in the preview's text took focus from the input.
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onKey,
                    child: GestureDetector(
                      onTap: () {}, // swallow: clicks inside never close
                      child: SizedBox(width: width, child: _panel(context, app, size.width, resultsH)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, FaController app, double windowWidth, double resultsH) {
    final c = context.fa;
    final aiReady = _resp?.meaningAvailable ?? (app.aiEnabled && app.index.model.ready);
    final flat = _flat;
    final split = flat.isNotEmpty;
    // Too narrow for both (≤ 820 px): the preview isn't mounted at all.
    final roomForPreview = windowWidth > 820;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final radius = BorderRadius.circular(FaRadius.xl);

    // `material`: popover at 92% over a 24px, 180%-saturated blur; shadow-2xl; rounded-xl.
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 50, spreadRadius: -12, offset: Offset(0, 25)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.compose(outer: _saturate180, inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24)),
          child: ColoredBox(
            color: c.popover.withValues(alpha: 0.92),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _inputRow(c, aiReady),
                  Divider(height: 1, thickness: 1, color: c.border),
                  _chipsRow(c, app),
                  Divider(height: 1, thickness: 1, color: c.border),
                  SizedBox(
                    height: resultsH,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final showPreview = split && roomForPreview && _shown != null;
                        final list = _list(c, app);
                        if (!split || !roomForPreview) return list;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: box.maxWidth / 2, child: list),
                            VerticalDivider(width: 1, thickness: 1, color: c.border),
                            Expanded(
                              child: showPreview
                                  ? _PreviewPane(
                                      row: _shown!,
                                      words: _previewWords(),
                                      query: _respQuery,
                                      home: app.home,
                                      onOpen: _open,
                                      onReveal: _reveal,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: c.border),
                  _footer(c, app, aiReady),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // The scoop comet orbiting the panel edge (-inset-px -m-px: 2px outside it).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -2,
          top: -2,
          right: -2,
          bottom: -2,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: ScoopTrailPainter(_orbit, base: c.border, comet: !still),
              ),
            ),
          ),
        ),
        panel,
      ],
    );
  }

  /// Words to light in the preview: the snippet's marked words, else the query's (3+ letters).
  List<String> _previewWords() {
    final sub = _shown?.snippet;
    if (sub != null) {
      final marked = markedWords(sub);
      if (marked.isNotEmpty) return marked;
    }
    final q = (_respQuery.isEmpty ? _query : _respQuery).toLowerCase();
    return {
      for (final w in q.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        if (w.runes.length >= 3) w,
    }.toList();
  }

  Widget _inputRow(FaColors c, bool aiReady) => SizedBox(
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: aiReady ? Scoop.mint : c.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              onChanged: (_) => _schedule(),
              style: FaText.sans(size: 15, color: c.foreground),
              cursorColor: c.foreground,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search by name, meaning, or tag…',
                hintStyle: FaText.sans(size: 15, color: c.mutedForeground),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_loading)
            const SizedBox(
              width: 15,
              height: 15,
              child: Padding(
                padding: EdgeInsets.all(0.75),
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Scoop.mint),
              ),
            )
          else
            const Kbd('esc'),
        ],
      ),
    ),
  );

  Widget _chipsRow(FaColors c, FaController app) {
    final tag = app.tags.where((t) => t.id == _Sticky.tagId).firstOrNull;
    final tagColor = tag == null ? null : Scoop.parse(tag.color);
    // px-3.5 py-2.5, gap-1.5 — wraps, never scrolls.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_hasFolder(app)) _scopeToggle(c),
          for (final f in _kindFilters)
            _FilterChip(
              label: f.label,
              dot: f.color,
              tint: _Sticky.kinds.contains(f.key) ? f.color : null,
              onTap: () => _setFilter(() {
                _Sticky.kinds.contains(f.key) ? _Sticky.kinds.remove(f.key) : _Sticky.kinds.add(f.key);
              }),
            ),
          if (app.tags.isNotEmpty)
            Builder(
              builder: (anchor) => _FilterChip(
                label: tag?.name ?? 'Tag',
                icon: tag == null ? Icons.sell_outlined : null,
                dot: tagColor,
                dotSize: 8,
                tint: tagColor,
                borderAlpha: 0x59 / 0xff,
                onTap: () => _menuBelow(anchor, [
                  FaMenuItem(
                    'Any tag',
                    leading: _RadioMark(on: _Sticky.tagId == null),
                    onTap: () => _setFilter(() => _Sticky.tagId = null),
                  ),
                  for (final t in app.tags)
                    FaMenuItem(
                      t.name,
                      leading: _RadioMark(on: t.id == _Sticky.tagId, dot: Scoop.parse(t.color)),
                      onTap: () => _setFilter(() => _Sticky.tagId = t.id),
                    ),
                ]),
              ),
            ),
          Builder(
            builder: (anchor) => _FilterChip(
              label: _Sticky.since.label,
              icon: Icons.schedule_rounded,
              tint: _Sticky.since == _Since.any ? null : Scoop.blueberry,
              onTap: () => _menuBelow(anchor, [
                for (final s in _Since.values)
                  FaMenuItem(
                    s.label,
                    leading: _RadioMark(on: s == _Sticky.since),
                    onTap: () => _setFilter(() => _Sticky.since = s),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Scope: a segmented pill (bg-muted h-6 p-0.5 mr-1; h-5 px-2 segments).
  Widget _scopeToggle(FaColors c) => Container(
    height: 24,
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in _Scope.values)
          Hoverable(
            onTap: () => _setFilter(() => _Sticky.scope = s),
            builder: (context, hover) {
              final on = _Sticky.scope == s;
              return AnimatedContainer(
                duration: _quick,
                curve: FaMotion.snappy,
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? c.background : c.background.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: on ? _shadowSm : null,
                ),
                child: Text(
                  s == _Scope.everywhere ? 'Everywhere' : 'This folder',
                  style: FaText.sans(size: 11, color: on || hover ? c.foreground : c.mutedForeground),
                ),
              );
            },
          ),
      ],
    ),
  );

  Widget _list(FaColors c, FaController app) {
    final strong = _strong;
    if (strong.isEmpty && _weak.isEmpty) return _emptyState(c, app);
    final tag = app.tags.where((t) => t.id == _Sticky.tagId).firstOrNull;
    final browsingTag = _query.isEmpty && tag != null;
    final children = <Widget>[];
    var i = 0;
    if (strong.isNotEmpty) {
      children.add(
        _SectionHeader(
          title: browsingTag ? 'Tagged “${tag.name}”' : 'Results',
          icon: browsingTag ? null : Icons.auto_awesome_outlined,
          iconColor: browsingTag ? null : Scoop.mint,
          dot: browsingTag ? Scoop.parse(tag.color) : null,
        ),
      );
      for (final r in strong) {
        children.add(_rowTile(c, app, r, i++));
      }
    }
    if (_weakShown && _weak.isNotEmpty) {
      children.add(const _SectionHeader(title: 'Weaker matches', icon: Icons.search_rounded));
      for (final r in _weak) {
        children.add(_rowTile(c, app, r, i++));
      }
    }
    final folded = _foldedWeak;
    if (folded > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Hoverable(
            cursor: SystemMouseCursors.basic,
            onTap: () => setState(() {
              _showWeak = true;
              _syncPreview();
            }),
            builder: (context, hover) => Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.foreground.withValues(alpha: hover ? 0.06 : 0),
                borderRadius: BorderRadius.circular(FaRadius.lg),
              ),
              child: Row(
                children: [
                  Icon(Icons.chevron_right_rounded, size: 11, color: hover ? c.foreground : c.mutedForeground),
                  const SizedBox(width: 6),
                  Text(
                    '$folded weaker ${folded == 1 ? 'match' : 'matches'}',
                    style: FaText.sans(size: 11, color: hover ? c.foreground : c.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: _listPadTop),
        children: children,
      ),
    );
  }

  Widget _rowTile(FaColors c, FaController app, _Row row, int i) {
    final active = i == _active;
    // The subline names the folder compactly ("~/Books", "…/Trips/2024") when there is no snippet.
    final sub = row.snippet ?? _compactDir(parentDir(row.entry.path), app.home);
    return SizedBox(
      key: ValueKey('row:${row.entry.path}'),
      height: _rowH,
      // Only a moving pointer takes the cursor (onMouseMove): results changing
      // under a still pointer never steal it from the keyboard.
      child: MouseRegion(
        onHover: (_) => _setActive(i),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(row),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.foreground.withValues(alpha: active ? 0.06 : 0),
              borderRadius: BorderRadius.circular(FaRadius.lg),
            ),
            child: Row(
              children: [
                FileIcon.entry(row.entry, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: row.entry.path,
                        waitDuration: const Duration(milliseconds: 800),
                        child: Text(
                          row.entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FaText.sans(size: 14, color: c.foreground, height: 20 / 14),
                        ),
                      ),
                      _Marked(sub, style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.5)),
                    ],
                  ),
                ),
                if (row.page != null) ...[
                  const SizedBox(width: 12),
                  Tooltip(
                    message: 'Matched on page ${row.page}',
                    // The preview beside the list opens there; the click only selects.
                    child: _PlacePill('p. ${row.page}', onTap: () => _setActive(i)),
                  ),
                ],
                if (row.best) ...[
                  const SizedBox(width: 12),
                  const Tooltip(message: 'Strongest match', child: _BestBadge()),
                ] else if (active) ...[
                  const SizedBox(width: 12),
                  const Kbd('↵'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(FaColors c, FaController app) {
    final q = _query;
    final String message;
    if (_loading) {
      message = 'Searching…';
    } else if (q.isNotEmpty || _Sticky.tagId != null) {
      message = 'No matches.';
    } else {
      message = 'Type to search by name or meaning.';
    }
    // flex-col items-center gap-2.5 px-6 py-12.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
              child: Icon(
                q.isEmpty ? Icons.auto_awesome_outlined : Icons.search_rounded,
                size: 17,
                color: c.mutedForeground,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FaText.sans(size: 14, color: c.mutedForeground),
            ),
            if (!app.aiEnabled) ...[
              const SizedBox(height: 10),
              Text(
                'Enable AI in Settings to also search by meaning.',
                textAlign: TextAlign.center,
                style: FaText.sans(size: 11, color: c.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(FaColors c, FaController app, bool aiReady) {
    final style = FaText.sans(size: 10, color: c.mutedForeground);
    final mod = Platform.isMacOS ? '⌘' : 'Ctrl';
    final where = _scopedToFolder
        ? (baseName(app.currentFolder).isEmpty ? app.currentFolder : baseName(app.currentFolder))
        : 'Everywhere';
    const gap = SizedBox(width: 6);
    const groupGap = SizedBox(width: 4);
    // px-4 py-1.5 text-3xs, justify-between gap-3; hint items gap-1.5, key groups gap-1.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Kbd('↑'),
          groupGap,
          const Kbd('↓'),
          gap,
          Text('Navigate ·', style: style),
          gap,
          const Kbd('↵'),
          gap,
          Text('Open ·', style: style),
          gap,
          Kbd(mod),
          groupGap,
          const Kbd('↵'),
          gap,
          Text('Show in Folder', style: style),
          const SizedBox(width: 12),
          const Spacer(),
          ScoopDot(aiReady ? Scoop.mint : c.mutedForeground.withValues(alpha: 0.4), size: 6),
          gap,
          Flexible(
            child: Text(
              '${aiReady ? 'Meaning + name search' : 'Name search'} · $where',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// `saturate(180%)` as a colour matrix (the `material` backdrop).
const _saturate180 = ColorFilter.matrix(<double>[
  1.6296, -0.572, -0.0576, 0, 0, //
  -0.1704, 1.228, -0.0576, 0, 0, //
  -0.1704, -0.572, 1.7424, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Tailwind `shadow-sm`.
const _shadowSm = [
  BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x1A000000), blurRadius: 2, spreadRadius: -1, offset: Offset(0, 1)),
];

/// The distinct «marked» words of a snippet, lowercased.
List<String> markedWords(String text) => {
  for (final m in RegExp('«([^«»]*)»').allMatches(text)) m.group(1)!.toLowerCase(),
}.where((w) => w.isNotEmpty).toList();

/// A folder path short enough to read at a glance: home becomes "~", and a
/// deep path keeps only its last two folders ("…/Books/Birds").
String _compactDir(String dir, String home) {
  final sep = Platform.pathSeparator;
  final underHome = home.isNotEmpty && (dir == home || dir.startsWith('$home$sep'));
  final shown = underHome ? '~${dir.substring(home.length)}' : dir;
  final parts = shown.split(sep).where((p) => p.isNotEmpty).toList();
  final lead = underHome ? 1 : 0; // "~" counts as a part
  if (parts.length - lead <= 3) return shown;
  return ['…', ...parts.sublist(parts.length - 2)].join(sep);
}

// ── pieces ───────────────────────────────────────────────────────────────────

/// A snippet with its marked words highlighted — a light wash, not weight.
class _Marked extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _Marked(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final mark = TextStyle(color: c.foreground, backgroundColor: c.primary.withValues(alpha: 0.10));
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in RegExp('«([^«»]*)»').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: mark));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Radix radio-item indicator (a filled 8px circle at the left) plus an optional tag dot.
class _RadioMark extends StatelessWidget {
  final bool on;
  final Color? dot;
  const _RadioMark({required this.on, this.dot});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 10, child: on ? ScoopDot(c.foreground, size: 8) : null),
        if (dot != null) ...[const SizedBox(width: 2), ScoopDot(dot!, size: 9)],
      ],
    );
  }
}

/// `active:scale-[0.97]` — a quick press-in for buttons and chips.
class _Press extends StatefulWidget {
  final Widget child;
  const _Press({required this.child});

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;
  void _set(bool v) {
    if (v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(scale: _down ? 0.97 : 1, duration: _quick, curve: FaMotion.snappy, child: widget.child),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Color? dot;
  const _SectionHeader({required this.title, this.icon, this.iconColor, this.dot});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    // px-4 pt-2.5 pb-1, gap-1.5, text-3xs tracking-wider uppercase.
    return SizedBox(
      height: _headerH,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            if (dot != null)
              ScoopDot(dot!, size: 8)
            else if (icon != null)
              Icon(icon, size: 11, color: iconColor ?? c.mutedForeground),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 10, color: c.mutedForeground, letterSpacing: 0.5, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A filter chip whose dot always carries its scoop; when on, it fills with that scoop's tint.
class _FilterChip extends StatelessWidget {
  final String label;
  final Color? dot;
  final double dotSize;
  final IconData? icon;
  final Color? tint;
  final double borderAlpha;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.onTap,
    this.dot,
    this.dotSize = 6,
    this.icon,
    this.tint,
    this.borderAlpha = 0.40,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final on = tint != null;
    // h-6 rounded-full border px-2.5 text-2xs gap-1.5; idle border/70, hover border + bg-accent.
    return _Press(
      child: Hoverable(
        cursor: SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hover) {
          final fg = on ? tint! : (hover ? c.foreground : c.mutedForeground);
          return AnimatedContainer(
            duration: _quick,
            curve: FaMotion.snappy,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: on ? tint!.withValues(alpha: 0.10) : c.accent.withValues(alpha: hover ? 1 : 0),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: on ? tint!.withValues(alpha: borderAlpha) : c.border.withValues(alpha: hover ? 1 : 0.7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[ScoopDot(dot!, size: dotSize), const SizedBox(width: 6)],
                if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 6)],
                Text(label, style: FaText.sans(size: 11, color: fg)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The "p. 7" pill on a row: border rounded-sm px-1.5 py-0.5 font-mono text-3xs.
class _PlacePill extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _PlacePill(this.text, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      onTap: onTap,
      builder: (context, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.foreground.withValues(alpha: hover && onTap != null ? 0.06 : 0),
          borderRadius: BorderRadius.circular(FaRadius.sm),
          border: Border.all(color: c.border),
        ),
        child: Text(
          text,
          style: FaText.mono(size: 10, color: hover && onTap != null ? c.foreground : c.mutedForeground),
        ),
      ),
    );
  }
}

class _BestBadge extends StatelessWidget {
  const _BestBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Scoop.mint.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(FaRadius.sm),
    ),
    child: Text('Best', style: FaText.sans(size: 10, color: Scoop.mint)),
  );
}

/// The active result, previewed: where it lives, a look inside (at its page), and what to do with it.
class _PreviewPane extends StatelessWidget {
  final _Row row;
  final List<String> words;
  final String query;
  final String home;
  final Future<void> Function(_Row) onOpen;
  final Future<void> Function(_Row) onReveal;
  const _PreviewPane({
    required this.row,
    required this.words,
    required this.query,
    required this.home,
    required this.onOpen,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final e = row.entry;
    final folder = parentDir(e.path);
    final facts = [if (!e.isDir) formatBytes(e.size), formatDate(e.mtime)].join(' · ');
    final mod = Platform.isMacOS ? '⌘' : 'Ctrl';
    final meta = FaText.mono(size: 10, color: c.mutedForeground);
    // flex-col gap-3 p-4.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: e.path,
                      waitDuration: const Duration(milliseconds: 800),
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 14, color: c.foreground, height: 20 / 14),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Tooltip(
                            message: folder,
                            waitDuration: const Duration(milliseconds: 800),
                            child: Text(
                              _compactDir(folder, home),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: meta,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('· $facts', style: meta),
                      ],
                    ),
                  ],
                ),
              ),
              if (row.page != null) ...[const SizedBox(width: 16), _PlacePill('page ${row.page}')],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FilePreview(
              key: ValueKey(e.path),
              entry: e,
              words: words,
              query: query,
              page: row.page,
              compact: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionButton(label: 'Show in folder', keys: '$mod↵', onTap: () => onReveal(row)),
              const SizedBox(width: 8),
              _ActionButton(
                label: e.isDir ? 'Go to folder' : 'Open',
                keys: '↵',
                secondary: true,
                onTap: () => onOpen(row),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// FilDOS `Button size="sm"`: h-8 rounded-sm px-3 gap-1.5 text-sm, ghost or secondary, with a keycap.
class _ActionButton extends StatelessWidget {
  final String label;
  final String keys;
  final bool secondary;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.keys, required this.onTap, this.secondary = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return _Press(
      child: Hoverable(
        cursor: SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hover) => AnimatedContainer(
          duration: _quick,
          curve: FaMotion.snappy,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: secondary
                ? c.muted.withValues(alpha: hover ? 0.8 : 1)
                : c.foreground.withValues(alpha: hover ? 0.09 : 0),
            borderRadius: BorderRadius.circular(FaRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: FaText.sans(size: 14, color: secondary || hover ? c.foreground : c.mutedForeground)),
              const SizedBox(width: 10),
              Kbd(keys),
            ],
          ),
        ),
      ),
    );
  }
}
