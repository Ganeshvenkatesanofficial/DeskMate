import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../state/fa_controller.dart';
import 'ui.dart';

/// Bottom-right stack of transient notifications.
class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<FaController>();
    final c = context.fa;
    return Positioned(
      right: 16,
      bottom: 36,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in app.toasts)
            Padding(
              key: ValueKey(t.id),
              padding: const EdgeInsets.only(top: 8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: FaMotion.medium,
                curve: FaMotion.snappy,
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: FaCard(
                      shadow: true,
                      color: c.popover,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (t.kind) {
                              ToastKind.error => Icons.error_outline_rounded,
                              ToastKind.success => Icons.check_circle_outline_rounded,
                              ToastKind.info => Icons.info_outline_rounded,
                            },
                            size: 16,
                            color: switch (t.kind) {
                              ToastKind.error => c.destructive,
                              ToastKind.success => Scoop.mint,
                              ToastKind.info => c.mutedForeground,
                            },
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(t.message, style: FaText.sans(size: 12.5, color: c.foreground)),
                          ),
                          if (t.actionLabel != null) ...[
                            const SizedBox(width: 10),
                            FaButton(
                              label: t.actionLabel!,
                              dense: true,
                              variant: FaButtonVariant.outline,
                              onPressed: () {
                                app.dismissToast(t.id);
                                t.onAction?.call();
                              },
                            ),
                          ],
                          const SizedBox(width: 4),
                          FaIconButton(icon: Icons.close_rounded, size: 22, onPressed: () => app.dismissToast(t.id)),
                        ],
                      ),
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
