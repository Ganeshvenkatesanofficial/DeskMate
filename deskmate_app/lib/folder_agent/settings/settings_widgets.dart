import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';

/// Building blocks shared by Settings and the onboarding tour (FilDOS
/// SettingsView idioms: section cards with a framed icon tile, Ink switches,
/// hairline rows, scoop colour only as an accent).

String formatCount(int n) => NumberFormat.decimalPattern().format(n);

/// A small on/off switch (Ink/white primary track).
class FaSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const FaSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Opacity(
      opacity: onChanged == null ? 0.45 : 1,
      child: Hoverable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        builder: (context, _) => AnimatedContainer(
          duration: FaMotion.medium,
          curve: FaMotion.snappy,
          width: 36,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? c.primary : (c.isDark ? c.border : const Color(0xFFDCDDE2)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: FaMotion.medium,
            curve: FaMotion.snappy,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: value ? c.primaryForeground : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section card: framed icon tile, title + subtitle, optional action, body.
class SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool mint;
  final List<Widget> children;
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.mint = false,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FaRadius.xl),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(FaRadius.md),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: Icon(icon, size: 17, color: mint ? Scoop.mint : c.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: FaText.sans(size: 13.5, weight: FontWeight.w500, color: c.foreground),
                    ),
                    const SizedBox(height: 1),
                    Text(subtitle, style: FaText.sans(size: 11.5, color: c.mutedForeground)),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
          ],
        ],
      ),
    );
  }
}

/// Uppercase sub-heading inside a card.
class SubLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SubLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(text.toUpperCase(), style: FaText.label(context.fa))),
      ?trailing,
    ],
  );
}

/// A label + description on the left and a control (switch, button) on the right.
class SettingRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;
  final bool divider;
  const SettingRow({super.key, required this.title, this.description, required this.trailing, this.divider = false});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: EdgeInsets.only(top: divider ? 14 : 0),
      decoration: divider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FaText.sans(size: 13, color: c.foreground)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!, style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// A small neutral pill ("Recommended", "Installed").
class FaBadge extends StatelessWidget {
  final String text;
  final Color? accent;
  const FaBadge(this.text, {super.key, this.accent});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent?.withValues(alpha: 0.15) ?? c.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: FaText.sans(size: 10, weight: FontWeight.w500, color: accent ?? c.mutedForeground),
      ),
    );
  }
}

/// A round radio indicator (FilDOS ChoiceCard / OptionRow).
class RadioDot extends StatelessWidget {
  final bool active;
  const RadioDot(this.active, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return AnimatedContainer(
      duration: FaMotion.fast,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? c.foreground : Colors.transparent,
        border: Border.all(color: active ? c.foreground : c.border, width: 1.2),
      ),
      child: active ? Icon(Icons.check_rounded, size: 11, color: c.background) : null,
    );
  }
}

// ── Appearance ─────────────────────────────────────────────────────────────

