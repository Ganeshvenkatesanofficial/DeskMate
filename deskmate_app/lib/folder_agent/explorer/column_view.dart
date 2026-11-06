import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'context_menu.dart';
import 'dnd.dart';
import 'entry_interactions.dart';
import 'grid_view.dart' show tagColorFor;
import 'quick_look.dart';
import 'x_common.dart';

const double _kColumnWidth = 240;
const double _kPreviewWidth = 280;
const double _kRowHeight = 28;

/// Miller columns (FilDOS ColumnView): the current folder is the first
/// column; picking a folder opens its contents in a new column to the right,
/// picking a file shows a preview column.
///
/// Column 0 is the explorer's own listing and selection (so the keyboard,
/// context menu, rename and drag & drop behave as in every other view).
/// Deeper columns keep a local trail of picked paths.
class ColumnBrowserView extends StatefulWidget {
  const ColumnBrowserView({super.key});

  @override
  State<ColumnBrowserView> createState() => _ColumnBrowserViewState();
}

class _ColumnBrowserViewState extends State<ColumnBrowserView> {
  final _scroll = ScrollController();

  /// Picked path in each deeper column (index 0 = column 1).
  final List<String> _trail = [];

  /// Listings of deeper folders (sorted folders-first).
  final Map<String, List<FsEntry>> _listings = {};
  final Map<String, String> _errors = {};
  final Set<String> _loading = {};
  String _root = '';
  int _lastColumnCount = 0;
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    final app = context.read<FaController>();
    _changes = app.fsChanged.listen((path) {
      if (!mounted) return;
      if (path.isEmpty) {
        _listings.clear();
      } else if (_listings.containsKey(path)) {
        _listings.remove(path);
      } else {
        return;
      }
      setState(() {});
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
        _listings[path] = sortFoldersFirst(r.value!.entries);
        _errors.remove(path);
      } else {
        _listings[path] = const [];
        _errors[path] = r.error?.message ?? 'Couldn\'t open this folder.';
      }
    });
  }

  /// Entries of a deeper column, kicking off the load if needed (null = loading).
  List<FsEntry>? _entriesOf(String folder) {
    final l = _listings[folder];
    if (l == null) scheduleMicrotask(() => _load(folder));
    return l;
  }

  void _pick(int column, FsEntry e) {
    // Column n (n >= 1) owns trail slot n - 1; picking drops everything deeper.
    setState(() {
      if (_trail.length > column - 1) _trail.length = column - 1;
      _trail.add(e.path);
      if (e.isDir) _listings.remove(e.path); // fresh listing every time a folder is opened
    });
  }

  void _truncate(int column) {
    if (_trail.length > column - 1) setState(() => _trail.length = column - 1);
  }

  void _scrollToEnd(int columns) {
    if (columns == _lastColumnCount) return;
    final grew = columns > _lastColumnCount;
    _lastColumnCount = columns;
    if (!grew) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: FaMotion.medium, curve: FaMotion.snappy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    if (_root != ex.current) {
      _root = ex.current;
      _trail.clear();
      _listings.clear();
      _errors.clear();
    }

    // Build the chain of columns: column 0 = current folder.
    final columns = <Widget>[_rootColumn(context, ex)];
    FsEntry? tail = ex.selection.length == 1 ? ex.primarySelection : null;
    var trailValid = 0;
    var depth = 1;
    while (tail != null && tail.isDir) {
      final folder = tail.path;
      final entries = _entriesOf(folder);
      String? picked;
      if (trailValid < _trail.length && parentDir(_trail[trailValid]) == folder) {
        picked = _trail[trailValid];
      }
      FsEntry? next;
      if (picked != null && entries != null) {
        for (final e in entries) {
          if (e.path == picked) {
            next = e;
            break;
          }
        }
      }
      final col = depth;
      columns.add(
        _DeepColumn(
          key: ValueKey('col:$folder'),
          folder: folder,
          entries: entries,
          error: _errors[folder],
          picked: next?.path,
          onPick: (e) => _pick(col, e),
          onBackground: () => _truncate(col),
        ),
      );
      if (next == null) break;
      trailValid++;
      depth++;
      tail = next;
    }
    if (_trail.length > trailValid) _trail.length = trailValid;
    if (tail != null && !tail.isDir) columns.add(_PreviewColumn(key: ValueKey('preview:${tail.path}'), entry: tail));

    _scrollToEnd(columns.length);
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final col in columns)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: c.border)),
                ),
                child: col,
              ),
          ],
        ),
      ),
    );
  }

  Widget _rootColumn(BuildContext context, ExplorerController ex) => SizedBox(
    width: _kColumnWidth,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: ex.clearSelection,
      onSecondaryTapDown: (d) => showBackgroundMenu(context, d.globalPosition),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemExtent: _kRowHeight,
        itemCount: ex.entries.length,
        itemBuilder: (context, i) => _RootRow(entry: ex.entries[i]),
      ),
    ),
  );
}

/// Row in column 0 — the explorer's own entries, with the shared interactions.
class _RootRow extends StatelessWidget {
  final FsEntry entry;
  const _RootRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ex = context.watch<ExplorerController>();
    final selected = ex.selection.contains(entry.path);
    return EntryInteractions(
      entry: entry,
      radius: BorderRadius.circular(FaRadius.sm),
      child: _ColumnRow(
        entry: entry,
        selected: selected,
        dimmed: ex.isCut(entry.path) || entry.hidden,
        tags: ex.tagsByPath[entry.path] ?? const [],
        renaming: ex.renaming == entry.path,
      ),
    );
  }
}

