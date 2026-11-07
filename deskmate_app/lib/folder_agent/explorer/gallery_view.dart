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

/// FilDOS GalleryView geometry (icon size "medium"): 136px square tiles with
/// 2px grout, inside the pane's 8px padding.
const double _tile = 136;
const double _grout = 2;
const double _step = _tile + _grout;
const double _pad = 8;

/// Gallery (FilDOS GalleryView): a wall of uniform square thumbnails with no
/// filenames. Images crop to fill, everything else shows its centred type
/// logo; hovering reveals the name over a dark gradient.
class GalleryBrowserView extends StatelessWidget {
  const GalleryBrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = context.select<ExplorerController, List<FsEntry>>((ex) => ex.entries);
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = math.max(1, ((box.maxWidth - _pad * 2 + _grout) / _step).floor());
        final rows = (entries.length / perRow).ceil();
        return PaneBackground(
          child: ListView.builder(
            padding: const EdgeInsets.all(_pad),
            itemExtent: _step,
            itemCount: rows,
            itemBuilder: (context, r) {
              final start = r * perRow;
              final end = math.min(start + perRow, entries.length);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: _tile,
                  child: Row(
                    children: [
                      for (var i = start; i < end; i++) ...[
                        if (i > start) const SizedBox(width: _grout),
                        _GalleryTile(key: ValueKey(entries[i].path), entry: entries[i]),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final FsEntry entry;
  const _GalleryTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final selected = context.select<ExplorerController, bool>((ex) => ex.selection.contains(entry.path));
    final tags = context.select<ExplorerController, List<int>>((ex) => ex.tagsByPath[entry.path] ?? const []);
    context.select<FaController, int>((app) => app.tags.length);
    final radius = BorderRadius.circular(FaRadius.md);
    final preview = canPreview(isDir: entry.isDir, ext: entry.ext);
    return Tooltip(
      message: entry.name,
      waitDuration: const Duration(milliseconds: 800),
      child: EntryInteractions(
        entry: entry,
        builder: (context, hover, drop) {
          // Top layer: drop target > selection > hover darkening.
          final Color overlay = drop
              ? c.primary.withValues(alpha: 0.10)
              : selected
              ? fdSelected(c)
              : hover
              ? Colors.black.withValues(alpha: 0.15)
              : Colors.transparent;
          final ring = drop || selected;
          return Opacity(
            opacity: entry.hidden ? kFdHiddenOpacity : 1,
            child: ClipRRect(
              borderRadius: radius,
              child: SizedBox(
                width: _tile,
                height: _tile,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // bg-muted + ring-1 ring-inset ring-border/50.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.muted,
                        borderRadius: radius,
                        border: Border.all(color: c.border.withValues(alpha: 0.5)),
                      ),
                    ),
                    if (preview)
                      FileIcon.entry(entry, size: _tile, logoSize: _tile * 0.55, thumbnail: true, fit: BoxFit.cover)
                    else
                      Center(child: FileIcon.entry(entry, size: _tile * 0.55)),
                    if (tags.isNotEmpty)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.background.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: TagDotsRow(tags, dotSize: 7),
                        ),
                      ),
                    // Hover: the name over a dark gradient at the bottom.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: hover ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 20, 6, 4),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color(0xBF000000), Color(0x40000000), Color(0x00000000)],
                              ),
                            ),
                            child: Text(
                              entry.name,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: FaText.sans(size: 11, weight: FontWeight.w500, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: const Cubic(0.4, 0, 0.2, 1),
                        decoration: BoxDecoration(
                          color: overlay,
                          borderRadius: radius,
                          border: Border.all(
                            color: ring ? c.primary.withValues(alpha: 0.6) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
