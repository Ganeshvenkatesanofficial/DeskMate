import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/file_icons.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../explorer/dnd.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';

/// FilDOS-style sidebar: logo, Quick Access, Drives, Tags, then Canvas /
/// Recents / Settings and the DeskMate agent switcher pinned to the bottom.
class FaSidebar extends StatelessWidget {
  const FaSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final browsing = app.section == FaSection.browse;
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(14, 14, 14, 4), child: DeskMateLogo(size: 17)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                const SectionLabel('Quick access'),
                for (final p in app.quickAccess)
                  EntryDropTarget(
                    folder: p.path,
                    child: _NavRow(
                      leading: SvgPicture.asset(folderIconAsset(p.name), width: 18, height: 18),
                      label: p.name,
                      selected: browsing && ex.current == p.path,
                      onTap: () => ex.open(p.path),
                    ),
                  ),
                if (app.drives.isNotEmpty) const SectionLabel('Drives'),
                for (final d in app.drives) _DriveRow(drive: d, selected: browsing && ex.current == d.path),
                SectionLabel(
                  'Tags',
                  trailing: FaIconButton(
                    icon: Icons.add_rounded,
                    size: 20,
                    tooltip: 'New tag',
                    onPressed: () => createTagFlow(context),
                  ),
                ),
                if (app.tags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Text(
                      'Right-click a file to tag it',
                      style: FaText.sans(size: 11.5, color: c.mutedForeground),
                    ),
                  ),
                for (final t in app.tags)
                  _NavRow(
                    leading: ScoopDot(Scoop.parse(t.color), size: 9),
                    label: t.name,
                    trailing: t.count > 0
                        ? Text('${t.count}', style: FaText.mono(size: 10, color: c.mutedForeground))
                        : null,
                    selected: app.section == FaSection.tag && app.activeTagId == t.id,
                    onTap: () => app.showSection(FaSection.tag, tagId: t.id),
                    onSecondaryTapDown: (d) => _tagMenu(context, t, d.globalPosition),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Column(
              children: [
                _NavRow(
                  leading: Icon(Icons.hub_outlined, size: 17, color: c.mutedForeground),
                  label: 'Canvas',
                  selected: app.section == FaSection.canvas,
                  onTap: () => app.showSection(FaSection.canvas),
                ),
                _NavRow(
                  leading: Icon(Icons.schedule_rounded, size: 17, color: c.mutedForeground),
                  label: 'Recents',
                  selected: app.section == FaSection.recents,
                  onTap: () => app.showSection(FaSection.recents),
                ),
                _NavRow(
                  leading: Icon(Icons.settings_outlined, size: 17, color: c.mutedForeground),
                  label: 'Settings',
                  selected: app.section == FaSection.settings,
                  onTap: () => app.showSection(FaSection.settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _tagMenu(BuildContext context, Tag t, Offset at) {
    final app = context.read<FaController>();
    showFaMenu(context, at, [
      FaMenuItem(
        'Rename…',
        icon: Icons.edit_outlined,
        onTap: () async {
          final name = await promptText(context, title: 'Rename tag', initial: t.name, confirm: 'Rename');
          if (name != null && name.isNotEmpty) {
            final r = await app.api.updateTag(t.id, name: name);
            r.ok ? await app.refreshTags() : app.toastError(r.error);
          }
        },
      ),
      FaMenuItem(
        'Colour',
        icon: Icons.palette_outlined,
        submenu: [
          for (var i = 0; i < Scoop.all.length; i++)
            FaMenuItem(
              Scoop.names[i],
              leading: ScoopDot(Scoop.all[i], size: 9),
              onTap: () async {
                await app.api.updateTag(t.id, color: Scoop.hex(Scoop.all[i]));
                await app.refreshTags();
              },
            ),
        ],
      ),
      const FaMenuItem.divider(),
      FaMenuItem(
        'Delete tag',
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onTap: () async {
          await app.api.removeTag(t.id);
          if (app.activeTagId == t.id) app.showSection(FaSection.browse);
          await app.refreshTags();
        },
      ),
    ]);
  }
}

/// Prompt for a tag name, create it with the next scoop colour, and optionally tag [paths].
Future<Tag?> createTagFlow(BuildContext context, {List<String> paths = const []}) async {
  final app = context.read<FaController>();
  final name = await promptText(context, title: 'New tag', hint: 'Work, Personal, Important…', confirm: 'Create');
  if (name == null || name.isEmpty) return null;
  final color = Scoop.hex(Scoop.all[app.tags.length % Scoop.all.length]);
  final r = await app.api.createTag(name, color);
  if (!r.ok) {
    app.toastError(r.error);
    return null;
  }
  if (paths.isNotEmpty) await app.api.assignTag(r.value!.id, paths);
  await app.refreshTags();
  if (context.mounted && paths.isNotEmpty) await context.read<ExplorerController>().refresh(silent: true);
  return r.value;
}

class _NavRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  const _NavRow({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        height: 30,
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.accent : (hover ? c.accent.withValues(alpha: 0.6) : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.sm),
        ),
        child: Row(
          children: [
            SizedBox(width: 20, child: Center(child: leading)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 13, weight: selected ? FontWeight.w500 : FontWeight.w400, color: c.foreground),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _DriveRow extends StatelessWidget {
  final Drive drive;
  final bool selected;
  const _DriveRow({required this.drive, required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.read<ExplorerController>();
    final frac = drive.total == 0 ? 0.0 : drive.used / drive.total;
    return Hoverable(
      onTap: () => ex.open(drive.path),
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 7),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: selected ? c.accent : (hover ? c.accent.withValues(alpha: 0.6) : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Icon(
                    drive.removable ? Icons.usb_rounded : Icons.storage_rounded,
                    size: 16,
                    color: c.mutedForeground,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    drive.name,
                    style: FaText.sans(size: 13, color: c.foreground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 29, top: 6),
              child: FaProgressBar(value: frac, height: 3, color: frac > 0.9 ? Scoop.strawberry : c.mutedForeground),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 29, top: 4),
              child: Text(
                '${formatBytes(drive.used)} of ${formatBytes(drive.total)}',
                style: FaText.sans(size: 10.5, color: c.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
