import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';

/// Title-bar row: navigation, the ⌘K search pill, and the Ask AI button.
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final browsing = app.section == FaSection.browse;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          FaIconButton(icon: Icons.chevron_left_rounded, tooltip: 'Back', onPressed: ex.canGoBack ? ex.back : null),
          FaIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Forward',
            onPressed: ex.canGoForward ? ex.forward : null,
          ),
          FaIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onPressed: browsing ? () => ex.refresh() : null,
          ),
          const Spacer(),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: const _SearchPill()),
          const Spacer(),
          _AskAiButton(active: app.section == FaSection.askAi),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return Hoverable(
      onTap: () => app.openSearch(),
      cursor: SystemMouseCursors.text,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: hover ? c.accent : c.muted.withValues(alpha: c.isDark ? 0.7 : 1),
          borderRadius: BorderRadius.circular(FaRadius.md),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 16, color: c.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Search', style: FaText.sans(size: 13, color: c.mutedForeground)),
            ),
            Kbd(shortcutLabel('K')),
          ],
        ),
      ),
    );
  }
}

class _AskAiButton extends StatelessWidget {
  final bool active;
  const _AskAiButton({required this.active});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return Hoverable(
      onTap: () => app.showSection(active ? FaSection.browse : FaSection.askAi),
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: c.isDark ? (hover ? const Color(0xFFDDE2EE) : c.primary) : (hover ? c.accent : c.card),
          borderRadius: BorderRadius.circular(FaRadius.md),
          border: Border.all(
            color: active ? Scoop.mint : (c.isDark ? Colors.transparent : c.border),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            const DeskMateMark(size: 16),
            const SizedBox(width: 7),
            Text(
              'Ask AI',
              style: FaText.sans(
                size: 13,
                weight: FontWeight.w500,
                color: c.isDark ? c.primaryForeground : c.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
