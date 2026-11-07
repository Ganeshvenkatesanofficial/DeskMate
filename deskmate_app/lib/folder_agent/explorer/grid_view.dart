import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import 'entry_interactions.dart';
import 'x_common.dart';

/// Legacy tile metrics still used by the tag-files page.
const double kGridTileWidth = 132;
const double kGridTileHeight = 132;

/// FilDOS GridView tile geometry (icon size "medium"): a 128×116 tile, a
/// 64px cover-cropped thumbnail or a 54px type logo, packed edge to edge.
const double _tileW = 128;
const double _tileH = 116;
const double _preview = 64;
const double _logo = 54;
const double _pad = 8; // p-2 around the grid

/// Icon grid (FilDOS GridView): type logos / thumbnails with names below.
class FileGridView extends StatelessWidget {
  const FileGridView({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = context.select<ExplorerController, List<FsEntry>>((ex) => ex.entries);
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = math.max(1, ((box.maxWidth - _pad * 2) / _tileW).floor());
        GridColumns.of(context)?.value = perRow;
        final rows = (entries.length / perRow).ceil();
        return PaneBackground(
          child: ListView.builder(
            padding: const EdgeInsets.all(_pad),
            itemExtent: _tileH,
            itemCount: rows,
            itemBuilder: (context, r) {
              final start = r * perRow;
              final end = math.min(start + perRow, entries.length);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = start; i < end; i++) _GridTile(key: ValueKey(entries[i].path), entry: entries[i]),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Lets the keyboard handler know how many items a row holds (↑/↓ in the grid).
class GridColumns extends InheritedWidget {
  final ValueNotifier<int> notifier;
  const GridColumns({super.key, required this.notifier, required super.child});
  static ValueNotifier<int>? of(BuildContext context) => context.getInheritedWidgetOfExactType<GridColumns>()?.notifier;
  @override
  bool updateShouldNotify(GridColumns old) => false;
}

class _GridTile extends StatelessWidget {
  final FsEntry entry;
  const _GridTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final selected = context.select<ExplorerController, bool>((ex) => ex.selection.contains(entry.path));
    final editing = context.select<ExplorerController, bool>((ex) => ex.renaming == entry.path);
    final tags = context.select<ExplorerController, List<int>>((ex) => ex.tagsByPath[entry.path] ?? const []);
    context.select<FaController, int>((app) => app.tags.length);
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
        final ring = drop ? 2.0 : (selected ? 1.0 : 0.0);
        return Opacity(
          opacity: entry.hidden ? kFdHiddenOpacity : 1,
          child: Container(
            width: _tileW,
            height: _tileH,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(FaRadius.lg)),
            foregroundDecoration: ring == 0
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(FaRadius.lg),
                    border: Border.all(color: fdRing(c), width: ring),
                  ),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FileIcon.entry(
                      entry,
                      size: _preview,
                      logoSize: _logo,
                      thumbnail: true,
                      fit: BoxFit.cover,
                      radius: FaRadius.sm,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (editing)
                  RenameField(entry: entry, align: TextAlign.center, fontSize: 12, strongBorder: true)
                else
                  Tooltip(
                    message: entry.name,
                    waitDuration: const Duration(milliseconds: 800),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (tags.isNotEmpty)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: TagDotsRow(tags, dotSize: 7),
                                ),
                              ),
                            TextSpan(text: entry.name),
                          ],
                        ),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground, height: 1.25),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
