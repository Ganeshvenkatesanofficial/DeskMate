import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'dnd.dart';

/// Breadcrumb path ("/ › Users › name"); click a crumb to go there, double-click
/// the empty area to type a path.
class AddressBar extends StatefulWidget {
  const AddressBar({super.key});
  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  bool _editing = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    final app = context.read<FaController>();
    if (_editing) {
      return SizedBox(
        height: 30,
        child: FaTextField(
          controller: _controller,
          autofocus: true,
          dense: true,
          mono: true,
          onSubmitted: (v) {
            setState(() => _editing = false);
            final target = v.trim().replaceFirst(RegExp(r'^~'), app.home);
            if (target.isNotEmpty) ex.open(target);
          },
        ),
      );
    }
    final crumbs = _crumbs(ex.current, app.sep);
    return GestureDetector(
      onDoubleTap: () {
        _controller.text = ex.current;
        setState(() => _editing = true);
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              if (i > 0) Icon(Icons.chevron_right_rounded, size: 14, color: c.mutedForeground.withValues(alpha: 0.7)),
              EntryDropTarget(
                folder: crumbs[i].$2,
                child: Hoverable(
                  onTap: () => ex.open(crumbs[i].$2),
                  builder: (context, hover) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: hover ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(FaRadius.sm),
                    ),
                    child: Text(
                      crumbs[i].$1,
                      style: FaText.sans(
                        size: 13,
                        weight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.w400,
                        color: i == crumbs.length - 1 ? c.foreground : c.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
