import 'package:flutter/material.dart';

import '../core/fa_theme.dart';

/// The 44px header row every main pane starts with (address bar, "Canvas",
/// "Ask AI", "Settings"…), with trailing actions on the right.
class PaneHeader extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  const PaneHeader({super.key, required this.title, this.actions = const []});

  /// A plain icon + label title.
  PaneHeader.simple({super.key, required IconData icon, required String label, this.actions = const []})
    : title = _SimpleTitle(icon: icon, label: label);

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(child: title),
          for (final a in actions) Padding(padding: const EdgeInsets.only(left: 4), child: a),
        ],
      ),
    );
  }
}

class _SimpleTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SimpleTitle({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Row(
      children: [
        Icon(icon, size: 16, color: c.foreground),
        const SizedBox(width: 8),
        Text(
          label,
          style: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
        ),
      ],
    );
  }
}
