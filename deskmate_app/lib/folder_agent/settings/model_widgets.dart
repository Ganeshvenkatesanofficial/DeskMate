import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';
import '../widgets/model_logo.dart';
import '../widgets/ui.dart';
import 'settings_widgets.dart';

/// Model cards shared by Settings and onboarding: the on-device embedding
/// model, the Ollama status line, and the chat-model picker with live pulls.

/// "phi4-mini" and "phi4-mini:latest" are the same Ollama model.
bool sameModel(String a, String b) => a.replaceAll(':latest', '') == b.replaceAll(':latest', '');

// ── chat model selection ───────────────────────────────────────────────────

/// The chat model the user chose (it stays chosen while it downloads), or what runs now.
String? currentChatModel(FaController app) => app.aiConfig.chatModel ?? app.aiConfig.effectiveModel;

/// Installed Ollama tag matching [id] ("phi4-mini" → "phi4-mini:latest").
String? installedName(AiStatus? ai, String id) => ai?.ollamaModels.where((m) => sameModel(m, id)).firstOrNull;

/// Choose the chat model. The engine owns the choice: an installed model or
/// Gemini is used from the next turn; a missing catalog model starts an Ollama
/// pull and stays the choice — turns use it as soon as it lands.
Future<void> chooseChatModel(FaController app, String id) async {
  final config = app.aiConfig;
  if (id == config.geminiChoice) {
    if (config.hasGeminiKey) await app.setChatModel(id);
    return;
  }
  final installed = installedName(app.ai, id);
  if (installed == null) {
    final r = await app.api.pullOllama(id);
    if (!r.ok) return app.toastError(r.error);
    _announceWhenPulled(app, id);
  }
  await app.setChatModel(installed ?? id);
}

final Set<String> _watching = {};

/// Tell the user when a download finishes or fails (selection needs no client logic).
void _announceWhenPulled(FaController app, String id) {
  if (!_watching.add(id)) return;
  late final VoidCallback listener;
  void stop() {
    app.removeListener(listener);
    _watching.remove(id);
  }

  listener = () {
    final m = app.ai?.catalog.where((m) => m.id == id).firstOrNull;
    final state = m?.pull?['state'];
    if (state == 'error') {
      stop();
      app.toast('${m?.label ?? id}: ${m?.pull?['error'] ?? 'download failed'}', kind: ToastKind.error);
    } else if (state == 'done' || (m?.installed == true && state != 'pulling')) {
      stop();
      app.toast('${m?.label ?? id} is ready to chat', kind: ToastKind.success);
    }
  };
  app.addListener(listener);
}

/// Pull progress of a catalog model, 0..1 (null = indeterminate).
double? pullFraction(Map<String, dynamic>? pull) {
  if (pull == null) return null;
  final total = (pull['total'] as num?)?.toDouble() ?? 0;
  final done = (pull['completed'] as num?)?.toDouble() ?? 0;
  return total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}

String _gb(num bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';

/// "Downloading… 42% · 1.1 / 2.6 GB".
String pullLabel(Map<String, dynamic> pull) {
  final f = pullFraction(pull);
  final total = (pull['total'] as num?) ?? 0;
  final done = (pull['completed'] as num?) ?? 0;
  if (f == null) {
    final status = '${pull['status'] ?? ''}'.trim();
    return status.isEmpty || status == 'starting'
        ? 'Starting download…'
        : '${status[0].toUpperCase()}${status.substring(1)}…';
  }
  return 'Downloading… ${(f * 100).round()}% · ${_gb(done)} / ${_gb(total)}';
}

// ── Embedding model ────────────────────────────────────────────────────────

/// The on-device embedding model (FastEmbed BGE Small) as a FilDOS `ModelRow`:
/// `rounded-lg border px-3 py-2.5`, label text-sm + component chip, a text-2xs
/// status line (+ h-1 progress while downloading), and a Ready pill or a
/// Download / Retry button.
class EmbedderCard extends StatelessWidget {
  const EmbedderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final m = app.ai?.embedder;
    final state = m?.state ?? 'missing';
    final pct = ((m?.progress ?? 0) * 100).round();
    final label = (m?.label.isNotEmpty ?? false) ? m!.label : 'BGE Small (English)';
    return RowBox(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: FaText.sans(size: 14, color: c.foreground),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _Chip('Text & docs'),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  switch (state) {
                    'ready' => '384-dimensional embeddings · FastEmbed, on this device',
                    'downloading' => 'Downloading… $pct%',
                    'error' => m?.error ?? 'Download failed',
                    _ => 'Not downloaded · ~67 MB',
                  },
                  style: FaText.sans(size: 11, color: c.mutedForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (state == 'downloading') ...[
                  const SizedBox(height: 6),
                  ThinBar(value: m!.progress, color: c.foreground.withValues(alpha: 0.5)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (state == 'ready')
            const FaBadge('Ready', accent: Scoop.mint, wide: true)
          else
            SmallButton(
              label: switch (state) {
                'downloading' => 'Downloading…',
                'error' => 'Retry',
                _ => 'Download',
              },
              variant: state == 'error' ? FaButtonVariant.secondary : FaButtonVariant.primary,
              onPressed: state == 'downloading' ? null : () => startEmbedderDownload(app),
            ),
        ],
      ),
    );
  }
}

/// `bg-muted text-muted-foreground rounded px-1.5 py-0.5 text-3xs` component chip.
class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: FaText.sans(size: 10, color: c.mutedForeground)),
    );
  }
}

