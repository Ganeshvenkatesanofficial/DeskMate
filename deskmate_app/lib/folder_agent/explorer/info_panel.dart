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

/// Right-hand Info panel (FilDOS InfoPanel): details of the primary selection,
/// or of the folder in view when nothing is selected; a summary for a
/// multi-selection.
class InfoPanel extends StatefulWidget {
  const InfoPanel({super.key});

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  Timer? _debounce;
  int _gen = 0;

  /// The path the loaded details below belong to.
  String? _path;
  FsEntry? _info;
  int? _childCount;
  bool _writable = true;
  String? _error;
  List<int>? _tags;

  /// Recursive folder size: null while computing.
  int? _folderBytes;
  bool _folderComplete = true;
  bool _sizing = false;

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
    _info = null;
    _childCount = null;
    _error = null;
    _tags = null;
    _folderBytes = null;
    _sizing = false;
    _writable = true;
    _debounce = Timer(const Duration(milliseconds: 160), () => _load(path, gen));
  }

  Future<void> _load(String path, int gen) async {
    final api = context.read<FaController>().api;
    final infoF = api.info(path);
    final tagsF = api.tagsForPaths([path]);
    final infoR = await infoF;
    final tagsR = await tagsF;
    if (!mounted || gen != _gen) return;
    final info = infoR.value;
    final tags = tagsR.value;
    setState(() {
      if (info != null) {
        _info = FsEntry.fromJson(info);
        _childCount = (info['childCount'] as num?)?.toInt();
        _writable = info['writable'] != false;
      } else {
        _error = infoR.error?.message ?? 'Couldn\'t read this item.';
      }
      _tags = tags?[path] ?? const [];
      _sizing = _info?.isDir ?? false;
    });
    if (_info?.isDir ?? false) {
      final r = await api.folderSize(path);
      if (!mounted || gen != _gen) return;
      setState(() {
        _sizing = false;
        if (r.ok) {
          _folderBytes = (r.value!['size'] as num?)?.toInt() ?? 0;
          _folderComplete = r.value!['complete'] != false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ex = context.watch<ExplorerController>();
    final app = context.watch<FaController>();
    final selected = ex.selectedEntries;

    Widget body;
    if (selected.length > 1) {
      body = _MultiInfo(entries: selected);
    } else {
      final target = selected.isEmpty ? ex.current : selected.first.path;
      if (target.isEmpty) {
        body = const SizedBox.shrink();
      } else {
        _schedule(target);
        body = _single(context, app, ex, target, selected.isEmpty ? null : selected.first);
      }
    }

    return ColoredBox(
      color: c.background,
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 24), child: body),
    );
  }

  Widget _single(BuildContext context, FaController app, ExplorerController ex, String path, FsEntry? known) {
    final c = context.fa;
    final e = _info ?? known;
    if (e == null) {
      if (_error != null) {
        return Text(_error!, style: FaText.sans(size: 12.5, color: c.destructive));
      }
      return const Padding(padding: EdgeInsets.only(top: 40), child: XLoading());
    }
    final tags = ex.tagsByPath[path] ?? _tags ?? const [];
    final noAi = hiddenFromAi(app, path);

    String sizeText;
    if (!e.isDir) {
      sizeText = formatBytes(e.size);
    } else if (_folderBytes != null) {
      sizeText = '${_folderComplete ? '' : '≈ '}${formatBytes(_folderBytes!)}';
    } else {
      sizeText = _sizing ? 'Calculating…' : '--';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero: thumbnail / icon + name + kind.
        Container(
          height: 150,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(FaRadius.lg),
          ),
          padding: const EdgeInsets.all(12),
          child: FileIcon.entry(e, size: e.hasThumbnail ? 126 : 72, thumbnail: true),
        ),
        const SizedBox(height: 14),
        SelectableText(
          e.name,
          textAlign: TextAlign.center,
          style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground, height: 1.3),
        ),
        const SizedBox(height: 3),
        Text(
          known == null ? 'Current folder · ${kindLabel(e.kind, e.ext)}' : kindLabel(e.kind, e.ext),
          textAlign: TextAlign.center,
          style: FaText.sans(size: 12, color: c.mutedForeground),
        ),
        if (noAi || !_writable) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (noAi) _Badge(icon: Icons.visibility_off_outlined, label: 'Hidden from AI'),
              if (!_writable) _Badge(icon: Icons.lock_outline_rounded, label: 'Read only'),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _Section('Tags'),
        if (tags.isEmpty)
          Text('No tags', style: FaText.sans(size: 12, color: c.mutedForeground))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in tags)
                for (final t in app.tags.where((t) => t.id == id))
                  FaChip(
                    label: t.name,
                    dot: Scoop.parse(t.color),
                    onTap: () => app.showSection(FaSection.tag, tagId: t.id),
                  ),
            ],
          ),
        const SizedBox(height: 16),
        _Section('Details'),
        Row(
          children: [
            Expanded(child: MetaRow('Size', sizeText)),
            if (_sizing)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
              ),
          ],
        ),
        if (e.isDir && _childCount != null) MetaRow('Contains', _childCount == 1 ? '1 item' : '$_childCount items'),
        MetaRow('Created', formatDate(e.ctime)),
        MetaRow('Modified', formatDate(e.mtime)),
        if (e.isSymlink) const MetaRow('Link', 'Symbolic link'),
        const SizedBox(height: 16),
        _Section(
          'Where',
          trailing: FaIconButton(
            icon: Icons.copy_rounded,
            size: 22,
            tooltip: 'Copy path',
            onPressed: () => copyPathToClipboard(app, path),
          ),
        ),
        SelectableText(path, style: FaText.mono(size: 11, color: c.foreground, height: 1.5)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FaButton(
                label: revealLabel(app),
                icon: Icons.folder_open_outlined,
                dense: true,
                expand: true,
                variant: FaButtonVariant.outline,
                onPressed: () => ex.reveal(path),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: noAi ? 'Hidden from AI' : 'Ask AI about this',
              child: FaIconButton(
                icon: Icons.auto_awesome_rounded,
                color: Scoop.mint,
                onPressed: noAi ? null : () => app.askAiAbout([path]),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MultiInfo extends StatelessWidget {
  final List<FsEntry> entries;
  const _MultiInfo({required this.entries});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    final files = entries.where((e) => !e.isDir).toList();
    final folders = entries.length - files.length;
    final total = files.fold<int>(0, (s, e) => s + e.size);
    final kinds = <String, int>{};
    for (final e in entries) {
      final k = kindLabel(e.kind, e.ext);
      kinds[k] = (kinds[k] ?? 0) + 1;
    }
    final preview = entries.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(FaRadius.lg),
          ),
          child: Center(
            child: SizedBox(
              width: 120,
              height: 100,
              child: Stack(
                children: [
                  for (var i = preview.length - 1; i >= 0; i--)
                    Positioned(
                      left: 18.0 + i * 14,
                      top: 10.0 + i * 6,
                      child: FileIcon.entry(preview[i], size: 56, thumbnail: true),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Multiple selection',
          textAlign: TextAlign.center,
          style: FaText.sans(size: 14, weight: FontWeight.w600, color: c.foreground),
        ),
        const SizedBox(height: 3),
        Text(
          '${entries.length} items · ${formatBytes(total)}${folders > 0 ? ' + $folders folder${folders == 1 ? '' : 's'}' : ''}',
          textAlign: TextAlign.center,
          style: FaText.sans(size: 12, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        _Section('Kinds'),
        for (final k in kinds.entries) MetaRow(k.key, '${k.value}'),
        const SizedBox(height: 16),
        _Section('Selected'),
        for (final e in entries.take(12))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                FileIcon.entry(e, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: FaText.sans(size: 12, color: c.foreground),
                  ),
                ),
              ],
            ),
          ),
        if (entries.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('and ${entries.length - 12} more', style: FaText.sans(size: 11.5, color: c.mutedForeground)),
          ),
        const SizedBox(height: 18),
        FaButton(
          label: 'Ask AI about ${entries.length} items',
          leading: const Icon(Icons.auto_awesome_rounded, size: 14, color: Scoop.mint),
          dense: true,
          expand: true,
          variant: FaButtonVariant.outline,
          onPressed: () => app.askAiAbout(entries.map((e) => e.path).toList()),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _Section(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: FaText.label(context.fa))),
        ?trailing,
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c.mutedForeground),
          const SizedBox(width: 5),
          Text(label, style: FaText.sans(size: 11.5, color: c.mutedForeground)),
        ],
      ),
    );
  }
}
