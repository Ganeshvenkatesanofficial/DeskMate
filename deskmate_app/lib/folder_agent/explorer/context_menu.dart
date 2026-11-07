import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
import '../core/fa_theme.dart';
import '../core/models.dart';
import '../shell/sidebar.dart' show createTagFlow;
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'quick_look.dart';

/// Right-click on a file/folder (FilDOS ContextMenu, "selection" mode).
///
/// The menu acts on the current folder's selection when [entry] is part of it,
/// otherwise on [entry] alone (e.g. a column-view row from another folder).
/// The caller selects the item first when it wasn't selected.
void showEntryMenu(BuildContext context, FsEntry entry, Offset at) {
  final ex = context.read<ExplorerController>();
  final app = context.read<FaController>();
  final selected = ex.selectedEntries;
  final targets = selected.any((e) => e.path == entry.path) ? selected : [entry];
  final paths = [for (final e in targets) e.path];
  final count = targets.length;
  final single = count == 1;
  final first = targets.first;
  final n = count > 1 ? ' ($count)' : '';
  final allExcluded = paths.every(app.excludes.contains);

  showFaMenu(context, at, [
    FaMenuItem('Open', icon: Icons.open_in_new_rounded, onTap: single ? () => ex.activate(first) : null),
    FaMenuItem(
      'Quick Look',
      icon: Icons.visibility_outlined,
      shortcut: 'Space',
      onTap: single ? () => showQuickLook(context, first) : null,
    ),
    FaMenuItem(
      'Reveal in ${app.isMac ? 'Finder' : 'Explorer'}',
      icon: Icons.folder_open_outlined,
      onTap: single ? () => ex.reveal(first.path) : null,
    ),
    const FaMenuItem.divider(),
    FaMenuItem('Copy$n', icon: Icons.copy_rounded, onTap: () => ex.copyPaths(paths)),
    FaMenuItem('Cut$n', icon: Icons.content_cut_rounded, onTap: () => ex.cutPaths(paths)),
    FaMenuItem('Paste', icon: Icons.content_paste_rounded, onTap: ex.clipboard.isNotEmpty ? () => ex.paste() : null),
    FaMenuItem('Duplicate', icon: Icons.copy_rounded, onTap: single ? () => ex.duplicatePath(first.path) : null),
    const FaMenuItem.divider(),
    FaMenuItem(
      'Tags',
      icon: Icons.sell_outlined,
      submenu: [
        for (final t in app.tags)
          FaMenuItem(
            t.name,
            leading: ScoopDot(Scoop.parse(t.color), size: 9),
            shortcut: paths.every((p) => ex.tagsByPath[p]?.contains(t.id) ?? false) ? '✓' : null,
            onTap: () => ex.toggleTag(t, paths),
          ),
        if (app.tags.isNotEmpty) const FaMenuItem.divider(),
        FaMenuItem(
          'New Tag…',
          icon: Icons.add_rounded,
          onTap: () => createTagFlow(context, paths: paths),
        ),
      ],
    ),
    const FaMenuItem.divider(),
    FaMenuItem('Rename', icon: Icons.edit_outlined, onTap: single ? () => ex.beginRename(first.path) : null),
    FaMenuItem(
      'Delete$n',
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onTap: () => ex.trashSelection(paths),
    ),
    if (app.aiEnabled)
      FaMenuItem(
        allExcluded ? 'Show to AI' : 'Hide from AI',
        icon: allExcluded ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        onTap: () async {
          final r = allExcluded ? await _removeExcludes(app, paths) : await app.api.addExcludes(paths);
          if (r.ok) {
            await app.refreshPrefs();
            final many = paths.length > 1;
            app.toast(
              allExcluded
                  ? (many ? '${paths.length} items visible to AI again' : 'Visible to AI again')
                  : (many ? '${paths.length} items hidden from AI' : 'Hidden from AI'),
              kind: ToastKind.success,
            );
          } else {
            app.toastError(r.error);
          }
        },
      ),
    // DeskMate: hand the items to the Folder Agent.
    FaMenuItem(
      count > 1 ? 'Ask AI about $count items' : 'Ask AI about this',
      leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
      onTap: paths.any(app.excludes.contains) ? null : () => app.askAiAbout(paths),
    ),
    const FaMenuItem.divider(),
    FaMenuItem('Get Info', icon: Icons.info_outline_rounded, onTap: single ? () => ex.showInfo(first.path) : null),
  ]);
}

Future<Result<dynamic>> _removeExcludes(FaController app, List<String> paths) async {
  Result<dynamic> last = const Ok(null);
  for (final p in paths) {
    last = await app.api.removeExclude(p);
    if (!last.ok) return last;
  }
  return last;
}

/// Right-click on empty space in a folder (FilDOS ContextMenu, "background"
/// mode). The selection is left as it is.
void showBackgroundMenu(BuildContext context, Offset at) {
  final ex = context.read<ExplorerController>();
  final app = context.read<FaController>();
  showFaMenu(context, at, [
    FaMenuItem(
      'New Folder',
      icon: Icons.create_new_folder_outlined,
      onTap: () async {
        final name = await promptText(context, title: 'New Folder', initial: 'untitled folder', confirm: 'Create');
        if (name != null && name.isNotEmpty) await ex.newFolder(name);
      },
    ),
    FaMenuItem(
      'New File',
      icon: Icons.note_add_outlined,
      onTap: () async {
        final name = await promptText(context, title: 'New File', initial: 'untitled.txt', confirm: 'Create');
        if (name != null && name.isNotEmpty) await ex.newTextFile(name);
      },
    ),
    FaMenuItem('Paste', icon: Icons.content_paste_rounded, onTap: ex.clipboard.isNotEmpty ? () => ex.paste() : null),
    const FaMenuItem.divider(),
    FaMenuItem(
      'Sort By',
      icon: Icons.sort_rounded,
      submenu: [
        for (final (key, label) in sortKeys)
          FaMenuItem(
            label,
            shortcut: key == ex.view.sortKey ? (ex.view.sortDesc ? '▼' : '▲') : null,
            onTap: () => ex.sortBy(key),
          ),
      ],
    ),
    FaMenuItem('Select All', icon: Icons.checklist_rounded, onTap: ex.selectAll),
    FaMenuItem(
      app.showHidden ? 'Hide Hidden Files' : 'Show Hidden Files',
      icon: app.showHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      onTap: () async {
        await app.setPrefs({'showHidden': !app.showHidden});
        await ex.refresh(silent: true);
      },
    ),
    FaMenuItem('Refresh', icon: Icons.refresh_rounded, onTap: () => ex.refresh(silent: true)),
    const FaMenuItem.divider(),
    // DeskMate: hand the folder to the Folder Agent.
    FaMenuItem(
      'Ask AI about this folder',
      leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
      onTap: () => app.askAiAbout([ex.current]),
    ),
  ]);
}

const viewModes = [('list', 'List'), ('grid', 'Icons'), ('gallery', 'Gallery'), ('columns', 'Columns')];

/// FilDOS sort options, in its order (Type = extension, Modified = mtime).
const sortKeys = [('name', 'Name'), ('size', 'Size'), ('kind', 'Type'), ('mtime', 'Modified')];
