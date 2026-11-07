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

/// A small pill for one attached file/folder mention (FilDOS `MentionChip`:
/// `max-w-44 gap-1.5 rounded-md border px-1.5 py-0.5 text-2xs`).
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
          constraints: const BoxConstraints(maxWidth: 176),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: hover && onTap != null ? c.accent : c.muted.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(FaRadius.md),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FileIcon(name: mention.name, isDir: mention.isFolder, ext: ext, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mention.name,
                  style: FaText.sans(size: 11, color: c.foreground, height: 1.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                Hoverable(
                  onTap: onRemove,
                  builder: (context, h) =>
                      Icon(Icons.close_rounded, size: 10, color: h ? c.foreground : c.mutedForeground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised keycap tinted with a scoop ("@", "#", "/") — FilDOS `Kbd variant=raised size=md`:
/// `rounded border px-1.5 py-0.5 font-mono text-2xs leading-none` + a 1px printed-key shadow.
class TriggerKey extends StatelessWidget {
  final String text;
  final Color tint;
  const TriggerKey(this.text, {super.key, required this.tint});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.border, offset: const Offset(0, 1))],
      ),
      child: Text(text, style: FaText.mono(size: 11, color: tint, height: 1)),
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
    'Create, copy, move, rename, or delete files',
  ),
];

/// The zero-message welcome (FilDOS `EmptyState`, page variant): mark tile,
/// heading, privacy line, syntax legend and starter recipes, `gap-6` apart.
class AskAiEmptyState extends StatelessWidget {
  final bool cloud;
  final void Function(String id) onPick;
  const AskAiEmptyState({super.key, required this.cloud, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 576 - 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                            spreadRadius: -1,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const DeskMateMark(size: 32),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Research across your files',
                      textAlign: TextAlign.center,
                      style: FaText.sans(size: 16, weight: FontWeight.w500, color: c.foreground, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cloud
                          ? 'Answers use Gemini in the cloud — the files you ask about are sent to Google to answer.'
                          : 'Answers come from a model running entirely on this device — nothing leaves your system.',
                      textAlign: TextAlign.center,
                      style: FaText.sans(size: 12, color: c.mutedForeground, height: 1.625),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
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
                              const SizedBox(width: 4),
                              Text(label, style: FaText.sans(size: 11, color: c.mutedForeground)),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, box) {
                        final two = box.maxWidth >= 440;
                        final w = two ? (box.maxWidth - 6) / 2 : box.maxWidth;
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
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
          ),
        ),
      ),
    );
  }
}

/// `rounded-xl border px-3 py-2.5 gap-2.5`, hover `border-mint/40`.
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
          borderRadius: BorderRadius.circular(FaRadius.xl),
          border: Border.all(color: hover ? Scoop.mint.withValues(alpha: 0.4) : c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: s.tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(FaRadius.lg),
              ),
              child: Icon(s.icon, size: 14, color: s.tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    maxLines: 1,
                    style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground, height: 16 / 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    s.desc,
                    maxLines: 1,
                    style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.5),
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

/// Saved conversations (FilDOS `HistoryView`): click to reopen; hover shows
/// rename / delete; right-click for the same menu.
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: c.mutedForeground),
              const SizedBox(height: 8),
              Text(
                'No saved conversations yet. Everything you ask is kept here.',
                textAlign: TextAlign.center,
                style: FaText.sans(size: 12, color: c.mutedForeground, height: 16 / 12),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < chat.history.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _HistoryRow(key: ValueKey(chat.history[i].id), chat: chat, summary: chat.history[i], onOpen: onOpen),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final FolderChatController chat;
  final ChatSummary summary;
  final ValueChanged<String> onOpen;
  const _HistoryRow({super.key, required this.chat, required this.summary, required this.onOpen});

  Future<void> _rename(BuildContext context) async {
    final title = summary.title;
    final next = await promptText(context, title: 'Rename conversation', initial: title, confirm: 'Rename');
    if (next != null && next.trim().isNotEmpty && next.trim() != title) await chat.renameChat(summary.id, next.trim());
  }

  Future<void> _menu(BuildContext context, Offset at) async {
    final id = summary.id;
    await showFaMenu(context, at, [
      FaMenuItem('Open', icon: Icons.chat_bubble_outline_rounded, onTap: () => onOpen(id)),
      FaMenuItem('Rename…', icon: Icons.drive_file_rename_outline_rounded, onTap: () => _rename(context)),
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
    return Hoverable(
      onTap: () => onOpen(id),
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        decoration: BoxDecoration(
          color: hover || current ? c.accent : c.accent.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(FaRadius.lg),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 52),
                    child: Row(
                      children: [
                        if (current) ...[const ScoopDot(Scoop.mint, size: 6), const SizedBox(width: 6)],
                        Expanded(
                          child: Text(
                            summary.title,
                            maxLines: 1,
                            style: FaText.sans(size: 12, weight: FontWeight.w500, color: c.foreground, height: 16 / 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatAgo(summary.updatedAt)} · $count message${count == 1 ? '' : 's'}',
                    style: FaText.sans(size: 10, color: c.mutedForeground, height: 1.5),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IgnorePointer(
                ignoring: !hover,
                child: AnimatedOpacity(
                  duration: FaMotion.fast,
                  opacity: hover ? 1 : 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RowAction(
                        icon: Icons.drive_file_rename_outline_rounded,
                        tooltip: 'Rename conversation',
                        onTap: () => _rename(context),
                      ),
                      const SizedBox(width: 2),
                      _RowAction(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Delete conversation',
                        danger: true,
                        onTap: () => chat.deleteChat(id),
                      ),
                    ],
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

/// `grid size-6 place-items-center rounded-md`, muted → foreground (or strawberry) on hover.
class _RowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool danger;
  final VoidCallback onTap;
  const _RowAction({required this.icon, required this.tooltip, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Tooltip(
      message: tooltip,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hover) => SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 13, color: hover ? (danger ? Scoop.strawberry : c.foreground) : c.mutedForeground),
        ),
      ),
    );
  }
}

/// A one-line notice above the composer (FilDOS `ResearchCallout`):
/// `px-3 pt-3` › `rounded-xl border bg-muted/40 px-3 py-2 gap-2.5`, a 24px tinted
/// tile, one `text-xs` sentence and a small primary button.
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(FaRadius.xl),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(FaRadius.lg),
              ),
              child: Icon(icon, size: 13, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: TextStyle(fontWeight: FontWeight.w500, color: c.foreground),
                    ),
                    if (detail != null) TextSpan(text: ' $detail'),
                  ],
                ),
                style: FaText.sans(size: 12, color: c.mutedForeground, height: 16 / 12),
              ),
            ),
            const SizedBox(width: 10),
            _CalloutButton(label: actionLabel, onTap: onAction),
            if (onDismiss != null) ...[
              const SizedBox(width: 10),
              _RowAction(icon: Icons.close_rounded, tooltip: 'Dismiss', onTap: onDismiss!),
            ],
          ],
        ),
      ),
    );
  }
}

/// `bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-2.5 py-1 text-2xs font-medium`.
class _CalloutButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CalloutButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: hover ? c.primary.withValues(alpha: 0.9) : c.primary,
          borderRadius: BorderRadius.circular(FaRadius.md),
        ),
        child: Text(
          label,
          style: FaText.sans(size: 11, weight: FontWeight.w500, color: c.primaryForeground, height: 1.5),
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
