import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../shell/pane_header.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'address_bar.dart';
import 'column_view.dart';
import 'context_menu.dart';
import 'gallery_view.dart';
import 'grid_view.dart';
import 'info_panel.dart';
import 'list_view.dart';

/// The browse pane: FilDOS's location row (breadcrumb + View menu + New File /
/// New Folder), the active view, and the 280px Info panel "Get Info" opens.
class ExplorerPane extends StatelessWidget {
  const ExplorerPane({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final noFolder = ex.current.isEmpty;
    return Column(
      children: [
        PaneHeader(
          title: const AddressBar(),
          actions: [
            _ViewMenuButton(mode: ex.view.mode),
            FaIconButton(
              icon: Icons.note_add_outlined,
              size: 32,
              variant: FaIconButtonVariant.secondary,
              tooltip: 'New file',
              onPressed: noFolder ? null : () => newFileFlow(context),
            ),
            FaIconButton(
              icon: Icons.create_new_folder_outlined,
              size: 32,
              variant: FaIconButtonVariant.secondary,
              tooltip: 'New folder',
              onPressed: noFolder ? null : () => newFolderFlow(context),
            ),
          ],
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: ColoredBox(color: c.background, child: _body(context, ex, c)),
              ),
              // FilDOS: "Get Info" opens it; its × closes it.
              if (ex.infoPath != null) ...[
                VerticalDivider(width: 1, thickness: 1, color: c.border),
                SizedBox(width: 280, child: InfoPanel(onClose: ex.closeInfo)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, ExplorerController ex, FaColors c) {
    if (ex.current.isEmpty || (ex.loading && ex.entries.isEmpty)) {
      return const _State(children: [_StateText('Loading…')]);
    }
    if (ex.error != null) {
      final denied = ex.error!.code == 'EACCES' || ex.error!.code == 'EPERM';
      final app = context.read<FaController>();
      return _State(
        children: [
          _StateText('Can’t open this folder', strong: true),
          _StateText(
            denied && app.isMac
                ? 'macOS needs your permission. Grant Full Disk Access to DeskMate in System Settings, then come back.'
                : ex.error!.message,
          ),
          const SizedBox(height: 8),
          denied && app.isMac
              ? FaButton(label: 'Open Privacy Settings', dense: true, onPressed: () => app.api.openPrivacySettings())
              : FaButton(label: 'Try again', dense: true, onPressed: () => ex.refresh()),
        ],
      );
    }
    if (ex.entries.isEmpty && ex.view.mode != 'list') {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => showBackgroundMenu(context, d.globalPosition),
        child: const _State(children: [_StateText('This folder is empty')]),
      );
    }
    return switch (ex.view.mode) {
      'list' => const FileListView(),
      'columns' => const ColumnBrowserView(),
      'gallery' => const GalleryBrowserView(),
      _ => const FileGridView(),
    };
  }
}

/// FilDOS `PromptDialog` "New Folder" (preset "untitled folder").
Future<void> newFolderFlow(BuildContext context) async {
  final ex = context.read<ExplorerController>();
  final name = await promptText(
    context,
    title: 'New Folder',
    label: 'Folder name',
    initial: 'untitled folder',
    confirm: 'Create',
  );
  if (name != null && name.isNotEmpty) await ex.newFolder(name);
}

/// FilDOS `PromptDialog` "New File" (preset "untitled.txt").
Future<void> newFileFlow(BuildContext context) async {
  final ex = context.read<ExplorerController>();
  final name = await promptText(
    context,
    title: 'New File',
    label: 'File name',
    initial: 'untitled.txt',
    confirm: 'Create',
  );
  if (name != null && name.isNotEmpty) await ex.newTextFile(name);
}

/// The layouts with their scoop accents (FilDOS `VIEW_OPTIONS`).
const _modes = [
  ('list', 'List', Icons.view_list_outlined, Scoop.blueberry),
  ('grid', 'Grid', Icons.grid_view_outlined, Scoop.mint),
  ('gallery', 'Gallery', Icons.photo_outlined, Scoop.bubblegum),
  ('columns', 'Column', Icons.view_week_outlined, Scoop.mango),
];

const _sorts = [('name', 'Name'), ('size', 'Size'), ('kind', 'Type'), ('mtime', 'Date modified')];

/// FilDOS's "View" trigger: `variant="secondary" size="sm" px-2 gap-1.5`, the
/// current layout's icon in its scoop colour.
class _ViewMenuButton extends StatelessWidget {
  final String mode;
  const _ViewMenuButton({required this.mode});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final m = _modes.firstWhere((x) => x.$1 == mode, orElse: () => _modes.first);
    return Tooltip(
      message: 'View options',
      child: Builder(
        builder: (context) => Hoverable(
          onTap: () => _open(context),
          pressScale: 0.97,
          builder: (context, hover) => AnimatedContainer(
            duration: FaMotion.fast,
            curve: FaMotion.snappy,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hover ? c.muted.withValues(alpha: 0.8) : c.muted,
              borderRadius: BorderRadius.circular(FaRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(m.$3, size: 16, color: m.$4),
                const SizedBox(width: 6),
                Text(
                  'View',
                  style: FaText.sans(size: 14, color: c.foreground, height: 20 / 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final ex = context.read<ExplorerController>();
    final app = context.read<FaController>();
    final box = context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(box.size.width, box.size.height));
    // FilDOS's View menu stays open while you change layout, sort or hidden
    // files, reflecting each change live.
    showFaMenu(
      context,
      at,
      const [],
      alignEnd: true,
      minWidth: 256,
      listenable: Listenable.merge([ex, app]),
      builder: () => [
        const FaMenuItem.label('Mode'),
        FaMenuItem.custom((context) => _ModeTiles(ex: ex)),
        const FaMenuItem.divider(),
        const FaMenuItem.label('Sort by'),
        for (final (key, label) in _sorts)
          FaMenuItem(
            label,
            leading: const SizedBox(width: 16),
            keepOpen: true,
            trailing: ex.view.sortKey == key
                ? Builder(
                    builder: (context) => Text(
                      ex.view.sortDesc ? 'Descending' : 'Ascending',
                      style: FaText.sans(size: 11, color: context.fa.mutedForeground),
                    ),
                  )
                : null,
            onTap: () => ex.sortBy(key),
          ),
        const FaMenuItem.divider(),
        FaMenuItem(
          'Show hidden files',
          leading: app.showHidden ? const Icon(Icons.check_rounded, size: 16) : const SizedBox(width: 16),
          keepOpen: true,
          onTap: () async {
            await app.setPrefs({'showHidden': !app.showHidden});
            await ex.refresh(silent: true);
          },
        ),
      ],
    );
  }
}

/// The View menu's 2×2 layout tiles: `rounded-md px-2 py-1.5 gap-2 text-sm`,
/// active = the scoop at 15%, hover = accent, ghost ⌘1–⌘4 keycaps.
class _ModeTiles extends StatelessWidget {
  final ExplorerController ex;
  const _ModeTiles({required this.ex});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    Widget tile(int i) {
      final (mode, label, icon, color) = _modes[i];
      final active = ex.view.mode == mode;
      return Expanded(
        child: Hoverable(
          cursor: SystemMouseCursors.click,
          onTap: () => ex.setView(mode: mode),
          builder: (context, hover) => AnimatedContainer(
            duration: FaMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active ? color.withValues(alpha: 0.15) : (hover ? c.accent : null),
              borderRadius: BorderRadius.circular(FaRadius.md),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: FaText.sans(size: 14, color: c.foreground, height: 20 / 14),
                  ),
                ),
                Kbd(shortcutLabel('${i + 1}'), variant: KbdVariant.ghost),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(children: [tile(0), const SizedBox(width: 4), tile(1)]),
          const SizedBox(height: 4),
          Row(children: [tile(2), const SizedBox(width: 4), tile(3)]),
        ],
      ),
    );
  }
}

/// FilDOS `STATE`: centred Mist text, `gap-1`; a bold Ink title for errors.
class _State extends StatelessWidget {
  final List<Widget> children;
  const _State({required this.children});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 4), children[i]],
          ],
        ),
      ),
    ),
  );
}

class _StateText extends StatelessWidget {
  final String text;
  final bool strong;
  const _StateText(this.text, {this.strong = false});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: FaText.sans(
        size: 13,
        weight: strong ? FontWeight.w700 : FontWeight.w400,
        color: strong ? c.foreground : c.mutedForeground,
        height: 1.5,
      ),
    );
  }
}
