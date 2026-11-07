import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';
import 'x_common.dart';

/// Right-hand Info panel (FilDOS `InfoPanel`): an "Info" header, the item's
/// preview (or type logo) and name, its tags, then labelled rows — Type, Size,
/// Where · Created, Modified · … — for the primary selection, or the folder in
/// view when nothing is selected; a short summary for a multi-selection.
///
/// FilDOS sizes it `w-70` (280px) on `bg-card` with a left hairline; the host
/// draws the hairline and passes [onClose] for the header's close button.
class InfoPanel extends StatefulWidget {
  final VoidCallback? onClose;
  const InfoPanel({super.key, this.onClose});

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  Timer? _debounce;
  int _gen = 0;

  /// The path the loaded details below belong to.
  String? _path;
  Map<String, dynamic>? _raw;
  FsEntry? _info;
  String? _error;

  /// Recursive folder size: null while computing.
  int? _folderBytes;
  bool _folderComplete = true;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule(String path) {
    if (path == _path) return;
    _path = path;
    _debounce?.cancel();
    final gen = ++_gen;
    // Reset synchronously so stale details never show for the new target.
    _raw = null;
    _info = null;
    _error = null;
    _folderBytes = null;
    _folderComplete = true;
    _debounce = Timer(const Duration(milliseconds: 120), () => _load(path, gen));
  }

  Future<void> _load(String path, int gen) async {
    final api = context.read<FaController>().api;
    final r = await api.info(path);
    if (!mounted || gen != _gen) return;
    setState(() {
      if (r.ok) {
        _raw = r.value;
        _info = FsEntry.fromJson(r.value!);
      } else {
        _error = r.error?.message ?? 'Couldn’t read this item.';
      }
    });
    // For folders, compute the recursive size in the background.
    if (_info?.isDir ?? false) {
      final s = await api.folderSize(path);
      if (!mounted || gen != _gen || !s.ok) return;
      setState(() {
        _folderBytes = (s.value!['size'] as num?)?.toInt() ?? 0;
        _folderComplete = s.value!['complete'] != false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final app = context.watch<FaController>();
    final selected = ex.selectedEntries;

    Widget? body;
    if (selected.length > 1) {
      body = _MultiInfo(entries: selected);
    } else {
      final target = selected.isEmpty ? ex.current : selected.first.path;
      if (target.isNotEmpty) {
        _schedule(target);
        body = _single(context, app, ex, target, selected.isEmpty ? null : selected.first);
      }
    }

    return ColoredBox(
      color: c.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(c),
          Expanded(
            child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
          ),
        ],
      ),
    );
  }

  /// border-b px-3 py-2.5 text-sm font-semibold "Info" + a ghost size-8 close button.
  Widget _header(FaColors c) => Container(
    height: 53,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: c.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Info',
            style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
          ),
        ),
        if (widget.onClose != null)
          Tooltip(
            message: 'Close info',
            child: Hoverable(
              cursor: SystemMouseCursors.basic,
              onTap: widget.onClose,
              builder: (context, hover) => AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.foreground.withValues(alpha: hover ? 0.09 : 0),
                  borderRadius: BorderRadius.circular(FaRadius.sm),
                ),
                child: Icon(Icons.close_rounded, size: 14, color: hover ? c.foreground : c.mutedForeground),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _single(BuildContext context, FaController app, ExplorerController ex, String path, FsEntry? known) {
    final c = context.fa;
    final e = _info ?? known;
    if (e == null) {
      if (_error != null) {
        return Text(_error!, style: FaText.sans(size: 13, color: c.destructive));
      }
      return const SizedBox.shrink();
    }

    final String size;
    if (!e.isDir) {
      size = formatBytes(e.size);
    } else if (_folderBytes != null) {
      size = '${_folderComplete ? '' : '≈ '}${formatBytes(_folderBytes!)}';
    } else {
      size = 'Calculating…';
    }
    final accessed = _date(_raw?['atime']);
    final permissions = _raw?['permissions'] as String?;
    final mode = (_raw?['mode'] as num?)?.toInt();
    final linksTo = _raw?['realPath'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview (or type logo) and name: items-center gap-2.5 pt-2 pb-4.5.
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 18),
          child: Column(
            children: [
              _Hero(entry: e),
              const SizedBox(height: 10),
              Tooltip(
                message: e.name,
                waitDuration: const Duration(milliseconds: 800),
                child: SelectableText(
                  e.name,
                  textAlign: TextAlign.center,
                  style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground, height: 20 / 14),
                ),
              ),
            ],
          ),
        ),
        _TagsRow(path: path),
        _Row('Type', _typeLabel(e)),
        _Row('Size', size),
        _Row('Where', path, mono: true),
        if (linksTo != null) _Row('Links to', linksTo, mono: true),
        if (hiddenFromAi(app, path)) const _Row('AI', 'Hidden from AI'),
        const _Rule(),
        _Row('Created', formatDate(e.ctime)),
        _Row('Modified', formatDate(e.mtime)),
        if (accessed != null) _Row('Accessed', formatDate(accessed)),
        if (permissions != null) ...[
          const _Rule(),
          _Row('Permissions', mode == null ? permissions : '$permissions (${mode.toRadixString(8)})', mono: true),
        ],
      ],
    );
  }
}

