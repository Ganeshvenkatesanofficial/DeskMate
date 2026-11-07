import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';

/// An in-app file drag. [paths] is resolved the moment the drag starts
/// (FilDOS `onItemDragStart`): the whole selection when the grabbed item is
/// part of it, otherwise just the grabbed item. Starting a drag never changes
/// the selection.
class EntryDrag {
  final FsEntry origin;
  List<String> paths = const [];
  EntryDrag(this.origin);
}

/// Movement (logical px) before a press becomes a drag — the browser's drag
/// threshold. Smaller jitters stay clicks, so a click always selects.
const double kEntryDragSlop = 4;

/// Makes [child] draggable; dragging a selected item carries the whole selection.
class DraggableEntry extends StatelessWidget {
  final FsEntry entry;
  final Widget child;
  const DraggableEntry({super.key, required this.entry, required this.child});

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    final drag = EntryDrag(entry);
    return _SlopDraggable(
      data: drag,
      onResolve: () {
        final selected = ex.selectedPaths;
        drag.paths = selected.contains(entry.path) ? selected : [entry.path];
      },
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Builder(
        builder: (_) => _DragFeedback(entry: entry, count: drag.paths.length, theme: Theme.of(context)),
      ),
      child: child,
    );
  }
}

/// [Draggable] whose drag starts only after [kEntryDragSlop] of movement
/// (Flutter's default for a mouse is 1px, which turned slightly shaky clicks
/// into drags that never selected anything).
class _SlopDraggable extends Draggable<EntryDrag> {
  final VoidCallback onResolve;
  const _SlopDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    required this.onResolve,
    super.dragAnchorStrategy,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      _SlopMultiDragRecognizer(allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = (position) {
          onResolve();
          return onStart(position);
        };
}

class _SlopMultiDragRecognizer extends MultiDragGestureRecognizer {
  _SlopMultiDragRecognizer({super.allowedButtonsFilter}) : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _SlopPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'entry drag';
}

class _SlopPointerState extends MultiDragPointerState {
  _SlopPointerState(super.initialPosition, super.kind, super.gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > kEntryDragSlop) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) => starter(initialPosition);
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
                  FileIcon.entry(entry, size: 20),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      count > 1 ? '$count items' : entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
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

/// FilDOS `handleDrop`: the dragged paths that would actually change place
/// (not the folder itself, not already inside it, not into their own subtree).
List<String> droppablePaths(EntryDrag drag, String dest) => [
  for (final p in drag.paths)
    if (p != dest && parentDir(p) != dest && !dest.startsWith('$p/')) p,
];

/// Drops [drag] into [dest]: an in-app drag moves, ⌥/Alt held copies.
void dropInto(ExplorerController ex, EntryDrag drag, String dest) {
  final valid = droppablePaths(drag, dest);
  if (valid.isEmpty) return;
  if (HardwareKeyboard.instance.isAltPressed) {
    ex.copyInto(valid, dest);
  } else {
    ex.moveInto(valid, dest);
  }
}

/// Drop zone builder: [active] is true while an acceptable drag hovers it.
class EntryDropZone extends StatelessWidget {
  final String folder;
  final Widget Function(BuildContext context, bool active) builder;
  const EntryDropZone({super.key, required this.folder, required this.builder});

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    return DragTarget<EntryDrag>(
      onWillAcceptWithDetails: (d) => droppablePaths(d.data, folder).isNotEmpty,
      onAcceptWithDetails: (d) => dropInto(ex, d.data, folder),
      builder: (context, candidates, _) => builder(context, candidates.isNotEmpty),
    );
  }
}

/// Drop zone with its own highlight (sidebar, address bar). Dropping moves the
/// entries into [folder] (⌥/Alt copies).
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
    return EntryDropZone(
      folder: folder,
      builder: (context, active) {
        final c = context.fa;
        // FilDOS drop highlight: accent wash + a 2px inset ring at 40%.
        return Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: active ? c.primary.withValues(alpha: 0.4) : Colors.transparent, width: 2),
          ),
          decoration: BoxDecoration(borderRadius: radius, color: active ? c.accent : Colors.transparent),
          child: child,
        );
      },
    );
  }
}