/// An abstract miniature of the app window in one theme's palette.
class MiniWindow extends StatelessWidget {
  final bool dark;
  const MiniWindow({super.key, required this.dark});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF16181F) : Colors.white;
    final side = dark ? const Color(0xFF0F1117) : const Color(0xFFF5F5F7);
    final line = dark ? const Color(0xFF262932) : const Color(0xFFE7E7EA);
    final bar = dark ? const Color(0xFF2E3340) : const Color(0xFFD9DADE);
    Widget pill(double f) => FractionallySizedBox(
      widthFactor: f,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 4,
        decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(4)),
      ),
    );
    return ColoredBox(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              decoration: BoxDecoration(
                color: side,
                border: Border(right: BorderSide(color: line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pill(0.75),
                  const SizedBox(height: 4),
                  pill(0.5),
                  const Spacer(),
                  const Row(
                    children: [
                      ScoopDot(Scoop.blueberry, size: 4),
                      SizedBox(width: 3),
                      ScoopDot(Scoop.mint, size: 4),
                      SizedBox(width: 3),
                      ScoopDot(Scoop.strawberry, size: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pill(0.33),
                  const SizedBox(height: 4),
                  Container(height: 1, color: line),
                  for (final w in const [0.9, 0.65, 0.8, 0.5]) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: pill(w)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.58, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width * 0.38, s.height)
    ..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

const themeChoices = [
  (ThemeMode.system, 'System', Icons.desktop_mac_outlined),
  (ThemeMode.light, 'Light', Icons.light_mode_outlined),
  (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
];

/// System / Light / Dark cards with live miniature previews. Selecting one
/// changes DeskMate's app-wide theme (ChatProvider) — Folder Agent follows it.
class ThemePicker extends StatelessWidget {
  final bool compact;
  const ThemePicker({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return Row(
      children: [
        for (var i = 0; i < themeChoices.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _ThemeCard(
              mode: themeChoices[i].$1,
              label: themeChoices[i].$2,
              icon: themeChoices[i].$3,
              active: chat.themeMode == themeChoices[i].$1,
              compact: compact,
              onTap: () => chat.setThemeMode(themeChoices[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool active;
  final bool compact;
  final VoidCallback onTap;
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final preview = mode == ThemeMode.system
        ? Stack(
            fit: StackFit.expand,
            children: [
              const MiniWindow(dark: false),
              ClipPath(clipper: _SystemClipper(), child: const MiniWindow(dark: true)),
            ],
          )
        : MiniWindow(dark: mode == ThemeMode.dark);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? c.primary.withValues(alpha: 0.08)
              : (hover ? c.accent.withValues(alpha: 0.6) : Colors.transparent),
          borderRadius: BorderRadius.circular(FaRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: compact ? 2.0 : 1.4,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FaRadius.md),
                  border: Border.all(color: c.border),
                ),
                child: preview,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(icon, size: 13, color: active ? c.foreground : c.mutedForeground),
                const SizedBox(width: 6),
                Text(label, style: FaText.sans(size: 13, color: active ? c.foreground : c.mutedForeground)),
                if (active) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, size: 13, color: c.foreground)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Paths ──────────────────────────────────────────────────────────────────

/// One folder in a list: icon + name with its location beneath, and a remove
/// affordance revealed on hover (FilDOS HiddenPathRow).
class PathRow extends StatelessWidget {
  final String path;
  final VoidCallback? onRemove;
  final String removeTooltip;
  final IconData icon;
  final Widget? trailing;
  const PathRow({
    super.key,
    required this.path,
    this.onRemove,
    this.removeTooltip = 'Remove',
    this.icon = Icons.folder_outlined,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final home = context.select<FaController, String>((a) => a.home);
    final parent = parentDir(path);
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hover) => AnimatedContainer(
        duration: FaMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hover ? c.accent.withValues(alpha: 0.5) : Colors.transparent,
          borderRadius: BorderRadius.circular(FaRadius.md),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c.mutedForeground),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baseName(path),
                    style: FaText.sans(size: 13, color: c.foreground),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (parent != path)
                    Text(
                      compactDir(parent, home),
                      style: FaText.mono(size: 10, color: c.mutedForeground),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            ?trailing,
            if (onRemove != null)
              AnimatedOpacity(
                duration: FaMotion.fast,
                opacity: hover ? 1 : 0,
                child: FaIconButton(icon: Icons.close_rounded, size: 24, tooltip: removeTooltip, onPressed: onRemove),
              ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder row for an empty list.
class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: FaText.sans(size: 12, color: c.mutedForeground),
      ),
    );
  }
}

// ── Privacy ────────────────────────────────────────────────────────────────

const suggestedExcludeExtensions = ['.key', '.pem', '.p12', '.kdbx'];

/// "Hide from AI": folders never read, indexed or shown to the agent, plus
/// file extensions to skip. Persists straight to the backend.
class PrivacyEditor extends StatefulWidget {
  const PrivacyEditor({super.key});
  @override
  State<PrivacyEditor> createState() => _PrivacyEditorState();
}

class _PrivacyEditorState extends State<PrivacyEditor> {
  final _ext = TextEditingController();

  @override
  void dispose() {
    _ext.dispose();
    super.dispose();
  }

  Future<void> _addFolders(FaController app) async {
    final picked = await app.api.pickFolders(prompt: 'Choose folders to hide from AI');
    if (!picked.ok) return app.toastError(picked.error);
    if (picked.value!.isEmpty) return;
    final r = await app.api.addExcludes(picked.value!);
    if (!r.ok) return app.toastError(r.error);
    await app.refreshPrefs();
  }

  Future<void> _remove(FaController app, String path) async {
    final r = await app.api.removeExclude(path);
    if (!r.ok) return app.toastError(r.error);
    await app.refreshPrefs();
  }

  Future<void> _setExts(FaController app, List<String> exts) async {
    final r = await app.api.setExcludeExtensions(exts);
    if (!r.ok) return app.toastError(r.error);
    await app.refreshPrefs();
  }

  void _submitExt(FaController app) {
    final raw = _ext.text
        .split(RegExp(r'[\s,]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e != '.')
        .map((e) => e.startsWith('.') ? e : '.$e');
    if (raw.isEmpty) return;
    _ext.clear();
    _setExts(app, {...app.excludeExtensions, ...raw}.toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final excludes = app.excludes;
    final exts = app.excludeExtensions;
    final suggestions = suggestedExcludeExtensions.where((e) => !exts.contains(e)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SubLabel(
          'Hidden folders',
          trailing: FaButton(
            label: 'Add folder…',
            icon: Icons.add_rounded,
            dense: true,
            variant: FaButtonVariant.outline,
            onPressed: () => _addFolders(app),
          ),
        ),
        const SizedBox(height: 8),
        if (excludes.isEmpty)
          const EmptyNote('Nothing hidden. Anything you add is never read, indexed, or shown to the agent.')
        else
          for (final p in excludes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: PathRow(
                path: p,
                icon: Icons.visibility_off_outlined,
                removeTooltip: 'Show to AI again',
                onRemove: () => _remove(app, p),
              ),
            ),
        const SizedBox(height: 14),
        const SubLabel('Skipped file types'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in exts) _ExtChip(ext: e, onRemove: () => _setExts(app, exts.where((x) => x != e).toList())),
            for (final e in suggestions)
              FaChip(label: e, icon: Icons.add_rounded, onTap: () => _setExts(app, [...exts, e])),
            SizedBox(
              width: 150,
              child: FaTextField(
                controller: _ext,
                hint: '.ext, then Enter',
                dense: true,
                mono: true,
                onSubmitted: (_) => _submitExt(app),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.lock_outline_rounded, size: 13, color: c.mutedForeground),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Secrets are always skipped — .env files, SSH keys, credentials and tokens are never read, '
                'indexed or sent to a model. Dotfiles, system folders and caches are ignored too.',
                style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.45),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExtChip extends StatelessWidget {
  final String ext;
  final VoidCallback onRemove;
  const _ExtChip({required this.ext, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: 10, right: 3),
      decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ext, style: FaText.mono(size: 11, color: c.foreground)),
          const SizedBox(width: 2),
          FaIconButton(icon: Icons.close_rounded, size: 20, tooltip: 'Stop skipping $ext', onPressed: onRemove),
        ],
      ),
    );
  }
}

/// Simple confirm dialog in the Folder Agent look.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: context.fa.overlay,
    builder: (ctx) {
      final c = ctx.fa;
      return Dialog(
        backgroundColor: c.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FaRadius.xl),
          side: BorderSide(color: c.border),
        ),
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FaText.sans(size: 15, weight: FontWeight.w600, color: c.foreground),
                ),
                const SizedBox(height: 8),
                Text(message, style: FaText.sans(size: 12.5, color: c.mutedForeground, height: 1.45)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FaButton(
                      label: 'Cancel',
                      variant: FaButtonVariant.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 8),
                    FaButton(
                      label: confirm,
                      variant: destructive ? FaButtonVariant.destructive : FaButtonVariant.primary,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok ?? false;
}
