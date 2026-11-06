import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../widgets/file_icon.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';
import 'composer_logic.dart';
import 'folder_chat_controller.dart';

/// Small leaf pieces of the Ask AI surface: mention chips, keycaps, the
/// empty state, history list, callouts and model logos.

/// A small pill for one attached file/folder mention.
class MentionChip extends StatelessWidget {
  final ChatMention mention;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  const MentionChip({super.key, required this.mention, this.onRemove, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final dot = mention.name.lastIndexOf('.');
    final ext = !mention.isFolder && dot > 0 ? mention.name.substring(dot + 1).toLowerCase() : '';
    return Tooltip(
      message: mention.path,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hover) => Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: hover && onTap != null ? c.accent : c.muted.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(FaRadius.sm),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FileIcon(name: mention.name, isDir: mention.isFolder, ext: ext, size: 14),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  mention.name,
                  style: FaText.sans(size: 11.5, color: c.foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                Hoverable(
                  onTap: onRemove,
                  builder: (context, h) =>
                      Icon(Icons.close_rounded, size: 11, color: h ? c.foreground : c.mutedForeground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised keycap tinted with a scoop ("@", "#", "/").
class TriggerKey extends StatelessWidget {
  final String text;
  final Color tint;
  final double size;
  const TriggerKey(this.text, {super.key, required this.tint, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(5),
        border: Border(
          top: BorderSide(color: c.border),
          left: BorderSide(color: c.border),
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border, width: 2),
        ),
      ),
      child: Text(
        text,
        style: FaText.mono(size: 11, weight: FontWeight.w700, color: tint),
      ),
    );
  }
}

class _Suggestion {
  final IconData icon;
  final Color tint;
  final String title;
  final String desc;
  final String id;
  const _Suggestion(this.id, this.icon, this.tint, this.title, this.desc);
}

const _suggestions = [
  _Suggestion(
    'summarize',
    Icons.folder_outlined,
    Scoop.blueberry,
    'Summarize this folder',
    'A quick gist of everything in view',
  ),
  _Suggestion('find', Icons.search_rounded, Scoop.mint, 'Find a file', 'Describe what you remember about it'),
  _Suggestion('explain', Icons.info_outline_rounded, Scoop.grape, 'Explain a file', 'Attach any file with @'),
  _Suggestion(
    'action',
    Icons.handyman_outlined,
    Scoop.strawberry,
    'Perform a file action',
    'Create, copy, move, rename, or delete to Trash',
  ),
];

/// The zero-message welcome: mark, syntax legend, starter recipes.
class AskAiEmptyState extends StatelessWidget {
  final bool cloud;
  final void Function(String id) onPick;
  const AskAiEmptyState({super.key, required this.cloud, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: c.isDark ? 0.3 : 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const DeskMateMark(size: 32),
              ),
              const SizedBox(height: 22),
              Text(
                'Research across your files',
                style: FaText.sans(size: 16, weight: FontWeight.w500, color: c.foreground),
              ),
              const SizedBox(height: 6),
              Text(
                cloud
                    ? 'Answers use Gemini in the cloud — the files you ask about are sent to Google to answer.'
                    : 'Answers come from a model running on this device — nothing leaves your system.',
                textAlign: TextAlign.center,
                style: FaText.sans(size: 12, color: c.mutedForeground, height: 1.5),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final (k, label, tint) in const [
                    ('@', 'file', Scoop.blueberry),
                    ('#', 'folder', Scoop.grape),
                    ('/', 'command', Scoop.mint),
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TriggerKey(k, tint: tint),
                        const SizedBox(width: 5),
                        Text(label, style: FaText.sans(size: 11.5, color: c.mutedForeground)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, box) {
                  final two = box.maxWidth >= 440;
                  final w = two ? (box.maxWidth - 8) / 2 : box.maxWidth;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _suggestions)
                        SizedBox(
                          width: w,
                          child: _SuggestionCard(s: s, onTap: () => onPick(s.id)),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final _Suggestion s;
  final VoidCallback onTap;
  const _SuggestionCard({required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hover ? Scoop.mint.withValues(alpha: 0.45) : c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: s.tint.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
              child: Icon(s.icon, size: 15, color: s.tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    s.desc,
                    style: FaText.sans(size: 11, color: c.mutedForeground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saved conversations — click to reopen, right-click / ⋯ to rename or delete.
class AskAiHistory extends StatelessWidget {
  final FolderChatController chat;
  final ValueChanged<String> onOpen;
  const AskAiHistory({super.key, required this.chat, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    if (chat.history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 22, color: c.mutedForeground),
              const SizedBox(height: 8),
              Text(
                'No saved conversations yet. Everything you ask is kept here.',
                textAlign: TextAlign.center,
                style: FaText.sans(size: 12, color: c.mutedForeground),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Conversations'),
                for (final s in chat.history) _HistoryRow(chat: chat, summary: s, onOpen: onOpen),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final FolderChatController chat;
  final ChatSummary summary;
  final ValueChanged<String> onOpen;
  const _HistoryRow({required this.chat, required this.summary, required this.onOpen});

  Future<void> _menu(BuildContext context, Offset at) async {
    final id = summary.id;
    final title = summary.title;
    await showFaMenu(context, at, [
      FaMenuItem('Open', icon: Icons.chat_bubble_outline_rounded, onTap: () => onOpen(id)),
      FaMenuItem(
        'Rename…',
        icon: Icons.drive_file_rename_outline_rounded,
        onTap: () async {
          final next = await promptText(context, title: 'Rename conversation', initial: title, confirm: 'Rename');
          if (next != null && next.isNotEmpty && next != title) await chat.renameChat(id, next);
        },
      ),
      const FaMenuItem.divider(),
      FaMenuItem('Delete', icon: Icons.delete_outline_rounded, destructive: true, onTap: () => chat.deleteChat(id)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final id = summary.id;
    final current = id == chat.chatId;
    final count = summary.messages;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Hoverable(
        onTap: () => onOpen(id),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        builder: (context, hover) => AnimatedContainer(
          duration: FaMotion.fast,
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            color: hover || current ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(FaRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (current) ...[const ScoopDot(Scoop.mint, size: 6), const SizedBox(width: 6)],
                        Expanded(
                          child: Text(
                            summary.title,
                            style: FaText.sans(size: 12.5, weight: FontWeight.w500, color: c.foreground),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatAgo(summary.updatedAt)}  ·  $count message${count == 1 ? '' : 's'}',
                      style: FaText.sans(size: 11, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              Opacity(
                opacity: hover ? 1 : 0,
                child: Builder(
                  builder: (btnContext) => FaIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'More',
                    size: 26,
                    onPressed: () {
                      final box = btnContext.findRenderObject() as RenderBox;
                      _menu(context, box.localToGlobal(Offset(0, box.size.height + 2)));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line notice above the composer (FilDOS ResearchCallout style).
class AskAiCallout extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String? detail;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onDismiss;
  const AskAiCallout({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.detail,
    required this.actionLabel,
    required this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
              child: Icon(icon, size: 14, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 1),
                    Text(detail!, style: FaText.sans(size: 11, color: c.mutedForeground)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            FaButton(label: actionLabel, dense: true, variant: FaButtonVariant.primary, onPressed: onAction),
            if (onDismiss != null) ...[
              const SizedBox(width: 2),
              FaIconButton(icon: Icons.close_rounded, size: 24, tooltip: 'Dismiss', onPressed: onDismiss),
            ],
          ],
        ),
      ),
    );
  }
}

// ── model logos ────────────────────────────────────────────────────────────

const _families = {
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

/// Logo asset for a model id, by family substring (fallback: custom).
String modelLogoAsset(String modelId) {
  final id = modelId.toLowerCase();
  for (final key in ['smollm', 'deepseek', 'granite', 'mistral', 'gemma', 'llama', 'qwen', 'phi', 'lfm']) {
    if (id.contains(key)) return 'assets/folder_agent/ai-logos/${_families[key]}';
  }
  return 'assets/folder_agent/ai-logos/custom.webp';
}

class ModelLogo extends StatelessWidget {
  final String modelId;
  final bool cloud;
  final double size;
  const ModelLogo({super.key, required this.modelId, this.cloud = false, this.size = 14});

  @override
  Widget build(BuildContext context) {
    if (cloud || modelId.isEmpty) return DeskMateMark(size: size);
    final asset = modelLogoAsset(modelId);
    final child = asset.endsWith('.svg')
        ? SvgPicture.asset(asset, width: size, height: size, fit: BoxFit.contain)
        : Image.asset(asset, width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    return ClipRRect(borderRadius: BorderRadius.circular(3), child: child);
  }
}
