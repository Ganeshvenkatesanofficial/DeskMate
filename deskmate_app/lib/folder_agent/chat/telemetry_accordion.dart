import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fa_theme.dart';
import 'messages.dart';

/// DeskMate's agent telemetry accordion: a header with the live status (or a
/// step summary), "Inspect all" and "View process" toggles, and a timeline of
/// reasoning, tool calls and observations. Each step expands into an inspector
/// (arguments JSON, raw output, chain of thought) with copy. Same layout,
/// sizes, palette and wording as DeskMate's chat, fed by the engine's
/// `AgentTelemetry` steps (live and saved).
class TelemetryAccordion extends StatefulWidget {
  final List<AgentStepTelemetry> steps;
  final bool isActive;
  final String? activeTitle;
  final bool initiallyExpanded;

  const TelemetryAccordion({
    super.key,
    required this.steps,
    this.isActive = false,
    this.activeTitle,
    this.initiallyExpanded = false,
  });

  @override
  State<TelemetryAccordion> createState() => _TelemetryAccordionState();
}

class _TelemetryAccordionState extends State<TelemetryAccordion> {
  late bool _isExpanded = widget.isActive || widget.initiallyExpanded;
  final Set<int> _expandedSteps = {};
  int? _copiedStepIndex;

  @override
  void initState() {
    super.initState();
    // While live, the latest step stays open.
    if (widget.isActive && widget.steps.isNotEmpty) _expandedSteps.add(widget.steps.length - 1);
  }

  @override
  void didUpdateWidget(TelemetryAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _isExpanded = true;
    if (!widget.isActive && oldWidget.isActive) {
      // The run finished: fold back to the summary, like a saved turn.
      _isExpanded = widget.initiallyExpanded;
      _expandedSteps.clear();
    }
    if (widget.isActive && widget.steps.length > oldWidget.steps.length) {
      _expandedSteps.add(widget.steps.length - 1);
    }
  }

  void _toggleStep(int index) => setState(() {
    if (!_expandedSteps.remove(index)) _expandedSteps.add(index);
  });

  void _toggleAllSteps() => setState(() {
    if (_expandedSteps.isNotEmpty) {
      _expandedSteps.clear();
    } else {
      _expandedSteps.addAll(List.generate(widget.steps.length, (i) => i));
    }
  });

