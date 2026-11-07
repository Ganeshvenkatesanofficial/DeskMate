import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fa_theme.dart';
import '../core/format.dart';
import '../state/fa_controller.dart';
import '../widgets/ui.dart';
import 'messages.dart';

/// The Folder Agent's live log — DeskMate's deliberate addition to FilDOS's
/// chat. Every tool call the SmolAgent made renders as a FilDOS activity chip
/// (`Message.tsx` › `ToolCallRow`: mint icon, summary, mint tick / strawberry
/// cross); tapping a chip reveals the tool's raw result. Reasoning steps render
/// as quiet muted lines. While the agent works the whole timeline shows with
/// FilDOS's three bouncing "thinking" dots and the current status; once the
/// answer is in, the chips stay and the reasoning folds behind a toggle.
class AgentLog extends StatefulWidget {
  final List<AgentStepTelemetry> steps;
  final bool active;
  final String activeTitle;
  const AgentLog({super.key, required this.steps, this.active = false, this.activeTitle = ''});

  @override
  State<AgentLog> createState() => _AgentLogState();
}

/// One row of the timeline: a reasoning line or a tool call (+ its result).
class _Entry {
  final AgentStepTelemetry step;
  final AgentStepTelemetry? result;
  const _Entry(this.step, [this.result]);
  bool get isTool => step.phase == 'tool_call';
}

List<_Entry> _timeline(List<AgentStepTelemetry> steps) {
  final out = <_Entry>[];
  final used = <int>{};
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    switch (s.phase) {
      case 'tool_call':
        AgentStepTelemetry? result;
        for (var j = i + 1; j < steps.length; j++) {
          final o = steps[j];
          if (used.contains(j) || o.phase != 'observation') continue;
          if (o.tool != null && s.tool != null && o.tool != s.tool) continue;
          used.add(j);
          result = o;
          break;
        }
        out.add(_Entry(s, result));
      case 'observation':
        if (used.contains(i)) break;
        // A result with no matching call (e.g. history saved before calls were logged).
        out.add(_Entry(AgentStepTelemetry(step: s.step, phase: 'tool_call', tool: s.tool), s));
      default:
        if ((s.summary ?? s.rawOutput ?? '').trim().isNotEmpty) out.add(_Entry(s));
    }
  }
  return out;
}

class _AgentLogState extends State<AgentLog> {
  bool _showReasoning = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final entries = _timeline(widget.steps);
    final reasoning = entries.where((e) => !e.isTool).length;
    final ms = widget.steps.fold<int>(0, (t, s) => t + (s.durationMs ?? 0));
    final all = widget.active || _showReasoning;

    // Keys are timeline positions, so a reasoning step that is re-sent as it
    // streams (a new object each time) keeps its row state and never flickers.
    final children = <Widget>[
      for (var i = 0; i < entries.length; i++)
        if (entries[i].isTool)
          _ToolChip(key: ValueKey('tool$i'), call: entries[i].step, result: entries[i].result, pending: widget.active)
        else if (all)
          _ReasoningLine(key: ValueKey('why$i'), step: entries[i].step),
      if (widget.active)
        _ThinkingRow(title: widget.activeTitle)
      else if (reasoning > 0)
        _LogToggle(
          open: _showReasoning,
          label: [
            _showReasoning ? 'Hide reasoning' : 'Show reasoning',
            '$reasoning step${reasoning == 1 ? '' : 's'}',
            if (ms > 0) _duration(ms),
          ].join(' · '),
          onTap: () => setState(() => _showReasoning = !_showReasoning),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      // FilDOS: `mb-1.5 flex flex-col gap-1` above the answer.
      padding: EdgeInsets.only(bottom: widget.active ? 0 : 6),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: c.foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 4), children[i]],
          ],
        ),
      ),
    );
  }
}

