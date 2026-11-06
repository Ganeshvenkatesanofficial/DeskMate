import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../shell/sidebar.dart' show createTagFlow;
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'quick_look.dart';

/// Right-click on a file/folder. Acts on the selection (selecting [entry] first if needed).
void showEntryMenu(BuildContext context, FsEntry entry, Offset at) {
  final ex = context.read<ExplorerController>();
  final app = context.read<FaController>();
  if (!ex.selection.contains(entry.path)) ex.select(entry);
  final paths = ex.selection.toList();
  final many = paths.length > 1;
  final hiddenFromAi = app.excludes.contains(entry.path);

  showFaMenu(context, at, [
    FaMenuItem(entry.isDir ? 'Open' : 'Open', icon: Icons.open_in_new_rounded, onTap: () => ex.activate(entry)),
    if (!entry.isDir)
      FaMenuItem('Quick Look', icon: Icons.visibility_outlined, shortcut: 'Space', onTap: () => showQuickLook(context, entry)),
    FaMenuItem('Show in ${app.isMac ? 'Finder' : 'File Manager'}', icon: Icons.folder_open_outlined, onTap: () => ex.reveal(entry.path)),
    const FaMenuItem.divider(),
    FaMenuItem(
      many ? 'Ask AI about ${paths.length} items' : 'Ask AI about this',
      leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint),
      onTap: hiddenFromAi ? null : () => app.askAiAbout(paths),
    ),
    const FaMenuItem.divider(),
    if (!many) FaMenuItem('Rename', icon: Icons.edit_outlined, shortcut: '↵', onTap: () => ex.beginRename(entry.path)),
    FaMenuItem('Duplicate', icon: Icons.control_point_duplicate_rounded, shortcut: shortcutLabel('D'), onTap: ex.duplicateSelection),
    FaMenuItem('Copy', icon: Icons.copy_rounded, shortcut: shortcutLabel('C'), onTap: ex.copySelection),
    FaMenuItem('Cut', icon: Icons.content_cut_rounded, shortcut: shortcutLabel('X'), onTap: ex.cutSelection),
    if (entry.isDir && ex.clipboard.isNotEmpty)
      FaMenuItem('Paste into folder', icon: Icons.content_paste_rounded, onTap: () => ex.paste(entry.path)),
    FaMenuItem('Copy path', icon: Icons.link_rounded, onTap: () {
      Clipboard.setData(ClipboardData(text: paths.join('\n')));
      app.toast(many ? 'Copied ${paths.length} paths' : 'Copied path');
    }),
    const FaMenuItem.divider(),
    FaMenuItem(
      'Tags',
      icon: Icons.sell_outlined,
      submenu: [
        for (final t in app.tags)
          FaMenuItem(
            t.name,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScoopDot(Scoop.parse(t.color), size: 9),
                if (paths.every((p) => ex.tagsByPath[p]?.contains(t.id) ?? false))
                  const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.check_rounded, size: 11)),
              ],
            ),
            onTap: () => ex.toggleTag(t, paths),
          ),
        if (app.tags.isNotEmpty) const FaMenuItem.divider(),
        FaMenuItem('New tag…', icon: Icons.add_rounded, onTap: () => createTagFlow(context, paths: paths)),
      ],
    ),
    FaMenuItem(
      hiddenFromAi ? 'Show to AI' : 'Hide from AI',
      icon: hiddenFromAi ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      onTap: () async {
        final r = hiddenFromAi ? await app.api.removeExclude(entry.path) : await app.api.addExcludes(paths);
        if (r.ok) {
          await app.refreshPrefs();
          app.toast(hiddenFromAi ? 'AI can see “${entry.name}” again' : 'Hidden from AI: indexing and chat will skip it');
        } else {
          app.toastError(r.error);
        }
      },
    ),
    const FaMenuItem.divider(),
    FaMenuItem('Move to Trash', icon: Icons.delete_outline_rounded, destructive: true, shortcut: shortcutLabel('⌫'), onTap: () => ex.trashSelection()),
  ]);
}

/// Right-click on empty space in a folder.
void showBackgroundMenu(BuildContext context, Offset at) {
  final ex = context.read<ExplorerController>();
  final app = context.read<FaController>();
  ex.clearSelection();
  showFaMenu(context, at, [
    FaMenuItem('New Folder', icon: Icons.create_new_folder_outlined, shortcut: shortcutLabel('⇧N'), onTap: ex.newFolder),
    FaMenuItem('New Text File', icon: Icons.note_add_outlined, onTap: ex.newTextFile),
    if (ex.clipboard.isNotEmpty) FaMenuItem('Paste', icon: Icons.content_paste_rounded, shortcut: shortcutLabel('V'), onTap: () => ex.paste()),
    const FaMenuItem.divider(),
    FaMenuItem(
      'View',
      icon: Icons.grid_view_rounded,
      submenu: [
        for (final (mode, label) in viewModes)
          FaMenuItem(label, icon: mode == ex.view.mode ? Icons.check_rounded : null, onTap: () => ex.setView(mode: mode)),
      ],
    ),
    FaMenuItem(
      'Sort by',
      icon: Icons.sort_rounded,
      submenu: [
        for (final (key, label) in sortKeys)
          FaMenuItem(label, icon: key == ex.view.sortKey ? Icons.check_rounded : null, onTap: () => ex.setView(sortKey: key)),
      ],
    ),
    FaMenuItem(
      app.showHidden ? 'Hide hidden files' : 'Show hidden files',
      icon: Icons.visibility_outlined,
      onTap: () async {
        await app.setPrefs({'showHidden': !app.showHidden});
        await ex.refresh();
      },
    ),
    const FaMenuItem.divider(),
    FaMenuItem('Ask AI about this folder', leading: const Icon(Icons.auto_awesome_rounded, size: 15, color: Scoop.mint), onTap: () => app.askAiAbout([ex.current])),
    FaMenuItem('Show in ${app.isMac ? 'Finder' : 'File Manager'}', icon: Icons.folder_open_outlined, onTap: () => ex.reveal(ex.current)),
  ]);
}

const viewModes = [('grid', 'Icons'), ('list', 'List'), ('columns', 'Columns'), ('gallery', 'Gallery')];
const sortKeys = [('name', 'Name'), ('mtime', 'Date Modified'), ('size', 'Size'), ('kind', 'Kind')];