/// The visual of a column row: icon, name, tag dots, chevron for folders.
class _ColumnRow extends StatelessWidget {
  final FsEntry entry;
  final bool selected;
  final bool dimmed;
  final List<int> tags;
  final bool renaming;
  const _ColumnRow({
    required this.entry,
    required this.selected,
    this.dimmed = false,
    this.tags = const [],
    this.renaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return Hoverable(
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.selection : (hover ? c.accent.withValues(alpha: 0.7) : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.sm),
        ),
        child: Opacity(
          opacity: dimmed ? 0.5 : 1,
          child: Row(
            children: [
              FileIcon.entry(entry, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: renaming
                    ? RenameField(entry: entry)
                    : Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: FaText.sans(
                          size: 12.5,
                          weight: selected ? FontWeight.w500 : FontWeight.w400,
                          color: c.foreground,
                        ),
                      ),
              ),
              for (final id in tags.take(3))
                Padding(padding: const EdgeInsets.only(left: 4), child: ScoopDot(tagColorFor(app, id), size: 6)),
              if (entry.isDir)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: selected ? c.foreground : c.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A column beyond the first: its own listing and a local pick.
class _DeepColumn extends StatelessWidget {
  final String folder;
  final List<FsEntry>? entries;
  final String? error;
  final String? picked;
  final ValueChanged<FsEntry> onPick;
  final VoidCallback onBackground;
  const _DeepColumn({
    super.key,
    required this.folder,
    required this.entries,
    required this.error,
    required this.picked,
    required this.onPick,
    required this.onBackground,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final list = entries;
    Widget body;
    if (list == null) {
      body = const Padding(padding: EdgeInsets.all(24), child: XLoading());
    } else if (error != null || list.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error ?? 'Empty folder',
            textAlign: TextAlign.center,
            style: FaText.sans(size: 12, color: c.mutedForeground),
          ),
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemExtent: _kRowHeight,
        itemCount: list.length,
        itemBuilder: (context, i) {
          final e = list[i];
          return _DeepRow(entry: e, selected: e.path == picked, onPick: () => onPick(e));
        },
      );
    }
    return SizedBox(
      width: _kColumnWidth,
      child: EntryDropTarget(
        folder: folder,
        radius: BorderRadius.zero,
        child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: onBackground, child: body),
      ),
    );
  }
}

class _DeepRow extends StatelessWidget {
  final FsEntry entry;
  final bool selected;
  final VoidCallback onPick;
  const _DeepRow({required this.entry, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    Widget row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPick,
      onDoubleTap: () => entry.isDir ? ex.open(entry.path) : ex.activate(entry),
      onSecondaryTapDown: (d) {
        onPick();
        _deepMenu(context, entry, d.globalPosition);
      },
      child: _ColumnRow(entry: entry, selected: selected, dimmed: entry.hidden),
    );
    if (entry.isDir) row = EntryDropTarget(folder: entry.path, radius: BorderRadius.circular(FaRadius.sm), child: row);
    return row;
  }
}

/// Context menu for an item in a deeper column (outside the explorer's
/// selection, so it offers the non-selection actions).
void _deepMenu(BuildContext context, FsEntry entry, Offset at) {
  final ex = context.read<ExplorerController>();
  final app = context.read<FaController>();
  final noAi = hiddenFromAi(app, entry.path);
  showFaMenu(context, at, [
    FaMenuItem('Open', icon: Icons.open_in_new_rounded, onTap: () => ex.activate(entry)),
    if (!entry.isDir)
      FaMenuItem(
        'Quick Look',
        icon: Icons.visibility_outlined,
        shortcut: 'Space',
        onTap: () => showQuickLook(context, entry),
      ),
    FaMenuItem('Show Enclosing Folder', icon: Icons.drive_file_move_outline, onTap: () => showInFolder(ex, entry.path)),
    FaMenuItem(revealLabel(app), icon: Icons.folder_open_outlined, onTap: () => ex.reveal(entry.path)),
    const FaMenuItem.divider(),
    FaMenuItem(
      'Ask AI about this',
      leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
      onTap: noAi ? null : () => app.askAiAbout([entry.path]),
    ),
    const FaMenuItem.divider(),
    FaMenuItem('Copy path', icon: Icons.link_rounded, onTap: () => copyPathToClipboard(app, entry.path)),
    FaMenuItem(
      'Move to Trash',
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onTap: () => ex.trashSelection([entry.path]),
    ),
  ]);
}

/// The trailing preview pane: a large thumbnail and key metadata for a file.
class _PreviewColumn extends StatelessWidget {
  final FsEntry entry;
  const _PreviewColumn({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.read<ExplorerController>();
    return SizedBox(
      width: _kPreviewWidth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(FaRadius.lg),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (context, box) => FileIcon.entry(
                    entry,
                    size: entry.hasThumbnail ? box.maxWidth : box.maxWidth * 0.5,
                    thumbnail: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              entry.name,
              textAlign: TextAlign.center,
              style: FaText.sans(size: 13.5, weight: FontWeight.w600, color: c.foreground),
            ),
            const SizedBox(height: 3),
            Text(kindLabel(entry.kind, entry.ext), style: FaText.sans(size: 12, color: c.mutedForeground)),
            const SizedBox(height: 14),
            MetaRow('Size', formatBytes(entry.size)),
            MetaRow('Modified', formatDate(entry.mtime)),
            MetaRow('Created', formatDate(entry.ctime)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FaButton(
                    label: 'Open',
                    icon: Icons.open_in_new_rounded,
                    dense: true,
                    expand: true,
                    onPressed: () => ex.activate(entry),
                  ),
                ),
                const SizedBox(width: 6),
                FaIconButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'Quick Look',
                  onPressed: () => showQuickLook(context, entry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
