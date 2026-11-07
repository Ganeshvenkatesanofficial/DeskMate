import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import 'entry_interactions.dart';
import 'x_common.dart';

/// FilDOS FileList geometry: 32px rows; Name fills, then Size 100 · Type 140 ·
/// Modified 200 (FilDOS's default column widths).
const double _rowH = 32;
const double _sizeW = 100, _typeW = 140, _modifiedW = 200;

/// Detail list (FilDOS FileList) with sortable Name / Size / Type / Modified.
class FileListView extends StatelessWidget {
  const FileListView({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = context.select<ExplorerController, List<FsEntry>>((ex) => ex.entries);
    return PaneBackground(
      child: Column(
        children: [
          const _Header(),
          // FilDOS keeps the column header above the empty message.
          if (entries.isEmpty)
            Expanded(
              child: Center(
                child: Text('This folder is empty', style: FaText.sans(size: 13, color: context.fa.mutedForeground)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemExtent: _rowH,
                itemCount: entries.length,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  final i = entries.indexWhere((e) => e.path == key.value);
                  return i < 0 ? null : i;
                },
                itemBuilder: (context, i) => _Row(key: ValueKey(entries[i].path), entry: entries[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    Widget col(String key, String label, {double? width}) {
      final active = ex.view.sortKey == key;
      final cell = _HeaderCell(
        label: label,
        arrow: active ? (ex.view.sortDesc ? '▼' : '▲') : null,
        onTap: () => ex.sortBy(key),
      );
      return width == null ? Expanded(child: cell) : SizedBox(width: width, child: cell);
    }

    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          col('name', 'Name'),
          col('size', 'Size', width: _sizeW),
          col('kind', 'Type', width: _typeW),
          col('mtime', 'Modified', width: _modifiedW),
        ],
      ),
    );
  }
}

/// `px-2.5 py-2 text-2xs font-semibold uppercase tracking-wider`, muted → foreground on hover.
class _HeaderCell extends StatefulWidget {
  final String label;
  final String? arrow;
  final VoidCallback onTap;
  const _HeaderCell({required this.label, required this.arrow, required this.onTap});
  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final color = _hover ? c.foreground : c.mutedForeground;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  widget.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: FaText.sans(size: 11, weight: FontWeight.w600, color: color, letterSpacing: 0.55, height: 1.5),
                ),
              ),
              if (widget.arrow != null) ...[
                const SizedBox(width: 4),
                Text(widget.arrow!, style: TextStyle(fontSize: 8, color: color, height: 1)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final FsEntry entry;
  const _Row({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final selected = context.select<ExplorerController, bool>((ex) => ex.selection.contains(entry.path));
    final editing = context.select<ExplorerController, bool>((ex) => ex.renaming == entry.path);
    final tags = context.select<ExplorerController, List<int>>((ex) => ex.tagsByPath[entry.path] ?? const []);
    context.select<FaController, int>((app) => app.tags.length);
    final cell = FaText.sans(size: 12, color: c.mutedForeground);
    Widget meta(String text, double width) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: cell),
      ),
    );
    return EntryInteractions(
      entry: entry,
      editing: editing,
      builder: (context, hover, drop) {
        final Color bg = drop
            ? fdHover(c)
            : selected
            ? fdSelected(c)
            : hover
            ? fdHover(c)
            : Colors.transparent;
        return Opacity(
          opacity: entry.hidden ? kFdHiddenOpacity : 1,
          child: Container(
            color: bg,
            foregroundDecoration: drop ? BoxDecoration(border: Border.all(color: fdRing(c), width: 2)) : null,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        FileIcon.entry(entry, size: 16),
                        const SizedBox(width: 8),
                        if (editing)
                          Expanded(child: RenameField(entry: entry))
                        else ...[
                          Flexible(
                            child: Text(
                              entry.name,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: FaText.sans(size: 13, weight: FontWeight.w500, color: c.foreground),
                            ),
                          ),
                          if (tags.isNotEmpty) ...[const SizedBox(width: 8), TagDotsRow(tags)],
                        ],
                      ],
                    ),
                  ),
                ),
                meta(entry.isDir ? '—' : fdFormatSize(entry.size), _sizeW),
                meta(typeLabel(entry), _typeW),
                meta(fdFormatDate(entry.mtime), _modifiedW),
              ],
            ),
          ),
        );
      },
    );
  }
}
