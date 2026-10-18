import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';

/// SQLite Database Explorer Dialog
///
/// A luxury macOS / Linear-style relational database explorer for DeskMate.
/// Features:
/// - Real-time introspection of local SQLite tables (`tasks`, `notes`, `memories`).
/// - Zero-overflow responsive grid with horizontal scrolling safety.
/// - Modular "box-of-design" sidebar cards with table-specific theming.
/// - Precision-aligned IDE status bar with live engine indicators and keyboard hints.
/// - Full interactive Database & Storage User Guide modal.
/// - Interactive Record Inspector modal on double-click.
/// - Safe read-only SQL Query Console with millisecond performance benchmarks.
class DatabaseExplorerDialog extends StatefulWidget {
  final VoidCallback onClose;

  const DatabaseExplorerDialog({super.key, required this.onClose});

  @override
  State<DatabaseExplorerDialog> createState() => _DatabaseExplorerDialogState();
}

class _DatabaseExplorerDialogState extends State<DatabaseExplorerDialog> {
  // Navigation: 0 = Tables & Records, 1 = SQL Query Console
  int _selectedTabIndex = 0;

  // DB Overview State
  bool _isLoadingOverview = true;
  String? _overviewError;
  Map<String, dynamic> _overviewData = {};
  List<Map<String, dynamic>> _tables = [];
  String _activeTableName = '';

  // Table Data State
  bool _isLoadingTableData = false;
  String? _tableDataError;
  List<String> _tableColumns = [];
  List<Map<String, dynamic>> _tableRows = [];
  String _filterQuery = '';
  final TextEditingController _filterController = TextEditingController();

  // Scroll controllers for synced table views
  final ScrollController _tableHorizontalScroll = ScrollController();
  final ScrollController _queryHorizontalScroll = ScrollController();