  void _copy(String text, int stepIndex) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copiedStepIndex = stepIndex);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copiedStepIndex == stepIndex) setState(() => _copiedStepIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty && !widget.isActive) return const SizedBox.shrink();
    final t = _Palette.of(context);
    final steps = widget.steps;
    final count = steps.length;
    final actions = steps.where((s) => s.isToolCall).length;
    final results = steps.where((s) => s.isResult).length;
    final thoughts = steps.where((s) => s.phase == 'reasoning').length;
    final header = widget.isActive
        ? (widget.activeTitle ?? 'Agent executing workflow: Tool Call ➔ LLM Analysis...')
        : '$count step${_s(count)} · $actions Action${_s(actions)}, $results Result${_s(results)}, '
              '$thoughts Thought${_s(thoughts)}';
    final anyOpen = _expandedSteps.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.isDark ? t.bgSubtle : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          if (widget.isActive)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: t.accentFg),
                            )
                          else
                            Icon(Icons.hub_outlined, size: 15, color: t.accentFg),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              header,
                              style: FaText.sans(size: 12, weight: FontWeight.w600, color: t.fgDefault),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_isExpanded && steps.isNotEmpty) ...[
                  _HeaderButton(
                    onTap: _toggleAllSteps,
                    radius: 6,
                    color: t.isDark ? const Color(0xFF1E232B) : const Color(0xFFEFF2F5),
                    borderColor: anyOpen ? t.accentFg.withValues(alpha: 0.5) : t.borderDefault,
                    borderWidth: 0.8,
                    children: [
                      Icon(
                        anyOpen ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                        size: 13,
                        color: t.accentFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        anyOpen ? 'Collapse all' : 'Inspect all',
                        style: FaText.sans(size: 10, weight: FontWeight.w600, color: t.accentFg),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                ],
                _HeaderButton(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  radius: 7,
                  color: t.bgEmphasis,
                  borderColor: _isExpanded ? t.accentFg.withValues(alpha: 0.4) : t.borderDefault,
                  borderWidth: 1,
                  children: [
                    Text(
                      _isExpanded ? 'Hide process' : 'View process',
                      style: FaText.sans(
                        size: 10,
                        weight: FontWeight.w600,
                        color: _isExpanded ? t.fgDefault : t.fgMuted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: _isExpanded ? t.fgDefault : t.fgMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isExpanded && steps.isNotEmpty) ...[
            Divider(height: 1, color: t.borderDefault),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (var i = 0; i < count; i++) _step(steps[i], i, i == count - 1, t)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _step(AgentStepTelemetry step, int index, bool isLast, _Palette t) {
    final look = _StepLook.of(step, t);
    final open = _expandedSteps.contains(index);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline node and connector.
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: look.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: look.color, width: 1.5),
                  ),
                  child: Center(child: Icon(look.icon, size: 11, color: look.color)),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: t.borderDefault,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Container(
                decoration: BoxDecoration(
                  color: open ? (t.isDark ? const Color(0xFF141820) : Colors.white) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: open ? look.color.withValues(alpha: 0.35) : Colors.transparent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () => _toggleStep(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: open ? 10 : 4, vertical: 6),
                        child: _stepHeader(step, look, open, t),
                      ),
                    ),
                    if (open)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(height: 12, color: t.borderDefault.withValues(alpha: 0.6)),
                            _inspector(step, index, t),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader(AgentStepTelemetry step, _StepLook look, bool open, _Palette t) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: look.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: look.color.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Text(
            look.badge,
            style: FaText.mono(size: 9, weight: FontWeight.w700, color: look.color),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          look.title,
          style: FaText.sans(size: 11.5, weight: FontWeight.w600, color: t.fgDefault),
        ),
        if (look.meta.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: look.meta,
              waitDuration: const Duration(milliseconds: 300),
              child: Text(
                look.meta,
                style: step.isToolCall
                    ? FaText.mono(size: 10.5, color: t.fgMuted)
                    : FaText.sans(size: 10.5, color: t.fgMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ] else
          const Spacer(),
        if ((step.durationMs ?? 0) > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(color: t.bgEmphasis, borderRadius: BorderRadius.circular(4)),
            child: Text(
              '${step.durationMs}ms',
              style: FaText.mono(size: 9.5, weight: FontWeight.w500, color: t.fgMuted),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: open
                ? look.color.withValues(alpha: 0.16)
                : (t.isDark ? const Color(0xFF1E232B) : const Color(0xFFEAEEF2)),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: open ? look.color.withValues(alpha: 0.45) : t.borderDefault, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                open ? 'Close' : 'Inspect',
                style: FaText.sans(size: 9.5, weight: FontWeight.w600, color: open ? look.color : t.fgMuted),
              ),
              const SizedBox(width: 2),
              Icon(
                open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: open ? look.color : t.fgMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Arguments JSON for a tool call, raw output for a result, the thought for reasoning.
  Widget _inspector(AgentStepTelemetry step, int index, _Palette t) {
    final kind = _ToolKind.of(step.tool);
    final copied = _copiedStepIndex == index;
    if (step.isToolCall) {
      final json = _formatJson(step.arguments ?? const {});
      return _InspectorPanel(
        icon: kind == _ToolKind.vector ? Icons.hub_rounded : Icons.input_rounded,
        title: kind == _ToolKind.vector ? 'Vector Search Parameters' : 'Input Arguments Payload',
        copyLabel: 'Copy JSON',
        copied: copied,
        accent: t.accentFg,
        onCopy: () => _copy(json, index),
        palette: t,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: _codeBox(t),
          child: SelectionArea(
            child: Text(json, style: FaText.mono(size: 11, height: 1.45, color: t.successText)),
          ),
        ),
      );
    }
    if (step.isResult) {
      final text = (step.rawOutput?.isNotEmpty ?? false) ? step.rawOutput! : (step.summary ?? 'No data returned.');
      final lines = text.split('\n').length;
      return _InspectorPanel(
        icon: kind == _ToolKind.vector ? Icons.grain_rounded : Icons.output_rounded,
        title: kind == _ToolKind.vector ? 'Semantic Vector Findings (Embeddings)' : 'Observation & Findings Data',
        badge: '$lines line${lines == 1 ? '' : 's'}',
        copyLabel: 'Copy Output',
        copied: copied,
        accent: t.accentFg,
        onCopy: () => _copy(text, index),
        palette: t,
        footer: Row(
          children: [
            Icon(Icons.subdirectory_arrow_right_rounded, size: 13, color: t.fgMuted),
            const SizedBox(width: 4),
            Text(
              'Transferred as context into next LLM deliberation phase',
              style: FaText.sans(size: 10, color: t.fgMuted).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(10),
          decoration: _codeBox(t),
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Text(text, style: FaText.mono(size: 10.5, height: 1.45, color: t.fgDefault)),
            ),
          ),
        ),
      );
    }
    final thought = step.rawOutput ?? step.summary ?? '';
    return _InspectorPanel(
      icon: Icons.psychology_rounded,
      iconColor: _Palette.purple,
      iconSize: 13,
      title: 'Model Strategy & Chain-of-Thought',
      copyLabel: 'Copy Thought',
      copied: copied,
      accent: _Palette.purple,
      onCopy: () => _copy(thought, index),
      palette: t,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 220),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.isDark ? const Color(0xFF1E1528) : const Color(0xFFF7F2FD),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.isDark ? const Color(0xFF4C2889) : const Color(0xFFD8B4FE), width: 0.8),
        ),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Text(
              thought,
              style: FaText.sans(
                size: 11,
                height: 1.5,
                color: t.isDark ? const Color(0xFFE2C5FF) : const Color(0xFF552299),
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ),
      ),
    );
  }

  static BoxDecoration _codeBox(_Palette t) => BoxDecoration(
    color: t.bgCode,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: t.borderDefault, width: 0.8),
  );

  static String _s(int n) => n == 1 ? '' : 's';

  static String _formatJson(Object? data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return '$data';
    }
  }
}

/// DeskMate's palette (GitHub-style neutrals with the DeskMate purple).
class _Palette {
  final bool isDark;
  const _Palette(this.isDark);
  factory _Palette.of(BuildContext context) => _Palette(Theme.of(context).brightness == Brightness.dark);

  static const purple = Color(0xFF6A35F5);
  static const blue = Color(0xFF0969DA);
  static const amber = Color(0xFFD29922);

  Color get bgSubtle => isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
  Color get bgEmphasis => isDark ? const Color(0xFF21262D) : const Color(0xFFD0D7DE);
  Color get bgCode => isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
  Color get fgDefault => isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
  Color get fgMuted => isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
  Color get borderDefault => isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
  Color get accentFg => isDark ? const Color(0xFF8E67F6) : purple;
  Color get successText => isDark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37);
  Color get statusOk => const Color(0xFF2DA44E);
}

/// How the Folder Agent's tools are grouped: index (embeddings) tools get the
/// vector look; everything else is a plain tool call.
enum _ToolKind {
  vector,
  other;

  static _ToolKind of(String? tool) => const {'search_index', 'index_files', 'search'}.contains(tool) ? vector : other;
}

/// Badge, title, inline preview, icon and colour of one step.
class _StepLook {
  final IconData icon;
  final Color color;
  final String badge;
  final String title;
  final String meta;
  const _StepLook(this.icon, this.color, this.badge, this.title, this.meta);

  factory _StepLook.of(AgentStepTelemetry step, _Palette t) {
    final kind = _ToolKind.of(step.tool);
    if (step.isToolCall) {
      final args = (step.arguments ?? const {}).entries
          .where((e) => e.value != null && e.key != 'content')
          .take(2)
          .map((e) => '${_cleanKey(e.key)}: "${e.value}"')
          .join(', ');
      final tool = step.tool ?? 'tool';
      return _StepLook(
        kind == _ToolKind.vector ? Icons.hub_rounded : Icons.terminal_rounded,
        kind == _ToolKind.vector ? _Palette.purple : _Palette.blue,
        kind == _ToolKind.vector
            ? (step.tool == 'index_files' ? 'VECTOR EMBEDDING STORE' : 'VECTOR EMBEDDING SEARCH')
            : 'TOOL CALL',
        _friendlyToolName(step.tool),
        args.isEmpty ? tool : '$tool($args)',
      );
    }
    if (step.isResult) {
      final summary = step.summary ?? step.rawOutput ?? '';
      final firstLine = summary.split('\n').first.trim().replaceAll('**', '');
      if (step.ok == false || summary.startsWith('Error') || summary.startsWith('Refused')) {
        return _StepLook(Icons.info_outline_rounded, _Palette.amber, 'SYSTEM NOTICE', 'Tool Notice', firstLine);
      }
      if (kind == _ToolKind.vector) {
        return _StepLook(
          Icons.grain_rounded,
          _Palette.purple,
          'EMBEDDING RESULTS',
          step.tool == 'index_files' ? 'Vector Index Updated' : 'Semantic Embeddings Retrieved',
          firstLine,
        );
      }
      return _StepLook(
        Icons.check_circle_rounded,
        t.statusOk,
        'OBSERVATION',
        'Findings Received',
        step.tool == 'list_folder' ? _folderCounts(step.rawOutput ?? summary) : firstLine,
      );
    }
    final thought = (step.summary ?? '').split('\n').first.trim().replaceAll('**', '');
    return _StepLook(Icons.psychology_rounded, _Palette.purple, 'AI REASONING', 'LLM Deliberation', thought);
  }

  /// "3 folders, 12 files discovered" from a `list_folder` result.
  static String _folderCounts(String out) {
    final rows = out.split('\n').where((l) => l.startsWith('- ')).toList();
    final dirs = rows.where((l) => l.startsWith('- 📁')).length;
    return '$dirs folders, ${rows.length - dirs} files discovered';
  }

  static String _cleanKey(String key) => switch (key) {
    'file_path' => 'file',
    'directory_path' || 'folder' => 'path',
    _ => key.replaceAll('_', ' '),
  };

  static String _friendlyToolName(String? tool) => switch (tool) {
    null || '' => 'Tool Execution',
    'list_folder' => 'Directory Inspection',
    'read_file' => 'Document Reader',
    'find_files' => 'File Search',
    'search_index' => 'Vector Search (Qdrant Embeddings)',
    'index_files' => 'Index Document Embeddings (Qdrant)',
    'search' => 'Hybrid Search (Names + Qdrant Embeddings)',
    'create_file' => 'Create File',
    'create_folder' => 'Create Folder',
    'copy_files' => 'Copy Files',
    'move_files' => 'Move Files',
    'rename_file' => 'Rename',
    'trash_files' => 'Move to Trash',
    final t => t.split('_').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
  };
}

/// The bordered pill buttons in the accordion header.
class _HeaderButton extends StatelessWidget {
  final VoidCallback onTap;
  final double radius;
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final List<Widget> children;
  const _HeaderButton({
    required this.onTap,
    required this.radius,
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    mouseCursor: SystemMouseCursors.click,
    onTap: onTap,
    borderRadius: BorderRadius.circular(radius),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// An inspector: icon + title (+ badge), a copy action, the content, an optional footer.
class _InspectorPanel extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final double iconSize;
  final String title;
  final String? badge;
  final String copyLabel;
  final bool copied;
  final Color accent;
  final VoidCallback onCopy;
  final _Palette palette;
  final Widget child;
  final Widget? footer;

  const _InspectorPanel({
    required this.icon,
    this.iconColor,
    this.iconSize = 12,
    required this.title,
    this.badge,
    required this.copyLabel,
    required this.copied,
    required this.accent,
    required this.onCopy,
    required this.palette,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final t = palette;
    final copyColor = copied ? t.statusOk : accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: iconSize, color: iconColor ?? t.fgMuted),
            const SizedBox(width: 5),
            Text(
              title,
              style: FaText.sans(size: 10.5, weight: FontWeight.w600, color: t.fgDefault),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: t.bgEmphasis, borderRadius: BorderRadius.circular(4)),
                child: Text(badge!, style: FaText.mono(size: 9.5, color: t.fgMuted)),
              ),
            ],
            const Spacer(),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: onCopy,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(copied ? Icons.check_rounded : Icons.copy_rounded, size: 11, color: copyColor),
                    const SizedBox(width: 4),
                    Text(
                      copied ? 'Copied' : copyLabel,
                      style: FaText.sans(size: 9.5, weight: FontWeight.w600, color: copyColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (footer != null) ...[const SizedBox(height: 6), footer!],
      ],
    );
  }
}
