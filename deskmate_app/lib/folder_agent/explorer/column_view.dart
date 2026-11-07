import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import 'context_menu.dart';
import 'entry_interactions.dart';
import 'explorer_common.dart';

/// FilDOS ColumnView geometry.
const double _kColumnWidth = 248;
const double _kPreviewWidth = 288; // w-72
const double _kRowHeight = 28;

/// Finder-style Miller columns (FilDOS ColumnView). The leftmost column is
/// the folder you were in when you switched to this view; clicking a folder
/// opens a column to its right *and navigates there* (so the address bar
/// follows), clicking a file shows a preview pane at the end. Navigating from
/// elsewhere (address bar, sidebar, Back/Forward) collapses the trail back to
/// that folder.
///
/// A column's highlight is the child drilled into (or the previewed file),
/// not the explorer's selection — exactly as in FilDOS.
class ColumnBrowserView extends StatefulWidget {
  const ColumnBrowserView({super.key});

  @override
  State<ColumnBrowserView> createState() => _ColumnBrowserViewState();
}

class _ColumnBrowserViewState extends State<ColumnBrowserView> {
  final _scroll = ScrollController();

  /// One folder path per column.
  List<String> _trail = const [];

  /// The file previewed after the deepest column.
  FsEntry? _preview;

  /// The folder we last navigated to ourselves, so our own drilling isn't
  /// mistaken for an external navigation.
  String _guard = '';

  /// The explorer folder seen at the last build.
  String _seen = '';

  /// Listings of the columns that aren't the explorer's current folder.
  final Map<String, List<FsEntry>> _raw = {};
  final Map<String, String> _errors = {};
  final Set<String> _loading = {};
  bool? _hiddenShown;
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    final ex = context.read<ExplorerController>();
    _trail = [ex.current];
    _guard = _seen = ex.current;
    _changes = ex.app.fsChanged.listen((path) {
      if (!mounted) return;
      if (path.isEmpty) {
        for (final p in _raw.keys.toList()) {
          _load(p);
        }
      } else if (_raw.containsKey(path)) {
        _load(path); // reload in place: the old listing stays until the new one lands
      }
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(String path) async {
    if (_loading.contains(path)) return;
    _loading.add(path);
    final app = context.read<FaController>();
    final r = await app.api.list(path, hidden: app.showHidden);
    _loading.remove(path);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _raw[path] = r.value!.entries;
        _errors.remove(path);
      } else {
        _raw[path] = const [];
        _errors[path] = r.error?.message ?? 'Couldn\'t open this folder.';
      }
    });
  }

  /// The explorer's folder is about to change: keep its listing for its column
  /// so the column doesn't blank while it becomes an ordinary one.
  void _keepCurrent(ExplorerController ex) {
    if (ex.error == null) _raw[ex.current] = ex.entries;
  }

  void _pickFolder(int col, FsEntry folder) {
    final ex = context.read<ExplorerController>();
    _keepCurrent(ex);
    setState(() {
      _guard = folder.path;
      _trail = [..._trail.take(col + 1), folder.path];
      _preview = null;
    });
    _scrollToEnd();
    ex.open(folder.path);
  }

  Future<void> _pickFile(int col, FsEntry file) async {
    final ex = context.read<ExplorerController>();
    final parent = _trail[col];
    if (parent != ex.current) _keepCurrent(ex);
    setState(() {
      _guard = parent;
      _trail = _trail.take(col + 1).toList();
      _preview = file;
    });
    _scrollToEnd();
    if (parent != ex.current) await ex.open(parent);
    if (!mounted) return;
    for (final e in ex.entries) {
      if (e.path == file.path) {
        ex.select(e);
        break;
      }
    }
  }

  /// Keep the newest column in view as the trail grows or a preview opens.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: FaMotion.medium, curve: FaMotion.snappy);
    });
  }

  void _sync(ExplorerController ex, FaController app) {
    if (ex.current != _seen) {
      _seen = ex.current;
      if (ex.current != _guard) {
        // External navigation → collapse to this folder.
        _guard = ex.current;
        _trail = [ex.current];
        _preview = null;
        _raw.clear();
        _errors.clear();
      }
    }
    if (_hiddenShown != app.showHidden) {
      final reload = _hiddenShown != null;
      _hiddenShown = app.showHidden;
      if (reload) {
        for (final p in _raw.keys.toList()) {
          scheduleMicrotask(() => _load(p));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final app = context.read<FaController>();
    _sync(ex, app);

    final columns = <Widget>[];
    for (var col = 0; col < _trail.length; col++) {
      final path = _trail[col];
      final highlight = col + 1 < _trail.length ? _trail[col + 1] : _preview?.path;
      List<FsEntry>? entries;
      String? error;
      if (path == ex.current) {
        entries = ex.entries;
        error = ex.error?.message;
      } else {
        final raw = _raw[path];
        if (raw == null) scheduleMicrotask(() => _load(path));
        entries = raw == null ? null : ex.sorted(raw.where((e) => app.showHidden || !e.hidden));
        error = _errors[path];
      }
      columns.add(
        _Column(
          key: ValueKey('col:$path'),
          folder: path,
          entries: entries,
          error: error,
          highlight: highlight,
          onPickFolder: (e) => _pickFolder(col, e),
          onPickFile: (e) => _pickFile(col, e),
        ),
      );
    }
    final preview = _preview;
    if (preview != null) columns.add(_PreviewColumn(key: ValueKey('preview:${preview.path}'), entry: preview));

    return PaneBackground(
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final col in columns)
                if (col is _Column)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: c.border)),
                    ),
                    child: col,
                  )
                else
                  col,
            ],
          ),
        ),
      ),
    );
  }
}

