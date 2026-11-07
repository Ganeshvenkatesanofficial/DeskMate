import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../shell/pane_header.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';
import 'model_widgets.dart';
import 'settings_widgets.dart';

/// FilDOS's four Settings pages — model management gets its own tab.
enum _Tab { general, search, assistant, privacy }

const _tabs = [
  (_Tab.general, 'General', Icons.light_mode_outlined),
  (_Tab.search, 'Searching', Icons.search_rounded),
  (_Tab.assistant, 'Ask AI', Icons.auto_awesome_outlined),
  (_Tab.privacy, 'Privacy', Icons.visibility_off_outlined),
];

/// Folder Agent settings (port of FilDOS SettingsView): a `max-w-2xl px-8
/// py-10` column — "Settings" heading, an underlined page-tab nav, then the
/// tab's Section cards `gap-5`. Escape goes back to the browser.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  _Tab _tab = _Tab.general;

  @override
  void initState() {
    super.initState();
    final app = context.read<FaController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      app.refreshAi();
      app.refreshIndex();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    context.read<FaController>().showSection(FaSection.browse);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: c.background,
        child: Column(
          children: [
            PaneHeader.simple(icon: Icons.settings_outlined, label: 'Settings'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 672),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Settings',
                          style: FaText.sans(size: 20, weight: FontWeight.w500, color: c.foreground),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Configure Folder Agent. AI features run on your machine by default.',
                          style: FaText.sans(size: 14, color: c.mutedForeground),
                        ),
                        const SizedBox(height: 24),
                        _TabBar(selected: _tab, onSelect: (t) => setState(() => _tab = t)),
                        const SizedBox(height: 24),
                        KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            _Tab.general => const _GeneralTab(),
                            _Tab.search => const _SearchTab(),
                            _Tab.assistant => const _AssistantTab(),
                            _Tab.privacy => const _PrivacyTab(),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `border-b` nav, `gap-6`; each tab `-mb-px border-b-2 pb-2.5 text-sm` with a
/// 14px icon — foreground + Ink underline when selected.
class _TabBar extends StatelessWidget {
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;
  const _TabBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Stack(
      children: [
        Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: c.border)),
        Row(
          children: [
            for (final (tab, label, icon) in _tabs)
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Hoverable(
                  onTap: () => onSelect(tab),
                  builder: (context, hover) {
                    final active = tab == selected;
                    final fg = active || hover ? c.foreground : c.mutedForeground;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: active ? c.foreground : Colors.transparent, width: 2)),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 14, color: fg),
                          const SizedBox(width: 6),
                          Text(label, style: FaText.sans(size: 14, color: fg)),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Widget _gap(List<Widget> children) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 20), children[i]],
  ],
);

// ── General ────────────────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  const _GeneralTab();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    return _gap([
      SettingsCard(
        icon: Icons.light_mode_outlined,
        title: 'Appearance',
        subtitle: 'Theme and how folders are listed',
        children: [
          const ThemePicker(compact: true),
          SettingRow(
            boxed: false,
            title: 'Show hidden files',
            description: 'Include dotfiles and hidden folders in the browser',
            trailing: FaSwitch(value: app.showHidden, onChanged: (v) => app.setPrefs({'showHidden': v})),
          ),
        ],
      ),
      SettingsCard(
        icon: Icons.info_outline_rounded,
        title: 'About',
        subtitle: 'Setup and release information',
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(FaRadius.xl),
                    border: Border.all(color: c.border.withValues(alpha: 0.6)),
                  ),
                  child: const Center(child: DeskMateMark(size: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DeskMateWordmark(size: 16),
                      Text(
                        'Folder Agent · AI-native file explorer',
                        style: FaText.sans(size: 11, color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _LinkRow(
                label: 'Replay onboarding',
                description: 'Walk through setup again — theme, folders, AI and privacy',
                icon: Icons.replay_rounded,
                onTap: () => app.setPrefs({'onboarded': false}),
              ),
              const _LinkRow(
                label: 'Design credits',
                description: 'File explorer design adapted from FilDOS (MIT)',
                icon: Icons.favorite_border_rounded,
              ),
            ],
          ),
        ],
      ),
    ]);
  }
}

