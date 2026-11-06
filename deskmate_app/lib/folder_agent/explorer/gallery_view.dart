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
import 'file_preview.dart';
import 'grid_view.dart' show tagColorFor;
import 'quick_look.dart';

const double _kThumb = 72;
const double _kThumbGap = 8;

/// Gallery: a large preview of the selected item (the first item when nothing
/// is selected) with its name and metadata, over a filmstrip of the folder.
/// ←/→ move the selection (handled by the shell), the stage follows.
class GalleryBrowserView extends StatefulWidget {
  const GalleryBrowserView({super.key});

  @override
  State<GalleryBrowserView> createState() => _GalleryBrowserViewState();
}

class _GalleryBrowserViewState extends State<GalleryBrowserView> {
  final _strip = ScrollController();
  String? _shown;

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  /// Keeps the selected thumbnail centred in the filmstrip.
  void _follow(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_strip.hasClients || index < 0) return;
      final pos = _strip.position;
      final center = 12 + index * (_kThumb + _kThumbGap) + _kThumb / 2;
      final target = (center - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
      _strip.animateTo(target, duration: FaMotion.medium, curve: FaMotion.snappy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    if (ex.entries.isEmpty) return const SizedBox.shrink();
    final entry = ex.primarySelection ?? ex.entries.first;
    if (_shown != entry.path) {
      _shown = entry.path;
      _follow(ex.entries.indexOf(entry));
    }

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) => showEntryMenu(context, entry, d.globalPosition),
            onDoubleTap: entry.isDir ? () => ex.activate(entry) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: AnimatedSwitcher(
                duration: FaMotion.fast,
                child: KeyedSubtree(
                  key: ValueKey(entry.path),
                  child: entry.isDir ? _FolderStage(entry: entry) : FilePreview(entry: entry),
                ),
              ),
            ),
          ),
        ),
        _Caption(entry: entry),
        Container(
          height: _kThumb + 24,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) => showBackgroundMenu(context, d.globalPosition),
            child: ListView.separated(
              controller: _strip,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: ex.entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: _kThumbGap),
              itemBuilder: (context, i) {
                final e = ex.entries[i];
                return _StripTile(entry: e, current: e.path == entry.path);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Name + "Kind · size · modified" under the stage.
class _Caption extends StatelessWidget {
  final FsEntry entry;
  const _Caption({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final app = context.read<FaController>();
    final tags = ex.tagsByPath[entry.path] ?? const [];
    final meta = [
      kindLabel(entry.kind, entry.ext),
      if (!entry.isDir) formatBytes(entry.size),
      'Modified ${formatDate(entry.mtime)}',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final id in tags.take(3))
                      Padding(padding: const EdgeInsets.only(right: 4), child: ScoopDot(tagColorFor(app, id), size: 7)),
                    if (tags.isNotEmpty) const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(meta, style: FaText.sans(size: 12, color: c.mutedForeground)),
              ],
            ),
          ),
          if (!entry.isDir)
            FaIconButton(
              icon: Icons.visibility_outlined,
              tooltip: 'Quick Look (Space)',
              onPressed: () => showQuickLook(context, entry),
            ),
          const SizedBox(width: 4),
          FaButton(
            label: 'Open',
            icon: Icons.open_in_new_rounded,
            dense: true,
            variant: FaButtonVariant.outline,
            onPressed: () => ex.activate(entry),
          ),
        ],
      ),
    );
  }
}

/// Stage for a folder: its large icon (folders have no preview).
class _FolderStage extends StatelessWidget {
  final FsEntry entry;
  const _FolderStage({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FileIcon.entry(entry, size: 140),
          const SizedBox(height: 12),
          Text('Double-click to open', style: FaText.sans(size: 12, color: c.mutedForeground)),
        ],
      ),
    );
  }
}

class _StripTile extends StatelessWidget {
  final FsEntry entry;
  final bool current;
  const _StripTile({required this.entry, required this.current});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final selected = ex.selection.contains(entry.path) || current;
    return Tooltip(
      message: entry.name,
      waitDuration: const Duration(milliseconds: 700),
      child: EntryInteractions(
        entry: entry,
        child: Hoverable(
          builder: (context, hover) => AnimatedContainer(
            duration: FaMotion.fast,
            width: _kThumb,
            height: _kThumb,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected ? c.selection : (hover ? c.accent : c.muted.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(FaRadius.md),
              border: Border.all(
                color: current ? c.foreground.withValues(alpha: 0.55) : c.border.withValues(alpha: 0.6),
                width: current ? 1.5 : 1,
              ),
            ),
            child: Opacity(
              opacity: ex.isCut(entry.path) || entry.hidden ? 0.5 : 1,
              child: Center(
                child: FileIcon.entry(entry, size: entry.hasThumbnail ? _kThumb - 12 : 36, thumbnail: true),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
