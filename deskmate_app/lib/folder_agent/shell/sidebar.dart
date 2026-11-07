import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/file_icons.dart';
import '../core/models.dart';
import '../explorer/dnd.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';

/// FilDOS `Sidebar`: `w-60` `bg-card` `border-r`; a 44px logo header that lines
/// up with the location row, then one scrolling column (`px-2 py-3`) of
/// Quick Access, Drives and Tags, a flexible spacer, and Canvas / Recents /
/// Settings at the foot.
class FaSidebar extends StatelessWidget {
  const FaSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final browsing = app.section == FaSection.browse;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: DeskMateLogo(size: 18)),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  sliver: SliverList.list(
                    children: [
                      const SectionLabel('Quick access', top: 0),
                      for (final p in app.quickAccess)
                        _NavRow(
                          dropFolder: p.path,
                          tooltip: p.path,
                          leading: SvgPicture.asset(folderIconAsset(p.name), width: 20, height: 20),
                          label: p.name,
                          selected: browsing && ex.current == p.path,
                          onTap: () => ex.open(p.path),
                        ),
                      if (app.drives.isNotEmpty) const SectionLabel('Drives'),
                      for (final d in app.drives) _DriveRow(drive: d, selected: browsing && ex.current == d.path),
                      if (app.tags.isNotEmpty) const SectionLabel('Tags'),
                      for (final t in app.tags)
                        _NavRow(
                          tooltip: 'Files tagged "${t.name}"',
                          // `TagDot` 9px with `mx-0.75`.
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ScoopDot(Scoop.parse(t.color), size: 9),
                          ),
                          leadingWidth: 15,
                          label: t.name,
                          trailing: t.count > 0
                              ? Text('${t.count}', style: FaText.sans(size: 11, color: c.mutedForeground))
                              : null,
                          selected: app.section == FaSection.tag && app.activeTagId == t.id,
                          onTap: () => app.showSection(FaSection.tag, tagId: t.id),
                          onSecondaryTapDown: (d) => _tagMenu(context, t, d.globalPosition),
                        ),
                    ],
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NavRow(
                          tooltip: 'Your storage as a living map — files connected by meaning, people and time',
                          leading: const Icon(Icons.psychology_outlined, size: 16),
                          label: 'Canvas',
                          selected: app.section == FaSection.canvas,
                          onTap: () => app.showSection(FaSection.canvas),
                        ),
                        _NavRow(
                          tooltip: 'Recently opened files',
                          leading: const Icon(Icons.schedule_rounded, size: 16),
                          label: 'Recents',
                          selected: app.section == FaSection.recents,
                          onTap: () => app.showSection(FaSection.recents),
                        ),
                        _NavRow(
                          tooltip: 'Settings',
                          leading: const Icon(Icons.settings_outlined, size: 16),
                          label: 'Settings',
                          selected: app.section == FaSection.settings,
                          onTap: () => app.showSection(FaSection.settings),
                        ),
                      ],
                    ),
                  ),
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
          final name = await promptText(
            context,
            title: 'Rename Tag',
            label: 'Tag name',
            initial: t.name,
            confirm: 'Rename',
          );
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
              leading: ScoopDot(Scoop.all[i]),
              onTap: () async {
                await app.api.updateTag(t.id, color: Scoop.hex(Scoop.all[i]));
                await app.refreshTags();
              },
            ),
        ],
      ),
      const FaMenuItem.divider(),
      FaMenuItem(
        'Delete Tag',
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

/// Prompt for a tag name (FilDOS "New Tag" dialog), create it with the next
/// scoop colour, and optionally tag [paths].
Future<Tag?> createTagFlow(BuildContext context, {List<String> paths = const []}) async {
  final app = context.read<FaController>();
  final n = paths.length;
  final name = await promptText(
    context,
    title: 'New Tag',
    label: n > 0 ? 'Tag name (applies to $n selected item${n > 1 ? 's' : ''})' : 'Tag name',
    confirm: 'Create',
  );
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

/// A sidebar item — FilDOS `itemClass`: `rounded-md px-2 py-1.5 gap-2`, 13px
/// text, Mist glyphs; hover `bg-accent`; active `bg-foreground/[0.09]`
/// `font-medium` with an Ink glyph (no hover change). No transition, like
/// FilDOS: the wash appears and leaves instantly.
class _NavRow extends StatelessWidget {
  final Widget leading;
  final double? leadingWidth;
  final String label;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;
  final String? dropFolder;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  const _NavRow({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leadingWidth,
    this.trailing,
    this.tooltip,
    this.dropFolder,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    Widget row = Hoverable(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      builder: (context, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.wash : (hover ? c.accent : null),
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Row(
          children: [
            IconTheme.merge(
              data: IconThemeData(color: selected ? c.foreground : c.mutedForeground),
              child: leadingWidth == null ? leading : SizedBox(width: leadingWidth, child: leading),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(
                  size: 13,
                  height: 1.5,
                  weight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: c.foreground,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
    if (tooltip != null) row = Tooltip(message: tooltip!, child: row);
    if (dropFolder != null) row = EntryDropTarget(folder: dropFolder!, child: row);
    return row;
  }
}

/// FilDOS's own capacity format (decimal units: 1-decimal TB/GB, whole MB/KB).
String _driveBytes(int bytes) {
  if (bytes >= 1e12) return '${(bytes / 1e12).toStringAsFixed(1)} TB';
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '${(bytes / 1e3).toStringAsFixed(0)} KB';
}

/// A drive: 16px drive glyph + `text-sm` name, then (`pl-6 mt-1`) a 4px
/// `bg-muted` capacity bar filled `foreground/30` (`destructive/70` from 90%)
/// and a `text-3xs` "used of total" line. Active adds a `ring-1
/// foreground/20` inset outline to the selection wash.
class _DriveRow extends StatelessWidget {
  final Drive drive;
  final bool selected;
  const _DriveRow({required this.drive, required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.read<ExplorerController>();
    final used = drive.total > 0 ? drive.total - drive.free : 0;
    final pct = drive.total > 0 ? (used / drive.total * 100).round() : 0;
    return EntryDropTarget(
      folder: drive.path,
      child: Tooltip(
        message: drive.path,
        child: Hoverable(
          onTap: () => ex.open(drive.path),
          builder: (context, hover) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.wash : (hover ? c.accent : null),
              borderRadius: BorderRadius.circular(FaRadius.md),
              border: selected ? Border.all(color: c.foreground.withValues(alpha: 0.2)) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      drive.removable ? Icons.usb_rounded : Icons.storage_rounded,
                      size: 16,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        drive.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 14, color: c.foreground, height: 20 / 14),
                      ),
                    ),
                  ],
                ),
                if (drive.total > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(999)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: pct / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                color: pct >= 90
                                    ? c.destructive.withValues(alpha: 0.7)
                                    : c.foreground.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_driveBytes(used)} of ${_driveBytes(drive.total)}',
                          style: FaText.sans(size: 10, color: c.mutedForeground, height: 1.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
