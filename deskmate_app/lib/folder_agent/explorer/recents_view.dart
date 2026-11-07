import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
import '../core/fa_theme.dart';
import '../core/models.dart';
import '../settings/settings_widgets.dart' show SmallButton;
import '../shell/pane_header.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'x_common.dart';

/// One recently opened item: the entry plus when it was opened.
class _Recent {
  final FsEntry entry;
  final DateTime openedAt;
  const _Recent(this.entry, this.openedAt);
}

/// Files recently opened through DeskMate, newest first (port of FilDOS
/// RecentsView): a flat list or tile grid, double-click to open, right-click
/// for Open / Show in Folder / Remove from Recents, Clear in the header and
/// Escape to go back.
class RecentsView extends StatefulWidget {
  const RecentsView({super.key});

  @override
  State<RecentsView> createState() => _RecentsViewState();
}

class _RecentsViewState extends State<RecentsView> {
  List<_Recent>? _items;
  FaError? _error;
  bool _grid = false;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<FaController>().api;
    // `/recents` returns entries with an `openedAt` timestamp.
    final r = await api.get<List<_Recent>>(
      '/recents',
      (d) => (d as List).map((raw) {
        final j = (raw as Map).cast<String, dynamic>();
        final e = FsEntry.fromJson(j);
        final at = (j['openedAt'] as num?)?.toDouble();
        return _Recent(e, at == null ? e.mtime : DateTime.fromMillisecondsSinceEpoch((at * 1000).round()));
      }).toList(),
    );
    if (!mounted) return;
    setState(() {
      _items = r.value ?? const [];
      _error = r.error;
    });
    if (!r.ok) context.read<FaController>().toastError(r.error);
  }

  Future<void> _open(FsEntry e) async {
    final ex = context.read<ExplorerController>();
    if (e.isDir) return ex.open(e.path);
    await ex.activate(e);
  }

  Future<void> _remove(FsEntry e) async {
    final app = context.read<FaController>();
    final r = await app.api.removeRecent(e.path);
    if (!r.ok) return app.toastError(r.error);
    await _load();
  }

  Future<void> _clear() async {
    final app = context.read<FaController>();
    final r = await app.api.clearRecents();
    if (!r.ok) return app.toastError(r.error);
    await _load();
  }

  Future<void> _menu(FsEntry e, Offset at) async {
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    _menuOpen = true;
    await showFaMenu(context, at, [
      FaMenuItem('Open', icon: Icons.open_in_new_rounded, onTap: () => _open(e)),
      FaMenuItem('Show in Folder', icon: Icons.folder_outlined, onTap: () => showInFolder(ex, e.path)),
      const FaMenuItem.divider(),
      FaMenuItem(
        'Ask AI about this',
        leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
        onTap: hiddenFromAi(app, e.path) ? null : () => app.askAiAbout([e.path]),
      ),
      const FaMenuItem.divider(),
      FaMenuItem('Remove from Recents', icon: Icons.close_rounded, onTap: () => _remove(e)),
    ]);
    _menuOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PageEscape(
      enabled: () => !_menuOpen,
      child: Column(
        children: [
          PaneHeader.simple(
            icon: Icons.schedule_rounded,
            label: 'Recents',
            actions: [
              PageViewToggle(grid: _grid, onChanged: (g) => setState(() => _grid = g)),
              const SizedBox(width: 4),
              SmallButton(
                label: 'Clear',
                variant: FaButtonVariant.outline,
                onPressed: (items?.isEmpty ?? true) ? null : _clear,
              ),
            ],
          ),
          Expanded(child: _body(items)),
        ],
      ),
    );
  }

  Widget _body(List<_Recent>? items) {
    if (items == null) return const PageSpinner();
    if (items.isEmpty) {
      return PageStateText(_error == null ? 'Nothing opened recently' : 'Recents couldn\'t be loaded');
    }
    if (_grid) {
      return PageGrid(
        children: [
          for (final r in items)
            PageGridTile(entry: r.entry, onDoubleTap: () => _open(r.entry), onMenu: (at) => _menu(r.entry, at)),
        ],
      );
    }
    return PageList(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final r = items[i];
        return PageListRow(
          entry: r.entry,
          date: r.openedAt,
          onDoubleTap: () => _open(r.entry),
          onMenu: (at) => _menu(r.entry, at),
        );
      },
    );
  }
}