/// FilDOS About link row: `-mx-2 px-2 py-2 rounded-lg hover:bg-accent`.
class _LinkRow extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  const _LinkRow({required this.label, required this.description, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    // `-mx-2`: the hover wash bleeds 8px past the card's content edge.
    return Hoverable(
      onTap: onTap,
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, hover) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -8,
            right: -8,
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: hover && onTap != null ? c.accent : c.accent.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(FaRadius.lg),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: FaText.sans(size: 14, color: c.foreground)),
                      Text(description, style: FaText.sans(size: 11, color: c.mutedForeground)),
                    ],
                  ),
                ),
                Icon(icon, size: 13, color: hover && onTap != null ? c.foreground : c.mutedForeground),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Searching ──────────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  const _SearchTab();

  Future<void> _run(FaController app, Future<Result<IndexStatus>> Function() call) async {
    final r = await call();
    if (!r.ok) app.toastError(r.error);
    await app.refreshIndex();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final on = app.aiEnabled;
    final ix = app.index;
    final running = ix.state == 'scanning' || ix.state == 'indexing' || ix.state == 'waiting-model';
    final modelReady = app.ai?.embedder.state == 'ready';
    return _gap([
      SettingsCard(
        icon: Icons.auto_awesome_outlined,
        mint: true,
        title: 'Embeddings',
        subtitle: 'On-device models that power semantic search',
        action: FaSwitch(
          value: on,
          onChanged: (v) async {
            await app.setPrefs({'aiEnabled': v});
            final s = app.ai?.embedder.state;
            if (v && s != 'ready' && s != 'downloading') await startEmbedderDownload(app);
          },
        ),
        children: [
          IgnorePointer(
            ignoring: !on,
            child: Opacity(
              opacity: on ? 1 : 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EmbedderCard(),
                  const SizedBox(height: 4),
                  Text(
                    'Downloads automatically when embeddings are enabled.',
                    style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.375),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      SettingsCard(
        icon: Icons.search_rounded,
        title: 'Indexing',
        subtitle: 'Builds the search index from your files in the background',
        disabled: !on,
        action: running
            ? SmallButton(
                label: 'Pause',
                variant: FaButtonVariant.secondary,
                onPressed: () => _run(app, app.api.indexPause),
              )
            : Tooltip(
                message: !modelReady
                    ? 'Download the model first'
                    : app.indexRoots.isEmpty
                    ? 'Add a folder to index first'
                    : '',
                child: SmallButton(
                  label: 'Start',
                  onPressed: modelReady && app.indexRoots.isNotEmpty ? () => _run(app, app.api.indexStart) : null,
                ),
              ),
        children: [
          _IndexProgress(ix: ix),
          const _FoldersRow(),
          if (!running) const _EstimateRow(),
          const SkipTypesRow(),
          Align(
            alignment: Alignment.centerLeft,
            child: _TextLink(
              label: 'Clear index',
              onTap: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Clear the index?',
                  message: 'Everything Folder Agent has indexed is removed. Press Start to read your folders again.',
                  confirm: 'Clear index',
                  danger: true,
                );
                if (ok) await _run(app, app.api.indexClear);
              },
            ),
          ),
        ],
      ),
      SettingsCard(
        icon: Icons.psychology_outlined,
        mint: true,
        title: 'Canvas',
        subtitle: 'The knowledge graph behind the Canvas view — connections by meaning, entities and time',
        disabled: !on,
        action: Tooltip(
          message: 'Recompute similarity edges and entities from scratch',
          child: SmallButton(
            label: 'Rebuild',
            variant: FaButtonVariant.secondary,
            onPressed: () async {
              final r = await app.api.buildGraph();
              if (!r.ok) app.toastError(r.error);
            },
          ),
        ),
        children: [
          Text(
            'The Canvas maps similarity, tags, people and places, and work sessions straight from the index. '
            'It updates after indexing; rebuild after large changes to your folders.',
            style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.375),
          ),
        ],
      ),
    ]);
  }
}

