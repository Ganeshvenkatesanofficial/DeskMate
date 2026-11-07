import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import 'context_menu.dart';
import 'dnd.dart';

/// Max gap between the two clicks of a double-click (the macOS default).
const Duration kDoubleClickTime = Duration(milliseconds: 500);

/// A right-click opens the menu on press (as `contextmenu` does in FilDOS on
/// macOS). The item under the pointer handles it first and marks the press as
/// consumed so the pane behind it doesn't open its background menu too
/// (`stopPropagation`).
abstract final class ContextClick {
  static int? _consumed;

  /// Secondary button, or Ctrl + primary on macOS (which the browser turns
  /// into a right-click instead of a Ctrl-click).
  static bool isContextPress(PointerDownEvent e) =>
      e.kind == PointerDeviceKind.mouse &&
      ((e.buttons & kSecondaryMouseButton) != 0 ||
          (Platform.isMacOS && (e.buttons & kPrimaryMouseButton) != 0 && HardwareKeyboard.instance.isControlPressed));

  static void consume(PointerDownEvent e) => _consumed = e.pointer;
  static bool isConsumed(PointerDownEvent e) => _consumed == e.pointer;
}

/// Hover / drop state handed to an item's visual.
typedef EntryVisualBuilder = Widget Function(BuildContext context, bool hover, bool dropTarget);

/// Mouse semantics shared by every browsing view (FilDOS views):
/// * click selects; ⌘/Ctrl-click toggles; Shift-click selects anchor..item;
/// * double-click opens (the second click still selects first, as in the DOM);
/// * right-click selects the item if it isn't already selected, then shows the
///   menu for the selection;
/// * press-and-move (past [kEntryDragSlop]) drags the selection or the item;
///   folders are drop targets;
/// * clicks are ignored while the item's name is being edited.
///
/// Views can override the click / open / menu actions (column view drills).
class EntryInteractions extends StatefulWidget {
  final FsEntry entry;
  final EntryVisualBuilder builder;
  final bool editing;
  final VoidCallback? onTap;
  final VoidCallback? onActivate;
  final void Function(Offset globalPosition)? onContextMenu;
  const EntryInteractions({
    super.key,
    required this.entry,
    required this.builder,
    this.editing = false,
    this.onTap,
    this.onActivate,
    this.onContextMenu,
  });

  @override
  State<EntryInteractions> createState() => _EntryInteractionsState();
}

class _EntryInteractionsState extends State<EntryInteractions> {
  bool _hover = false;
  DateTime? _lastClick;

  void _setHover(bool v) {
    if (_hover != v && mounted) setState(() => _hover = v);
  }

  void _click() {
    if (widget.editing) return;
    final keys = HardwareKeyboard.instance;
    // On macOS Ctrl-click is a right-click (handled on press), not a toggle.
    if (Platform.isMacOS && keys.isControlPressed && !keys.isMetaPressed) return;
    final ex = context.read<ExplorerController>();
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      ex.select(widget.entry, toggle: keys.isMetaPressed || keys.isControlPressed, range: keys.isShiftPressed);
    }
    final now = DateTime.now();
    final last = _lastClick;
    if (last != null && now.difference(last) <= kDoubleClickTime) {
      _lastClick = null;
      (widget.onActivate ?? () => ex.activate(widget.entry))();
    } else {
      _lastClick = now;
    }
  }

  void _pointerDown(PointerDownEvent e) {
    if (!ContextClick.isContextPress(e) || ContextClick.isConsumed(e)) return;
    ContextClick.consume(e);
    _lastClick = null;
    if (widget.onContextMenu != null) {
      widget.onContextMenu!(e.position);
      return;
    }
    final ex = context.read<ExplorerController>();
    if (!ex.selection.contains(widget.entry.path)) ex.select(widget.entry);
    showEntryMenu(context, widget.entry, e.position);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    Widget visual(bool drop) => MouseRegion(
      // Hover only from a free pointer: during a drag the browser freezes :hover.
      onEnter: (e) => _setHover(e.buttons == 0),
      onHover: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Listener(
        onPointerDown: _pointerDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _click,
          child: widget.builder(context, _hover, drop),
        ),
      ),
    );

    Widget body = entry.isDir
        ? EntryDropZone(folder: entry.path, builder: (context, active) => visual(active))
        : visual(false);
    if (!widget.editing) body = DraggableEntry(entry: entry, child: body);
    return body;
  }
}

/// The empty area of a view (FilDOS scroll container): a click clears the
/// selection, a right-click shows the folder menu, and a drop lands in the
/// current folder.
class PaneBackground extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const PaneBackground({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    return Listener(
      onPointerDown: (e) {
        if (!ContextClick.isContextPress(e) || ContextClick.isConsumed(e)) return;
        ContextClick.consume(e);
        showBackgroundMenu(context, e.position);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // macOS Ctrl-click is a right-click (handled on press), not a click.
          if (Platform.isMacOS && HardwareKeyboard.instance.isControlPressed) return;
          (onTap ?? ex.clearSelection)();
        },
        child: EntryDropZone(folder: ex.current, builder: (context, _) => child),
      ),
    );
  }
}

/// Inline rename field (FilDOS `RenameInput`): focuses with the name stem
/// selected (everything before the last dot, or all of it), Enter or losing
/// focus commits, Esc cancels. Commits only a changed, non-empty name.
class RenameField extends StatefulWidget {
  final FsEntry entry;
  final TextAlign align;
  final double fontSize;

  /// Grid tiles use `border-primary`; list rows `border-foreground/30`.
  final bool strongBorder;
  const RenameField({
    super.key,
    required this.entry,
    this.align = TextAlign.start,
    this.fontSize = 13,
    this.strongBorder = false,
  });

  @override
  State<RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<RenameField> {
  late final TextEditingController _c = TextEditingController(text: widget.entry.name);
  final _focus = FocusNode();
  bool _done = false;
  bool _hadFocus = false;

  /// Whatever had focus before the field (the shell's keyboard scope): it gets
  /// focus back when the field closes so the keyboard map keeps working.
  final FocusNode? _previous = FocusManager.instance.primaryFocus;

  void _restoreFocus() {
    final prev = _previous;
    if (prev != null && prev.context != null && prev.canRequestFocus) prev.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    final name = widget.entry.name;
    final dot = name.lastIndexOf('.');
    _c.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : name.length);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _hadFocus = true;
      } else if (_hadFocus && mounted) {
        _commit();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (_done) return;
    _done = true;
    final ex = context.read<ExplorerController>();
    final name = _c.text.trim();
    if (name.isEmpty || name == widget.entry.name) {
      ex.cancelRename();
    } else {
      ex.commitRename(widget.entry.path, name);
    }
    _restoreFocus();
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    context.read<ExplorerController>().cancelRename();
    _restoreFocus();
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(FaRadius.sm),
      borderSide: BorderSide(color: widget.strongBorder ? c.primary : c.foreground.withValues(alpha: 0.3)),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: TextField(
        controller: _c,
        focusNode: _focus,
        textAlign: widget.align,
        maxLines: 1,
        style: FaText.sans(size: widget.fontSize, color: c.foreground, height: 1.25),
        cursorColor: c.foreground,
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          filled: true,
          fillColor: c.background,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
  }
}
