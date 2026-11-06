import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
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
  day('Today', Duration(days: 1)),
  week('Past week', Duration(days: 7)),
  month('Past month', Duration(days: 30)),
  year('Past year', Duration(days: 365));

  final String label;
  final Duration? window;
  const _Since(this.label, this.window);

  DateTime? get cutoff {
    if (this == _Since.day) {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day);
    }
    return window == null ? null : DateTime.now().subtract(window!);
  }
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
  static final List<String> recent = [];
}

/// How long the cursor rests on a row before the preview follows it.
const _previewDelay = Duration(milliseconds: 120);
const _debounce = Duration(milliseconds: 180);

// Fixed list geometry, so arrow keys can keep the active row in view.
const _listPadTop = 6.0;
const _headerH = 30.0;
const _rowH = 52.0;

class _SearchOverlayState extends State<SearchOverlay> with TickerProviderStateMixin {
  late final TextEditingController _text;
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _scroll = ScrollController();
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 160))
    ..forward();
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  Timer? _debounceTimer;
  Timer? _previewTimer;
  int _req = 0;
  bool _loading = false;
  FaError? _error;
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

  void _schedule({bool immediate = false}) {
    _debounceTimer?.cancel();
    final id = ++_req;
    final q = _query;
    if (q.isEmpty) {
      setState(() {
        _resp = null;
        _respQuery = '';
        _error = null;
        _loading = _Sticky.tagId != null;
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
    setState(() {
      _loading = false;
      _tagFiles = r.value ?? const [];
      _error = r.error;
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
    setState(() {
      _loading = false;
      _resp = r.value;
      _respQuery = q;
      _error = r.error;
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
      SearchHit? best;
      for (final h in hits) {
        if (h.strong) {
          best = h;
          break;
        }
      }
      _Row row(SearchHit h) => _Row(
        h.entry,
        snippet: (h.snippet ?? '').trim().isEmpty ? null : h.snippet,
        page: h.page,
        best: identical(h, best),
      );
      _strong = [
        for (final h in hits)
          if (!weak(h)) row(h),
      ];
      _weak = [
        for (final h in hits)
          if (weak(h)) row(h),
      ];
      // Nothing clear: the weaker ones are all there is — show them.
      if (_strong.isEmpty) {
        _strong = _weak;
        _weak = const [];
      }
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

  List<_Row> get _flat => _showWeak ? [..._strong, ..._weak] : _strong;
  int get _foldedWeak => _showWeak ? 0 : _weak.length;
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
    if (_shown!.entry.path == row.entry.path && _shown!.page == row.page) return;
    _previewTimer = Timer(_previewDelay, () {
      if (mounted) setState(() => _shown = _activeRow);
    });
  }

  void _setActive(int i, {bool ensureVisible = false}) {
    final n = _flat.length;
    if (n == 0) return;
    final next = i.clamp(0, n - 1);
    if (next == _active) return;
    setState(() {
      _active = next;
      _syncPreview();
    });
    if (ensureVisible) _ensureVisible(next);
  }

  void _ensureVisible(int i) {
    if (!_scroll.hasClients) return;
    final weakHeader = _showWeak && _weak.isNotEmpty && i >= _strong.length ? _headerH : 0.0;
    final top = _listPadTop + _headerH + weakHeader + i * _rowH;
    final bottom = top + _rowH;
    final pos = _scroll.position;
    if (top - 8 < pos.pixels) {
      _scroll.jumpTo((top - 8 - (i == 0 ? _headerH + _listPadTop : 0)).clamp(0.0, pos.maxScrollExtent));
    } else if (bottom + 8 > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo((bottom + 8 - pos.viewportDimension).clamp(0.0, pos.maxScrollExtent));
    }
  }

  // ── actions ──────────────────────────────────────────────────────────────

  void _remember() {
    final q = _query;
    if (q.isEmpty) return;
    _Sticky.recent
      ..remove(q)
      ..insert(0, q);
    if (_Sticky.recent.length > 6) _Sticky.recent.removeLast();
  }

  Future<void> _open(_Row row) async {
    final app = _app;
    final ex = context.read<ExplorerController>();
    _remember();
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
    _remember();
    _app.closeSearch();
    final path = row.entry.path;
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
      if (row != null) isPrimaryModifierPressed() ? _reveal(row) : _open(row);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
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
    final c = context.fa;
    final app = context.watch<FaController>();
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.94).clamp(320.0, 1040.0);
    final topGap = size.height * 0.08;
    final resultsH = (size.height * 0.66)
        .clamp(140.0, 620.0)
        .clamp(140.0, (size.height - topGap - 200).clamp(140.0, 620.0));
    final fade = CurvedAnimation(parent: _enter, curve: FaMotion.snappy);

    return Positioned.fill(
      child: Stack(
        children: [
          // Dimmed, blurred backdrop; a click outside closes.
          Positioned.fill(
            child: FadeTransition(
              opacity: fade,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: ColoredBox(color: c.overlay),
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
                  scale: Tween(begin: 0.96, end: 1.0).animate(fade),
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () {}, // swallow: clicks inside never close
                    child: SizedBox(width: width, child: _panel(context, app, size.width, resultsH)),
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
    final roomForPreview = windowWidth > 820;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final panel = Container(
      decoration: BoxDecoration(
        color: c.popover,
        borderRadius: BorderRadius.circular(FaRadius.xl),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.55 : 0.18),
            blurRadius: 48,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FaRadius.xl),
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
                    final list = _list(c, app, aiReady);
                    if (!showPreview) return list;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: box.maxWidth / 2, child: list),
                        VerticalDivider(width: 1, thickness: 1, color: c.border),
                        Expanded(
                          child: _PreviewPane(
                            row: _shown!,
                            words: _previewWords(),
                            home: app.home,
                            onOpen: _open,
                            onReveal: _reveal,
                          ),
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
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        panel,
        if (!still)
          Positioned(
            left: -1,
            top: -1,
            right: -1,
            bottom: -1,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: ScoopTrailPainter(_orbit, radius: FaRadius.xl + 1)),
              ),
            ),
          ),
      ],
    );
  }

  /// Words to light in the preview: the snippet's marked words, else the query's.
  String _previewWords() {
    final sub = _shown?.snippet;
    if (sub != null) {
      final marked = RegExp('«([^«»]*)»').allMatches(sub).map((m) => m.group(1)!.toLowerCase()).toSet();
      if (marked.isNotEmpty) return '${marked.join(' ')} $_respQuery';
    }
    return _respQuery.isEmpty ? _query : _respQuery;
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
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Scoop.mint))
          else
            const Kbd('esc'),
        ],
      ),
    ),
  );

  Widget _chipsRow(FaColors c, FaController app) {
    final tag = app.tags.where((t) => t.id == _Sticky.tagId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_hasFolder(app)) _scopeToggle(c, app),
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
                dot: tag == null ? null : Scoop.parse(tag.color),
                tint: tag == null ? null : Scoop.parse(tag.color),
                onTap: () => _menuBelow(anchor, [
                  FaMenuItem(
                    'Any tag',
                    icon: _Sticky.tagId == null ? Icons.check_rounded : null,
                    onTap: () => _setFilter(() => _Sticky.tagId = null),
                  ),
                  const FaMenuItem.divider(),
                  for (final t in app.tags)
                    FaMenuItem(
                      t.name,
                      leading: ScoopDot(Scoop.parse(t.color), size: 9),
                      shortcut: t.id == _Sticky.tagId ? '✓' : null,
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
                    icon: s == _Sticky.since ? Icons.check_rounded : null,
                    leading: s == _Sticky.since ? null : const SizedBox(width: 15),
                    onTap: () => _setFilter(() => _Sticky.since = s),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeToggle(FaColors c, FaController app) => Container(
    height: 26,
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
                duration: FaMotion.fast,
                curve: FaMotion.snappy,
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? c.background : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: on
                      ? [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.4 : 0.08), blurRadius: 3)]
                      : null,
                ),
                child: Text(
                  s == _Scope.everywhere ? 'Everywhere' : 'This folder',
                  style: FaText.sans(
                    size: 11.5,
                    weight: on ? FontWeight.w500 : FontWeight.w400,
                    color: on || hover ? c.foreground : c.mutedForeground,
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );

  Widget _list(FaColors c, FaController app, bool aiReady) {
    final strong = _strong;
    if (strong.isEmpty) return _emptyState(c, aiReady);
    final tag = app.tags.where((t) => t.id == _Sticky.tagId).firstOrNull;
    final browsingTag = _query.isEmpty && tag != null;
    final children = <Widget>[
      _SectionHeader(
        title: browsingTag ? 'Tagged “${tag.name}”' : 'Results',
        icon: browsingTag ? null : Icons.auto_awesome_outlined,
        iconColor: Scoop.mint,
        dot: browsingTag ? Scoop.parse(tag.color) : null,
      ),
    ];
    var i = 0;
    for (final r in strong) {
      children.add(_rowTile(c, app, r, i++));
    }
    if (_showWeak && _weak.isNotEmpty) {
      children.add(const _SectionHeader(title: 'Weaker matches', icon: Icons.search_rounded));
      for (final r in _weak) {
        children.add(_rowTile(c, app, r, i++));
      }
    }
    final folded = _foldedWeak;
    if (folded > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
          child: Hoverable(
            onTap: () => setState(() => _showWeak = true),
            builder: (context, hover) => AnimatedContainer(
              duration: FaMotion.fast,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: hover ? c.foreground.withValues(alpha: 0.06) : Colors.transparent,
                borderRadius: BorderRadius.circular(FaRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.chevron_right_rounded, size: 14, color: hover ? c.foreground : c.mutedForeground),
                  const SizedBox(width: 4),
                  Text(
                    '$folded weaker ${folded == 1 ? 'match' : 'matches'}',
                    style: FaText.sans(size: 11.5, color: hover ? c.foreground : c.mutedForeground),
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
        padding: const EdgeInsets.only(top: _listPadTop, bottom: 6),
        children: children,
      ),
    );
  }

  Widget _rowTile(FaColors c, FaController app, _Row row, int i) {
    final active = i == _active;
    final sub = row.snippet ?? compactDir(parentDir(row.entry.path), app.home);
    return SizedBox(
      height: _rowH,
      child: MouseRegion(
        onHover: (_) => _setActive(i),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(row),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active ? c.foreground.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(FaRadius.md),
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
                      Text(
                        row.entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 13.5, color: c.foreground),
                      ),
                      const SizedBox(height: 2),
                      MarkedText(sub, style: FaText.sans(size: 11, color: c.mutedForeground)),
                    ],
                  ),
                ),
                if (row.page != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(message: 'Matched on page ${row.page}', child: _MonoPill('p. ${row.page}')),
                ],
                if (row.best) ...[
                  const SizedBox(width: 8),
                  Tooltip(message: 'Strongest match', child: _BestBadge()),
                ] else if (active) ...[
                  const SizedBox(width: 8),
                  const Kbd('↵'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(FaColors c, bool aiReady) {
    final q = _query;
    final recent = _Sticky.recent;
    final String message;
    if (_error != null) {
      message = 'Search failed — ${_error!.message}';
    } else if (_loading) {
      message = 'Searching…';
    } else if (q.isNotEmpty || _Sticky.tagId != null) {
      message = 'No matches.';
    } else {
      message = 'Type to search by name or meaning.';
    }
    final hint = Column(
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
          style: FaText.sans(size: 13, color: c.mutedForeground),
        ),
        if (!aiReady) ...[
          const SizedBox(height: 6),
          Text(
            'Turn on AI in Settings to also search by meaning.',
            style: FaText.sans(size: 11, color: c.mutedForeground),
          ),
        ],
      ],
    );
    if (q.isNotEmpty || recent.isEmpty || _Sticky.tagId != null) {
      return Center(
        child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: hint),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: _listPadTop, bottom: 12),
      children: [
        const _SectionHeader(title: 'Recent searches', icon: Icons.history_rounded),
        for (final r in recent)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Hoverable(
              onTap: () {
                _text.text = r;
                _text.selection = TextSelection.collapsed(offset: r.length);
                _focus.requestFocus();
                _schedule(immediate: true);
              },
              builder: (context, hover) => Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: hover ? c.foreground.withValues(alpha: 0.06) : Colors.transparent,
                  borderRadius: BorderRadius.circular(FaRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 15, color: c.mutedForeground),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 13, color: c.foreground),
                      ),
                    ),
                    if (hover) Icon(Icons.north_west_rounded, size: 13, color: c.mutedForeground),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        hint,
      ],
    );
  }

  Widget _footer(FaColors c, FaController app, bool aiReady) {
    final style = FaText.sans(size: 10.5, color: c.mutedForeground);
    final mod = Platform.isMacOS ? '⌘' : 'Ctrl';
    final where = _scopedToFolder
        ? (baseName(app.currentFolder).isEmpty ? app.currentFolder : baseName(app.currentFolder))
        : 'Everywhere';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          const Kbd('↑'),
          const SizedBox(width: 2),
          const Kbd('↓'),
          Text(' Navigate · ', style: style),
          const Kbd('↵'),
          Text(' Open · ', style: style),
          Kbd(mod),
          const SizedBox(width: 2),
          const Kbd('↵'),
          Text(' Show in Folder', style: style),
          const Spacer(),
          ScoopDot(aiReady ? Scoop.mint : c.mutedForeground.withValues(alpha: 0.4), size: 6),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${aiReady ? 'Meaning + name search' : 'Name search only'} · $where',
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

// ── pieces ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Color? dot;
  const _SectionHeader({required this.title, this.icon, this.iconColor, this.dot});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return SizedBox(
      height: _headerH,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
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
                style: FaText.label(c).copyWith(fontSize: 10),
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
  final IconData? icon;
  final Color? tint;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.onTap, this.dot, this.icon, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final on = tint != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        curve: FaMotion.snappy,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? tint!.withValues(alpha: 0.10) : (hover ? c.accent : Colors.transparent),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? tint!.withValues(alpha: 0.40) : (hover ? c.border : c.border.withValues(alpha: 0.7)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[ScoopDot(dot!, size: 6), const SizedBox(width: 6)],
            if (icon != null) ...[
              Icon(icon, size: 12, color: on ? tint : (hover ? c.foreground : c.mutedForeground)),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: FaText.sans(
                size: 11.5,
                weight: on ? FontWeight.w500 : FontWeight.w400,
                color: on ? tint : (hover ? c.foreground : c.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonoPill extends StatelessWidget {
  final String text;
  const _MonoPill(this.text);
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: FaText.mono(size: 10, color: c.mutedForeground)),
    );
  }
}

class _BestBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Scoop.mint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
    child: Text(
      'Best',
      style: FaText.sans(size: 10, weight: FontWeight.w500, color: Scoop.mint),
    ),
  );
}

/// The active result, previewed: where it lives, a look inside (at its page), and what to do with it.
class _PreviewPane extends StatelessWidget {
  final _Row row;
  final String words;
  final String home;
  final Future<void> Function(_Row) onOpen;
  final Future<void> Function(_Row) onReveal;
  const _PreviewPane({
    required this.row,
    required this.words,
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
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 13.5, weight: FontWeight.w500, color: c.foreground),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            compactDir(folder, home),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FaText.mono(size: 10, color: c.mutedForeground),
                          ),
                        ),
                        Text(' · $facts', style: FaText.mono(size: 10, color: c.mutedForeground)),
                      ],
                    ),
                  ],
                ),
              ),
              if (row.page != null) ...[const SizedBox(width: 12), _MonoPill('page ${row.page}')],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FilePreview(key: ValueKey(e.path), entry: e, query: words, page: row.page, compact: true),
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
                primary: true,
                onTap: () => onOpen(row),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String keys;
  final bool primary;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.keys, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        height: 28,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          color: primary ? (hover ? c.border : c.muted) : (hover ? c.accent : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
            ),
            const SizedBox(width: 6),
            Kbd(keys),
          ],
        ),
      ),
    );
  }
}