/// FilDOS h-1 progress track (`bg-muted` track, rounded fill, width transition).
class ThinBar extends StatelessWidget {
  final double value;
  final Color? color;
  const ThinBar({super.key, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      height: 4,
      decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(999)),
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, box) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: box.maxWidth * value.clamp(0.0, 1.0),
          decoration: BoxDecoration(
            color: color ?? c.foreground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

Future<void> startEmbedderDownload(FaController app) async {
  final r = await app.api.downloadEmbedder();
  if (!r.ok) app.toastError(r.error);
  await app.refreshAi();
}

// ── Ollama status ──────────────────────────────────────────────────────────

/// "This machine" (FilDOS Settings → Ask AI): the hardware line in mono
/// text-2xs plus a "Best fit" pill for the recommended model.
class MachineRow extends StatelessWidget {
  const MachineRow({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final ai = context.watch<FaController>().ai;
    final rec = ai?.catalog.where((m) => m.id == ai.recommended).firstOrNull;
    final specs = ai == null
        ? 'Detecting hardware…'
        : [
            if (ai.appleSilicon) 'Apple Silicon' else if (ai.platform.isNotEmpty) ai.platform,
            if (ai.ramGb != null) '${ai.ramGb} GB memory',
          ].join(' · ');
    return RowBox(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This machine', style: FaText.sans(size: 14, color: c.foreground)),
                const SizedBox(height: 2),
                Text(
                  specs,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FaText.mono(size: 11, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          if (rec != null) ...[
            const SizedBox(width: 12),
            FaBadge('Best fit: ${rec.label}', accent: Scoop.mint, wide: true),
          ],
        ],
      ),
    );
  }
}

/// Ollama's state as a Settings row box, with a "Check again" button.
class OllamaStatus extends StatefulWidget {
  const OllamaStatus({super.key});
  @override
  State<OllamaStatus> createState() => _OllamaStatusState();
}

class _OllamaStatusState extends State<OllamaStatus> {
  bool _checking = false;

  Future<void> _check(FaController app) async {
    setState(() => _checking = true);
    await app.refreshAi();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final status = app.ai?.ollamaStatus ?? 'offline';
    final n = app.ai?.ollamaModels.length ?? 0;
    final (title, sub) = switch (status) {
      'online' => ('Ollama is running', '$n model${n == 1 ? '' : 's'} installed — local chat runs through it'),
      'no_models' => ('Ollama is running', 'No models installed yet — pick one below to download it'),
      _ => (
        'Ollama isn\'t running',
        'Local chat models run through Ollama. Install it from ollama.com and open it — or use Gemini in the cloud.',
      ),
    };
    return RowBox(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ScoopDot(status == 'offline' ? Scoop.mango : Scoop.mint, size: 6),
                    const SizedBox(width: 6),
                    Text(title, style: FaText.sans(size: 14, color: c.foreground)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub, style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.375)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SmallButton(
            label: _checking ? 'Checking…' : 'Check again',
            variant: FaButtonVariant.secondary,
            onPressed: _checking ? null : () => _check(app),
          ),
        ],
      ),
    );
  }
}

// ── Chat model picker ──────────────────────────────────────────────────────

/// Radio list of chat models: installed Ollama models, the curated catalog
/// (with Recommended / Installed badges and live pull progress), and Gemini.
class ChatModelPicker extends StatefulWidget {
  /// Max height of the scrolling list (null = no inner scrolling).
  final double? maxHeight;
  const ChatModelPicker({super.key, this.maxHeight});
  @override
  State<ChatModelPicker> createState() => _ChatModelPickerState();
}

class _ChatModelPickerState extends State<ChatModelPicker> {
  final _key = TextEditingController();
  bool _geminiOpen = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveKey(FaController app) async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    if (!await app.setGeminiKey(key, select: true)) return;
    _key.clear();
    if (mounted) setState(() => _geminiOpen = false);
    app.toast('Gemini key saved', kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ai = app.ai;
    final config = app.aiConfig;
    final selected = currentChatModel(app);
    final offline = (ai?.ollamaStatus ?? 'offline') == 'offline';
    bool isSel(String id) => selected != null && sameModel(selected, id);

    final catalog = ai?.catalog ?? const <CatalogModel>[];
    // Recommended first, then the catalog in size order.
    final ordered = [
      ...catalog.where((m) => m.id == ai?.recommended),
      ...catalog.where((m) => m.id != ai?.recommended),
    ];
    final extraInstalled = (ai?.ollamaModels ?? const <String>[])
        .where((n) => !catalog.any((m) => sameModel(m.id, n)))
        .toList();

    final rows = <Widget>[
      for (final name in extraInstalled)
        _ModelRow(
          active: isSel(name),
          logo: ModelLogo(name),
          title: name,
          badges: const [FaBadge('Installed')],
          onTap: () => chooseChatModel(app, name),
        ),
      for (final m in ordered)
        _ModelRow(
          active: isSel(m.id),
          logo: ModelLogo(m.family),
          title: m.label,
          meta: '${m.sizeGb.toStringAsFixed(1)} GB',
          desc: m.note,
          badges: [
            if (m.id == ai?.recommended) const FaBadge('Recommended', accent: Scoop.mint),
            if (m.installed) const FaBadge('Installed'),
          ],
          pull: m.installed ? null : m.pull,
          disabled: offline && !m.installed,
          onTap: () => chooseChatModel(app, m.id),
        ),
      _ModelRow(
        active: config.usesGemini || selected == config.geminiChoice,
        logo: Icon(Icons.cloud_outlined, size: 17, color: c.mutedForeground),
        title: 'Use Gemini (cloud)',
        desc: config.hasGeminiKey
            ? 'Key saved. Files you ask about are sent to Google to answer.'
            : 'Runs in Google\'s cloud — needs an API key. Files you ask about are sent to Google.',
        badges: [if (config.hasGeminiKey) const FaBadge('Key saved')],
        onTap: () {
          if (config.hasGeminiKey) {
            chooseChatModel(app, config.geminiChoice);
          } else {
            setState(() => _geminiOpen = true);
          }
        },
        trailing: config.hasGeminiKey
            ? SmallButton(
                label: _geminiOpen ? 'Cancel' : 'Change key',
                variant: FaButtonVariant.ghost,
                onPressed: () => setState(() => _geminiOpen = !_geminiOpen),
              )
            : null,
        expanded: _geminiOpen
            ? Row(
                children: [
                  Expanded(
                    child: FaTextField(
                      controller: _key,
                      hint: 'Gemini API key',
                      dense: true,
                      mono: true,
                      autofocus: true,
                      onSubmitted: (_) => _saveKey(app),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(label: 'Save', variant: FaButtonVariant.primary, onPressed: () => _saveKey(app)),
                ],
              )
            : null,
      ),
    ];

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 6), rows[i]],
      ],
    );
    if (ai == null) {
      return const EmptyNote('Loading models…');
    }
    if (widget.maxHeight == null) return list;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight!),
      child: SingleChildScrollView(padding: const EdgeInsets.only(right: 4), child: list),
    );
  }
}

