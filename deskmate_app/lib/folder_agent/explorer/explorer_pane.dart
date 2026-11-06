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

/// The browse pane: address bar + view controls, the active view, and the
/// optional info panel.
class ExplorerPane extends StatefulWidget {
  const ExplorerPane({super.key});
  @override
  State<ExplorerPane> createState() => _ExplorerPaneState();
}

class _ExplorerPaneState extends State<ExplorerPane> {
  bool _info = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    return Column(
      children: [
        PaneHeader(
          title: const AddressBar(),
          actions: [
            _ViewMenuButton(mode: ex.view.mode),
            FaIconButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: 'New Folder',
              onPressed: ex.current.isEmpty ? null : ex.newFolder,
            ),
            FaIconButton(
              icon: Icons.info_outline_rounded,
              tooltip: 'Info',
              active: _info,
              onPressed: () => setState(() => _info = !_info),
            ),
          ],
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _body(context, ex, c)),
              if (_info) ...[
                VerticalDivider(width: 1, thickness: 1, color: c.border),
                const SizedBox(width: 300, child: InfoPanel()),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, ExplorerController ex, FaColors c) {
    if (ex.current.isEmpty || (ex.loading && ex.entries.isEmpty)) {
      return const Center(child: SizedBox(width: 120, child: FaProgressBar()));
    }
    if (ex.error != null) {
      final denied = ex.error!.code == 'EACCES' || ex.error!.code == 'EPERM';
      final app = context.read<FaController>();
      return _EmptyState(
        icon: denied ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
        title: denied ? 'DeskMate can\'t open this folder' : 'This folder couldn\'t be opened',
        body: denied && app.isMac
            ? 'macOS needs your permission. Grant Full Disk Access to DeskMate in System Settings, then come back.'
            : ex.error!.message,
        action: denied && app.isMac
            ? FaButton(label: 'Open Privacy Settings', onPressed: () => app.api.openPrivacySettings())
            : FaButton(label: 'Try again', onPressed: () => ex.refresh()),
      );
    }
    if (ex.entries.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => showBackgroundMenu(context, d.globalPosition),
        child: _EmptyState(
          icon: Icons.folder_open_outlined,
          title: 'This folder is empty',
          body: ex.hiddenCount > 0 ? '${ex.hiddenCount} hidden item(s). Right-click to show hidden files.' : 'Right-click to create a folder or file.',
        ),
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

class _ViewMenuButton extends StatelessWidget {
  final String mode;
  const _ViewMenuButton({required this.mode});
  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    final icon = switch (mode) {
      'list' => Icons.view_list_rounded,
      'columns' => Icons.view_column_rounded,
      'gallery' => Icons.view_carousel_rounded,
      _ => Icons.grid_view_rounded,
    };
    return Builder(
      builder: (context) => FaButton(
        label: 'View',
        icon: icon,
        dense: true,
        variant: FaButtonVariant.ghost,
        onPressed: () {
          final box = context.findRenderObject() as RenderBox;
          final at = box.localToGlobal(Offset(0, box.size.height + 4));
          showFaMenu(context, at, [
            for (final (m, label) in viewModes)
              FaMenuItem(label, icon: m == mode ? Icons.check_rounded : null, onTap: () => ex.setView(mode: m)),
            const FaMenuItem.divider(),
            for (final (k, label) in sortKeys)
              FaMenuItem(
                'Sort by $label',
                icon: k == ex.view.sortKey ? (ex.view.sortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded) : null,
                onTap: () => ex.sortBy(k),
              ),
          ]);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const _EmptyState({required this.icon, required this.title, required this.body, this.action});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: c.mutedForeground),
            const SizedBox(height: 12),
            Text(title, style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: FaText.sans(size: 12.5, color: c.mutedForeground, height: 1.45)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