  // SQL Query Console State
  final TextEditingController _queryController = TextEditingController(
    text: 'SELECT * FROM tasks ORDER BY id DESC LIMIT 20;',
  );
  bool _isExecutingQuery = false;
  String? _queryError;
  List<String> _queryColumns = [];
  List<Map<String, dynamic>> _queryRows = [];
  int? _queryExecutionDurationMs;
  bool _hasExecutedQuery = false;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  @override
  void dispose() {
    _filterController.dispose();
    _queryController.dispose();
    _tableHorizontalScroll.dispose();
    _queryHorizontalScroll.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _isLoadingOverview = true;
      _overviewError = null;
    });

    try {
      final apiService = context.read<ChatProvider>().apiService;
      final overview = await apiService.getDatabaseOverview();

      if (overview['status'] == 'offline') {
        setState(() {
          _isLoadingOverview = false;
          _overviewError =
              'Database service is currently offline or unreachable.';
        });
        return;
      }

      final rawTables = overview['tables'] as List<dynamic>? ?? [];
      final parsedTables = rawTables
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();

      String initialTable = _activeTableName;
      if (initialTable.isEmpty && parsedTables.isNotEmpty) {
        initialTable = parsedTables.first['name']?.toString() ?? '';
      }

      setState(() {
        _isLoadingOverview = false;
        _overviewData = overview;
        _tables = parsedTables;
        _activeTableName = initialTable;
      });

      if (initialTable.isNotEmpty) {
        await _loadTableData(initialTable);
      }
    } catch (e) {
      setState(() {
        _isLoadingOverview = false;
        _overviewError = 'Failed to load database overview: $e';
      });
    }
  }

  Future<void> _loadTableData(String tableName) async {
    setState(() {
      _activeTableName = tableName;
      _isLoadingTableData = true;
      _tableDataError = null;
      _filterQuery = '';
      _filterController.clear();
    });

    try {
      final apiService = context.read<ChatProvider>().apiService;
      final data = await apiService.getDatabaseTableData(tableName, limit: 300);

      if (data['status'] == 'error') {
        setState(() {
          _isLoadingTableData = false;
          _tableDataError =
              data['detail'] ?? 'Failed to load data for $tableName';
        });
        return;
      }

      final rawCols = data['columns'] as List<dynamic>? ?? [];
      final rawRows = data['rows'] as List<dynamic>? ?? [];

      setState(() {
        _isLoadingTableData = false;
        _tableColumns = rawCols.map((c) => c.toString()).toList();
        _tableRows = rawRows
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      });
    } catch (e) {
      setState(() {
        _isLoadingTableData = false;
        _tableDataError = 'Error fetching rows: $e';
      });
    }
  }

  Future<void> _runCustomQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isExecutingQuery = true;
      _queryError = null;
      _hasExecutedQuery = true;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final apiService = context.read<ChatProvider>().apiService;
      final result = await apiService.executeDatabaseQuery(query);
      stopwatch.stop();

      if (result['status'] == 'error') {
        setState(() {
          _isExecutingQuery = false;
          _queryError = result['error'] ?? 'SQL execution error.';
          _queryColumns = [];
          _queryRows = [];
          _queryExecutionDurationMs = stopwatch.elapsedMilliseconds;
        });
        return;
      }

      final rawCols = result['columns'] as List<dynamic>? ?? [];
      final rawRows = result['rows'] as List<dynamic>? ?? [];

      setState(() {
        _isExecutingQuery = false;
        _queryColumns = rawCols.map((c) => c.toString()).toList();
        _queryRows = rawRows
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _queryExecutionDurationMs = stopwatch.elapsedMilliseconds;
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _isExecutingQuery = false;
        _queryError = 'Execution failed: $e';
        _queryColumns = [];
        _queryRows = [];
        _queryExecutionDurationMs = stopwatch.elapsedMilliseconds;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showRecordDetailsDialog(Map<String, dynamic> row) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              width: 560,
              constraints: const BoxConstraints(maxHeight: 580),
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.bgCanvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.borderDefault, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.isDark ? 0.65 : 0.22,
                    ),
                    blurRadius: 36,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          bottom: BorderSide(
                            color: theme.borderDefault,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.accentFg.withValues(
                                alpha: theme.isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: theme.accentFg.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Icon(
                              Icons.feed_rounded,
                              size: 15,
                              color: theme.accentFg,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Record Details',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: theme.fgDefault,
                                ),
                              ),
                              const SizedBox(height: 1.5),
                              Text(
                                'Inspecting row from "$_activeTableName"',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.fgMuted,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: IconButton(
                              mouseCursor: SystemMouseCursors.click,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => Navigator.of(ctx).pop(),
                              splashRadius: 16,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: row.entries.map((entry) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 9),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.isDark
                                    ? const Color(0xFF181B22)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.borderDefault,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: theme.isDark ? 0.25 : 0.03,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        entry.key.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                          color: theme.accentFg,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const Spacer(),
                                      MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: InkWell(
                                          mouseCursor: SystemMouseCursors.click,
                                          onTap: () => _copyToClipboard(
                                            entry.value?.toString() ?? '',
                                            'Field "${entry.key}"',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: Tooltip(
                                            message: 'Copy ${entry.key}',
                                            child: Padding(
                                              padding: const EdgeInsets.all(3),
                                              child: Icon(
                                                Icons.copy_rounded,
                                                size: 13,
                                                color: theme.fgMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  SelectableText(
                                    entry.value == null
                                        ? 'NULL'
                                        : entry.value.toString(),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: entry.value == null
                                          ? theme.fgMuted.withValues(
                                              alpha: 0.55,
                                            )
                                          : theme.fgDefault,
                                      fontFamily:
                                          (entry.key.toLowerCase().contains(
                                                'date',
                                              ) ||
                                              entry.key.toLowerCase().contains(
                                                'time',
                                              ) ||
                                              entry.key.toLowerCase() == 'id' ||
                                              num.tryParse(
                                                    entry.value?.toString() ??
                                                        '',
                                                  ) !=
                                                  null)
                                          ? 'monospace'
                                          : null,
                                      fontStyle: entry.value == null
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    // Footer
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          top: BorderSide(color: theme.borderDefault, width: 1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.copy_all_rounded,
                                size: 13.5,
                                color: theme.fgDefault,
                              ),
                              label: Text(
                                'Copy JSON',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.fgDefault,
                                ),
                              ),
                              style: ButtonStyle(
                                mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click,
                                ),
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                ),
                                side: WidgetStateProperty.all(
                                  BorderSide(color: theme.borderDefault),
                                ),
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              onPressed: () {
                                _copyToClipboard(
                                  jsonEncode(row),
                                  'Record JSON',
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: ButtonStyle(
                                mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click,
                                ),
                                backgroundColor: WidgetStateProperty.all(
                                  theme.accentFg,
                                ),
                                foregroundColor: WidgetStateProperty.all(
                                  Colors.white,
                                ),
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                ),
                                elevation: WidgetStateProperty.all(0),
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDatabaseGuideDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              width: 660,
              height: 600,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.bgCanvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.borderDefault, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.isDark ? 0.7 : 0.25,
                    ),
                    blurRadius: 40,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    // Guide Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          bottom: BorderSide(
                            color: theme.borderDefault,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.accentFg.withValues(
                                alpha: theme.isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.accentFg.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              size: 16,
                              color: theme.accentFg,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DeskMate SQLite & Storage Guide',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: theme.fgDefault,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 1.5),
                                Text(
                                  'Everything you need to know about your offline personal data',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.fgMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: IconButton(
                              mouseCursor: SystemMouseCursors.click,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => Navigator.of(ctx).pop(),
                              splashRadius: 14,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Guide Body Cards with Visible Scrollbar
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildGuideCard(
                                theme: theme,
                                icon: Icons.shield_rounded,
                                title:
                                    '100% Offline & Private Local SSD Storage',
                                badge: 'Private & Secure',
                                description:
                                    'DeskMate stores all persistent personal data in an embedded SQLite 3 database ("deskmate_agent.db") located on your local Mac SSD inside ~/Library/Application Support/DeskMate/. There are zero external servers, zero telemetry tracking, and zero cloud DB syncs. Your data is strictly yours.',
                              ),
                              const SizedBox(height: 14),

                              Row(
                                children: [
                                  Icon(
                                    Icons.hub_outlined,
                                    size: 13,
                                    color: theme.accentFg,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'HOW DATA ARRIVES IN EACH TABLE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: theme.accentFg,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: theme.borderDefault.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              _buildGuideCard(
                                theme: theme,
                                icon: Icons.task_alt_rounded,
                                title: 'tasks',
                                isMonospaceTitle: true,
                                badge: 'Tasks, Deadlines & Todos',
                                description:
                                    'Populated automatically whenever you instruct DeskMate to track, schedule, or complete tasks (e.g. "Add a task to review PR by 5 PM", "Mark audit task as completed").',
                                schema:
                                    'id (PK) • title • priority (HIGH/MEDIUM/LOW) • due_date • done (0/1) • created_at',
                              ),
                              const SizedBox(height: 10),

                              _buildGuideCard(
                                theme: theme,
                                icon: Icons.sticky_note_2_rounded,
                                title: 'notes',
                                isMonospaceTitle: true,
                                badge: 'Quick Notes & Scratchpad',
                                description:
                                    'Populated when you instruct DeskMate to jot down snippets or scratch notes (e.g. "Take a note: Meeting room is 402", "Note down API key format").',
                                schema: 'id (PK) • content • tags • created_at',
                              ),
                              const SizedBox(height: 10),

                              _buildGuideCard(
                                theme: theme,
                                icon: Icons.psychology_rounded,
                                title: 'memories',
                                isMonospaceTitle: true,
                                badge: 'Persistent AI Context',
                                description:
                                    'Populated when you share long-term facts, rules, or personal preferences (e.g. "Remember that I prefer dark theme", "Remember my name is Ganesh"). DeskMate loads these memories across every session to tailor its responses.',
                                schema: 'id (PK) • content • tags • created_at',
                              ),
                              const SizedBox(height: 14),

                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    size: 13,
                                    color: theme.accentFg,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'SYSTEM INTEGRITY & WORKFLOW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: theme.accentFg,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: theme.borderDefault.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              _buildGuideCard(
                                theme: theme,
                                icon: Icons.save_rounded,
                                title:
                                    'Does "New Conversation" delete my database?',
                                badge: '100% Persistent',
                                description:
                                    'ABSOLUTELY NOT. Clicking "New Conversation" only resets the in-memory chat transcript and LLM context buffer for that conversation ID so you get a fresh prompt window. Your SQLite database file on disk remains 100% persistent across new chats, app restarts, and machine reboots.',
                              ),
                              const SizedBox(height: 10),

                              _buildGuideCard(
                                theme: theme,
                                icon: Icons.terminal_rounded,
                                title: 'How to use this Explorer',
                                badge: 'Read-Only Console',
                                customBody: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildGuideBulletRow(
                                      theme,
                                      'Live Keyword Filter',
                                      'Type keywords in the search bar to filter table records in real time.',
                                    ),
                                    const SizedBox(height: 6),
                                    _buildGuideBulletRow(
                                      theme,
                                      'Record Inspector',
                                      'Double-click any row in the table to view multiline text and copy individual columns.',
                                    ),
                                    const SizedBox(height: 6),
                                    _buildGuideBulletRow(
                                      theme,
                                      'Safe SQL Console',
                                      'Switch to the "SQL Query Console" tab to run custom SELECT queries with millisecond execution benchmarks.',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Guide Footer
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          top: BorderSide(color: theme.borderDefault, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: theme.accentFg,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Safe read-only explorer • Zero risk of data loss',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.fgMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: ButtonStyle(
                                mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click,
                                ),
                                backgroundColor: WidgetStateProperty.all(
                                  theme.accentFg,
                                ),
                                foregroundColor: WidgetStateProperty.all(
                                  Colors.white,
                                ),
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                ),
                                elevation: WidgetStateProperty.all(0),
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Got it',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuideCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    String? badge,
    String? description,
    Widget? customBody,
    String? schema,
    bool isMonospaceTitle = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF181B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderDefault, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.25 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.accentFg.withValues(
                    alpha: theme.isDark ? 0.16 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(6.5),
                  border: Border.all(
                    color: theme.accentFg.withValues(alpha: 0.32),
                    width: 0.8,
                  ),
                ),
                child: Icon(icon, size: 14.5, color: theme.accentFg),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: isMonospaceTitle ? 'monospace' : null,
                  color: theme.fgDefault,
                  letterSpacing: isMonospaceTitle ? 0.2 : -0.1,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.5,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(
                      alpha: theme.isDark ? 0.14 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(4.5),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.28),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: theme.accentFg,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.fgMuted,
                height: 1.45,
              ),
            ),
          ],
          if (customBody != null) ...[const SizedBox(height: 8), customBody],
          if (schema != null) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
              decoration: BoxDecoration(
                color: theme.isDark ? theme.bgInset : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.borderDefault.withValues(alpha: 0.65),
                  width: 0.8,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SCHEMA: ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: theme.accentFg,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      schema,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: theme.fgDefault,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuideBulletRow(ThemeData theme, String boldPrefix, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6, right: 8),
          width: 4.5,
          height: 4.5,
          decoration: BoxDecoration(
            color: theme.accentFg,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$boldPrefix: ',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: theme.fgDefault,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.fgMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredTableRows {
    if (_filterQuery.isEmpty) return _tableRows;
    final q = _filterQuery.toLowerCase();
    return _tableRows.where((row) {
      return row.values.any((val) {
        if (val == null) return false;
        return val.toString().toLowerCase().contains(q);
      });
    }).toList();
  }

  IconData _getTableIcon(String tableName) {
    switch (tableName.toLowerCase()) {
      case 'tasks':
        return Icons.task_alt_rounded;
      case 'notes':
        return Icons.sticky_note_2_rounded;
      case 'memories':
        return Icons.psychology_rounded;
      default:
        return Icons.table_chart_rounded;
    }
  }

  String _getTableSubtitle(String tableName) {
    switch (tableName.toLowerCase()) {
      case 'tasks':
        return 'Todo items, deadlines & task states';
      case 'notes':
        return 'Saved notes, snippets & scratchpad';
      case 'memories':
        return 'AI preferences & user context';
      default:
        return 'Relational SQLite storage table';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final dialogWidth = min(size.width * 0.94, 1100.0);
    final dialogHeight = min(size.height * 0.88, 700.0);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          decoration: BoxDecoration(
            color: theme.bgCanvas,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.borderDefault, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.isDark ? 0.65 : 0.22,
                ),
                blurRadius: 40,
                spreadRadius: 2,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUnifiedHeader(theme),
                _buildLiveStatusBar(theme),
                Expanded(
                  child: _isLoadingOverview
                      ? _buildLoadingState(
                          theme,
                          'Connecting to SQLite Database...',
                        )
                      : (_overviewError != null
                            ? _buildErrorBanner(theme, _overviewError!)
                            : (_selectedTabIndex == 0
                                  ? _buildTablesView(theme)
                                  : _buildQueryConsoleView(theme))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 1. TOP HEADER BAR (Clean, Elegant, Matching Image 4 Architecture)
  // =========================================================================
  Widget _buildUnifiedHeader(ThemeData theme) {
    final dbPath = _overviewData['path']?.toString() ?? 'deskmate_agent.db';
    final dbFileName = dbPath.split('/').last.split('\\').last;
    final sizeKb = _overviewData['size_kb']?.toString() ?? '20.0';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgCanvas : Colors.white,
        border: Border(
          bottom: BorderSide(color: theme.borderDefault, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Clean 32x32 Milky Icon Tile (Matching Image 4)
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accentFg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentFg.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Icon(Icons.storage_rounded, size: 17, color: theme.accentFg),
          ),
          const SizedBox(width: 12),

          // Title & Clean Subtitle (Not clumsy, matching Image 4!)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SQLite Database Explorer',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1.5),
                Text(
                  'Local SSD storage ("$dbFileName" • $sizeKb KB)',
                  style: TextStyle(fontSize: 11.5, color: theme.fgMuted),
                ),
              ],
            ),
          ),

          // Right: Segmented Switcher (Exact match to Image 2!)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF161B22)
                  : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentTab(
                  theme: theme,
                  title: 'Tables & Records',
                  icon: Icons.table_chart_rounded,
                  isSelected: _selectedTabIndex == 0,
                  onTap: () => setState(() => _selectedTabIndex = 0),
                ),
                const SizedBox(width: 3),
                _buildSegmentTab(
                  theme: theme,
                  title: 'SQL Query Console',
                  icon: Icons.terminal_rounded,
                  isSelected: _selectedTabIndex == 1,
                  onTap: () => setState(() => _selectedTabIndex = 1),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),
          Container(
            width: 1,
            height: 20,
            color: theme.borderDefault.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),

          // Refresh Button with mouse pointer
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: IconButton(
              mouseCursor: SystemMouseCursors.click,
              icon: Icon(Icons.refresh_rounded, size: 18, color: theme.fgMuted),
              tooltip: 'Refresh Database',
              hoverColor: theme.bgEmphasis,
              splashRadius: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _loadOverview,
            ),
          ),
          const SizedBox(width: 4),

          // Close Button with mouse pointer
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: IconButton(
              mouseCursor: SystemMouseCursors.click,
              icon: Icon(Icons.close_rounded, size: 19, color: theme.fgMuted),
              tooltip: 'Close (Esc)',
              hoverColor: theme.bgEmphasis,
              splashRadius: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: widget.onClose,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 1B. LIVE STATUS BAR (Matching Image 3 & 4 Credentials Setup Dialog!)
  // =========================================================================
  Widget _buildLiveStatusBar(ThemeData theme) {
    final isOnline = _overviewData['status'] == 'ok';
    final dbPath = _overviewData['path']?.toString() ?? 'deskmate_agent.db';
    final dbFileName = dbPath.split('/').last.split('\\').last;
    final sizeKb = _overviewData['size_kb']?.toString() ?? '20.0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6.5),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgSubtle : const Color(0xFFF6F8FA),
        border: Border(
          bottom: BorderSide(color: theme.borderDefault, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'LIVE STATUS:',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: theme.fgMuted,
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusPill(
              theme,
              'Local DB',
              isOnline ? 'Ready (SQLite)' : 'Offline',
              isOnline,
            ),
            const SizedBox(width: 6),
            _buildStatusPill(theme, 'Engine', 'SQLite 3.x (Offline)', true),
            const SizedBox(width: 6),
            _buildStatusPill(theme, 'File', dbFileName, true),
            const SizedBox(width: 6),
            _buildStatusPill(theme, 'Size', '$sizeKb KB', true),
            const SizedBox(width: 6),
            _buildStatusPill(
              theme,
              'Tables',
              '${_tables.length} tables loaded',
              _tables.isNotEmpty,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(
    ThemeData theme,
    String label,
    String state,
    bool isOk,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOk
            ? const Color(0xFF2DA44E).withValues(alpha: 0.12)
            : theme.isDark
            ? const Color(0xFF21262D)
            : const Color(0xFFEAEEF2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOk
              ? const Color(0xFF2DA44E).withValues(alpha: 0.35)
              : theme.borderDefault,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOk ? const Color(0xFF2DA44E) : theme.fgMuted,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $state',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isOk
                  ? (theme.isDark
                        ? const Color(0xFF7EE787)
                        : const Color(0xFF1A7F37))
                  : theme.fgMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTab({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? (theme.isDark ? theme.bgCanvas : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: theme.isDark ? 0.35 : 0.08,
                      ),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? theme.accentFg : theme.fgMuted,
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? theme.fgDefault : theme.fgMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableModeItem(ThemeData theme, Map<String, dynamic> t) {
    final name = t['name']?.toString() ?? '';
    final rowCount = t['row_count'] ?? 0;
    final isSelected = name == _activeTableName;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: _getTableSubtitle(name),
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          onTap: () => _loadTableData(name),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: isSelected
                  ? Border.all(color: theme.borderDefault, width: 1)
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: theme.isDark ? 0.25 : 0.04,
                        ),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  _getTableIcon(name),
                  size: 15,
                  color: isSelected ? theme.accentFg : theme.fgMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected ? theme.fgDefault : theme.fgMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (theme.isDark
                              ? const Color(0xFF262A34)
                              : const Color(0xFFF1F3F5))
                        : (theme.isDark
                              ? const Color(0xFF1E222A)
                              : const Color(0xFFF5F6F8)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? theme.borderDefault
                          : theme.borderDefault.withValues(alpha: 0.5),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    '$rowCount rows',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? theme.fgDefault : theme.fgMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 2. MODULAR "BOX-OF-DESIGN" SIDEBAR & DATA VIEW
  // =========================================================================
  Widget _buildTablesView(ThemeData theme) {
    if (_tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 40, color: theme.fgMuted),
            const SizedBox(height: 10),
            Text(
              'No SQLite tables found in database',
              style: TextStyle(color: theme.fgMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredTableRows;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column: Modular Box-of-Design Tables List
        Container(
          width: 256,
          decoration: BoxDecoration(
            color: theme.bgSubtle,
            border: Border(
              right: BorderSide(color: theme.borderDefault, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modular Section Header Box
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.dataset_outlined,
                      size: 13.5,
                      color: theme.fgMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'DATABASE TABLES',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: theme.fgMuted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgEmphasis.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_tables.length} tables',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: theme.fgMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Modular Table Card Boxes (Matching Image 2 Architecture)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: theme.bgCanvas,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.borderDefault,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int idx = 0; idx < _tables.length; idx++) ...[
                            if (idx > 0) const SizedBox(height: 4),
                            _buildTableModeItem(theme, _tables[idx]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Modular Database User Guide Box at Bottom (Matching Image 2 Box Architecture)
              Container(
                margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                decoration: BoxDecoration(
                  color: theme.bgCanvas,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.borderDefault, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: theme.isDark ? 0.2 : 0.04,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: _showDatabaseGuideDialog,
                      borderRadius: BorderRadius.circular(10),
                      hoverColor: theme.bgEmphasis.withValues(alpha: 0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.accentFg.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: theme.accentFg.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Icon(
                                Icons.menu_book_rounded,
                                size: 14,
                                color: theme.accentFg,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Database User Guide',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: theme.fgDefault,
                                    ),
                                  ),
                                  const SizedBox(height: 1.5),
                                  Text(
                                    'How data gets here & why',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: theme.fgMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: theme.fgMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Column: Table Records View
        Expanded(
          child: Container(
            color: theme.bgCanvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Clean Sub-Header Toolbar
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: theme.bgSubtle,
                    border: Border(
                      bottom: BorderSide(color: theme.borderDefault, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Active Table Pill (Milky shade, purple theme)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentFg.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.accentFg.withValues(alpha: 0.35),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: theme.isDark ? 0.25 : 0.04,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getTableIcon(_activeTableName),
                              size: 13,
                              color: theme.accentFg,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _activeTableName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.accentFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${filtered.length} rows)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.fgMuted,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Search Box
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: TextField(
                            controller: _filterController,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.fgDefault,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Filter records in "$_activeTableName"...',
                              hintStyle: TextStyle(
                                fontSize: 11.5,
                                color: theme.fgMuted,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 14,
                                color: theme.fgMuted,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 28,
                              ),
                              suffixIcon: _filterQuery.isNotEmpty
                                  ? MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: IconButton(
                                        mouseCursor: SystemMouseCursors.click,
                                        icon: const Icon(
                                          Icons.clear_rounded,
                                          size: 13,
                                        ),
                                        splashRadius: 10,
                                        onPressed: () {
                                          setState(() {
                                            _filterController.clear();
                                            _filterQuery = '';
                                          });
                                        },
                                      ),
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              fillColor: theme.isDark
                                  ? theme.bgCanvas
                                  : Colors.white,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: theme.borderDefault,
                                  width: 0.8,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: theme.borderDefault,
                                  width: 0.8,
                                ),
                              ),
                            ),
                            onChanged: (val) {
                              setState(() => _filterQuery = val.trim());
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Copy JSON Button
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () {
                            _copyToClipboard(
                              jsonEncode(filtered),
                              'Table "$_activeTableName" JSON',
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5.5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.isDark
                                  ? theme.bgCanvas
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.borderDefault,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_all_rounded,
                                  size: 13,
                                  color: theme.fgMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Copy JSON',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.fgDefault,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Reload Table Button
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          icon: Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: theme.fgMuted,
                          ),
                          tooltip: 'Reload Table',
                          hoverColor: theme.bgEmphasis,
                          splashRadius: 12,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () => _loadTableData(_activeTableName),
                        ),
                      ),
                    ],
                  ),
                ),

                // Table Rows Grid
                Expanded(
                  child: _isLoadingTableData
                      ? _buildLoadingState(
                          theme,
                          'Loading rows for $_activeTableName...',
                        )
                      : (_tableDataError != null
                            ? _buildErrorBanner(theme, _tableDataError!)
                            : (filtered.isEmpty
                                  ? _buildEmptyRowsView(theme)
                                  : _buildCrispDataGrid(
                                      theme: theme,
                                      columns: _tableColumns,
                                      rows: filtered,
                                      scrollController: _tableHorizontalScroll,
                                    ))),
                ),

                // ─── Precision-Aligned Bottom Status Bar (Organized & Quiet) ───
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.isDark
                        ? theme.bgSubtle
                        : const Color(0xFFF6F8FA),
                    border: Border(
                      top: BorderSide(color: theme.borderDefault, width: 1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left: Clean record counter
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.table_rows_rounded,
                            size: 13.5,
                            color: theme.fgMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Showing ${filtered.length} records in "$_activeTableName"',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.fgDefault,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Right: Clean, structured Double-Click Notice
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 13.5,
                            color: theme.accentFg,
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5.5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accentFg.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: theme.accentFg.withValues(alpha: 0.35),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              '⏎ Double-Click',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                                color: theme.accentFg,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'inspect record details',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.fgMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyRowsView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 38, color: theme.fgMuted),
          const SizedBox(height: 8),
          Text(
            _filterQuery.isNotEmpty
                ? 'No records match filter "$_filterQuery"'
                : 'No records in "$_activeTableName" table yet.',
            style: TextStyle(color: theme.fgMuted, fontSize: 12.5),
          ),
          if (_filterQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                style: TextButton.styleFrom(
                  enabledMouseCursor: SystemMouseCursors.click,
                ),
                onPressed: () {
                  setState(() {
                    _filterController.clear();
                    _filterQuery = '';
                  });
                },
                child: const Text(
                  'Clear Filter',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // 3. SQL QUERY CONSOLE VIEW
  // =========================================================================
  Widget _buildQueryConsoleView(ThemeData theme) {
    return Container(
      color: theme.bgCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quick Query Templates
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.bgSubtle,
              border: Border(
                bottom: BorderSide(color: theme.borderDefault, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'TEMPLATES:',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: theme.fgMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildQueryChip(theme, 'All Tasks', 'SELECT * FROM tasks;'),
                  _buildQueryChip(
                    theme,
                    'Pending Tasks',
                    'SELECT * FROM tasks WHERE done = 0;',
                  ),
                  _buildQueryChip(
                    theme,
                    'Completed Tasks',
                    'SELECT * FROM tasks WHERE done = 1;',
                  ),
                  _buildQueryChip(
                    theme,
                    'All Notes',
                    'SELECT * FROM notes ORDER BY id DESC;',
                  ),
                  _buildQueryChip(
                    theme,
                    'All Memories',
                    'SELECT * FROM memories ORDER BY id DESC;',
                  ),
                  _buildQueryChip(
                    theme,
                    'Tasks by Priority',
                    'SELECT priority, count(*) as count FROM tasks GROUP BY priority;',
                  ),
                ],
              ),
            ),
          ),

          // SQL Input Area
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.isDark ? theme.bgInset : const Color(0xFFF6F8FA),
              border: Border(
                bottom: BorderSide(color: theme.borderDefault, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _queryController,
                  maxLines: 3,
                  minLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: theme.fgDefault,
                    height: 1.35,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter SELECT SQL query...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: theme.fgMuted,
                    ),
                    contentPadding: const EdgeInsets.all(10),
                    fillColor: theme.isDark ? theme.bgCanvas : Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: BorderSide(color: theme.borderDefault),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: BorderSide(color: theme.borderDefault),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: BorderSide(color: theme.accentFg, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 13,
                      color: theme.accentFg,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Safe read-only execution (SELECT statements)',
                      style: TextStyle(fontSize: 11, color: theme.fgMuted),
                    ),
                    const Spacer(),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: ElevatedButton.icon(
                        onPressed: _isExecutingQuery ? null : _runCustomQuery,
                        icon: _isExecutingQuery
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(
                          _isExecutingQuery ? 'Running...' : 'Run Query',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ButtonStyle(
                          mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click,
                          ),
                          backgroundColor: WidgetStateProperty.all(
                            theme.accentFg,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            Colors.white,
                          ),
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
                          ),
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          elevation: WidgetStateProperty.all(0),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Query Result Area
          Expanded(
            child: _isExecutingQuery
                ? _buildLoadingState(theme, 'Executing SQL Query...')
                : (_queryError != null
                      ? _buildErrorBanner(theme, _queryError!)
                      : (_hasExecutedQuery
                            ? (_queryRows.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Query completed: 0 rows returned.',
                                        style: TextStyle(
                                          color: theme.fgMuted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Result status bar
                                        Container(
                                          height: 38,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.bgSubtle,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: theme.borderDefault,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: theme.isDark
                                                      ? const Color(0xFF14241C)
                                                      : const Color(0xFFECFDF5),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: theme.isDark
                                                        ? const Color(
                                                            0xFF203E2D,
                                                          )
                                                        : const Color(
                                                            0xFFA7F3D0,
                                                          ),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .check_circle_rounded,
                                                      size: 13,
                                                      color: theme.isDark
                                                          ? const Color(
                                                              0xFF6EE7B7,
                                                            )
                                                          : const Color(
                                                              0xFF15803D,
                                                            ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      '${_queryRows.length} rows returned'
                                                      '${_queryExecutionDurationMs != null ? ' in ${_queryExecutionDurationMs}ms' : ''}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: theme.isDark
                                                            ? const Color(
                                                                0xFF6EE7B7,
                                                              )
                                                            : const Color(
                                                                0xFF15803D,
                                                              ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Spacer(),
                                              MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: InkWell(
                                                  mouseCursor:
                                                      SystemMouseCursors.click,
                                                  onTap: () {
                                                    _copyToClipboard(
                                                      jsonEncode(_queryRows),
                                                      'Query Results JSON',
                                                    );
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4.5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: theme.isDark
                                                          ? theme.bgCanvas
                                                          : Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color:
                                                            theme.borderDefault,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .copy_all_rounded,
                                                          size: 12.5,
                                                          color: theme.fgMuted,
                                                        ),
                                                        const SizedBox(
                                                          width: 4.5,
                                                        ),
                                                        Text(
                                                          'Copy JSON',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                theme.fgDefault,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: _buildCrispDataGrid(
                                            theme: theme,
                                            columns: _queryColumns,
                                            rows: _queryRows,
                                            scrollController:
                                                _queryHorizontalScroll,
                                          ),
                                        ),
                                      ],
                                    ))
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.terminal_rounded,
                                      size: 34,
                                      color: theme.accentFg.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Select a template above or write a SQL query and click "Run Query"',
                                      style: TextStyle(
                                        color: theme.fgMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ))),
          ),

          // ─── Precision-Aligned Bottom Status Bar for Query Console ───
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.isDark ? theme.bgSubtle : const Color(0xFFF6F8FA),
              border: Border(
                top: BorderSide(color: theme.borderDefault, width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      size: 13.5,
                      color: theme.accentFg,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _hasExecutedQuery
                          ? 'Query executed • ${_queryRows.length} records returned${_queryExecutionDurationMs != null ? ' (${_queryExecutionDurationMs}ms)' : ''}'
                          : 'SQL Query Console • Safe read-only mode',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_hasExecutedQuery && _queryRows.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 13.5,
                        color: theme.accentFg,
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5.5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentFg.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.accentFg.withValues(alpha: 0.35),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          '⏎ Double-Click',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: theme.accentFg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'inspect record details',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.fgMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryChip(ThemeData theme, String label, String sql) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: () {
            _queryController.text = sql;
            _runCustomQuery();
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
            decoration: BoxDecoration(
              color: theme.isDark ? theme.bgCanvas : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.borderDefault, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.isDark ? 0.2 : 0.03,
                  ),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.code_rounded, size: 11.5, color: theme.accentFg),
                const SizedBox(width: 4.5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isColumnCentered(String col, int totalCols) {
    final lower = col.toLowerCase();
    // Descriptive multiline sentences must remain left-aligned for natural reading
    if (lower == 'content' ||
        lower == 'title' ||
        lower == 'description' ||
        lower == 'notes' ||
        lower == 'note' ||
        lower == 'message' ||
        lower == 'prompt' ||
        lower == 'summary') {
      return false;
    }
    // When 2 or fewer columns (like SQL console PRIORITY & COUNT query), center both!
    if (totalCols <= 2) {
      return true;
    }
    // In tables, center badges, IDs, counts, dates, tags, and status
    return lower == 'id' ||
        lower == 'priority' ||
        lower == 'done' ||
        lower == 'count' ||
        lower.contains('count') ||
        lower == 'total' ||
        lower == 'sum' ||
        lower == 'avg' ||
        lower == 'tags' ||
        lower == 'status' ||
        lower.contains('date') ||
        lower.contains('time');
  }

  // =========================================================================
  // ZERO-OVERFLOW RESPONSIVE DATA GRID
  // =========================================================================
  Widget _buildCrispDataGrid({
    required ThemeData theme,
    required List<String> columns,
    required List<Map<String, dynamic>> rows,
    required ScrollController scrollController,
  }) {
    if (columns.isEmpty && rows.isNotEmpty) {
      columns = rows.first.keys.toList();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgCanvas : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.25 : 0.035),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = max(0.0, constraints.maxWidth);
            // Calculate safe proportional column widths
            final colWidths = _computeColumnWidths(columns, availableWidth);
            final totalTableWidth = colWidths.values.fold<double>(
              0.0,
              (sum, w) => sum + w,
            );

            // By embedding inside a horizontal SingleChildScrollView, the Row will NEVER overflow
            // because maxWidth is unbounded for layout measurement!
            return Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: availableWidth),
                  child: SizedBox(
                    width: max(availableWidth, totalTableWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Row
                        Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: theme.bgSubtle,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.borderDefault,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: columns.asMap().entries.map((entry) {
                              final colIdx = entry.key;
                              final col = entry.value;
                              final width = colWidths[col] ?? 120.0;
                              final isCentered = _isColumnCentered(
                                col,
                                columns.length,
                              );
                              final isLast = colIdx == columns.length - 1;

                              return Container(
                                width: width,
                                height: 38,
                                alignment: isCentered
                                    ? Alignment.center
                                    : Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: isLast
                                        ? BorderSide.none
                                        : BorderSide(
                                            color: theme.borderDefault
                                                .withValues(alpha: 0.35),
                                            width: 1,
                                          ),
                                  ),
                                ),
                                child: Text(
                                  col.toUpperCase(),
                                  textAlign: isCentered
                                      ? TextAlign.center
                                      : TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: theme.fgMuted,
                                    letterSpacing: 0.6,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Data Rows
                        Expanded(
                          child: ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, rowIdx) {
                              final row = rows[rowIdx];
                              final isEven = rowIdx % 2 == 0;
                              final isLastRow = rowIdx == rows.length - 1;

                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: InkWell(
                                  mouseCursor: SystemMouseCursors.click,
                                  onDoubleTap: () =>
                                      _showRecordDetailsDialog(row),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isEven
                                          ? (theme.isDark
                                                ? theme.bgCanvas
                                                : Colors.white)
                                          : (theme.isDark
                                                ? theme.bgSubtle.withValues(
                                                    alpha: 0.35,
                                                  )
                                                : const Color(0xFFF9FAFB)),
                                      border: Border(
                                        bottom: isLastRow
                                            ? BorderSide.none
                                            : BorderSide(
                                                color: theme.borderDefault
                                                    .withValues(alpha: 0.4),
                                                width: 1,
                                              ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: columns.asMap().entries.map((
                                        entry,
                                      ) {
                                        final colIdx = entry.key;
                                        final col = entry.value;
                                        final width = colWidths[col] ?? 120.0;
                                        final val = row[col];
                                        final isCentered = _isColumnCentered(
                                          col,
                                          columns.length,
                                        );
                                        final isLast =
                                            colIdx == columns.length - 1;

                                        return Container(
                                          width: width,
                                          constraints: const BoxConstraints(
                                            minHeight: 42,
                                          ),
                                          alignment: isCentered
                                              ? Alignment.center
                                              : Alignment.centerLeft,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              right: isLast
                                                  ? BorderSide.none
                                                  : BorderSide(
                                                      color: theme.borderDefault
                                                          .withValues(
                                                            alpha: 0.25,
                                                          ),
                                                      width: 1,
                                                    ),
                                            ),
                                          ),
                                          child: _renderCellWidget(
                                            theme,
                                            col,
                                            val,
                                            row,
                                            isCentered: isCentered,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Calculates column widths safely with subpixel margins
  Map<String, double> _computeColumnWidths(
    List<String> columns,
    double availableWidth,
  ) {
    final Map<String, double> widths = {};
    double fixedTotal = 0;
    final List<String> flexCols = [];

    for (final col in columns) {
      final lower = col.toLowerCase();
      if (lower == 'id') {
        widths[col] = 60.0;
        fixedTotal += 60.0;
      } else if (lower == 'done') {
        widths[col] = 130.0;
        fixedTotal += 130.0;
      } else if (lower == 'priority') {
        widths[col] = 110.0;
        fixedTotal += 110.0;
      } else if (lower == 'count' ||
          lower.contains('count') ||
          lower == 'total' ||
          lower == 'sum' ||
          lower == 'avg') {
        widths[col] = 110.0;
        fixedTotal += 110.0;
      } else if (lower == 'due_date') {
        widths[col] = 120.0;
        fixedTotal += 120.0;
      } else if (lower == 'created_at' || lower.contains('time')) {
        widths[col] = 165.0;
        fixedTotal += 165.0;
      } else if (lower == 'tags') {
        widths[col] = 135.0;
        fixedTotal += 135.0;
      } else if (lower == 'content' ||
          lower == 'title' ||
          lower == 'description') {
        flexCols.add(col);
      } else {
        if (columns.length <= 4 &&
            !lower.contains('count') &&
            !lower.contains('sum') &&
            !lower.contains('avg')) {
          flexCols.add(col);
        } else {
          widths[col] = 140.0;
          fixedTotal += 140.0;
        }
      }
    }

    if (flexCols.isNotEmpty) {
      // 16px safety margin prevents subpixel rounding border clipping
      final remainingWidth = max(0.0, availableWidth - fixedTotal - 16.0);
      final flexWidth = max(240.0, remainingWidth / flexCols.length);
      for (final col in flexCols) {
        widths[col] = flexWidth;
      }
    } else if (fixedTotal < availableWidth - 16.0 && columns.isNotEmpty) {
      // Distribute extra space evenly across all columns so they stay balanced and aligned
      final extraPerCol = (availableWidth - 16.0 - fixedTotal) / columns.length;
      for (final col in columns) {
        widths[col] = (widths[col] ?? 120.0) + extraPerCol;
      }
    }

    return widths;
  }

  Widget _renderCellWidget(
    ThemeData theme,
    String colName,
    dynamic val,
    Map<String, dynamic> row, {
    bool isCentered = false,
  }) {
    if (val == null) {
      return Text(
        'NULL',
        textAlign: isCentered ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontSize: 10.5,
          fontFamily: 'monospace',
          fontStyle: FontStyle.italic,
          color: theme.fgMuted.withValues(alpha: 0.55),
        ),
      );
    }

    final lower = colName.toLowerCase();

    // ID (Milky neutral, not neon purple)
    if (lower == 'id') {
      return Text(
        val.toString(),
        textAlign: isCentered ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          color: theme.isDark
              ? const Color(0xFFE5E7EB)
              : const Color(0xFF334155),
        ),
      );
    }

    // Done Status (Milky shade, not glassy)
    if (lower == 'done') {
      final isDone = val == 1 || val == true;
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDone
                ? (theme.isDark
                      ? const Color(0xFF14241C)
                      : const Color(0xFFECFDF5))
                : (theme.isDark
                      ? const Color(0xFF20242C)
                      : const Color(0xFFF3F4F6)),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDone
                  ? (theme.isDark
                        ? const Color(0xFF203E2D)
                        : const Color(0xFFA7F3D0))
                  : (theme.isDark
                        ? const Color(0xFF303642)
                        : const Color(0xFFE5E7EB)),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDone ? Icons.check_circle_rounded : Icons.pending_outlined,
                size: 11,
                color: isDone
                    ? (theme.isDark
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF065F46))
                    : theme.fgMuted,
              ),
              const SizedBox(width: 4.5),
              Text(
                isDone ? 'Completed' : 'Pending',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDone
                      ? (theme.isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF065F46))
                      : theme.fgMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Priority (Milky shade, not glassy)
    if (lower == 'priority') {
      final p = val.toString().toLowerCase();
      final isHigh = p == 'high' || p == 'urgent';
      final isMed = p == 'medium';
      final isLow = p == 'low';

      final Color bgColor;
      final Color borderColor;
      final Color fgColor;

      if (isHigh) {
        bgColor = theme.isDark
            ? const Color(0xFF29181B)
            : const Color(0xFFFEF2F2);
        borderColor = theme.isDark
            ? const Color(0xFF452227)
            : const Color(0xFFFECACA);
        fgColor = theme.isDark
            ? const Color(0xFFFCA5A5)
            : const Color(0xFF991B1B);
      } else if (isMed) {
        bgColor = theme.isDark
            ? const Color(0xFF271F14)
            : const Color(0xFFFFFBEB);
        borderColor = theme.isDark
            ? const Color(0xFF42331D)
            : const Color(0xFFFDE68A);
        fgColor = theme.isDark
            ? const Color(0xFFFCD34D)
            : const Color(0xFF92400E);
      } else if (isLow) {
        bgColor = theme.isDark
            ? const Color(0xFF14241C)
            : const Color(0xFFECFDF5);
        borderColor = theme.isDark
            ? const Color(0xFF203E2D)
            : const Color(0xFFA7F3D0);
        fgColor = theme.isDark
            ? const Color(0xFF6EE7B7)
            : const Color(0xFF065F46);
      } else {
        bgColor = theme.isDark
            ? const Color(0xFF20242C)
            : const Color(0xFFF3F4F6);
        borderColor = theme.isDark
            ? const Color(0xFF303642)
            : const Color(0xFFE5E7EB);
        fgColor = theme.fgMuted;
      }

      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Text(
            val.toString().toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
        ),
      );
    }

    // Tags (Milky shade, not glassy)
    if (lower == 'tags') {
      final tagStr = val.toString().trim();
      if (tagStr.isEmpty) {
        return Text(
          '—',
          textAlign: isCentered ? TextAlign.center : TextAlign.left,
          style: TextStyle(color: theme.fgMuted, fontSize: 11),
        );
      }
      final tagList = tagStr
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty);
      return Wrap(
        alignment: isCentered ? WrapAlignment.center : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 3.5,
        runSpacing: 2,
        children: tagList.map((tag) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF222630)
                  : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.isDark
                    ? const Color(0xFF323846)
                    : const Color(0xFFE5E7EB),
                width: 0.8,
              ),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: theme.fgDefault,
              ),
            ),
          );
        }).toList(),
      );
    }

    // Content or Title
    if (lower == 'content' || lower == 'title' || lower == 'description') {
      final str = val.toString();
      return Tooltip(
        message: str,
        waitDuration: const Duration(milliseconds: 500),
        child: Text(
          str,
          textAlign: isCentered ? TextAlign.center : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: theme.fgDefault, height: 1.3),
        ),
      );
    }

    final strVal = val.toString();
    final isMonospace =
        lower.contains('date') ||
        lower.contains('time') ||
        lower == 'count' ||
        lower.contains('count') ||
        num.tryParse(strVal) != null;

    return Tooltip(
      message: strVal,
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        strVal,
        textAlign: isCentered ? TextAlign.center : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontFamily: isMonospace ? 'monospace' : null,
          color: theme.fgDefault,
        ),
      ),
    );
  }

  // =========================================================================
  // HELPERS
  // =========================================================================
  Widget _buildLoadingState(ThemeData theme, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: theme.accentFg,
            ),
          ),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: theme.fgMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String error) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.dangerBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dangerBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: theme.dangerFg, size: 20),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                error,
                style: TextStyle(color: theme.dangerFg, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
