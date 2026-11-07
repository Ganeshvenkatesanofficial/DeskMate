import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../state/fa_controller.dart';
import 'ui.dart';

/// Bottom-right stack of transient notifications — FilDOS `Toasts`: `right-4
/// bottom-4 gap-2`; each a `material` card (`rounded-lg border p-3 shadow-lg`,
/// 288–384px wide) with a 20px status icon, `text-sm leading-snug` message
/// and a 24px dismiss button; slides in from 8px below over 200ms and back
/// out on dismiss.
class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the toast list changes, not on every controller tick.
    context.select<FaController, int>((a) => a.toastRev);
    final app = context.read<FaController>();
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < app.toasts.length; i++)
            Padding(
              key: ValueKey(app.toasts[i].id),
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _Toast(toast: app.toasts[i]),
            ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final FaToast toast;
  const _Toast({required this.toast});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.read<FaController>();
    final t = toast;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: t.exiting ? 0 : 1),
      duration: const Duration(milliseconds: 200),
      curve: FaMotion.snappy,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 288, maxWidth: 384),
          child: FaMaterial(
            radius: FaRadius.lg,
            shadow: FaShadow.lg,
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    switch (t.kind) {
                      ToastKind.error => Icons.error_outline_rounded,
                      ToastKind.success => Icons.check_circle_outline_rounded,
                      ToastKind.info => Icons.info_outline_rounded,
                    },
                    size: 20,
                    color: switch (t.kind) {
                      ToastKind.error => c.destructive,
                      ToastKind.success => c.success,
                      ToastKind.info => c.mutedForeground,
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  fit: FlexFit.tight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.message, style: FaText.sans(size: 14, color: c.foreground, height: 1.375)),
                        if (t.actionLabel != null) ...[
                          const SizedBox(height: 8),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Transform.translate(
                  offset: const Offset(4, -4),
                  child: FaIconButton(
                    icon: Icons.close_rounded,
                    size: 24,
                    iconSize: 16,
                    onPressed: () => app.dismissToast(t.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
