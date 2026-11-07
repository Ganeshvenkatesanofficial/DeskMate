import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';

/// Small helpers shared by the column / gallery / info / recents / tag views.

// ── FilDOS view tokens (shared by the grid / list / column / gallery views) ──

/// `hover:bg-accent`.
Color fdHover(FaColors c) => c.accent;

/// `bg-primary/15` — the selection wash.
Color fdSelected(FaColors c) => c.selection;

/// `ring-primary/40` — selected grid tile ring and drop-target ring.
Color fdRing(FaColors c) => c.primary.withValues(alpha: 0.4);

/// `opacity-55` on hidden (dot) files.
const double kFdHiddenOpacity = 0.55;

/// FilDOS `TagDots`: up to [max] coloured dots (3px apart) and a "+N" overflow.
class TagDotsRow extends StatelessWidget {
  final List<int> tagIds;
  final int max;
  final double dotSize;
  const TagDotsRow(this.tagIds, {super.key, this.max = 3, this.dotSize = 9});

  @override
  Widget build(BuildContext context) {
    if (tagIds.isEmpty) return const SizedBox.shrink();
    final c = context.fa;
    final app = context.read<FaController>();
    final names = <String>[];
    final colors = <Color>[];
    for (final id in tagIds) {
      for (final t in app.tags) {
        if (t.id == id) {
          names.add(t.name);
          colors.add(Scoop.parse(t.color));
          break;
        }
      }
    }
    if (colors.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: names.join(', '),
      waitDuration: const Duration(milliseconds: 600),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < colors.length && i < max; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            ScoopDot(colors[i], size: dotSize),
          ],
          if (colors.length > max) ...[
            const SizedBox(width: 3),
            Text('+${colors.length - max}', style: FaText.sans(size: 10, color: c.mutedForeground)),
          ],
        ],
      ),
    );
  }
}

/// Navigates the explorer to [path]'s folder and selects it there.
Future<void> showInFolder(ExplorerController ex, String path) async {
  await ex.open(parentDir(path));
  for (final e in ex.entries) {
    if (e.path == path) {
      ex.select(e);
      break;
    }
  }
}

/// True when [path] (or one of its ancestors) is excluded from AI.
bool hiddenFromAi(FaController app, String path) =>
    app.excludes.any((x) => path == x || path.startsWith(x.endsWith('/') ? x : '$x/'));
