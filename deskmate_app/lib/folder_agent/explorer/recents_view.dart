import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/fa_api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../shell/pane_header.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'quick_look.dart';
import 'x_common.dart';

/// One recently opened item: the entry plus when it was opened.
class _Recent {
  final FsEntry entry;
  final DateTime openedAt;
  const _Recent(this.entry, this.openedAt);
}

/// Files recently opened through DeskMate, newest first, grouped by day.
class RecentsView extends StatefulWidget {
  const RecentsView({super.key});

  @override
  State<RecentsView> createState() => _RecentsViewState();
}

class _RecentsViewState extends State<RecentsView> {
  List<_Recent>? _items;
  FaError? _error;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<FaController>().api;
    // `/recents` returns entries with an `openedAt` timestamp; read it directly
    // so items group by when they were opened, not modified.
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
    app.toast('Cleared Recents');
    await _load();
  }

  void _menu(FsEntry e, Offset at) {
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    setState(() => _selected = e.path);
    showFaMenu(context, at, [
      FaMenuItem('Open', icon: Icons.open_in_new_rounded, onTap: () => _open(e)),
      if (!e.isDir) FaMenuItem('Quick Look', icon: Icons.visibility_outlined, onTap: () => showQuickLook(context, e)),
      FaMenuItem('Show in Folder', icon: Icons.drive_file_move_outline, onTap: () => showInFolder(ex, e.path)),
      FaMenuItem(revealLabel(app), icon: Icons.folder_open_outlined, onTap: () => ex.reveal(e.path)),
      const FaMenuItem.divider(),
      FaMenuItem(
        'Ask AI about this',
        leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
        onTap: hiddenFromAi(app, e.path) ? null : () => app.askAiAbout([e.path]),
      ),
      FaMenuItem('Copy path', icon: Icons.link_rounded, onTap: () => copyPathToClipboard(app, e.path)),
      const FaMenuItem.divider(),
      FaMenuItem('Remove from Recents', icon: Icons.history_toggle_off_rounded, onTap: () => _remove(e)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      children: [
        PaneHeader.simple(
          icon: Icons.schedule_rounded,
          label: 'Recents',
          actions: [
            FaIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh', onPressed: _load),
            FaButton(
              label: 'Clear',
              dense: true,
              variant: FaButtonVariant.ghost,
              onPressed: (items?.isEmpty ?? true) ? null : _clear,
            ),
          ],
        ),
        Expanded(child: _body(context, items)),
      ],
    );
  }

  Widget _body(BuildContext context, List<_Recent>? items) {
    if (items == null) return const XLoading();
    if (_error != null) {
      return XEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Recents couldn\'t be loaded',
        body: _error!.message,
        action: FaButton(label: 'Try again', onPressed: _load),
      );
    }
    if (items.isEmpty) {
      return const XEmptyState(
        icon: Icons.schedule_rounded,
        title: 'No recent files',
        body: 'Files you open from DeskMate show up here, newest first.',
      );
    }

    final groups = <String, List<_Recent>>{};
    for (final r in items) {
      groups.putIfAbsent(_bucket(r.openedAt), () => []).add(r);
    }
    final rows = <Widget>[];
    for (final g in groups.entries) {
      rows.add(SectionLabel(g.key, trailing: _Count(g.value.length)));
      for (final r in g.value) {
        rows.add(
          _RecentRow(
            item: r,
            selected: _selected == r.entry.path,
            onTap: () => setState(() => _selected = r.entry.path),
            onDoubleTap: () => _open(r.entry),
            onMenu: (at) => _menu(r.entry, at),
          ),
        );
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => _selected = null),
      child: ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 24), children: rows),
    );
  }

  static String _bucket(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Earlier this week';
    return 'Older';
  }
}

class _Count extends StatelessWidget {
  final int n;
  const _Count(this.n);
  @override
  Widget build(BuildContext context) => Text('$n', style: FaText.mono(size: 10, color: context.fa.mutedForeground));
}

class _RecentRow extends StatelessWidget {
  final _Recent item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMenu;
  const _RecentRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    final e = item.entry;
    return Hoverable(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? c.selection : (hover ? c.accent.withValues(alpha: 0.7) : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Row(
          children: [
            SizedBox(width: 26, height: 26, child: Center(child: FileIcon.entry(e, size: 24, thumbnail: true))),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(
                e.name,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 12.5, weight: FontWeight.w500, color: c.foreground),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                compactDir(parentDir(e.path), app.home),
                overflow: TextOverflow.ellipsis,
                style: FaText.mono(size: 10.5, color: c.mutedForeground),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Tooltip(
                message: formatDate(item.openedAt),
                child: Text(
                  formatAgo(item.openedAt),
                  textAlign: TextAlign.right,
                  style: FaText.sans(size: 11.5, color: c.mutedForeground),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
