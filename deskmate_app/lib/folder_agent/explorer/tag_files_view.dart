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
import 'grid_view.dart' show kGridTileWidth, kGridTileHeight;
import 'quick_look.dart';
import 'x_common.dart';

/// Every file and folder carrying one tag, as an icon grid.
class TagFilesView extends StatefulWidget {
  final int tagId;
  const TagFilesView({super.key, required this.tagId});

  @override
  State<TagFilesView> createState() => _TagFilesViewState();
}

class _TagFilesViewState extends State<TagFilesView> {
  List<FsEntry>? _files;
  FaError? _error;
  String? _selected;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TagFilesView old) {
    super.didUpdateWidget(old);
    if (old.tagId != widget.tagId) {
      _files = null;
      _selected = null;
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (widget.tagId < 0) return;
    final r = await context.read<FaController>().api.tagFiles(widget.tagId);
    if (!mounted || gen != _gen) return;
    setState(() {
      _files = r.value == null ? const [] : sortFoldersFirst(r.value!);
      _error = r.error;
    });
  }

  Tag? _tag(FaController app) {
    for (final t in app.tags) {
      if (t.id == widget.tagId) return t;
    }
    return null;
  }

  Future<void> _open(FsEntry e) => context.read<ExplorerController>().activate(e);

  Future<void> _untag(FsEntry e) async {
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    final r = await app.api.unassignTag(widget.tagId, [e.path]);
    if (!r.ok) return app.toastError(r.error);
    await Future.wait([_load(), app.refreshTags()]);
    if (parentDir(e.path) == ex.current) await ex.refresh(silent: true);
  }

  void _menu(FsEntry e, Offset at) {
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    final tag = _tag(app);
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
      FaMenuItem(
        tag == null ? 'Remove tag' : 'Remove “${tag.name}” tag',
        leading: tag == null ? null : ScoopDot(Scoop.parse(tag.color), size: 9),
        icon: tag == null ? Icons.label_off_outlined : null,
        onTap: () => _untag(e),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final tag = _tag(app);
    final files = _files;
    return Column(
      children: [
        PaneHeader(
          title: Row(
            children: [
              ScoopDot(tag == null ? c.mutedForeground : Scoop.parse(tag.color), size: 10),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  tag?.name ?? 'Tag',
                  overflow: TextOverflow.ellipsis,
                  style: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
                ),
              ),
              if (files != null) ...[
                const SizedBox(width: 8),
                Text(
                  files.length == 1 ? '1 item' : '${files.length} items',
                  style: FaText.mono(size: 10.5, color: c.mutedForeground),
                ),
              ],
            ],
          ),
          actions: [FaIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh', onPressed: _load)],
        ),
        Expanded(child: _body(context, tag, files)),
      ],
    );
  }

  Widget _body(BuildContext context, Tag? tag, List<FsEntry>? files) {
    final app = context.read<FaController>();
    if (widget.tagId < 0 || (tag == null && app.tags.isNotEmpty)) {
      return const XEmptyState(
        icon: Icons.sell_outlined,
        title: 'Tag not found',
        body: 'This tag may have been deleted. Pick another tag in the sidebar.',
      );
    }
    if (files == null) return const XLoading();
    if (_error != null) {
      return XEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Tagged files couldn\'t be loaded',
        body: _error!.message,
        action: FaButton(label: 'Try again', onPressed: _load),
      );
    }
    if (files.isEmpty) {
      return XEmptyState(
        icon: Icons.sell_outlined,
        title: 'No files tagged “${tag?.name ?? ''}” yet',
        body: 'Right-click any file or folder and choose Tags to add it here.',
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = ((box.maxWidth - 24) / (kGridTileWidth + 8)).floor().clamp(1, 64);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() => _selected = null),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: kGridTileHeight + 32,
              crossAxisSpacing: 8,
              mainAxisSpacing: 6,
            ),
            itemCount: files.length,
            itemBuilder: (context, i) {
              final e = files[i];
              return _TagTile(
                entry: e,
                selected: _selected == e.path,
                onTap: () => setState(() => _selected = e.path),
                onDoubleTap: () => _open(e),
                onMenu: (at) => _menu(e, at),
              );
            },
          ),
        );
      },
    );
  }
}

/// Grid tile matching the explorer's icon grid, plus the item's folder.
class _TagTile extends StatelessWidget {
  final FsEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMenu;
  const _TagTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return Tooltip(
      message: entry.path,
      waitDuration: const Duration(milliseconds: 800),
      child: Hoverable(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        builder: (context, hover) => AnimatedContainer(
          duration: FaMotion.fast,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
          decoration: BoxDecoration(
            color: selected ? c.selection : (hover ? c.accent.withValues(alpha: 0.7) : Colors.transparent),
            borderRadius: BorderRadius.circular(FaRadius.lg),
          ),
          child: Opacity(
            opacity: entry.hidden ? 0.5 : 1,
            child: Column(
              children: [
                SizedBox(
                  height: 76,
                  child: Center(child: FileIcon.entry(entry, size: entry.hasThumbnail ? 72 : 60, thumbnail: true)),
                ),
                const SizedBox(height: 10),
                Text(
                  entry.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: FaText.sans(size: 12.5, weight: FontWeight.w500, color: c.foreground, height: 1.3),
                ),
                const SizedBox(height: 3),
                Text(
                  compactDir(parentDir(entry.path), app.home),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: FaText.mono(size: 9.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
