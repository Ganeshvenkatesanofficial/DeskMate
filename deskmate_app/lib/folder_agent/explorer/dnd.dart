import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';

/// Marker for an in-app file drag. The dragged items are the explorer's
/// selection (the drag start selects the grabbed item if it wasn't).
class EntryDrag {
  const EntryDrag();
}

/// Makes [child] draggable; dragging a selected item carries the whole selection.
class DraggableEntry extends StatelessWidget {
  final FsEntry entry;
  final Widget child;
  const DraggableEntry({super.key, required this.entry, required this.child});

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    return Draggable<EntryDrag>(
      data: const EntryDrag(),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        if (!ex.selection.contains(entry.path)) ex.select(entry);
      },
      feedback: Builder(
        builder: (_) {
          final paths = ex.selection.contains(entry.path) ? ex.selection.toList() : [entry.path];
          return _DragFeedback(entry: entry, count: paths.length, theme: Theme.of(context));
        },
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final FsEntry entry;
  final int count;
  final ThemeData theme;
  const _DragFeedback({required this.entry, required this.count, required this.theme});
  @override
  Widget build(BuildContext context) => Theme(
    data: theme,
    child: Builder(
      builder: (context) {
        final c = context.fa;
        return Material(
          color: Colors.transparent,
          child: Transform.translate(
            offset: const Offset(10, 10),
            child: FaCard(
              shadow: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FileIcon.entry(entry, size: 22),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      count > 1 ? '$count items' : entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: FaText.sans(size: 12.5, color: c.foreground),
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

/// Drop zone: dropping entries here moves them into [folder] (⌥/Ctrl copies).
class EntryDropTarget extends StatelessWidget {
  final String folder;
  final Widget child;
  final BorderRadius radius;
  const EntryDropTarget({
    super.key,
    required this.folder,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(FaRadius.md)),
  });

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    return DragTarget<EntryDrag>(
      onWillAcceptWithDetails: (_) {
        final paths = ex.selection.toList();
        return paths.isNotEmpty && !paths.contains(folder) && !paths.any((p) => folder.startsWith('$p/'));
      },
      onAcceptWithDetails: (_) {
        final paths = ex.selection.toList();
        if (isPrimaryModifierPressed()) {
          ex.copyInto(paths, folder);
        } else {
          ex.moveInto(paths, folder);
        }
      },
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: FaMotion.fast,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: active ? Scoop.blueberry : Colors.transparent, width: 1.5),
            color: active ? Scoop.blueberry.withValues(alpha: 0.10) : Colors.transparent,
          ),
          child: child,
        );
      },
    );
  }
}