class _TextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TextLink({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => Text(
        label,
        style: FaText.sans(
          size: 11,
          color: hover ? c.foreground : c.mutedForeground,
        ).copyWith(decoration: hover ? TextDecoration.underline : null, decorationColor: c.foreground),
      ),
    );
  }
}

/// FilDOS index progress box: title text-sm, subtitle text-2xs, the failed
/// count on the right, and (while running) an h-1 bar plus the current file.
class _IndexProgress extends StatelessWidget {
  final IndexStatus ix;
  const _IndexProgress({required this.ix});

  static String _verb(String? file) {
    final ext = (file ?? '').contains('.') ? file!.split('.').last.toLowerCase() : '';
    if (ext == 'pdf') return 'Parsing PDF';
    if (const ['md', 'mdx', 'rst', 'txt'].contains(ext)) return 'Reading document';
    if (const ['ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs'].contains(ext)) return 'Embedding TypeScript';
    if (ext == 'py') return 'Embedding Python';
    if (const ['go', 'rs', 'java', 'cpp', 'c', 'cs', 'swift', 'rb', 'kt', 'dart'].contains(ext)) {
      return 'Embedding source code';
    }
    if (const ['json', 'yaml', 'yml', 'toml'].contains(ext)) return 'Indexing config';
    if (const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'avif'].contains(ext)) return 'Encoding image';
    return 'Building search vectors';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final (title, sub) = switch (ix.state) {
      'scanning' => ('Walking the file tree…', ix.total > 0 ? '${formatCount(ix.total)} files found' : null),
      'indexing' => ('${_verb(ix.current)}…', '${formatCount(ix.done)} / ${formatCount(ix.total)} files'),
      'waiting-model' => ('Waiting for the search model…', 'Indexing starts as soon as it has downloaded'),
      'paused' => ('Paused', ix.total > 0 ? '${formatCount(ix.done)} of ${formatCount(ix.total)} done' : null),
      'error' => (
        ix.error ?? 'Indexing failed',
        ix.failed > 0 ? '${ix.failed} file${ix.failed == 1 ? '' : 's'} failed' : null,
      ),
      _ => (
        'Idle',
        ix.indexed > 0 ? '${formatCount(ix.indexed)} files in the index' : 'No files indexed yet — press Start',
      ),
    };
    final running = ix.state == 'scanning' || ix.state == 'indexing';
    final pct = ix.total > 0 ? (ix.done / ix.total).clamp(0.0, 1.0) : 0.0;
    return RowBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: FaText.sans(size: 14, color: c.foreground)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: FaText.sans(size: 11, color: c.mutedForeground)),
                    ],
                  ],
                ),
              ),
              if (ix.failed > 0 && ix.state != 'error')
                Tooltip(
                  message: 'Files that couldn\'t be indexed. They retry on the next scan.',
                  child: Text('${ix.failed} failed', style: FaText.sans(size: 11, color: c.mutedForeground)),
                ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 8),
            ThinBar(value: pct),
            if (ix.current != null) ...[
              const SizedBox(height: 6),
              Text(
                ix.current!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FaText.mono(size: 10, color: c.mutedForeground),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// DeskMate's indexed folders (FilDOS indexes the whole home): the roots as
/// path rows, with Add.
class _FoldersRow extends StatelessWidget {
  const _FoldersRow();

  Future<void> _setRoots(FaController app, List<String> roots) async {
    final r = await app.api.setIndexRoots(roots);
    if (!r.ok) return app.toastError(r.error);
    await Future.wait([app.refreshPrefs(), app.refreshIndex()]);
  }

  Future<void> _add(FaController app) async {
    final r = await app.api.pickFolders(prompt: 'Choose folders for DeskMate to index');
    if (!r.ok) return app.toastError(r.error);
    if (r.value!.isEmpty) return;
    await _setRoots(app, {...app.indexRoots, ...r.value!}.toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final roots = app.indexRoots;
    return RowBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Folders to index', style: FaText.sans(size: 14, color: c.foreground)),
                    Text(
                      'Only these are read for search, Ask AI and Canvas',
                      style: FaText.sans(size: 11, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SmallButton(
                label: 'Add',
                icon: Icons.add_rounded,
                variant: FaButtonVariant.secondary,
                onPressed: () => _add(app),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (roots.isEmpty)
            const EmptyNote('No folders yet. Add Documents, Desktop or a project folder to get started.')
          else
            for (var i = 0; i < roots.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              PathRow(
                path: roots[i],
                removeTooltip: 'Stop indexing',
                onRemove: () => _setRoots(app, roots.where((x) => x != roots[i]).toList()),
              ),
            ],
        ],
      ),
    );
  }
}

/// "How much is there to index?" — walks the indexed folders on request (sizes
/// only, nothing is read), FilDOS EstimateRow.
class _EstimateRow extends StatefulWidget {
  const _EstimateRow();
  @override
  State<_EstimateRow> createState() => _EstimateRowState();
}

class _EstimateRowState extends State<_EstimateRow> {
  Map<String, dynamic>? _estimate;
  bool _loading = false;

  Future<void> _run() async {
    final app = context.read<FaController>();
    setState(() => _loading = true);
    final r = await app.api.estimate(app.indexRoots);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _estimate = r.value;
    });
    if (!r.ok) app.toastError(r.error);
  }

  @override
  Widget build(BuildContext context) {
    final e = _estimate;
    final files = (e?['files'] as num?)?.toInt() ?? 0;
    final bytes = (e?['bytes'] as num?)?.toInt() ?? 0;
    final more = e?['complete'] == false ? '+' : '';
    return SettingRow(
      title: 'Size of your folders',
      description: _loading
          ? 'Looking through your folders…'
          : e == null
          ? 'Count what the indexed folders hold — nothing is read, only sizes and kinds'
          : files == 0
          ? 'Nothing to index in these folders.'
          : 'About ${formatCount(files)}$more files · ${formatBytes(bytes)}$more to read',
      trailing: SmallButton(
        label: e == null ? 'Estimate' : 'Re-estimate',
        variant: FaButtonVariant.secondary,
        onPressed: _loading ? null : _run,
      ),
    );
  }
}

// ── Ask AI ─────────────────────────────────────────────────────────────────

class _AssistantTab extends StatelessWidget {
  const _AssistantTab();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return _gap([
      SettingsCard(
        icon: Icons.auto_awesome_outlined,
        mint: true,
        title: 'Ask AI',
        subtitle: 'Chat models — run on this machine through Ollama, or Gemini in the cloud',
        children: [
          const MachineRow(),
          const OllamaStatus(),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [SubLabel('Model library'), SizedBox(height: 8), ChatModelPicker()],
          ),
          Text(
            'Local models run fully on this device through Ollama — nothing leaves your machine. '
            'With Gemini, the files you ask about are sent to Google to answer.',
            style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.375),
          ),
        ],
      ),
    ]);
  }
}

// ── Privacy ────────────────────────────────────────────────────────────────

class _PrivacyTab extends StatelessWidget {
  const _PrivacyTab();
  @override
  Widget build(BuildContext context) {
    final app = context.read<FaController>();
    return SettingsCard(
      icon: Icons.visibility_off_outlined,
      title: 'Hide from AI',
      subtitle: 'Files and folders AI features never read, index, or search',
      action: SmallButton(
        label: 'Add',
        icon: Icons.add_rounded,
        variant: FaButtonVariant.secondary,
        onPressed: () => pickExcludes(app),
      ),
      children: const [HiddenPathsList()],
    );
  }
}
