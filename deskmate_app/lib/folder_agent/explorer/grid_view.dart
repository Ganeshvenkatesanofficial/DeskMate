import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'context_menu.dart';
import 'entry_interactions.dart';

const double kGridTileWidth = 132;
const double kGridTileHeight = 132;

/// Icon grid (the FilDOS default view): big type icons / thumbnails, names below.
class FileGridView extends StatelessWidget {
  const FileGridView({super.key});

  @override
  Widget build(BuildContext context) {
    final ex = context.watch<ExplorerController>();
    return LayoutBuilder(
      builder: (context, box) {
        final columns = ((box.maxWidth - 24) / (kGridTileWidth + 8)).floor().clamp(1, 64);
        GridColumns.of(context)?.value = columns;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: ex.clearSelection,
          onSecondaryTapDown: (d) => showBackgroundMenu(context, d.globalPosition),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: kGridTileHeight + 18,
              crossAxisSpacing: 8,
              mainAxisSpacing: 6,
            ),
            itemCount: ex.entries.length,
            itemBuilder: (context, i) => _GridTile(entry: ex.entries[i]),
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
  const _GridTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final app = context.read<FaController>();
    final selected = ex.selection.contains(entry.path);
    final renaming = ex.renaming == entry.path;
    final tags = ex.tagsByPath[entry.path] ?? const [];
    return EntryInteractions(
      entry: entry,
      child: Hoverable(
        builder: (context, hover) => AnimatedContainer(
          duration: FaMotion.fast,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
          decoration: BoxDecoration(
            color: selected ? c.selection : (hover ? c.accent.withValues(alpha: 0.7) : Colors.transparent),
            borderRadius: BorderRadius.circular(FaRadius.lg),
          ),
          child: Opacity(
            opacity: ex.isCut(entry.path) || entry.hidden ? 0.5 : 1,
            child: Column(
              children: [
                SizedBox(
                  height: 76,
                  child: Center(child: FileIcon.entry(entry, size: entry.hasThumbnail ? 72 : 60, thumbnail: true)),
                ),
                const SizedBox(height: 10),
                if (renaming)
                  RenameField(entry: entry, align: TextAlign.center, maxLines: 2)
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final id in tags.take(3))
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: ScoopDot(tagColorFor(app, id), size: 7),
                        ),
                      if (tags.isNotEmpty) const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          entry.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: FaText.sans(size: 12.5, weight: FontWeight.w500, color: c.foreground, height: 1.3),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color tagColorFor(FaController app, int id) {
  for (final t in app.tags) {
    if (t.id == id) return Scoop.parse(t.color);
  }
  return Scoop.blueberry;
}
