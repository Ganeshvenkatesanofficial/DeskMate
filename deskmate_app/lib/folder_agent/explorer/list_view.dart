import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'context_menu.dart';
import 'entry_interactions.dart';
import 'grid_view.dart' show tagColorFor;

/// Detail list with sortable Name / Date Modified / Size / Kind columns.
class FileListView extends StatelessWidget {
  const FileListView({super.key});

  @override
  Widget build(BuildContext context) {
    final ex = context.watch<ExplorerController>();
    return Column(
      children: [
        const _Header(),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: ex.clearSelection,
            onSecondaryTapDown: (d) => showBackgroundMenu(context, d.globalPosition),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
              itemExtent: 30,
              itemCount: ex.entries.length,
              itemBuilder: (context, i) => _Row(entry: ex.entries[i], striped: i.isOdd),
            ),
          ),
        ),
      ],
    );
  }
}

const _dateW = 190.0, _sizeW = 96.0, _kindW = 150.0;

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    Widget col(String key, String label, {double? width, bool right = false}) {
      final active = ex.view.sortKey == key;
      final cell = Hoverable(
        onTap: () => ex.sortBy(key),
        builder: (context, hover) => Row(
          mainAxisAlignment: right ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Text(
              label,
              style: FaText.sans(
                size: 11,
                weight: FontWeight.w500,
                color: active || hover ? c.foreground : c.mutedForeground,
              ),
            ),
            if (active)
              Icon(ex.view.sortDesc ? Icons.arrow_drop_down_rounded : Icons.arrow_drop_up_rounded, size: 16, color: c.foreground),
          ],
        ),
      );
      return width == null ? Expanded(child: cell) : SizedBox(width: width, child: cell);
    }

    return Container(
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          col('name', 'Name'),
          col('mtime', 'Date Modified', width: _dateW),
          col('size', 'Size', width: _sizeW, right: true),
          const SizedBox(width: 18),
          col('kind', 'Kind', width: _kindW),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final FsEntry entry;
  final bool striped;
  const _Row({required this.entry, required this.striped});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final app = context.read<FaController>();
    final selected = ex.selection.contains(entry.path);
    final tags = ex.tagsByPath[entry.path] ?? const [];
    final meta = FaText.sans(size: 12, color: c.mutedForeground);
    return EntryInteractions(
      entry: entry,
      radius: BorderRadius.circular(FaRadius.sm),
      child: Hoverable(
        builder: (context, hover) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? c.selection
                : hover
                ? c.accent.withValues(alpha: 0.7)
                : (striped ? c.muted.withValues(alpha: c.isDark ? 0.35 : 0.55) : Colors.transparent),
            borderRadius: BorderRadius.circular(FaRadius.sm),
          ),
          child: Opacity(
            opacity: ex.isCut(entry.path) || entry.hidden ? 0.5 : 1,
            child: Row(
              children: [
                FileIcon.entry(entry, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: ex.renaming == entry.path
                      ? RenameField(entry: entry)
                      : Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.name,
                                overflow: TextOverflow.ellipsis,
                                style: FaText.sans(size: 12.5, color: c.foreground),
                              ),
                            ),
                            for (final id in tags.take(3))
                              Padding(padding: const EdgeInsets.only(left: 5), child: ScoopDot(tagColorFor(app, id), size: 7)),
                          ],
                        ),
                ),
                SizedBox(width: _dateW, child: Text(formatDate(entry.mtime), style: meta, overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: _sizeW,
                  child: Text(entry.isDir ? '--' : formatBytes(entry.size), style: meta, textAlign: TextAlign.right),
                ),
                const SizedBox(width: 18),
                SizedBox(width: _kindW, child: Text(kindLabel(entry.kind, entry.ext), style: meta, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