DateTime? _date(Object? seconds) =>
    seconds is num ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()) : null;

/// FilDOS `typeLabel`: Folder, Alias, "PDF file", File.
String _typeLabel(FsEntry e) {
  if (e.isDir) return 'Folder';
  if (e.isSymlink) return 'Alias';
  return e.ext.isEmpty ? 'File' : '${e.ext.toUpperCase()} file';
}

/// A live preview (max-h-32 rounded-md object-contain) for previewable files, else the 40px type logo.
class _Hero extends StatelessWidget {
  final FsEntry entry;
  const _Hero({required this.entry});

  @override
  Widget build(BuildContext context) {
    final logo = FileIcon.entry(entry, size: 40);
    if (!canPreview(isDir: entry.isDir, ext: entry.ext)) return logo;
    final api = context.read<FaController>().api;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 128),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FaRadius.md),
        child: Image.network(
          api.thumbnailUrl(entry.path, size: 256, mtime: entry.mtime),
          key: ValueKey(entry.path),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          // The logo holds the space until the thumbnail has decoded (and stays if none can be made).
          frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : logo,
          errorBuilder: (_, _, _) => logo,
        ),
      ),
    );
  }
}

/// mb-2.5; a 10px semibold tracking-wider uppercase muted label over a selectable value.
class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _Row(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: mono
                ? FaText.mono(size: 12, color: c.foreground, height: 16 / 12)
                : FaText.sans(size: 13, color: c.foreground, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: FaText.sans(
      size: 10,
      weight: FontWeight.w600,
      color: context.fa.mutedForeground,
      letterSpacing: 0.5,
      height: 1.5,
    ),
  );
}

/// bg-border my-3 h-px.
class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: context.fa.border);
}

/// Tag chips with a picker to attach any not-yet-applied tag; hidden when there are no tags at all.
class _TagsRow extends StatelessWidget {
  final String path;
  const _TagsRow({required this.path});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final ids = ex.tagsByPath[path] ?? const <int>[];
    final attached = [
      for (final t in app.tags)
        if (ids.contains(t.id)) t,
    ];
    final addable = [
      for (final t in app.tags)
        if (!ids.contains(t.id)) t,
    ];
    if (attached.isEmpty && addable.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Tags'),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final t in attached)
                _TagChip(
                  children: [
                    ScoopDot(Scoop.parse(t.color), size: 9),
                    const SizedBox(width: 6),
                    Text(t.name, style: FaText.sans(size: 11, color: c.foreground)),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Remove “${t.name}”',
                      child: Hoverable(
                        cursor: SystemMouseCursors.basic,
                        onTap: () => ex.toggleTag(t, [path]),
                        builder: (context, hover) =>
                            Icon(Icons.close_rounded, size: 10, color: hover ? c.destructive : c.mutedForeground),
                      ),
                    ),
                  ],
                ),
              if (addable.isNotEmpty)
                Builder(
                  builder: (anchor) => Hoverable(
                    cursor: SystemMouseCursors.basic,
                    onTap: () {
                      final box = anchor.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      showFaMenu(anchor, box.localToGlobal(Offset(0, box.size.height + 4)), [
                        for (final t in addable)
                          FaMenuItem(
                            t.name,
                            leading: ScoopDot(Scoop.parse(t.color), size: 9),
                            onTap: () => ex.toggleTag(t, [path]),
                          ),
                      ]);
                    },
                    builder: (context, hover) => _TagChip(
                      border: hover ? c.foreground.withValues(alpha: 0.4) : null,
                      children: [
                        Text('+ Add', style: FaText.sans(size: 11, color: hover ? c.foreground : c.mutedForeground)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// rounded-full border bg-background px-1.5 py-0.5 text-2xs.
class _TagChip extends StatelessWidget {
  final List<Widget> children;
  final Color? border;
  const _TagChip({required this.children, this.border});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border ?? c.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Several items selected (FilDOS shows one path at a time; DeskMate sums the
/// selection in the same row style).
class _MultiInfo extends StatelessWidget {
  final List<FsEntry> entries;
  const _MultiInfo({required this.entries});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final files = entries.where((e) => !e.isDir).toList();
    final folders = entries.length - files.length;
    final total = files.fold<int>(0, (s, e) => s + e.size);
    final kinds = <String, int>{};
    for (final e in entries) {
      final k = _typeLabel(e);
      kinds[k] = (kinds[k] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 18),
          child: Column(
            children: [
              SizedBox(
                width: 64,
                height: 40,
                child: Stack(
                  children: [
                    // The first item on top, the next two peeking out to the right.
                    for (var i = entries.length.clamp(0, 3) - 1; i >= 0; i--)
                      Positioned(left: i * 12.0, top: 0, child: FileIcon.entry(entries[i], size: 40)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${entries.length} items',
                textAlign: TextAlign.center,
                style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground, height: 20 / 14),
              ),
            ],
          ),
        ),
        _Row('Size', '${formatBytes(total)}${folders > 0 ? ' + $folders folder${folders == 1 ? '' : 's'}' : ''}'),
        const _Rule(),
        for (final k in kinds.entries) _Row(k.key, k.value == 1 ? '1 item' : '${k.value} items'),
      ],
    );
  }
}
