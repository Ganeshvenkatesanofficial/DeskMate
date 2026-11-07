import 'package:flutter/material.dart';

import '../core/fa_theme.dart';

/// The location row every main pane starts with — FilDOS `Toolbar`: `h-11`
/// (44px), `bg-card`, `border-b`, `px-3`, `gap-2` between the title (address
/// bar / page name) and the trailing controls, which sit [actionGap] apart
/// (`gap-1` for the folder controls; pages may tighten it).
class PaneHeader extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final double actionGap;
  const PaneHeader({super.key, required this.title, this.actions = const [], this.actionGap = 4});

  /// A page title: icon + name, as FilDOS's breadcrumb shows a metadata page
  /// (`px-1.5 gap-1.5 font-semibold`, 15px icon).
  PaneHeader.simple({
    super.key,
    required IconData icon,
    required String label,
    this.actions = const [],
    this.actionGap = 4,
  }) : title = PageTitle(icon: Icon(icon, size: 15), label: label);

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(child: title),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (var i = 0; i < actions.length; i++) ...[if (i > 0) SizedBox(width: actionGap), actions[i]],
          ],
        ],
      ),
    );
  }
}

/// A metadata page's name in the location row: leading glyph + semibold label.
class PageTitle extends StatelessWidget {
  final Widget icon;
  final String label;
  const PageTitle({super.key, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: IconTheme.merge(
        data: IconThemeData(color: c.foreground),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
