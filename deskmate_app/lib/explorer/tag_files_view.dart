import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../settings/settings_widgets.dart' show SmallButton;
import '../shell/pane_header.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'recents_view.dart'
    show PageEscape, PageGrid, PageGridTile, PageList, PageListRow, PageSpinner, PageStateText, PageViewToggle;
import 'explorer_common.dart';

/// Every file carrying one tag (port of FilDOS TagFilesView): a note line,
/// a flat list or tile grid, double-click to open, right-click for Open /
/// Show in Folder / Remove tag, and Rename / Delete for the tag itself in the
/// header. Escape goes back.
class TagFilesView extends StatefulWidget {
  final int tagId;
  const TagFilesView({super.key, required this.tagId});

  @override
  State<TagFilesView> createState() => _TagFilesViewState();
}

class _TagFilesViewState extends State<TagFilesView> {
  List<FsEntry>? _files;
  FaError? _error;
  int _gen = 0;
  bool _grid = false;
  bool _renaming = false;
  bool _confirmingDelete = false;
  bool _menuOpen = false;
  final _rename = TextEditingController();
  final _renameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _renameFocus.addListener(() {
      if (!_renameFocus.hasFocus && _renaming) _commitRename();
    });
    _load();
  }

  @override
  void dispose() {
    _rename.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TagFilesView old) {
    super.didUpdateWidget(old);
    if (old.tagId != widget.tagId) {
      _files = null;
      _renaming = false;
      _confirmingDelete = false;
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (widget.tagId < 0) return;
    final app = context.read<FaController>();
    final r = await app.api.tagFiles(widget.tagId);
    if (!mounted || gen != _gen) return;
    setState(() {
      _files = r.value ?? const [];
      _error = r.error;
    });
    if (!r.ok) app.toastError(r.error);
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

  void _startRename(Tag tag) {
    _rename.text = tag.name;
    _rename.selection = TextSelection(baseOffset: 0, extentOffset: tag.name.length);
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _renameFocus.requestFocus());
  }

  Future<void> _commitRename() async {
    if (!_renaming) return;
    final app = context.read<FaController>();
    final tag = _tag(app);
    final name = _rename.text.trim();
    setState(() => _renaming = false);
    if (tag == null || name.isEmpty || name == tag.name) return;
    final r = await app.api.updateTag(tag.id, name: name);
    if (!r.ok) return app.toastError(r.error);
    await app.refreshTags();
  }

  Future<void> _delete() async {
    final app = context.read<FaController>();
    app.showSection(FaSection.browse);
    final r = await app.api.removeTag(widget.tagId);
    if (!r.ok) return app.toastError(r.error);
    await app.refreshTags();
  }

  Future<void> _menu(FsEntry e, Offset at) async {
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    _menuOpen = true;
    await showFaMenu(context, at, [
      FaMenuItem('Open', icon: Icons.open_in_new_rounded, onTap: () => _open(e)),
      FaMenuItem(
        'Show in Folder',
        icon: Icons.folder_outlined,
        onTap: () => e.isDir ? ex.open(e.path) : showInFolder(ex, e.path),
      ),
      const FaMenuItem.divider(),
      FaMenuItem(
        'Ask AI about this',
        leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
        onTap: hiddenFromAi(app, e.path) ? null : () => app.askAiAbout([e.path]),
      ),
      const FaMenuItem.divider(),
      FaMenuItem('Remove tag', icon: Icons.close_rounded, onTap: () => _untag(e)),
    ]);
    _menuOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final tag = context.select<FaController, Tag?>(_tag);
    final files = _files;
    final dot = ScoopDot(tag == null ? c.mutedForeground : Scoop.parse(tag.color), size: 10);
    return PageEscape(
      enabled: () => !_menuOpen && !_renaming,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneHeader(
            title: Row(
              children: [
                dot,
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    tag?.name ?? 'Tag',
                    overflow: TextOverflow.ellipsis,
                    style: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
                  ),
                ),
              ],
            ),
            actions: [
              if (_renaming)
                SizedBox(width: 200, child: _renameField(c))
              else if (tag != null) ...[
                PageViewToggle(grid: _grid, onChanged: (g) => setState(() => _grid = g)),
                const SizedBox(width: 4),
                SmallButton(
                  label: 'Rename',
                  icon: Icons.edit_outlined,
                  iconSize: 14,
                  variant: FaButtonVariant.outline,
                  onPressed: () => _startRename(tag),
                ),
                const SizedBox(width: 4),
                if (_confirmingDelete)
                  SmallButton(
                    label: 'Delete tag and ${files?.isNotEmpty ?? false ? '${files!.length} assignment(s)' : 'close'}?',
                    variant: FaButtonVariant.destructive,
                    onPressed: _delete,
                  )
                else
                  SmallButton(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    iconSize: 14,
                    variant: FaButtonVariant.outline,
                    onPressed: () => setState(() => _confirmingDelete = true),
                  ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              'Files don\'t move when tagged — a tag is just a saved collection you can return to.',
              style: FaText.sans(size: 12, color: c.mutedForeground, height: 1.375),
            ),
          ),
          Expanded(child: _body(tag, files)),
        ],
      ),
    );
  }

  Widget _renameField(FaColors c) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () {
        setState(() => _renaming = false);
      },
    },
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(FaRadius.sm),
        border: Border.all(color: c.foreground.withValues(alpha: 0.5)),
      ),
      child: TextField(
        controller: _rename,
        focusNode: _renameFocus,
        onSubmitted: (_) => _commitRename(),
        style: FaText.sans(size: 13, color: c.foreground),
        cursorColor: c.foreground,
        cursorHeight: 14,
        decoration: const InputDecoration.collapsed(hintText: ''),
      ),
    ),
  );

  Widget _body(Tag? tag, List<FsEntry>? files) {
    final app = context.read<FaController>();
    if (widget.tagId < 0 || (tag == null && app.tags.isNotEmpty)) {
      return const PageStateText('This tag no longer exists');
    }
    if (files == null) return const PageSpinner();
    if (files.isEmpty) {
      return PageStateText(_error == null ? 'No files carry this tag yet' : 'Tagged files couldn\'t be loaded');
    }
    if (_grid) {
      return PageGrid(
        children: [
          for (final e in files) PageGridTile(entry: e, onDoubleTap: () => _open(e), onMenu: (at) => _menu(e, at)),
        ],
      );
    }
    return PageList(
      itemCount: files.length,
      itemBuilder: (context, i) {
        final e = files[i];
        return PageListRow(entry: e, date: e.mtime, onDoubleTap: () => _open(e), onMenu: (at) => _menu(e, at));
      },
    );
  }
}
