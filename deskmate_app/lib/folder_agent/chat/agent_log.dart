import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'messages.dart';

/// The Folder Agent's live log: every reasoning step, tool call and tool
/// result the SmolAgent produced for one answer, in FilDOS's activity-chip
/// style. Expanded while the agent works, collapsed to a one-line summary
/// once the answer is in.
class AgentLog extends StatefulWidget {
  final List<AgentStepTelemetry> steps;
  final bool active;
  final String activeTitle;
  const AgentLog({super.key, required this.steps, this.active = false, this.activeTitle = ''});

  @override
  State<AgentLog> createState() => _AgentLogState();
}

class _AgentLogState extends State<AgentLog> {
  late bool _open = widget.active;

  @override
  void didUpdateWidget(AgentLog old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final steps = widget.steps;
    final tools = steps.where((s) => s.phase == 'tool_call').length;
    final ms = steps.fold<int>(0, (t, s) => t + (s.durationMs ?? 0));
    final summary = widget.active
        ? (widget.activeTitle.isEmpty ? 'Thinking…' : widget.activeTitle)
        : [
            'Agent log',
            '${steps.length} step${steps.length == 1 ? '' : 's'}',
            if (tools > 0) '$tools tool call${tools == 1 ? '' : 's'}',
            if (ms > 0) _duration(ms),
          ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: c.isDark ? 0.45 : 0.6),
        borderRadius: BorderRadius.circular(FaRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hoverable(
            onTap: steps.isEmpty ? null : () => setState(() => _open = !_open),
            builder: (context, hover) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: widget.active
                        ? const _ThinkingDots()
                        : const Icon(Icons.auto_awesome_rounded, size: 14, color: Scoop.mint),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      summary,
                      overflow: TextOverflow.ellipsis,
                      style: FaText.sans(size: 12.5, weight: FontWeight.w500, color: c.foreground),
                    ),
                  ),
                  if (steps.isNotEmpty)
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: FaMotion.fast,
                      child: Icon(Icons.expand_more_rounded, size: 17, color: hover ? c.foreground : c.mutedForeground),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: FaMotion.medium,
            curve: FaMotion.snappy,
            alignment: Alignment.topCenter,
            child: _open && steps.isNotEmpty
                ? Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final s in steps) _StepRow(step: s)],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

String _duration(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';

const _toolIcons = <String, IconData>{
  'list_folder': Icons.folder_open_rounded,
  'read_file': Icons.description_outlined,
  'find_files': Icons.search_rounded,
  'search_index': Icons.manage_search_rounded,
  'search': Icons.search_rounded,
  'create_file': Icons.note_add_outlined,
  'create_folder': Icons.create_new_folder_outlined,
  'copy_files': Icons.copy_rounded,
  'move_files': Icons.drive_file_move_outlined,
  'rename_file': Icons.edit_outlined,
  'trash_files': Icons.delete_outline_rounded,
};

const _toolLabels = <String, String>{
  'list_folder': 'Listed folder',
  'read_file': 'Read file',
  'find_files': 'Searched names',
  'search_index': 'Searched by meaning',
  'search': 'Searched your files',
  'create_file': 'Created file',
  'create_folder': 'Created folder',
  'copy_files': 'Copied',
  'move_files': 'Moved',
  'rename_file': 'Renamed',
  'trash_files': 'Moved to Trash',
};

class _StepRow extends StatefulWidget {
  final AgentStepTelemetry step;
  const _StepRow({required this.step});
  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _expanded = false;

  String _args(String home) {
    final args = widget.step.arguments;
    if (args == null || args.isEmpty) return '';
    final parts = <String>[];
    args.forEach((k, v) {
      if (v == null || k == 'content') return;
      final text = v is List ? v.map((e) => compactDir('$e', home)).join(', ') : compactDir('$v', home);
      parts.add(text);
    });
    return parts.join(' → ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final s = widget.step;
    final home = context.read<FaController>().home;
    switch (s.phase) {
      case 'tool_call':
        final tool = s.tool ?? 'tool';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(FaRadius.md),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_toolIcons[tool] ?? Icons.build_outlined, size: 13, color: Scoop.mint),
                  const SizedBox(width: 6),
                  Text(
                    _toolLabels[tool] ?? tool,
                    style: FaText.sans(size: 11.5, weight: FontWeight.w500, color: c.foreground),
                  ),
                  if (_args(home).isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        _args(home),
                        overflow: TextOverflow.ellipsis,
                        style: FaText.mono(size: 10.5, color: c.mutedForeground),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      case 'observation':
        final out = (s.rawOutput ?? s.summary ?? '').trim();
        if (out.isEmpty) return const SizedBox.shrink();
        final failed = out.startsWith('Error') || out.startsWith('Refused');
        return Padding(
          padding: const EdgeInsets.only(left: 14, top: 1, bottom: 4),
          child: Hoverable(
            onTap: () => setState(() => _expanded = !_expanded),
            builder: (context, hover) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    failed ? Icons.error_outline_rounded : Icons.subdirectory_arrow_right_rounded,
                    size: 13,
                    color: failed ? Scoop.strawberry : c.mutedForeground,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _expanded
                      ? Container(
                          constraints: const BoxConstraints(maxHeight: 260),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: c.background,
                            borderRadius: BorderRadius.circular(FaRadius.sm),
                            border: Border.all(color: c.border),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              out,
                              style: FaText.mono(size: 10.5, color: c.foreground, height: 1.45),
                            ),
                          ),
                        )
                      : Text(
                          out.replaceAll(RegExp(r'\s+'), ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FaText.mono(
                            size: 10.5,
                            color: failed ? Scoop.strawberry : (hover ? c.foreground : c.mutedForeground),
                          ),
                        ),
                ),
                if (s.durationMs != null) ...[
                  const SizedBox(width: 8),
                  Text(_duration(s.durationMs!), style: FaText.mono(size: 10, color: c.mutedForeground)),
                ],
                if (_expanded) ...[
                  const SizedBox(width: 4),
                  FaIconButton(
                    icon: Icons.copy_rounded,
                    size: 20,
                    tooltip: 'Copy result',
                    onPressed: () => Clipboard.setData(ClipboardData(text: out)),
                  ),
                ],
              ],
            ),
          ),
        );
      default:
        // reasoning / thought / status
        final raw = (s.summary ?? s.rawOutput ?? s.title ?? '').trim();
        if (raw.isEmpty) return const SizedBox.shrink();
        // Collapsed: no blank lines (they'd show as empty rows); expanded: the full text.
        final text = _expanded ? raw : raw.split('\n').where((l) => l.trim().isNotEmpty).join('\n');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Hoverable(
            onTap: () => setState(() => _expanded = !_expanded),
            builder: (context, hover) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.lightbulb_outline_rounded, size: 12, color: Scoop.mint),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    text,
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: FaText.sans(size: 12, color: hover ? c.foreground : c.mutedForeground, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// FilDOS's "thinking" indicator: three Mint dots bouncing in turn.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Transform.translate(
            offset: Offset(0, -2.5 * _bounce((_c.value - i * 0.15) % 1.0)),
            child: Container(
              width: 3.5,
              height: 3.5,
              margin: const EdgeInsets.symmetric(horizontal: 0.6),
              decoration: const BoxDecoration(color: Scoop.mint, shape: BoxShape.circle),
            ),
          ),
      ],
    ),
  );

  static double _bounce(double t) => t < 0.5 ? Curves.easeOut.transform(t * 2) : Curves.easeIn.transform((1 - t) * 2);
}