/// One chat model, FilDOS `OptionRow` / `ChatModelCard` style: `rounded-lg
/// border px-3 py-2.5 gap-3`, radio, size-5 logo, label text-sm + pills,
/// size in mono text-3xs on the right, description text-2xs, and the Mint
/// h-1 bar while it downloads.
class _ModelRow extends StatelessWidget {
  final bool active;
  final Widget logo;
  final String title;
  final String? meta;
  final String? desc;
  final List<Widget> badges;
  final Map<String, dynamic>? pull;
  final bool disabled;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? expanded;
  const _ModelRow({
    required this.active,
    required this.logo,
    required this.title,
    this.meta,
    this.desc,
    this.badges = const [],
    this.pull,
    this.disabled = false,
    required this.onTap,
    this.trailing,
    this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final pullState = pull?['state'];
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Hoverable(
        onTap: disabled ? null : onTap,
        builder: (context, hover) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? c.primary.withValues(alpha: 0.1)
                : (hover && !disabled ? c.accent.withValues(alpha: 0.5) : c.card.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(FaRadius.lg),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  RadioDot(active),
                  const SizedBox(width: 12),
                  SizedBox(width: 20, height: 20, child: Center(child: logo)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: FaText.sans(size: 14, color: c.foreground),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            for (final b in badges) ...[const SizedBox(width: 8), b],
                            const Spacer(),
                            if (meta != null) Text(meta!, style: FaText.mono(size: 10, color: c.mutedForeground)),
                          ],
                        ),
                        if (pullState == 'pulling') ...[
                          const SizedBox(height: 2),
                          Text(pullLabel(pull!), style: FaText.sans(size: 11, color: c.mutedForeground)),
                          const SizedBox(height: 6),
                          ThinBar(value: pullFraction(pull) ?? 0, color: Scoop.mint),
                        ] else if (pullState == 'error') ...[
                          const SizedBox(height: 2),
                          Text(
                            '${pull!['error'] ?? 'Download failed'} — click to retry',
                            style: FaText.sans(size: 11, color: c.destructive),
                          ),
                        ] else if (desc != null && desc!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(desc!, style: FaText.sans(size: 11, color: c.mutedForeground)),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                ],
              ),
              if (expanded != null) ...[
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.only(left: 28), child: expanded!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
