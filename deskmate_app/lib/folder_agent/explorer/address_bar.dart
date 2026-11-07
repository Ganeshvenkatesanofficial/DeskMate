import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'dnd.dart';

/// FilDOS `AddressBar`: a breadcrumb trail ("/ › Users › name", `gap-0.5`, Mist
/// `›` at 60%) whose crumbs are `rounded-[5px] px-1.5 py-1`, max 200px; the
/// current folder is Ink semibold and inert, the rest Mist with an accent
/// hover. Double-click the bar, press ⌘L, or use the ⌖ button (shown on
/// hover) to type a path; Enter goes there, Esc or blur cancels.
class AddressBar extends StatefulWidget {
  const AddressBar({super.key});
  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  bool _editing = false;
  bool _hover = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final FaController _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<FaController>();
    _app.editAddress.addListener(_startEdit);
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing && mounted) setState(() => _editing = false);
    });
  }

  @override
  void dispose() {
    _app.editAddress.removeListener(_startEdit);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    final current = context.read<ExplorerController>().current;
    if (!mounted || current.isEmpty) return;
    _controller.text = current;
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: current.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _submit(String v) async {
    final ex = context.read<ExplorerController>();
    setState(() => _editing = false);
    final p = v.trim().replaceFirst(RegExp(r'^~'), _app.home);
    if (p.isEmpty || p == ex.current) return;
    final r = await _app.api.info(p);
    if (!r.ok) return _app.toast(r.error?.message ?? 'Couldn’t open that path.', kind: ToastKind.error);
    if (FsEntry.fromJson(r.value!).isDir) {
      await ex.open(p);
    } else {
      _app.toast('That path is a file, not a folder.', kind: ToastKind.error);
    }
  }

  List<(String, String)> _crumbs(String path, String sep) {
    if (path.isEmpty) return const [];
    final out = <(String, String)>[];
    if (path.startsWith('/')) {
      out.add(('/', '/'));
      final parts = path.split('/').where((p) => p.isNotEmpty).toList();
      for (var i = 0; i < parts.length; i++) {
        out.add((parts[i], '/${parts.sublist(0, i + 1).join('/')}'));
      }
    } else {
      final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
      for (var i = 0; i < parts.length; i++) {
        final p = parts.sublist(0, i + 1).join(sep);
        out.add((parts[i], i == 0 ? '$p$sep' : p));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    if (_editing) {
      // `rounded-md border-foreground/30 bg-background px-2 py-1.25` + focus ring.
      return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _editing = false)},
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(FaRadius.md),
            border: Border.all(color: c.foreground.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(color: c.ring, spreadRadius: 3),
              BoxShadow(color: c.card, spreadRadius: 1),
            ],
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            onSubmitted: _submit,
            style: FaText.sans(size: 13, color: c.foreground),
            cursorColor: c.foreground,
            decoration: const InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
              border: InputBorder.none,
            ),
          ),
        ),
      );
    }
    final crumbs = _crumbs(ex.current, _app.sep);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: ex.current,
        waitDuration: const Duration(milliseconds: 1000),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _startEdit,
          child: Align(
            alignment: Alignment.centerLeft,
            // A long path keeps its tail (the current folder) in view.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(width: 2),
                      Text('›', style: FaText.sans(size: 13, color: c.mutedForeground.withValues(alpha: 0.6))),
                      const SizedBox(width: 2),
                    ],
                    _Crumb(label: crumbs[i].$1, path: crumbs[i].$2, last: i == crumbs.length - 1),
                  ],
                  const SizedBox(width: 2),
                  AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: FaMotion.fast,
                    child: Hoverable(
                      onTap: _startEdit,
                      builder: (context, hover) => Tooltip(
                        message: 'Edit path (${shortcutLabel('L')})',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: hover ? c.accent : null,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '⌖',
                            style: FaText.sans(size: 13, color: hover ? c.foreground : c.mutedForeground),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final String path;
  final bool last;
  const _Crumb({required this.label, required this.path, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.read<ExplorerController>();
    final text = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FaText.sans(size: 13, weight: last ? FontWeight.w600 : FontWeight.w400, color: c.foreground),
      ),
    );
    if (last) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: text);
    }
    return EntryDropTarget(
      folder: path,
      child: Hoverable(
        onTap: () => ex.open(path),
        builder: (context, hover) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: hover ? c.accent : null, borderRadius: BorderRadius.circular(5)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FaText.sans(size: 13, color: hover ? c.foreground : c.mutedForeground),
            ),
          ),
        ),
      ),
    );
  }
}
