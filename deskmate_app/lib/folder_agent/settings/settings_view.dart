import 'package:flutter/material.dart';
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

enum _Tab { general, ai, indexing, privacy, about }

const _tabs = [
  (_Tab.general, 'General', Icons.tune_rounded),
  (_Tab.ai, 'AI & Models', Icons.auto_awesome_outlined),
  (_Tab.indexing, 'Indexing', Icons.manage_search_rounded),
  (_Tab.privacy, 'Privacy', Icons.visibility_off_outlined),
  (_Tab.about, 'About', Icons.info_outline_rounded),
];

/// Folder Agent settings (port of FilDOS SettingsView): a centred column with
/// page tabs and section cards — General, AI & Models, Indexing, Privacy, About.
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

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Material(
      color: c.background,
      child: Column(
        children: [
          PaneHeader.simple(icon: Icons.settings_outlined, label: 'Settings'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Settings',
                        style: FaText.sans(size: 20, weight: FontWeight.w500, color: c.foreground, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configure Folder Agent. Search and indexing run on this device.',
                        style: FaText.sans(size: 13, color: c.mutedForeground),
                      ),
                      const SizedBox(height: 22),
                      _TabBar(selected: _tab, onSelect: (t) => setState(() => _tab = t)),
                      const SizedBox(height: 22),
                      KeyedSubtree(
                        key: ValueKey(_tab),
                        child: switch (_tab) {
                          _Tab.general => const _GeneralTab(),
                          _Tab.ai => const _AiTab(),
                          _Tab.indexing => const _IndexingTab(),
                          _Tab.privacy => const _PrivacyTab(),
                          _Tab.about => const _AboutTab(),
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
    );
  }
}

class _TabBar extends StatelessWidget {
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;
  const _TabBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (tab, label, icon) in _tabs)
              Hoverable(
                onTap: () => onSelect(tab),
                builder: (context, hover) {
                  final active = tab == selected;
                  final fg = active || hover ? c.foreground : c.mutedForeground;
                  return AnimatedContainer(
                    duration: FaMotion.fast,
                    margin: const EdgeInsets.only(right: 22),
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: active ? c.foreground : Colors.transparent, width: 2)),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 14, color: fg),
                        const SizedBox(width: 6),
                        Text(label, style: FaText.sans(size: 13, color: fg)),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

Widget _gap(List<Widget> children) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 18), children[i]],
  ],
);

// ── General ────────────────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  const _GeneralTab();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<FaController>();
    return _gap([
      const SettingsCard(
        icon: Icons.light_mode_outlined,
        title: 'Appearance',
        subtitle: 'Light, dark, or match your system',
        children: [ThemePicker(compact: true)],
      ),
      SettingsCard(
        icon: Icons.folder_open_outlined,
        title: 'Browsing',
        subtitle: 'How folders are listed',
        children: [
          SettingRow(
            title: 'Show hidden files',
            description: 'Include dotfiles and hidden folders in the browser.',
            trailing: FaSwitch(value: app.showHidden, onChanged: (v) => app.setPrefs({'showHidden': v})),
          ),
        ],
      ),
    ]);
  }
}

// ── AI & Models ────────────────────────────────────────────────────────────

class _AiTab extends StatelessWidget {
  const _AiTab();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<FaController>();
    final on = app.aiEnabled;
    return _gap([
      SettingsCard(
        icon: Icons.auto_awesome_outlined,
        mint: true,
        title: 'On-device AI',
        subtitle: on ? 'Search by meaning, Ask AI and Canvas are on' : 'Folder Agent is a plain file browser',
        action: FaSwitch(
          value: on,
          onChanged: (v) async {
            await app.setPrefs({'aiEnabled': v});
            if (v && app.ai?.embedder.state != 'ready' && app.ai?.embedder.state != 'downloading') {
              await startEmbedderDownload(app);
            }
          },
        ),
        children: const [SubLabel('Search model'), EmbedderCard()],
      ),
      Opacity(
        opacity: on ? 1 : 0.55,
        child: const SettingsCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Chat model',
          subtitle: 'Used by Ask AI to answer and act on your files',
          children: [OllamaStatus(), ChatModelPicker()],
        ),
      ),
    ]);
  }
}

// ── Indexing ───────────────────────────────────────────────────────────────

class _IndexingTab extends StatelessWidget {
  const _IndexingTab();

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

