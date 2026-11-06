import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';

/// Small helpers shared by the column / gallery / info / recents / tag views.

final _chunks = RegExp(r'(\d+)|(\D+)');

/// Natural, case-insensitive compare ("file2" < "file10").
int naturalCompare(String a, String b) {
  final ma = _chunks.allMatches(a.toLowerCase()).toList();
  final mb = _chunks.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < ma.length && i < mb.length; i++) {
    final x = ma[i].group(0)!, y = mb[i].group(0)!;
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ma.length.compareTo(mb.length);
}

/// Folders first, then natural name order.
List<FsEntry> sortFoldersFirst(Iterable<FsEntry> entries) {
  final list = List<FsEntry>.from(entries);
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return naturalCompare(a.name, b.name);
  });
  return list;
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

void copyPathToClipboard(FaController app, String path) {
  Clipboard.setData(ClipboardData(text: path));
  app.toast('Copied path');
}

String revealLabel(FaController app) => 'Show in ${app.isMac ? 'Finder' : 'File Manager'}';

/// "Label ............ value" metadata row (uppercase muted label).
class MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const MetaRow(this.label, this.value, {super.key, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.7))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: FaText.label(c).copyWith(fontSize: 9.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: mono ? FaText.mono(size: 11, color: c.foreground) : FaText.sans(size: 12, color: c.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered icon + title + body (+ optional action) for empty / error states.
class XEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const XEmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: c.mutedForeground),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: FaText.sans(size: 12.5, color: c.mutedForeground, height: 1.45),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Indeterminate loading bar, centered.
class XLoading extends StatelessWidget {
  const XLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: SizedBox(width: 120, child: FaProgressBar()));
}