// ── FilDOS Page primitives (shared with the tag files page) ──────────────────

/// Escape leaves the page (FilDOS `onBack`) unless a text field has focus.
class PageEscape extends StatelessWidget {
  final Widget child;
  final bool Function() enabled;
  const PageEscape({super.key, required this.child, required this.enabled});

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, e) {
      if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape || !enabled()) {
        return KeyEventResult.ignored;
      }
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) {
        return KeyEventResult.ignored;
      }
      context.read<FaController>().showSection(FaSection.browse);
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// List / grid toggle: `rounded-md border` pair, active `bg-foreground/[0.09]`.
class PageViewToggle extends StatelessWidget {
  final bool grid;
  final ValueChanged<bool> onChanged;
  const PageViewToggle({super.key, required this.grid, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    Widget btn(bool isGrid, IconData icon) {
      final active = grid == isGrid;
      return Hoverable(
        onTap: () => onChanged(isGrid),
        builder: (context, h) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: active ? c.foreground.withValues(alpha: 0.09) : (h ? c.accent : c.accent.withValues(alpha: 0)),
          child: Icon(icon, size: 13, color: active ? c.foreground : c.mutedForeground),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [btn(false, Icons.view_list_rounded), btn(true, Icons.grid_view_rounded)],
      ),
    );
  }
}

/// FilDOS `PageLoader`: a 20px muted spinner, centred.
class PageSpinner extends StatelessWidget {
  const PageSpinner({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.fa.mutedForeground.withValues(alpha: 0.5),
      ),
    ),
  );
}

/// FilDOS `PageState`: muted centred text, `py-10`.
class PageStateText extends StatelessWidget {
  final String text;
  const PageStateText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(text, style: FaText.sans(size: 13, color: context.fa.mutedForeground)),
    ),
  );
}

/// FilDOS `PageList`: `px-2 pb-2` scrolling column.
class PageList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  const PageList({super.key, required this.itemCount, required this.itemBuilder});
  @override
  Widget build(BuildContext context) =>
      ListView.builder(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), itemCount: itemCount, itemBuilder: itemBuilder);
}

/// "Mar 5, 2024, 3:04 PM" (FilDOS `formatDate`).
String pageDate(DateTime d) => DateFormat('MMM d, y, h:mm a').format(d);

/// FilDOS `PageRow`: `px-2.5 py-2 rounded-md gap-2.5 hover:bg-accent` — a 16px
/// icon, the name with its full path beneath (text-2xs), the date (text-2xs).
class PageListRow extends StatelessWidget {
  final FsEntry entry;
  final DateTime date;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMenu;
  const PageListRow({
    super.key,
    required this.entry,
    required this.date,
    required this.onDoubleTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      builder: (context, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hover ? c.accent : c.accent.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: FileIcon.entry(entry, size: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: entry.path,
                waitDuration: const Duration(milliseconds: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: FaText.sans(color: c.foreground)),
                    Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FaText.sans(size: 11, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(pageDate(date), style: FaText.sans(size: 11, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

/// FilDOS `PageGrid`: `p-2`, wrapped tiles with a 2px gap.
class PageGrid extends StatelessWidget {
  final List<Widget> children;
  const PageGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(8),
    child: SizedBox(
      width: double.infinity,
      child: Wrap(spacing: 2, runSpacing: 2, children: children),
    ),
  );
}

/// 128×116 tile: `p-1.5 rounded-lg hover:bg-accent`, a ≤54px logo, the name
/// below (text-xs medium, two lines, centred).
class PageGridTile extends StatelessWidget {
  final FsEntry entry;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMenu;
  const PageGridTile({super.key, required this.entry, required this.onDoubleTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: entry.path,
      waitDuration: const Duration(milliseconds: 800),
      child: Hoverable(
        cursor: SystemMouseCursors.basic,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        builder: (context, hover) => Container(
          width: 128,
          height: 116,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: hover ? c.accent : c.accent.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(FaRadius.lg),
          ),
          child: Column(
            children: [
              Expanded(child: Center(child: FileIcon.entry(entry, size: 54, thumbnail: true))),
              const SizedBox(height: 6),
              Text(
                entry.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
