import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

/// Folders first, then name order (FilDOS `sortEntries` with the default
/// Name ▲ sort: case-insensitive).
List<FsEntry> sortFoldersFirst(Iterable<FsEntry> entries) {
  final list = List<FsEntry>.from(entries);
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    final r = ExplorerController.compareNames(a.name, b.name);
    return r != 0 ? r : a.name.compareTo(b.name);
  });
  return list;
}

// ── FilDOS view tokens (shared by the grid / list / column / gallery views) ──

/// `hover:bg-accent`.
Color fdHover(FaColors c) => c.accent;

/// `bg-primary/15` — the selection wash.
Color fdSelected(FaColors c) => c.selection;

/// `ring-primary/40` — selected grid tile ring and drop-target ring.
Color fdRing(FaColors c) => c.primary.withValues(alpha: 0.4);

/// `opacity-55` on hidden (dot) files.
const double kFdHiddenOpacity = 0.55;

/// FilDOS `typeLabel`: "Folder", "Alias", "PNG file", "File".
String typeLabel(FsEntry e) {
  if (e.isDir) return 'Folder';
  if (e.isSymlink) return 'Alias';
  return e.ext.isNotEmpty ? '${e.ext.toUpperCase()} file' : 'File';
}

/// FilDOS `formatSize`: binary units, one decimal ("0 B", "12.4 KB").
String fdFormatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  if (i == 0) return '$bytes B';
  final r = (v * 10).round() / 10;
  return '${r == r.roundToDouble() ? r.toInt() : r} ${units[i]}';
}

final _fdDate = DateFormat('MMM d, y, h:mm a');

/// FilDOS `formatDate`: "Jun 8, 2026, 9:04 AM" ("—" when unknown).
String fdFormatDate(DateTime d) => d.millisecondsSinceEpoch == 0 ? '—' : _fdDate.format(d);

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
