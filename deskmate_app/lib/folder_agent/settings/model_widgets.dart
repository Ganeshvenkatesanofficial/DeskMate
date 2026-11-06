import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/chat_provider.dart';
import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'settings_widgets.dart';

/// Model cards shared by Settings and onboarding: the on-device embedding
/// model, the Ollama status line, and the chat-model picker with live pulls.

const _logos = {
  'llama': 'llama.webp',
  'qwen': 'qwen.png',
  'gemma': 'gemma.webp',
  'phi': 'phi.webp',
  'mistral': 'mistral.webp',
  'deepseek': 'deepseek.png',
  'granite': 'granite.svg',
  'smollm': 'smollm.webp',
  'lfm': 'lfm.png',
};

/// Model family from a catalog family or an Ollama model name ("qwen3:4b" → qwen).
String modelFamily(String nameOrFamily) {
  final n = nameOrFamily.toLowerCase();
  for (final f in _logos.keys) {
    if (n.startsWith(f)) return f;
  }
  return 'custom';
}

/// "phi4-mini" and "phi4-mini:latest" are the same Ollama model.
bool sameModel(String a, String b) => a.replaceAll(':latest', '') == b.replaceAll(':latest', '');

class ModelLogo extends StatelessWidget {
  final String family;
  final double size;
  const ModelLogo(this.family, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final file = _logos[modelFamily(family)] ?? 'custom.webp';
    final path = 'assets/folder_agent/ai-logos/$file';
    final img = file.endsWith('.svg')
        ? SvgPicture.asset(path, width: size, height: size, fit: BoxFit.contain)
        : Image.asset(path, width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    return ClipRRect(borderRadius: BorderRadius.circular(size * 0.22), child: img);
  }
}

// ── chat model selection ───────────────────────────────────────────────────

/// The chat model currently chosen: a pending pull (prefs.chatModel) wins so
/// the picker shows what the user picked while it downloads.
String? currentChatModel(FaController app, ChatProvider chat) {
  final pref = app.chatModel;
  if (pref != null && pref.isNotEmpty) {
    final pulling = app.ai?.catalog.where((m) => m.id == pref).firstOrNull?.pull?['state'] == 'pulling';
    if (pulling) return pref;
  }
  if (chat.selectedModel.isNotEmpty) return chat.selectedModel;
  return (pref == null || pref.isEmpty) ? null : pref;
}

/// Installed Ollama tag matching [id] ("phi4-mini" → "phi4-mini:latest").
String? installedName(AiStatus? ai, String id) => ai?.ollamaModels.where((m) => sameModel(m, id)).firstOrNull;

/// Applies a chat-model choice everywhere: Gemini or an installed model is
/// selected right away; a missing catalog model starts an Ollama pull and is
/// selected once it lands (even if the view that asked has gone).
Future<void> chooseChatModel(FaController app, ChatProvider chat, String id) async {
  if (id == AppConstants.geminiModelId) {
    if (!chat.hasGeminiKey) return;
    await chat.saveAiConfiguration(model: id, geminiApiKey: chat.geminiApiKey);
    await app.setPrefs({'chatModel': id});
    return;
  }
  final installed = installedName(app.ai, id);
  if (installed != null) {
    await chat.setSelectedLocalModel(installed);
    await app.setPrefs({'chatModel': installed});
    return;
  }
  final r = await app.api.pullOllama(id);
  if (!r.ok) {
    app.toastError(r.error);
    return;
  }
  await app.setPrefs({'chatModel': id});
  await app.refreshAi();
  _selectWhenPulled(app, chat, id);
}

final Set<String> _watching = {};

void _selectWhenPulled(FaController app, ChatProvider chat, String id) {
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
      final name = installedName(app.ai, id) ?? id;
      if (app.chatModel == null || sameModel(app.chatModel!, id)) {
        chat.fetchAvailableModels().whenComplete(() => chat.setSelectedLocalModel(name));
        app.setPrefs({'chatModel': name});
      }
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

/// The on-device embedding model (FastEmbed BGE Small) with live state and a
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(FaRadius.sm)),
            child: const Icon(Icons.auto_awesome_outlined, size: 15, color: Scoop.mint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: FaText.sans(size: 13, color: c.foreground),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const FaBadge('Search by meaning'),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  switch (state) {
                    'ready' => 'Ready · runs on this device',
                    'downloading' => 'Downloading… $pct%',
                    'error' => m?.error ?? 'Download failed',
                    _ => 'Not downloaded · ~67 MB, one-time',
                  },
                  style: FaText.sans(size: 11.5, color: state == 'error' ? c.destructive : c.mutedForeground),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (state == 'downloading') ...[
                  const SizedBox(height: 6),
                  FaProgressBar(value: m!.progress > 0 ? m.progress : null, height: 4),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (state == 'ready')
            const FaBadge('Ready', accent: Scoop.mint)
          else
            FaButton(
              label: switch (state) {
                'downloading' => 'Downloading…',
                'error' => 'Retry',
                _ => 'Download',
              },
              dense: true,
              variant: state == 'error' ? FaButtonVariant.secondary : FaButtonVariant.primary,
              onPressed: state == 'downloading' ? null : () => startEmbedderDownload(app),
            ),
        ],
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

/// One-line Ollama status, or (offline) a card explaining how to get it.
class OllamaStatus extends StatefulWidget {
  const OllamaStatus({super.key});
  @override
  State<OllamaStatus> createState() => _OllamaStatusState();
}

class _OllamaStatusState extends State<OllamaStatus> {
  bool _checking = false;

  Future<void> _check(FaController app, ChatProvider chat) async {
    setState(() => _checking = true);
    await app.refreshAi();
    await chat.fetchAvailableModels();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final chat = context.read<ChatProvider>();
    final status = app.ai?.ollamaStatus ?? 'offline';
    final button = FaButton(
      label: _checking ? 'Checking…' : 'Check again',
      icon: Icons.refresh_rounded,
      dense: true,
      variant: FaButtonVariant.outline,
      onPressed: _checking ? null : () => _check(app, chat),
    );
    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(FaRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 3), child: ScoopDot(Scoop.mango, size: 8)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ollama isn\'t running',
                    style: FaText.sans(size: 13, weight: FontWeight.w500, color: c.foreground),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Local chat models run through Ollama. Install it from ollama.com, open it, '
                    'then check again — or use Gemini in the cloud instead.',
                    style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            button,
          ],
        ),
      );
    }
    final n = app.ai?.ollamaModels.length ?? 0;
    return Row(
      children: [
        ScoopDot(status == 'online' ? c.success : Scoop.mango, size: 7),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            status == 'online'
                ? 'Ollama is running · $n model${n == 1 ? '' : 's'} installed'
                : 'Ollama is running, but no models are installed yet — pick one below',
            style: FaText.sans(size: 12, color: c.mutedForeground),
          ),
        ),
        button,
      ],
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

  Future<void> _saveKey(FaController app, ChatProvider chat) async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    await chat.setGeminiApiKey(key);
    await chat.saveAiConfiguration(model: AppConstants.geminiModelId, geminiApiKey: key);
    await app.setPrefs({'chatModel': AppConstants.geminiModelId});
    _key.clear();
    if (mounted) setState(() => _geminiOpen = false);
    app.toast('Gemini key saved', kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final chat = context.watch<ChatProvider>();
    final ai = app.ai;
    final selected = currentChatModel(app, chat);
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
          onTap: () => chooseChatModel(app, chat, name),
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
          onTap: () => chooseChatModel(app, chat, m.id),
        ),
      _ModelRow(
        active: isSel(AppConstants.geminiModelId),
        logo: Icon(Icons.cloud_outlined, size: 17, color: c.mutedForeground),
        title: 'Use Gemini (cloud)',
        desc: chat.hasGeminiKey
            ? 'Key saved. Files you ask about are sent to Google to answer.'
            : 'Runs in Google\'s cloud — needs an API key. Files you ask about are sent to Google.',
        badges: [if (chat.hasGeminiKey) const FaBadge('Key saved')],
        onTap: () {
          if (chat.hasGeminiKey) {
            chooseChatModel(app, chat, AppConstants.geminiModelId);
          } else {
            setState(() => _geminiOpen = true);
          }
        },
        trailing: chat.hasGeminiKey
            ? FaButton(
                label: _geminiOpen ? 'Cancel' : 'Change key',
                dense: true,
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
                      onSubmitted: (_) => _saveKey(app, chat),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FaButton(
                    label: 'Save',
                    dense: true,
                    variant: FaButtonVariant.primary,
                    onPressed: () => _saveKey(app, chat),
                  ),
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
                ? c.primary.withValues(alpha: 0.07)
                : (hover && !disabled ? c.accent.withValues(alpha: 0.6) : Colors.transparent),
            borderRadius: BorderRadius.circular(FaRadius.md),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: RadioDot(active)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(width: 18, height: 18, child: Center(child: logo)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                title,
                                style: FaText.sans(size: 13, color: c.foreground),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            for (final b in badges) ...[const SizedBox(width: 6), b],
                            const Spacer(),
                            if (meta != null) Text(meta!, style: FaText.mono(size: 10, color: c.mutedForeground)),
                          ],
                        ),
                        if (desc != null && desc!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(desc!, style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.4)),
                        ],
                        if (pullState == 'pulling') ...[
                          const SizedBox(height: 8),
                          FaProgressBar(
                            value: pullFraction(pull),
                            height: 4,
                            color: c.foreground.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 4),
                          Text(pullLabel(pull!), style: FaText.mono(size: 10, color: c.mutedForeground)),
                        ] else if (pullState == 'error') ...[
                          const SizedBox(height: 4),
                          Text(
                            '${pull!['error'] ?? 'Download failed'} — click to retry',
                            style: FaText.sans(size: 11.5, color: c.destructive),
                          ),
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

/// Live status line for the chosen chat model (onboarding "Power it up",
/// Settings): ready / downloading with progress / cloud.
class ChosenModelProgress extends StatelessWidget {
  const ChosenModelProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final chat = context.watch<ChatProvider>();
    final id = currentChatModel(app, chat);
    if (id == null) {
      return Text('No chat model chosen yet.', style: FaText.sans(size: 12, color: c.mutedForeground));
    }
    final gemini = id == AppConstants.geminiModelId;
    final m = app.ai?.catalog.where((m) => sameModel(m.id, id)).firstOrNull;
    final installed = installedName(app.ai, id) != null || (m?.installed ?? false);
    final pull = m?.pull;
    final state = gemini || installed ? 'ready' : (pull?['state'] ?? 'missing');
    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: gemini
                ? Icon(Icons.cloud_outlined, size: 17, color: c.mutedForeground)
                : ModelLogo(m?.family ?? id, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                gemini ? AppConstants.geminiModelLabel : (m?.label ?? id),
                style: FaText.sans(size: 13, color: c.foreground),
              ),
              const SizedBox(height: 2),
              Text(switch (state) {
                'ready' => gemini ? 'Cloud model · nothing to download' : 'Ready · runs on this device',
                'pulling' => pullLabel(pull!),
                'done' => 'Ready · runs on this device',
                'error' => '${pull?['error'] ?? 'Download failed'}',
                _ => 'Not downloaded yet',
              }, style: FaText.sans(size: 11.5, color: state == 'error' ? c.destructive : c.mutedForeground)),
              if (state == 'pulling') ...[
                const SizedBox(height: 6),
                FaProgressBar(value: pullFraction(pull), height: 4),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (state == 'ready' || state == 'done')
          const FaBadge('Ready', accent: Scoop.mint)
        else if (state == 'error' || state == 'missing')
          FaButton(
            label: state == 'error' ? 'Retry' : 'Download',
            dense: true,
            variant: FaButtonVariant.secondary,
            onPressed: () => chooseChatModel(app, chat, m?.id ?? id),
          ),
      ],
    );
  }
}