/// One folder's column: its rows, or a loading / error / empty note.
class _Column extends StatelessWidget {
  final String folder;
  final List<FsEntry>? entries;
  final String? error;
  final String? highlight;
  final ValueChanged<FsEntry> onPickFolder;
  final ValueChanged<FsEntry> onPickFile;
  const _Column({
    super.key,
    required this.folder,
    required this.entries,
    required this.error,
    required this.highlight,
    required this.onPickFolder,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final list = entries;
    Widget note(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: FaText.sans(size: 11, color: c.mutedForeground),
        ),
      ),
    );
    final Widget body;
    if (list == null) {
      body = note('Loading…');
    } else if (error != null) {
      body = note(error!);
    } else if (list.isEmpty) {
      body = note('Empty folder');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemExtent: _kRowHeight,
        itemCount: list.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final i = list.indexWhere((e) => e.path == key.value);
          return i < 0 ? null : i;
        },
        itemBuilder: (context, i) {
          final e = list[i];
          return _ColumnRow(
            key: ValueKey(e.path),
            entry: e,
            active: e.path == highlight,
            onPick: () => e.isDir ? onPickFolder(e) : onPickFile(e),
          );
        },
      );
    }
    return SizedBox(width: _kColumnWidth, child: body);
  }
}

/// `mx-1 px-2 gap-2 rounded-md`, 28px: logo, name, tag dots, chevron for folders.
class _ColumnRow extends StatelessWidget {
  final FsEntry entry;
  final bool active;
  final VoidCallback onPick;
  const _ColumnRow({super.key, required this.entry, required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.read<ExplorerController>();
    final editing = context.select<ExplorerController, bool>((x) => x.renaming == entry.path);
    final tags = context.select<ExplorerController, List<int>>((x) => x.tagsByPath[entry.path] ?? const []);
    context.select<FaController, int>((app) => app.tags.length);
    return EntryInteractions(
      entry: entry,
      editing: editing,
      onTap: onPick,
      // Single-click already drills into folders; double-click opens files.
      onActivate: entry.isDir ? () {} : () => ex.activate(entry),
      onContextMenu: (at) {
        ex.select(entry);
        showEntryMenu(context, entry, at);
      },
      builder: (context, hover, drop) {
        final Color bg = drop
            ? fdHover(c)
            : active
            ? fdSelected(c)
            : hover
            ? fdHover(c)
            : Colors.transparent;
        return Opacity(
          opacity: entry.hidden ? kFdHiddenOpacity : 1,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(FaRadius.md)),
            foregroundDecoration: drop
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(FaRadius.md),
                    border: Border.all(color: fdRing(c), width: 2),
                  )
                : null,
            child: Row(
              children: [
                FileIcon.entry(entry, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: editing
                      ? RenameField(entry: entry, fontSize: 12)
                      : Text(
                          entry.name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
                        ),
                ),
                if (tags.isNotEmpty) ...[const SizedBox(width: 8), TagDotsRow(tags, dotSize: 6)],
                if (entry.isDir) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 14, color: c.mutedForeground),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The trailing preview pane: a large thumbnail and key metadata for a file.
class _PreviewColumn extends StatelessWidget {
  final FsEntry entry;
  const _PreviewColumn({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return SizedBox(
      width: _kPreviewWidth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(FaRadius.lg),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.muted),
                  position: DecorationPosition.background,
                  child: Container(
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(FaRadius.lg),
                      border: Border.all(color: c.border.withValues(alpha: 0.5)),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) => Center(
                        child: FileIcon.entry(
                          entry,
                          size: box.maxWidth,
                          logoSize: box.maxWidth * 0.5,
                          thumbnail: true,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              entry.name,
              textAlign: TextAlign.center,
              style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
            ),
            const SizedBox(height: 2),
            Text(entry.typeLabel, style: FaText.sans(size: 12, color: c.mutedForeground)),
            const SizedBox(height: 16),
            _PreviewRow('Size', formatBytes(entry.size)),
            const SizedBox(height: 6),
            _PreviewRow('Modified', formatDate(entry.mtime)),
            const SizedBox(height: 6),
            _PreviewRow('Created', formatDate(entry.ctime)),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _PreviewRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: FaText.sans(size: 11, weight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.55),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FaText.sans(size: 11, color: c.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
