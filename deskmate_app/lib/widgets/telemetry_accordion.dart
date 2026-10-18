import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

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
  late bool _isExpanded;
  final Set<int> _expandedSteps = {};
  int? _copiedStepIndex;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isActive || widget.initiallyExpanded;
    // By default, if active, auto-expand the latest step
    if (widget.isActive && widget.steps.isNotEmpty) {
      _expandedSteps.add(widget.steps.length - 1);
    }
  }

  @override
  void didUpdateWidget(TelemetryAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _isExpanded = true;
    }
    // If a new step arrives while active, keep it expanded for live tracking
    if (widget.isActive && widget.steps.length > oldWidget.steps.length) {
      _expandedSteps.add(widget.steps.length - 1);
    }
  }

  void _toggleStep(int index) {
    setState(() {
      if (_expandedSteps.contains(index)) {
        _expandedSteps.remove(index);
      } else {
        _expandedSteps.add(index);
      }
    });
  }

  void _toggleAllSteps() {
    setState(() {
      if (_expandedSteps.length == widget.steps.length) {
        _expandedSteps.clear();
      } else {
        _expandedSteps.addAll(List.generate(widget.steps.length, (i) => i));
      }
    });
  }

  void _copyContent(String text, String label, int stepIndex) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() {
      _copiedStepIndex = stepIndex;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          if (_copiedStepIndex == stepIndex) _copiedStepIndex = null;
        });
      }
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 240,
      ),
    );
  }

  static String _friendlyToolName(String? tool) {
    if (tool == null || tool.isEmpty) return 'Tool Execution';
    switch (tool.toLowerCase()) {
      case 'list_directory':
        return 'Directory Inspection';
      case 'read_file':
        return 'Document Reader';
      case 'search_files':
        return 'File Search';
      case 'index_document':
        return 'Index Document Embeddings (Qdrant)';
      case 'search_qdrant':
        return 'Vector Search (Qdrant Embeddings)';
      case 'get_datetime':
        return 'System Clock';
      case 'save_to_memory':
        return 'Store Embedding Memory (FAISS)';
      case 'recall_memory':
      case 'search_memory':
        return 'Vector Search (FAISS Embeddings)';
      case 'duckduckgo_search':
        return 'Web Research';
      case 'web_search':
        return 'Web Search (DuckDuckGo)';
      case 'get_unread_emails':
        return 'Gmail Inbox (Unread)';
      case 'search_emails':
        return 'Gmail Search';
      case 'send_email':
        return 'Send Email';
      case 'reply_email':
        return 'Reply Email';
      case 'delete_email':
        return 'Delete Email';
      case 'mark_email_read':
        return 'Mark Email Read';
      case 'create_draft_email':
        return 'Draft Email';
      case 'list_calendar_events':
      case 'list_events':
        return 'Google Calendar Agenda';
      case 'create_calendar_event':
      case 'create_event':
        return 'Schedule Calendar Event';
      case 'delete_calendar_event':
        return 'Delete Calendar Event';
      case 'update_calendar_event':
        return 'Update Calendar Event';
      case 'search_drive_files':
      case 'search_drive':
        return 'Google Drive Search';
      case 'read_drive_file':
        return 'Google Drive Reader';
      case 'create_drive_file':
        return 'Create Drive File';
      case 'delete_drive_file':
        return 'Delete Drive File';
      case 'list_google_tasks':
        return 'Google Tasks List';
      case 'create_google_task':
        return 'Create Google Task';
      case 'complete_google_task':
        return 'Complete Google Task';
      case 'run_sql_query':
        return 'SQL Database Query (SQLite)';
      case 'list_tasks':
        return 'List Tasks (SQLite DB)';
      case 'add_task':
        return 'Add Task (SQLite DB)';
      case 'complete_task':
        return 'Complete Task (SQLite DB)';
      case 'save_note':
        return 'Save Note (SQLite DB)';
      case 'search_notes':
        return 'Search Notes (SQLite DB)';
      case 'get_weather':
        return 'Live Weather Forecast';
      case 'search_github_issues':
        return 'Search GitHub Issues';
      case 'create_github_issue':
        return 'Create GitHub Issue';
      default:
        return tool
            .split('_')
            .map((w) {
              if (w.isEmpty) return '';
              return w[0].toUpperCase() + w.substring(1);
            })
            .join(' ');
    }
  }

  static String _formatJson(dynamic data) {
    if (data == null) return '{}';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  static String _cleanKey(String key) {
    switch (key.toLowerCase()) {
      case 'directory_path':
        return 'path';
      case 'file_path':
        return 'file';
      case 'pattern':
        return 'pattern';
      case 'query':
        return 'query';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty && !widget.isActive) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final count = widget.steps.length;
    final toolCallsCount = widget.steps
        .where((s) => s.phase == 'tool_call')
        .length;
    final obsCount = widget.steps.where((s) => s.phase == 'observation').length;
    final reasoningCount = widget.steps
        .where((s) => s.phase == 'reasoning')
        .length;

    String headerSummary;
    if (widget.isActive) {
      headerSummary =
          widget.activeTitle ??
          'Agent executing workflow: Tool Call ➔ LLM Analysis...';
    } else {
      headerSummary =
          '$count step${count > 1 ? 's' : ''} · $toolCallsCount Action${toolCallsCount > 1 ? 's' : ''}, $obsCount Result${obsCount > 1 ? 's' : ''}, $reasoningCount Thought${reasoningCount > 1 ? 's' : ''}';
    }

    final allExpanded =
        widget.steps.isNotEmpty && _expandedSteps.length == widget.steps.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgSubtle : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Main Accordion Header ──────────────────────────────────────
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  if (widget.isActive) ...[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.accentFg,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else ...[
                    Icon(Icons.hub_outlined, size: 15, color: theme.accentFg),
                    const SizedBox(width: 10),
                  ],
                  // Header Title
                  Expanded(
                    child: Text(
                      headerSummary,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // "Expand all" toggle (only when accordion is open)
                  if (_isExpanded && widget.steps.isNotEmpty) ...[
                    InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: _toggleAllSteps,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.isDark
                              ? const Color(0xFF1E232B)
                              : const Color(0xFFEFF2F5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.borderDefault,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          allExpanded ? 'Collapse details' : 'Inspect all',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.accentFg,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // "Hide / View process" toggle button
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? const Color(0xFF21262D)
                          : const Color(0xFFEAEEF2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.borderDefault, width: 1),
                    ),
                    child: Text(
                      _isExpanded ? 'Hide process' : 'View process',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: theme.fgMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: theme.fgMuted,
                  ),
                ],
              ),
            ),
          ),

          // ─── Interactive Workflow Timeline Body ─────────────────────────
          if (_isExpanded && widget.steps.isNotEmpty) ...[
            Divider(height: 1, color: theme.borderDefault),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < widget.steps.length; i++)
                    _buildInteractiveTimelineStep(
                      widget.steps[i],
                      i,
                      i == widget.steps.length - 1,
                      theme,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInteractiveTimelineStep(
    AgentStepTelemetry step,
    int index,
    bool isLast,
    ThemeData theme,
  ) {
    final isTool = step.phase == 'tool_call';
    final isObs = step.phase == 'observation';
    final isReasoning = step.phase == 'reasoning' || (!isTool && !isObs);
    final isStepExpanded = _expandedSteps.contains(index);

    final rawTool = (step.tool ?? '').toLowerCase();
    final isVectorTool =
        rawTool == 'recall_memory' ||
        rawTool == 'save_to_memory' ||
        rawTool == 'search_memory' ||
        rawTool == 'search_qdrant' ||
        rawTool == 'index_document';
    final isDbTool =
        rawTool == 'run_sql_query' ||
        rawTool == 'search_notes' ||
        rawTool == 'save_note' ||
        rawTool == 'list_tasks' ||
        rawTool == 'add_task' ||
        rawTool == 'complete_task';

    IconData icon;
    Color nodeColor;
    String stageBadge;
    String primaryTitle;
    String inlineMeta = '';

    if (isTool) {
      if (isVectorTool) {
        icon = Icons.hub_rounded;
        nodeColor = const Color(0xFF8250DF); // GitHub Purple
        stageBadge =
            (rawTool == 'save_to_memory' || rawTool == 'index_document')
            ? 'VECTOR EMBEDDING STORE'
            : 'VECTOR EMBEDDING SEARCH';
      } else if (isDbTool) {
        icon = Icons.storage_rounded;
        nodeColor = const Color(0xFFD29922); // GitHub Amber
        stageBadge = rawTool == 'run_sql_query'
            ? 'DATABASE QUERY (SQL)'
            : 'DATABASE TRANSACTION';
      } else {
        icon = Icons.terminal_rounded;
        nodeColor = const Color(0xFF0969DA); // GitHub Blue
        stageBadge = 'TOOL CALL';
      }
      final toolLabel = _friendlyToolName(step.tool);
      final displayTool = step.tool ?? 'tool';
      // Inline argument preview
      String argPreview = '';
      if (step.arguments != null && step.arguments is Map) {
        final entries = (step.arguments as Map).entries
            .take(2)
            .map((e) => '${_cleanKey(e.key.toString())}: "${e.value}"');
        argPreview = entries.join(', ');
      }
      primaryTitle = toolLabel;
      inlineMeta = argPreview.isNotEmpty
          ? '$displayTool($argPreview)'
          : displayTool;
    } else if (isObs) {
      final summary = step.summary ?? '';
      final isWarning =
          summary.contains("is not a valid directory") ||
          summary.contains("Error:");

      if (isWarning) {
        icon = Icons.info_outline_rounded;
        nodeColor = const Color(0xFFD29922);
        stageBadge = 'SYSTEM NOTICE';
        primaryTitle = 'Path Adjustment';
      } else if (isVectorTool) {
        icon = Icons.grain_rounded;
        nodeColor = const Color(0xFF8250DF);
        stageBadge = 'EMBEDDING RESULTS';
        primaryTitle =
            (rawTool == 'index_document' || rawTool == 'save_to_memory')
            ? 'Vector Index Updated'
            : 'Semantic Embeddings Retrieved';
      } else if (isDbTool) {
        icon = Icons.dns_rounded;
        nodeColor = const Color(0xFF2DA44E); // Green
        stageBadge = 'DATABASE RESULTS';
        primaryTitle = rawTool == 'run_sql_query'
            ? 'SQL Query Results'
            : 'Database Records Found';
      } else {
        icon = Icons.check_circle_rounded;
        nodeColor = const Color(0xFF2DA44E); // Green
        stageBadge = 'OBSERVATION';
        primaryTitle = 'Findings Received';
      }

      if (isVectorTool || isDbTool) {
        final firstLine = summary.split('\n').first.trim();
        inlineMeta = firstLine.length > 55
            ? '${firstLine.substring(0, 52)}...'
            : firstLine;
      } else {
        // Smart concise summary for the preview row
        final dirCount = RegExp(r'\[DIR\]').allMatches(summary).length;
        final fileCount = RegExp(r'\[FILE\]').allMatches(summary).length;
        if (dirCount > 0 || fileCount > 0) {
          inlineMeta = '$dirCount folders, $fileCount files discovered';
        } else if (summary.contains("is not a valid directory")) {
          inlineMeta = 'Adjusted to absolute path';
        } else {
          inlineMeta = summary.split('\n').first.trim();
          if (inlineMeta.length > 55) {
            inlineMeta = '${inlineMeta.substring(0, 52)}...';
          }
        }
      }
    } else {
      icon = Icons.psychology_rounded;
      nodeColor = const Color(0xFF8250DF); // GitHub Purple
      stageBadge = 'AI REASONING';
      primaryTitle = 'LLM Deliberation';
      final firstThought = (step.summary ?? '').split('\n').first.trim();
      inlineMeta = firstThought.length > 55
          ? '${firstThought.substring(0, 52)}...'
          : firstThought;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Timeline Node & Vertical Connector ──────────────────────────
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: nodeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: nodeColor, width: 1.5),
                  ),
                  child: Center(child: Icon(icon, size: 11, color: nodeColor)),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: theme.borderDefault,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ─── Timeline Step Card ──────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10.0),
              child: Container(
                decoration: BoxDecoration(
                  color: isStepExpanded
                      ? (theme.isDark
                            ? const Color(0xFF141820)
                            : const Color(0xFFFFFFFF))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isStepExpanded
                      ? Border.all(
                          color: nodeColor.withValues(alpha: 0.35),
                          width: 1,
                        )
                      : Border.all(color: Colors.transparent, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Clickable Step Header Bar
                    InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () => _toggleStep(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isStepExpanded ? 10 : 4,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            // Phase Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: nodeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: nodeColor.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                stageBadge,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: nodeColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Primary Label
                            Text(
                              primaryTitle,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: theme.fgDefault,
                              ),
                            ),

                            // Inline preview summary
                            if (inlineMeta.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  inlineMeta,
                                  style: TextStyle(
                                    fontFamily: isTool ? 'monospace' : null,
                                    fontSize: 10.5,
                                    color: theme.fgMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else
                              const Spacer(),

                            // Execution Duration Badge
                            if (step.durationMs != null &&
                                step.durationMs! > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.isDark
                                      ? const Color(0xFF21262D)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${step.durationMs}ms',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9.5,
                                    color: theme.fgMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(width: 6),
                            // Expand / Inspect Chevron Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isStepExpanded
                                    ? nodeColor.withValues(alpha: 0.15)
                                    : (theme.isDark
                                          ? const Color(0xFF1E232B)
                                          : const Color(0xFFEAEEF2)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isStepExpanded ? 'Close' : 'Inspect',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: isStepExpanded
                                          ? nodeColor
                                          : theme.fgMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    isStepExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 13,
                                    color: isStepExpanded
                                        ? nodeColor
                                        : theme.fgMuted,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ─── Expanded Transparent Inspector Panel ─────────────────
                    if (isStepExpanded) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(
                              height: 12,
                              color: theme.borderDefault.withValues(alpha: 0.6),
                            ),

                            // 1. Tool Call Arguments Inspector
                            if (isTool)
                              _buildToolArgumentsInspector(step, index, theme),

                            // 2. Observation / Raw Findings Inspector
                            if (isObs)
                              _buildObservationInspector(step, index, theme),

                            // 3. AI Reasoning Thought Inspector
                            if (isReasoning)
                              _buildReasoningInspector(step, index, theme),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tool Call Arguments Inspector Panel ─────────────────────────────────
  Widget _buildToolArgumentsInspector(
    AgentStepTelemetry step,
    int stepIndex,
    ThemeData theme,
  ) {
    final rawTool = (step.tool ?? '').toLowerCase();
    final isVectorTool =
        rawTool == 'recall_memory' ||
        rawTool == 'save_to_memory' ||
        rawTool == 'search_memory' ||
        rawTool == 'search_qdrant' ||
        rawTool == 'index_document';
    final isDbTool =
        rawTool == 'run_sql_query' ||
        rawTool == 'search_notes' ||
        rawTool == 'save_note' ||
        rawTool == 'list_tasks' ||
        rawTool == 'add_task' ||
        rawTool == 'complete_task';

    final panelTitle = isVectorTool
        ? 'Vector Search Parameters'
        : (isDbTool ? 'Database Query Parameters' : 'Input Arguments Payload');
    final panelIcon = isVectorTool
        ? Icons.hub_rounded
        : (isDbTool ? Icons.storage_rounded : Icons.input_rounded);

    final args = step.arguments ?? {};
    final jsonStr = _formatJson(args);
    final isCopied = _copiedStepIndex == stepIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(panelIcon, size: 12, color: theme.fgMuted),
            const SizedBox(width: 5),
            Text(
              panelTitle,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: theme.fgDefault,
              ),
            ),
            const Spacer(),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () =>
                  _copyContent(jsonStr, 'Arguments payload', stepIndex),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isCopied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 11,
                      color: isCopied
                          ? const Color(0xFF2DA44E)
                          : theme.accentFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCopied ? 'Copied' : 'Copy JSON',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isCopied
                            ? const Color(0xFF2DA44E)
                            : theme.accentFg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Monospace Code Container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.isDark
                ? const Color(0xFF0D1117)
                : const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 0.8),
          ),
          child: SelectionArea(
            child: Text(
              jsonStr,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
                color: theme.isDark
                    ? const Color(0xFF7EE787)
                    : const Color(0xFF116329),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Observation / Findings Inspector Panel ──────────────────────────────
  Widget _buildObservationInspector(
    AgentStepTelemetry step,
    int stepIndex,
    ThemeData theme,
  ) {
    final rawTool = (step.tool ?? '').toLowerCase();
    final isVectorTool =
        rawTool == 'recall_memory' ||
        rawTool == 'save_to_memory' ||
        rawTool == 'search_memory' ||
        rawTool == 'search_qdrant' ||
        rawTool == 'index_document';
    final isDbTool =
        rawTool == 'run_sql_query' ||
        rawTool == 'search_notes' ||
        rawTool == 'save_note' ||
        rawTool == 'list_tasks' ||
        rawTool == 'add_task' ||
        rawTool == 'complete_task';

    final panelTitle = isVectorTool
        ? 'Semantic Vector Findings (Embeddings)'
        : (isDbTool
              ? 'Database Records (SQLite Data)'
              : 'Observation & Findings Data');
    final panelIcon = isVectorTool
        ? Icons.grain_rounded
        : (isDbTool ? Icons.dns_rounded : Icons.output_rounded);

    // Show full raw output if available, else summary
    final fullText = (step.rawOutput != null && step.rawOutput!.isNotEmpty)
        ? step.rawOutput!
        : (step.summary ?? 'No data returned.');
    final lineCount = fullText.split('\n').length;
    final isCopied = _copiedStepIndex == stepIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(panelIcon, size: 12, color: theme.fgMuted),
            const SizedBox(width: 5),
            Text(
              panelTitle,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: theme.fgDefault,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF21262D)
                    : const Color(0xFFEAEEF2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$lineCount line${lineCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  color: theme.fgMuted,
                ),
              ),
            ),
            const Spacer(),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => _copyContent(fullText, 'Output data', stepIndex),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isCopied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 11,
                      color: isCopied
                          ? const Color(0xFF2DA44E)
                          : theme.accentFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCopied ? 'Copied' : 'Copy Output',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isCopied
                            ? const Color(0xFF2DA44E)
                            : theme.accentFg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Scrollable Raw Data Box
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.isDark
                ? const Color(0xFF0D1117)
                : const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 0.8),
          ),
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Text(
                fullText,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  height: 1.45,
                  color: theme.fgDefault,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),
        // Pipeline indicator
        Row(
          children: [
            Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 13,
              color: theme.fgMuted,
            ),
            const SizedBox(width: 4),
            Text(
              'Transferred as context into next LLM deliberation phase',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: theme.fgMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── AI Reasoning Thought Inspector Panel ────────────────────────────────
  Widget _buildReasoningInspector(
    AgentStepTelemetry step,
    int stepIndex,
    ThemeData theme,
  ) {
    final thoughtText = step.rawOutput ?? step.summary ?? '';
    final isCopied = _copiedStepIndex == stepIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.psychology_rounded,
              size: 13,
              color: const Color(0xFF8250DF),
            ),
            const SizedBox(width: 5),
            Text(
              'Model Strategy & Chain-of-Thought',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: theme.fgDefault,
              ),
            ),
            const Spacer(),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () =>
                  _copyContent(thoughtText, 'Thought process', stepIndex),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isCopied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 11,
                      color: isCopied
                          ? const Color(0xFF2DA44E)
                          : const Color(0xFF8250DF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCopied ? 'Copied' : 'Copy Thought',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isCopied
                            ? const Color(0xFF2DA44E)
                            : const Color(0xFF8250DF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Reasoning Text Card
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.isDark
                ? const Color(0xFF1E1528)
                : const Color(0xFFF7F2FD),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.isDark
                  ? const Color(0xFF4C2889)
                  : const Color(0xFFD8B4FE),
              width: 0.8,
            ),
          ),
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Text(
                thoughtText,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: theme.isDark
                      ? const Color(0xFFE2C5FF)
                      : const Color(0xFF552299),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
