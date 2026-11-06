import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import 'context_menu.dart';
import 'dnd.dart';

/// Click semantics shared by every view: click selects, ⌘/Ctrl-click toggles,
/// Shift-click extends, double-click opens, right-click shows the menu, and the
/// item is draggable (folders are drop targets).
class EntryInteractions extends StatelessWidget {
  final FsEntry entry;
  final Widget child;
  final BorderRadius radius;
  const EntryInteractions({
    super.key,
    required this.entry,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(FaRadius.md)),
  });

  @override
  Widget build(BuildContext context) {
    final ex = context.read<ExplorerController>();
    Widget body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final keys = HardwareKeyboard.instance;
        ex.select(entry, toggle: keys.isMetaPressed || keys.isControlPressed, range: keys.isShiftPressed);
      },
      onDoubleTap: () => ex.activate(entry),
      onSecondaryTapDown: (d) => showEntryMenu(context, entry, d.globalPosition),
      child: child,
    );
    body = DraggableEntry(entry: entry, child: body);
    if (entry.isDir) body = EntryDropTarget(folder: entry.path, radius: radius, child: body);
    return body;
  }
}

/// Inline rename field: selects the stem, Enter commits, Esc cancels, blur commits.
class RenameField extends StatefulWidget {
  final FsEntry entry;
  final TextAlign align;
  final int maxLines;
  const RenameField({super.key, required this.entry, this.align = TextAlign.start, this.maxLines = 1});

  @override
  State<RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<RenameField> {
  late final TextEditingController _c = TextEditingController(text: widget.entry.name);
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final name = widget.entry.name;
    final dot = widget.entry.isDir ? -1 : name.lastIndexOf('.');
    _c.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : name.length);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    if (_done) return;
    _done = true;
    context.read<ExplorerController>().commitRename(widget.entry.path, _c.text);
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _done = true;
          context.read<ExplorerController>().cancelRename();
        },
      },
      child: TextField(
        controller: _c,
        focusNode: _focus,
        textAlign: widget.align,
        maxLines: widget.maxLines,
        minLines: 1,
        style: FaText.sans(size: 12.5, color: c.foreground),
        cursorColor: c.foreground,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Scoop.blueberry),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Scoop.blueberry, width: 1.5),
          ),
        ),
      ),
    );
  }
}
