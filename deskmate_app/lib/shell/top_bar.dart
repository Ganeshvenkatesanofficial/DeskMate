import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../state/explorer_controller.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';

/// Back across folders *and* pages, FilDOS-style: from a page, Back returns to
/// the folder behind it; otherwise it steps the folder history.
void navBack(FaController app, ExplorerController ex) {
  if (app.onPage) {
    app.leavePage();
  } else if (ex.canGoBack) {
    app.dropForwardPage();
    ex.back();
  }
}

/// Forward: to the page Back just left, else forward in the folder history.
void navForward(FaController app, ExplorerController ex) {
  if (app.canForwardToPage) {
    app.forwardToPage();
  } else if (!app.onPage && ex.canGoForward) {
    ex.forward();
  }
}

/// FilDOS `TopBar`: the full-width window chrome — `h-13` (52px) `bg-card`
/// `border-b` `px-3 gap-2`; Back / Forward / Refresh (32px ghost icons,
/// `gap-1`) on the left, the centred search launcher (`max-w-120`) and the
/// Ask AI button (primary, `size="sm"`) on the right.
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final canBack = app.onPage || ex.canGoBack;
    final canForward = app.canForwardToPage || (!app.onPage && ex.canGoForward);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    return Container(
      height: 52,
      padding: EdgeInsets.only(left: isMac ? 88 : 12, right: 12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // `flex-1 | w-full max-w-120 | flex-1`: the search pill takes up to
          // 480px and the two clusters split the rest evenly.
          const clusterMin = 112.0;
          final pill = math.max(0.0, math.min(480.0, box.maxWidth - 16 - 2 * clusterMin));
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    FaIconButton(
                      icon: Icons.chevron_left_rounded,
                      size: 32,
                      iconSize: 20,
                      tooltip: 'Back',
                      onPressed: canBack ? () => navBack(app, ex) : null,
                    ),
                    const SizedBox(width: 4),
                    FaIconButton(
                      icon: Icons.chevron_right_rounded,
                      size: 32,
                      iconSize: 20,
                      tooltip: 'Forward',
                      onPressed: canForward ? () => navForward(app, ex) : null,
                    ),
                    const SizedBox(width: 4),
                    FaIconButton(
                      icon: Icons.refresh_rounded,
                      size: 32,
                      tooltip: 'Refresh',
                      onPressed: () => ex.refresh(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: pill, child: const _SearchPill()),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _AskAiButton(active: app.section == FaSection.askAi),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The search launcher: `h-10 rounded-md border px-2.5 gap-2`, `bg-muted/60`
/// with Mist text, `hover:bg-muted hover:text-foreground` over 150ms; 12px
/// "Search" and an outlined ⌘K keycap.
class _SearchPill extends StatelessWidget {
  const _SearchPill();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return Hoverable(
      onTap: () => app.openSearch(),
      pressScale: 0.97,
      builder: (context, hover) {
        final fg = hover ? c.foreground : c.mutedForeground;
        return AnimatedContainer(
          duration: FaMotion.fast,
          curve: FaMotion.snappy,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hover ? c.muted : c.muted.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(FaRadius.md),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FaText.sans(size: 12, color: fg, height: 1),
                ),
              ),
              const SizedBox(width: 8),
              Kbd(shortcutLabel('K'), variant: KbdVariant.outline),
            ],
          ),
        );
      },
    );
  }
}

/// Ask AI — FilDOS `<Button variant="default" size="sm">`: Ink fill (near-white
/// in dark mode), `h-8 px-2.5 gap-1.5 rounded-sm`, 16px mark, `hover:bg-primary/90`;
/// while open it wears a 2px `mint/50` ring offset 1px from the bar.
class _AskAiButton extends StatelessWidget {
  final bool active;
  const _AskAiButton({required this.active});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    return Tooltip(
      message: 'Ask AI',
      child: Hoverable(
        onTap: () => active ? app.leavePage() : app.showSection(FaSection.askAi),
        pressScale: 0.97,
        builder: (context, hover) => AnimatedContainer(
          duration: FaMotion.fast,
          curve: FaMotion.snappy,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hover ? c.primary.withValues(alpha: 0.9) : c.primary,
            borderRadius: BorderRadius.circular(FaRadius.sm),
            boxShadow: [
              ...FaShadow.xs,
              if (active) ...[
                // Painted in order: the 3px mint ring, then the 1px card offset over it.
                BoxShadow(color: Scoop.mint.withValues(alpha: 0.5), spreadRadius: 3),
                BoxShadow(color: c.card, spreadRadius: 1),
              ],
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DeskMateMark(size: 16),
              const SizedBox(width: 6),
              Text(
                'Ask AI',
                style: FaText.sans(size: 14, color: c.primaryForeground, height: 20 / 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