String _duration(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';

const _toolIcons = <String, IconData>{
  'list_folder': Icons.format_list_bulleted_rounded,
  'read_file': Icons.visibility_outlined,
  'find_files': Icons.search_rounded,
  'search_index': Icons.search_rounded,
  'search': Icons.search_rounded,
  'create_file': Icons.note_add_outlined,
  'create_folder': Icons.create_new_folder_outlined,
  'copy_files': Icons.copy_rounded,
  'move_files': Icons.arrow_forward_rounded,
  'rename_file': Icons.drive_file_rename_outline_rounded,
  'trash_files': Icons.delete_outline_rounded,
  'delete_files': Icons.delete_outline_rounded,
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
  'delete_files': 'Moved to Trash',
};

String _argsText(Map<String, dynamic>? args, String home) {
  if (args == null || args.isEmpty) return '';
  final parts = <String>[];
  args.forEach((k, v) {
    if (v == null || k == 'content') return;
    parts.add(v is List ? v.map((e) => compactDir('$e', home)).join(', ') : compactDir('$v', home));
  });
  return parts.join(' → ');
}

bool _failed(String out) => out.startsWith('Error') || out.startsWith('Refused');

/// FilDOS `ToolCallRow`: `w-fit max-w-full rounded-lg border bg-muted/40 px-2 py-1 gap-1.5`,
/// a 12px tool icon, the `text-2xs` summary and a 10px tick / cross. DeskMate
/// adds the call's arguments, its duration and a tap-to-reveal raw result.
class _ToolChip extends StatefulWidget {
  final AgentStepTelemetry call;
  final AgentStepTelemetry? result;
  final bool pending;
  const _ToolChip({super.key, required this.call, required this.result, required this.pending});
  @override
  State<_ToolChip> createState() => _ToolChipState();
}

class _ToolChipState extends State<_ToolChip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final home = context.select<FaController, String>((a) => a.home);
    final tool = widget.call.tool ?? 'tool';
    final result = widget.result;
    final out = (result?.rawOutput ?? result?.summary ?? '').trim();
    final done = result != null;
    final ok = done && !_failed(out);
    final tint = !done ? c.mutedForeground : (ok ? Scoop.mint : Scoop.strawberry);
    final args = _argsText(widget.call.arguments, home);
    final canOpen = out.isNotEmpty;

    final chip = Hoverable(
      onTap: canOpen ? () => setState(() => _open = !_open) : null,
      builder: (context, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hover && canOpen ? c.accent : c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(FaRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_toolIcons[tool] ?? Icons.auto_awesome_rounded, size: 12, color: done ? tint : Scoop.mint),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: _toolLabels[tool] ?? tool),
                    if (args.isNotEmpty)
                      TextSpan(
                        text: '  $args',
                        style: FaText.mono(size: 10, color: c.mutedForeground),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FaText.sans(size: 11, color: done && !ok ? Scoop.strawberry : c.foreground, height: 1.5),
              ),
            ),
            if (result?.durationMs != null) ...[
              const SizedBox(width: 6),
              Text(_duration(result!.durationMs!), style: FaText.mono(size: 10, color: c.mutedForeground)),
            ],
            const SizedBox(width: 6),
            if (done)
              Icon(ok ? Icons.check_rounded : Icons.close_rounded, size: 10, color: tint)
            else if (widget.pending)
              const SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(strokeWidth: 1.3, color: Scoop.mint),
              ),
          ],
        ),
      ),
    );

    if (!_open || !canOpen) return chip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chip,
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(FaRadius.lg),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header like FilDOS's code block: label + Copy.
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    Text('RESULT', style: FaText.mono(size: 10, color: c.mutedForeground).copyWith(letterSpacing: 0.5)),
                    const Spacer(),
                    _CopyLabel(text: out),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: SelectableText(
                    out,
                    style: FaText.mono(size: 11, color: ok ? c.foreground : Scoop.strawberry, height: 1.625),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// FilDOS code-block copy affordance: `text-3xs` "Copy" → mint tick "Copied".
class _CopyLabel extends StatefulWidget {
  final String text;
  const _CopyLabel({required this.text});
  @override
  State<_CopyLabel> createState() => _CopyLabelState();
}

class _CopyLabelState extends State<_CopyLabel> {
  bool _copied = false;
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.text));
        setState(() => _copied = true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      builder: (context, hover) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 11,
            color: _copied ? Scoop.mint : (hover ? c.foreground : c.mutedForeground),
          ),
          const SizedBox(width: 4),
          Text(
            _copied ? 'Copied' : 'Copy',
            style: FaText.sans(size: 10, color: hover ? c.foreground : c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// A reasoning / thought step: a muted `text-xs` line (two lines, tap for all).
class _ReasoningLine extends StatefulWidget {
  final AgentStepTelemetry step;
  const _ReasoningLine({super.key, required this.step});
  @override
  State<_ReasoningLine> createState() => _ReasoningLineState();
}

class _ReasoningLineState extends State<_ReasoningLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final raw = (widget.step.summary ?? widget.step.rawOutput ?? '').trim();
    // Collapsed: no blank lines (they'd read as empty rows); expanded: the full text.
    final text = _expanded ? raw : raw.split('\n').where((l) => l.trim().isNotEmpty).join('\n');
    return Hoverable(
      onTap: () => setState(() => _expanded = !_expanded),
      builder: (context, hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Icons.auto_awesome_rounded, size: 12, color: Scoop.mint),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: FaText.sans(size: 12, color: hover ? c.foreground : c.mutedForeground, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The finished-answer toggle that folds the reasoning steps, chip-styled.
class _LogToggle extends StatelessWidget {
  final bool open;
  final String label;
  final VoidCallback onTap;
  const _LogToggle({required this.open, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: FaText.sans(size: 11, color: hover ? c.foreground : c.mutedForeground, height: 1.5)),
            const SizedBox(width: 2),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 13,
              color: hover ? c.foreground : c.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// FilDOS `TypingDots` + DeskMate's live status line ("Executing tool: read_file").
class _ThinkingRow extends StatelessWidget {
  final String title;
  const _ThinkingRow({required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TypingDots(),
        if (title.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}

/// FilDOS's mint "thinking" indicator: three 6px dots (`gap-1 py-1.5`) on
/// Tailwind's `animate-bounce` (−25% ↔ 0, 900ms, staggered 0 / 150 / 300ms).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  static const _up = Cubic(0.8, 0, 1, 1);
  static const _down = Cubic(0, 0, 0.2, 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Tailwind `bounce`: 0% / 100% at −25% (ease-in), 50% at rest (ease-out).
  static double _offset(double t) {
    if (t < 0.5) return -1.5 * (1 - _up.transform(t * 2));
    return -1.5 * _down.transform((t - 0.5) * 2);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Thinking',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Transform.translate(
                offset: Offset(0, _offset((_c.value - i / 6) % 1.0)),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: Scoop.mint, shape: BoxShape.circle),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