  Future<void> _run(FaController app, Future<Result<IndexStatus>> Function() call) async {
    final r = await call();
    if (!r.ok) app.toastError(r.error);
    await app.refreshIndex();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final roots = app.indexRoots;
    final ix = app.index;
    final running = ix.state == 'scanning' || ix.state == 'indexing' || ix.state == 'waiting-model';
    return _gap([
      if (!app.aiEnabled)
        Text(
          'On-device AI is off — turn it on in AI & Models to index these folders.',
          style: FaText.sans(size: 12, color: c.mutedForeground),
        ),
      SettingsCard(
        icon: Icons.folder_copy_outlined,
        title: 'Indexed folders',
        subtitle: 'Only these are read for search, Ask AI and Canvas',
        action: FaButton(
          label: 'Add folder…',
          icon: Icons.add_rounded,
          dense: true,
          variant: FaButtonVariant.outline,
          onPressed: () => _add(app),
        ),
        children: [
          if (roots.isEmpty)
            const EmptyNote('No folders yet. Add Documents, Desktop or a project folder to get started.')
          else
            Column(
              children: [
                for (final r in roots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: PathRow(
                      path: r,
                      removeTooltip: 'Stop indexing',
                      onRemove: () => _setRoots(app, roots.where((x) => x != r).toList()),
                    ),
                  ),
              ],
            ),
        ],
      ),
      SettingsCard(
        icon: Icons.manage_search_rounded,
        mint: true,
        title: 'Index',
        subtitle: ix.lastRun == null ? 'Never run' : 'Last run ${formatAgo(ix.lastRun!)}',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running)
              FaButton(
                label: 'Pause',
                icon: Icons.pause_rounded,
                dense: true,
                variant: FaButtonVariant.secondary,
                onPressed: () => _run(app, app.api.indexPause),
              )
            else
              FaButton(
                label: ix.state == 'paused' ? 'Resume' : 'Start',
                icon: Icons.play_arrow_rounded,
                dense: true,
                variant: FaButtonVariant.primary,
                onPressed: roots.isEmpty || !app.aiEnabled ? null : () => _run(app, app.api.indexStart),
              ),
            const SizedBox(width: 6),
            FaButton(
              label: 'Rebuild',
              icon: Icons.restart_alt_rounded,
              dense: true,
              variant: FaButtonVariant.ghost,
              onPressed: roots.isEmpty || !app.aiEnabled
                  ? null
                  : () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Rebuild the index?',
                        message:
                            'This clears everything Folder Agent has indexed and reads your folders again from '
                            'scratch. Search by meaning works on partial results while it rebuilds.',
                        confirm: 'Rebuild index',
                        destructive: true,
                      );
                      if (!ok) return;
                      final cleared = await app.api.indexClear();
                      if (!cleared.ok) return app.toastError(cleared.error);
                      await _run(app, app.api.indexStart);
                    },
            ),
          ],
        ),
        children: [_IndexStatusBody(ix: ix)],
      ),
    ]);
  }
}

class _IndexStatusBody extends StatelessWidget {
  final IndexStatus ix;
  const _IndexStatusBody({required this.ix});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final home = context.select<FaController, String>((a) => a.home);
    final (title, dot) = switch (ix.state) {
      'scanning' => ('Walking the file tree…', Scoop.mint),
      'indexing' => ('Building search vectors…', Scoop.mint),
      'waiting-model' => ('Waiting for the search model to download…', Scoop.mango),
      'paused' => ('Paused', Scoop.mango),
      'error' => (ix.error ?? 'Indexing failed', Scoop.strawberry),
      _ => (ix.indexed > 0 ? 'Up to date' : 'Idle — press Start', c.mutedForeground),
    };
    final active = ix.state == 'scanning' || ix.state == 'indexing';
    final frac = ix.total > 0 ? (ix.done / ix.total).clamp(0.0, 1.0) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ScoopDot(dot, size: 7),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: FaText.sans(size: 13, color: c.foreground)),
            ),
            if (ix.total > 0)
              Text(
                '${formatCount(ix.done)} / ${formatCount(ix.total)}',
                style: FaText.mono(size: 11, color: c.mutedForeground),
              ),
          ],
        ),
        if (active || ix.state == 'paused') ...[
          const SizedBox(height: 10),
          FaProgressBar(value: ix.state == 'scanning' ? null : frac, height: 4, color: Scoop.mint),
        ],
        if (active && ix.current != null) ...[
          const SizedBox(height: 6),
          Text(
            compactDir(ix.current!, home),
            style: FaText.mono(size: 10, color: c.mutedForeground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(label: 'Indexed', value: ix.indexed),
            _Stat(label: 'Skipped', value: ix.skipped),
            _Stat(label: 'Failed', value: ix.failed, warn: ix.failed > 0),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final bool warn;
  const _Stat({required this.label, required this.value, this.warn = false});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: FaText.label(c)),
            const SizedBox(height: 3),
            Text(
              formatCount(value),
              style: FaText.sans(size: 16, weight: FontWeight.w500, color: warn ? c.destructive : c.foreground),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Privacy ────────────────────────────────────────────────────────────────

class _PrivacyTab extends StatelessWidget {
  const _PrivacyTab();
  @override
  Widget build(BuildContext context) => const SettingsCard(
    icon: Icons.visibility_off_outlined,
    title: 'Hide from AI',
    subtitle: 'Folders and file types Folder Agent never reads, indexes or shows the agent',
    children: [PrivacyEditor()],
  );
}

// ── About ──────────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  const _AboutTab();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return _gap([
      SettingsCard(
        icon: Icons.info_outline_rounded,
        title: 'About',
        subtitle: 'Folder Agent for DeskMate',
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(FaRadius.lg),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: const Center(child: DeskMateMark(size: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DeskMateWordmark(size: 17),
                    const SizedBox(height: 2),
                    Text(
                      'Folder Agent · AI-native file explorer',
                      style: FaText.sans(size: 11.5, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SettingRow(
            divider: true,
            title: 'Replay onboarding',
            description: 'Walk through setup again — theme, folder access, AI and privacy.',
            trailing: FaButton(
              label: 'Replay',
              dense: true,
              variant: FaButtonVariant.outline,
              onPressed: () => app.setPrefs({'onboarded': false}),
            ),
          ),
          Text(
            'File explorer design adapted from FilDOS (MIT).',
            style: FaText.sans(size: 11.5, color: c.mutedForeground),
          ),
        ],
      ),
    ]);
  }
}
