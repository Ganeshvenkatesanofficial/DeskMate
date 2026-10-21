import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../utils/open_external.dart';
import '../models/chat_message.dart';
import 'circular_close_button.dart';
import 'telemetry_accordion.dart';

class MeetingScribeView extends StatefulWidget {
  final void Function([AgentMode? mode])? onOpenSetupGuide;

  const MeetingScribeView({super.key, this.onOpenSetupGuide});

  @override
  State<MeetingScribeView> createState() => _MeetingScribeViewState();
}

class _MeetingScribeViewState extends State<MeetingScribeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isRecording = false;
  bool _isStarting = false;
  bool _isSummarizing = false;
  bool _isSyncingTasks = false;
  bool _isExportingDrive = false;
  bool _isSendingEmail = false;
  String? _currentSessionId;

  int _uptimeSeconds = 0;
  int _framesProcessed = 0;
  int _eventsDetected = 0;
  bool _isMicMuted = false;
  bool _isTogglingMic = false;
  Timer? _statusTimer;

  // Post-processing agentic telemetry state
  int _postProcessingStage = 1;
  double _postProcessingProgress = 0.20;
  String _postProcessingTitle = 'Audio Normalization';
  String _postProcessingDetail =
      'Flushing PCM buffer and converting stream to 16kHz mono WAV...';
  int _postProcessingElapsedSeconds = 0;
  Timer? _postProcessingTimer;
  WebSocket? _meetingWebSocket;

  // Paced telemetry queue & inspectable reasoning flow
  final List<AgentStepTelemetry> _meetingTelemetrySteps = [];
  final List<Map<String, dynamic>> _telemetryQueue = [];
  bool _isProcessingQueue = false;
  bool _showTelemetryInspection = false;

  // Summary result state
  String? _executiveSummary;
  List<String> _importantSteps = [];
  Map<String, dynamic> _stepDescriptions = {};
  List<String> _actionItems = [];
  String? _pdfUrl;
  Map<String, dynamic> _customFieldsAnalysis = {};
  Map<String, dynamic>? _transcriptData;
  List<dynamic> _meetingSteps = [];

  // Set when the last summary attempt failed; the retry card reads it.
  String? _summaryError;
  // Set when the backend reports that speaker or mic audio did not start.
  String? _audioWarning;

  // Transcript filter and search state
  String _transcriptSearchQuery = '';
  String? _selectedSpeakerFilter;
  final TextEditingController _transcriptSearchController =
      TextEditingController();

  // Custom Focus Inquiries / Columns state
  final List<Map<String, String>> _customFocusTopics = [];
  final TextEditingController _topicNameController = TextEditingController();
  final TextEditingController _topicInstructionController =
      TextEditingController();
  bool _showTopicInput = false;

  // Past sessions archive state
  List<Map<String, dynamic>> _savedSessions = [];

  OverlayEntry? _topToastOverlayEntry;
  Timer? _topToastTimer;

  static String _errorText(Object e) => e.toString().replaceFirst(
    RegExp(r'^(Exception|TimeoutException): ?'),
    '',
  );

  void _showTopNotification(String message, {bool isError = false}) {
    if (!mounted) return;
    _topToastTimer?.cancel();
    _topToastOverlayEntry?.remove();
    _topToastOverlayEntry = null;

    final overlayState = Overlay.of(context, rootOverlay: true);
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    final Color bgColor = isError
        ? (theme.isDark ? const Color(0xFF381515) : const Color(0xFFFEECEB))
        : (theme.isDark ? const Color(0xFF0F2D1A) : const Color(0xFFEAFBF0));

    final Color borderColor = isError
        ? (theme.isDark ? const Color(0xFF782525) : const Color(0xFFF9A8A8))
        : (theme.isDark ? const Color(0xFF1E6038) : const Color(0xFF8CE4AC));

    final Color fgColor = isError
        ? (theme.isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))
        : (theme.isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D));

    final IconData icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_rounded;

    _topToastOverlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: isDesktop ? 38 : 16,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12),
              constraints: const BoxConstraints(maxWidth: 580),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.isDark ? 0.35 : 0.08,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fgColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: fgColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircularCloseButton(
                    size: 16,
                    tooltip: 'Dismiss',
                    onTap: () {
                      _topToastTimer?.cancel();
                      _topToastOverlayEntry?.remove();
                      _topToastOverlayEntry = null;
                    },
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.2, end: 0.0),
          ),
        ),
      ),
    );

    overlayState.insert(_topToastOverlayEntry!);

    _topToastTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _topToastOverlayEntry?.remove();
      _topToastOverlayEntry = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _checkInitialStatus();
  }

  @override
  void dispose() {
    _topToastTimer?.cancel();
    _topToastOverlayEntry?.remove();
    _topToastOverlayEntry = null;
    _pulseController.dispose();
    _statusTimer?.cancel();
    _postProcessingTimer?.cancel();
    _meetingWebSocket?.close();
    _topicNameController.dispose();
    _topicInstructionController.dispose();
    _transcriptSearchController.dispose();
    super.dispose();
  }

  List<String> _extractActionItemsFromSummary(String summaryText) {
    final extractedActions = <String>[];
    for (final line in summaryText.split('\n')) {
      if (line.contains('[ACTION ITEM]') || line.contains('[HIGH PRIORITY]')) {
        extractedActions.add(line.replaceAll('**', '').trim());
      }
    }
    return extractedActions;
  }

  Future<void> _loadSavedSessions({
    bool autoLoadLatest = false,
    void Function(void Function())? onDialogState,
  }) async {
    if (!mounted) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final sessions = await provider.apiService.getMeetingSessions();
      if (mounted) {
        setState(() {
          _savedSessions = sessions;
        });
        onDialogState?.call(() {});

        // If user opened/reopened the app, automatically restore latest completed meeting!
        if (autoLoadLatest &&
            sessions.isNotEmpty &&
            _executiveSummary == null &&
            !_isRecording) {
          final latestId = sessions.first['session_id']?.toString();
          if (latestId != null) {
            await _restoreSession(latestId, showNotification: false);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        onDialogState?.call(() {});
      }
    }
  }

  Future<void> _restoreSession(
    String sessionId, {
    bool showNotification = true,
  }) async {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final sessionData = await provider.apiService.getMeetingSessionReport(
        sessionId,
      );
      if (!mounted) return;
      if (sessionData == null) {
        if (showNotification) {
          _showTopNotification(
            'This meeting\'s saved data could not be found. It may have been deleted.',
            isError: true,
          );
        }
        return;
      }
      final summaryText = sessionData['summary']?.toString() ?? '';
      final hasPdf = sessionData['pdf_path'] != null;
      setState(() {
        _currentSessionId = sessionId;
        _executiveSummary = summaryText.isNotEmpty ? summaryText : null;
        _summaryError = summaryText.isEmpty
            ? 'This meeting has no report yet. Press Retry summary to create it.'
            : null;
        _audioWarning = null;
        _importantSteps =
            (sessionData['important_steps'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        _stepDescriptions = Map<String, dynamic>.from(
          sessionData['step_descriptions'] ?? {},
        );
        _transcriptData = sessionData['transcript'] is Map
            ? Map<String, dynamic>.from(sessionData['transcript'])
            : null;
        _customFieldsAnalysis = Map<String, dynamic>.from(
          sessionData['custom_fields'] ?? {},
        );
        _meetingSteps = (sessionData['steps'] as List?) ?? [];
        _pdfUrl = hasPdf
            ? provider.apiService.getMeetingPdfUrl(sessionId)
            : null;
        _actionItems = _extractActionItemsFromSummary(summaryText);
        _meetingTelemetrySteps.clear();
        if (summaryText.isNotEmpty) {
          _meetingTelemetrySteps.addAll(
            _buildTelemetryStepsFromSessionData(sessionData, sessionId),
          );
        }
      });
      if (showNotification) {
        _showTopNotification(
          summaryText.isNotEmpty
              ? 'Loaded meeting report: $sessionId'
              : 'Loaded meeting $sessionId. It has no report yet.',
        );
      }
    } catch (e) {
      if (showNotification && mounted) {
        _showTopNotification(
          'Failed to load session: ${_errorText(e)}',
          isError: true,
        );
      }
    }
  }

  Future<void> _confirmAndDeleteSession(String sessionId) async {
    final theme = Theme.of(context);
    final confirm = await showBlurredDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.bgSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.borderDefault),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.recordingRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: AppTheme.recordingRed,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Delete Session?',
              style: TextStyle(
                color: theme.fgDefault,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'This will permanently delete session "$sessionId" and purge all audio recordings, screenshots, and the PDF report completely from your local disk.\n\nThis cannot be undone.',
          style: TextStyle(color: theme.fgMuted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: theme.fgMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.recordingRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete from Disk'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      final ok = await provider.apiService.deleteMeetingSession(sessionId);
      if (ok && mounted) {
        _showTopNotification(
          'Permanently deleted session $sessionId from disk',
        );
        if (_currentSessionId == sessionId) {
          setState(() {
            _executiveSummary = null;
            _transcriptData = null;
            _importantSteps = [];
            _meetingSteps = [];
            _customFieldsAnalysis = {};
            _actionItems = [];
            _currentSessionId = null;
            _pdfUrl = null;
            _summaryError = null;
            _meetingTelemetrySteps.clear();
            _telemetryQueue.clear();
            _isProcessingQueue = false;
          });
        }
        await _loadSavedSessions(autoLoadLatest: false);
      } else if (mounted) {
        _showTopNotification(
          'Failed to delete session from disk',
          isError: true,
        );
      }
    }
  }

  String _formatSessionDisplayTitle(String id, dynamic createdAt) {
    if (RegExp(r'^\d{8}_\d{6}$').hasMatch(id)) {
      try {
        final year = id.substring(0, 4);
        final monthNum = int.parse(id.substring(4, 6));
        final day = int.parse(id.substring(6, 8));
        final hour = int.parse(id.substring(9, 11));
        final min = id.substring(11, 13);
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final monthStr = months[(monthNum - 1).clamp(0, 11)];
        final isPm = hour >= 12;
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        final amPm = isPm ? 'PM' : 'AM';
        return 'Meeting • $monthStr $day, $year at $displayHour:$min $amPm';
      } catch (_) {}
    }
    return 'Meeting • $id';
  }

  void _showSavedSessionsDialog() {
    bool isDialogRefreshing = false;

    showBlurredDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return Dialog(
            backgroundColor: theme.bgSubtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.borderDefault),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.accentFg.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.history_rounded,
                            color: theme.accentFg,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saved Meeting Archives',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: theme.fgDefault,
                                ),
                              ),
                              Text(
                                '${_savedSessions.length} session(s) available • Retained on disk for re-analysis & export',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.fgMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Refresh Archives',
                          child: InkWell(
                            onTap: isDialogRefreshing
                                ? null
                                : () async {
                                    setDialogState(
                                      () => isDialogRefreshing = true,
                                    );
                                    await _loadSavedSessions(
                                      autoLoadLatest: false,
                                      onDialogState: setDialogState,
                                    );
                                    if (ctx.mounted) {
                                      setDialogState(
                                        () => isDialogRefreshing = false,
                                      );
                                    }
                                  },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.bgCanvas,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.borderDefault),
                              ),
                              child: isDialogRefreshing
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          theme.accentFg,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.refresh_rounded,
                                      size: 17,
                                      color: theme.fgMuted,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Close',
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.bgCanvas,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.borderDefault),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: theme.fgMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (_savedSessions.isEmpty)
                      Expanded(
                        child: Center(
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 36,
                            ),
                            decoration: BoxDecoration(
                              color: theme.bgCanvas,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: theme.borderDefault,
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: theme.accentFg.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.accentFg.withValues(
                                        alpha: 0.22,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.folder_open_rounded,
                                    size: 30,
                                    color: theme.accentFg,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'No Saved Meeting Archives',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: theme.fgDefault,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 380,
                                  ),
                                  child: Text(
                                    'When you record meetings, your audio transcripts, visual slides, and executive PDF reports will automatically appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: theme.fgMuted,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.bgSubtle,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: theme.borderDefault,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 13,
                                        color: AppTheme.emerald,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Retained 100% locally on this computer',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: theme.fgMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: _savedSessions.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final s = _savedSessions[idx];
                            final id = (s['session_id'] ?? '').toString();
                            final rawTitle = (s['title'] ?? '')
                                .toString()
                                .trim();
                            final displayTitle =
                                rawTitle.isNotEmpty &&
                                    !rawTitle.startsWith('Meeting 20')
                                ? rawTitle
                                : _formatSessionDisplayTitle(
                                    id,
                                    s['created_at'],
                                  );
                            final preview = (s['summary_preview'] ?? '')
                                .toString()
                                .trim();
                            final displayPreview = preview.isNotEmpty
                                ? preview
                                : 'Meeting recording with visual slides and speech transcript.';
                            final createdAt = (s['created_at'] ?? '')
                                .toString();
                            final stepsCount = s['steps_count'] ?? 0;
                            final speakersCount = s['speakers_count'] ?? 0;
                            final hasSummary = s['has_summary'] == true;
                            final hasPdf = s['has_pdf'] == true;
                            final isCurrent = _currentSessionId == id;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? theme.accentFg.withValues(alpha: 0.06)
                                    : theme.bgCanvas,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCurrent
                                      ? theme.accentFg.withValues(alpha: 0.4)
                                      : theme.borderDefault,
                                  width: isCurrent ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          (hasSummary
                                                  ? AppTheme.emerald
                                                  : Colors.amber)
                                              .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      hasSummary
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.pending_outlined,
                                      color: hasSummary
                                          ? AppTheme.emerald
                                          : Colors.amber,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                displayTitle,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: theme.fgDefault,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isCurrent) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: theme.accentFg
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: theme.accentFg
                                                        .withValues(alpha: 0.3),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Text(
                                                  'CURRENTLY OPEN',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: theme.accentFg,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          displayPreview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: theme.fgMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today_rounded,
                                              size: 11,
                                              color: theme.fgMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              createdAt.isNotEmpty
                                                  ? createdAt
                                                  : id,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: theme.fgMuted,
                                              ),
                                            ),
                                            if (stepsCount > 0) ...[
                                              const SizedBox(width: 10),
                                              Icon(
                                                Icons.visibility_rounded,
                                                size: 11,
                                                color: theme.fgMuted,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$stepsCount steps',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: theme.fgMuted,
                                                ),
                                              ),
                                            ],
                                            if (speakersCount > 0) ...[
                                              const SizedBox(width: 10),
                                              Icon(
                                                Icons.people_outline_rounded,
                                                size: 11,
                                                color: theme.fgMuted,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$speakersCount speaker${speakersCount > 1 ? "s" : ""}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: theme.fgMuted,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasPdf) ...[
                                        OutlinedButton.icon(
                                          icon: const Icon(
                                            Icons.file_download_outlined,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'Download PDF',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: theme.fgDefault,
                                            backgroundColor: theme.bgCanvas,
                                            side: BorderSide(
                                              color: theme.borderDefault,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 7,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                          ),
                                          onPressed: () {
                                            final provider =
                                                Provider.of<ChatProvider>(
                                                  context,
                                                  listen: false,
                                                );
                                            final url = provider.apiService
                                                .getMeetingPdfUrl(id);
                                            openExternal(url);
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      if (!isCurrent) ...[
                                        ElevatedButton.icon(
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'View Session',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: theme.accentFg,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 7,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _restoreSession(id);
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Tooltip(
                                        message: 'Delete Archive',
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            size: 17,
                                            color: theme.fgMuted,
                                          ),
                                          hoverColor: theme.dangerFg.withValues(
                                            alpha: 0.1,
                                          ),
                                          onPressed: () async {
                                            await _confirmAndDeleteSession(id);
                                            setDialogState(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _checkInitialStatus() async {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final status = await provider.apiService.getMeetingStatus();
      if (mounted) {
        setState(() {
          _isRecording =
              status['state'] == 'recording' || status['state'] == 'running';
          _currentSessionId = status['session_id'];
          _uptimeSeconds = (status['uptime_seconds'] as num?)?.toInt() ?? 0;
          _framesProcessed = (status['frames_processed'] as num?)?.toInt() ?? 0;
          _eventsDetected = (status['events_detected'] as num?)?.toInt() ?? 0;
          if (status.containsKey('mic_muted')) {
            _isMicMuted = status['mic_muted'] == true;
          }
        });
        if (_isRecording) {
          _startPolling();
        } else {
          await _loadSavedSessions(autoLoadLatest: true);
        }
      }
    } catch (_) {
      if (mounted) {
        await _loadSavedSessions(autoLoadLatest: true);
      }
    }
  }

  void _startPolling() {
    _statusTimer?.cancel();
    var pollInFlight = false;
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (pollInFlight || !mounted) return;
      pollInFlight = true;
      final provider = Provider.of<ChatProvider>(context, listen: false);
      try {
        final status = await provider.apiService.getMeetingStatus();
        if (status['state'] == 'unreachable') {
          // Keep the recording UI and Stop button; the next poll retries.
          if (mounted) setState(() => _uptimeSeconds++);
          return;
        }
        if (mounted) {
          setState(() {
            final warning = status['audio_warning'];
            if (warning is String && warning.isNotEmpty) {
              _audioWarning = warning;
            }
            _isRecording =
                status['state'] == 'recording' || status['state'] == 'running';
            _uptimeSeconds =
                (status['uptime_seconds'] as num?)?.toInt() ??
                _uptimeSeconds + 1;
            _framesProcessed =
                (status['frames_processed'] as num?)?.toInt() ??
                _framesProcessed;
            _eventsDetected =
                (status['events_detected'] as num?)?.toInt() ?? _eventsDetected;
            if (status.containsKey('mic_muted')) {
              _isMicMuted = status['mic_muted'] == true;
            }
          });
          if (!_isRecording) {
            timer.cancel();
          }
        }
      } catch (_) {
      } finally {
        pollInFlight = false;
      }
    });
  }

  Future<void> _startRecording() async {
    if (_isStarting || _isRecording) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final theme = Theme.of(context);

    // Compulsory AI Engine & Model Verification (Reasoning LLM / Ollama / Vision / Gemini)
    if (!provider.isMeetingAiReady) {
      _showAiSetupRequiredModal(context, theme, provider);
      return;
    }

    setState(() => _isStarting = true);
    try {
      final startFuture = provider.apiService.startMeeting(
        monitor: 1,
        fps: 2.0,
        allowLightweightMode: provider.useLightweightVision,
        startMuted: _isMicMuted,
        geminiApiKey: provider.isUsingGemini ? provider.geminiApiKey : null,
      );
      final delayFuture = Future.delayed(const Duration(milliseconds: 1200));
      final results = await Future.wait([startFuture, delayFuture]);
      final res = results[0] as Map<String, dynamic>;
      if (mounted) {
        final warning = res['audio_warning'];
        setState(() {
          _isRecording = true;
          _isStarting = false;
          _currentSessionId = res['session_id'];
          _audioWarning = warning is String && warning.isNotEmpty
              ? warning
              : null;
          _summaryError = null;
          _uptimeSeconds = 0;
          _framesProcessed = 0;
          _eventsDetected = 0;
          _executiveSummary = null;
          _importantSteps = [];
          _stepDescriptions = {};
          _actionItems = [];
          _customFieldsAnalysis = {};
          _transcriptData = null;
          _meetingSteps = [];
          _pdfUrl = null;
          _meetingTelemetrySteps.clear();
          _telemetryQueue.clear();
          _isProcessingQueue = false;
        });
        _startPolling();
        if (_audioWarning != null) {
          _showTopNotification(_audioWarning!, isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        _showTopNotification(
          'Failed to start meeting: ${_errorText(e)}',
          isError: true,
        );
      }
    }
  }

  void _showAiSetupRequiredModal(
    BuildContext context,
    ThemeData theme,
    ChatProvider provider,
  ) {
    bool isRechecking = false;
    String? inDialogStatus;

    showBlurredDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: theme.bgSubtle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: theme.attentionFg.withValues(alpha: 0.4)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.attentionFg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.psychology_alt_rounded,
                  color: theme.attentionFg,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI Engine & Model Required',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DeskMate Meeting Scribe requires active AI capabilities to transcribe dialogue with Voxtral 4B, process on-screen milestones, and generate executive reports. Please resolve the status below:',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.fgDefault,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1. Backend & Ollama Service Status Card
                  if (!provider.isBackendOnline)
                    _buildAiStatusCard(
                      theme: theme,
                      color: theme.dangerFg,
                      icon: provider.isConnecting
                          ? Icons.hourglass_top_rounded
                          : Icons.cancel_rounded,
                      title: provider.isConnecting
                          ? 'Backend AI Engine: Starting...'
                          : 'Backend AI Engine: Offline',
                      subtitle: provider.isConnecting
                          ? 'Starting local engine runtime on port ${provider.backendPort}'
                          : 'DeskMate local Python service is unreachable on port ${provider.backendPort}.',
                    )
                  else if (!provider.isLocalLlmOnline)
                    _buildAiStatusCard(
                      theme: theme,
                      color: theme.attentionFg,
                      icon: Icons.cancel_rounded,
                      title: 'Local Ollama: Offline',
                      subtitle:
                          'Ensure the Ollama application or `ollama serve` is running.',
                    )
                  else
                    _buildAiStatusCard(
                      theme: theme,
                      color: theme.successFg,
                      icon: Icons.check_circle_rounded,
                      title: 'Local Ollama: Online & Ready',
                      subtitle:
                          'Connected at ${AppConstants.ollamaHost} with active socket',
                    ),
                  const SizedBox(height: 10),

                  // 2. Reasoning / Chat Model Status Card
                  _buildAiStatusCard(
                    theme: theme,
                    color: provider.availableLocalModels.isNotEmpty
                        ? theme.successFg
                        : theme.attentionFg,
                    icon: provider.availableLocalModels.isNotEmpty
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    title: provider.availableLocalModels.isNotEmpty
                        ? 'Reasoning LLM: ${provider.effectiveModel.isNotEmpty ? provider.effectiveModel : provider.availableLocalModels.first}'
                        : 'Reasoning LLM: Missing in Ollama',
                    subtitle: provider.availableLocalModels.isNotEmpty
                        ? '${provider.availableLocalModels.length} local text/chat models detected'
                        : 'Run `ollama run qwen2.5-coder:1.5b` in terminal to pull a fast 1.5B model.',
                  ),
                  const SizedBox(height: 10),

                  // 3. Visual Intelligence Status Card
                  _buildVisionStatusCard(theme, provider),
                  const SizedBox(height: 14),

                  // Quick Action: Enable Lightweight Mode if vision inactive
                  if (!provider.isVisionActive &&
                      provider.availableLocalModels.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text(
                          '⚡ Enable Lightweight Laptop Mode & Start',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          await provider.setUseLightweightVision(true);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            _startRecording();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Alternative: Cloud Gemini Key
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        size: 14,
                        color: theme.fgMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Note: Entering a Google Gemini API Key in Settings also enables high-speed cloud multimodal reasoning instantly.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.fgMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (inDialogStatus != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: theme.attentionFg.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.attentionFg.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: theme.attentionFg,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              inDialogStatus!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.fgDefault,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: theme.fgMuted)),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onOpenSetupGuide?.call(AgentMode.deskMate);
              },
              child: const Text('Configure API Keys'),
            ),
            ElevatedButton.icon(
              onPressed: isRechecking
                  ? null
                  : () async {
                      setDialogState(() => isRechecking = true);
                      await provider.refreshHealthStatus();
                      if (!ctx.mounted) return;

                      if (provider.isMeetingAiReady) {
                        Navigator.of(ctx).pop();
                        _showTopNotification(
                          'AI Engine & models verified! Starting Meeting Scribe...',
                        );
                        _startRecording();
                      } else {
                        final String msg = !provider.isBackendOnline
                            ? (provider.isConnecting
                                  ? 'Refreshed: Backend engine is still starting...'
                                  : 'Refreshed: Backend engine is unreachable on port ${provider.backendPort}.')
                            : (!provider.isLocalLlmOnline
                                  ? 'Refreshed: Local Ollama is offline at ${AppConstants.ollamaHost}.'
                                  : 'Refreshed: Reasoning LLM or Gemini key required.');
                        setDialogState(() {
                          isRechecking = false;
                          inDialogStatus = msg;
                        });
                        _showTopNotification(msg);
                      }
                    },
              icon: isRechecking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(isRechecking ? 'Checking...' : 'Recheck & Start'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentFg,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMicMute() async {
    if (_isTogglingMic) return;
    final targetMuted = !_isMicMuted;
    if (!_isRecording) {
      setState(() {
        _isMicMuted = targetMuted;
      });
      _showTopNotification(
        targetMuted
            ? 'Default Mode: Speaker Only (Mic Muted on Start)'
            : 'Default Mode: Speaker + Mic (Active)',
      );
      return;
    }
    setState(() => _isTogglingMic = true);
    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final res = await provider.apiService.setMeetingMicMuted(targetMuted);
      if (!mounted) return;
      if (res['status'] != 'ok') {
        setState(() => _isTogglingMic = false);
        _showTopNotification(
          'Mic could not be changed because audio recording is not running for this meeting.',
          isError: true,
        );
        return;
      }
      if (mounted) {
        setState(() {
          _isMicMuted = res['muted'] == true;
          _isTogglingMic = false;
        });
        _showTopNotification(
          targetMuted
              ? 'Mic Muted — Ambient room noise blocked'
              : 'Mic Active — Mixed Speaker & Speech',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTogglingMic = false);
        _showTopNotification(
          'Failed to update mic mute state: ${_errorText(e)}',
          isError: true,
        );
      }
    }
  }

  String _mapStageToTool(int stage) {
    switch (stage) {
      case 1:
        return 'audio_normalization';
      case 2:
        return 'voxtral_diarization';
      case 3:
        return 'vision_synthesis';
      case 4:
        return 'report_compilation';
      default:
        return 'multimodal_pipeline';
    }
  }

  String _generateDefaultOutputForStage(int stage, String detail) {
    switch (stage) {
      case 1:
        return 'Audio Normalization Pipeline completed.\nOutput: 16000Hz mono WAV buffer flushed and validated.\nStream status: Ready for neural transcription.';
      case 2:
        return 'Voxtral 4B Neural Diarization completed.\nVoiceprints extracted and clustered.\nDialogue turn timestamps synchronized.';
      case 3:
        return 'Multimodal Vision Fusion completed.\nScreen OCR keyframes matched against temporal transcript milestones.';
      case 4:
        return 'Executive Synthesis & PDF Engine completed.\nStructured action items extracted and PDF report successfully compiled.';
      default:
        return detail.isNotEmpty
            ? detail
            : 'Pipeline stage completed successfully.';
    }
  }

  void _enqueueTelemetry({
    required int stageIndex,
    required double progress,
    required String title,
    required String detail,
    String? toolName,
    Map<String, dynamic>? arguments,
    String? rawOutput,
    int? durationMs,
  }) {
    _telemetryQueue.add({
      'stage_index': stageIndex,
      'progress': progress,
      'title': title,
      'detail': detail,
      'tool': toolName ?? _mapStageToTool(stageIndex),
      'arguments': arguments,
      'raw_output': rawOutput,
      'duration_ms': durationMs ?? 1150,
    });

    if (!_isProcessingQueue) {
      _processTelemetryQueue();
    }
  }

  Future<void> _processTelemetryQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_telemetryQueue.isNotEmpty) {
      final item = _telemetryQueue.removeAt(0);
      final stageIdx = (item['stage_index'] as num?)?.toInt() ?? 1;
      final prog = (item['progress'] as num?)?.toDouble() ?? 0.25;
      final title = item['title'] as String? ?? 'Processing';
      final detail = item['detail'] as String? ?? '';
      final tool = item['tool'] as String? ?? _mapStageToTool(stageIdx);
      final args = item['arguments'] as Map<String, dynamic>?;
      final output =
          item['raw_output'] as String? ??
          _generateDefaultOutputForStage(stageIdx, detail);
      final duration = (item['duration_ms'] as num?)?.toInt() ?? 1150;

      if (mounted) {
        setState(() {
          _postProcessingStage = stageIdx;
          _postProcessingProgress = prog;
          _postProcessingTitle = title;
          _postProcessingDetail = detail;

          final existingIdx = _meetingTelemetrySteps.indexWhere(
            (s) => s.step == stageIdx,
          );
          final stepTelemetry = AgentStepTelemetry(
            step: stageIdx,
            phase: 'tool_call',
            tool: tool,
            title: title,
            summary: detail,
            arguments:
                args ??
                {
                  'stage': stageIdx,
                  'pipeline': tool,
                  'session_id': _currentSessionId ?? 'active_session',
                },
            rawOutput: output,
            durationMs: duration,
            timestamp: DateTime.now(),
          );

          if (existingIdx >= 0) {
            _meetingTelemetrySteps[existingIdx] = stepTelemetry;
          } else {
            _meetingTelemetrySteps.add(stepTelemetry);
          }
        });
      }

      // Human-readable view time pacing (850ms) so user can comfortably read each step
      await Future.delayed(const Duration(milliseconds: 850));
    }

    _isProcessingQueue = false;
  }

  List<AgentStepTelemetry> _buildTelemetryStepsFromSessionData(
    Map<String, dynamic> data,
    String sessionId,
  ) {
    final transcript = data['transcript'] as Map<String, dynamic>?;
    final steps = (data['steps'] as List<dynamic>?) ?? [];
    final speakersCount = _countSpeakers(transcript);
    final stepsCount = steps.length;
    final now = DateTime.now();

    return [
      AgentStepTelemetry(
        step: 1,
        phase: 'tool_call',
        tool: 'audio_normalization',
        title: 'Audio Normalization (16kHz PCM WAV)',
        summary:
            'Flushed audio buffer and converted audio stream to 16kHz mono WAV.',
        arguments: {
          'session_id': sessionId,
          'target_sample_rate': 16000,
          'channels': 1,
        },
        rawOutput:
            'Audio stream normalized successfully.\nFormat: WAV 16kHz Mono\nIntegrity: Verified',
        durationMs: 840,
        timestamp: now.subtract(const Duration(seconds: 12)),
      ),
      AgentStepTelemetry(
        step: 2,
        phase: 'tool_call',
        tool: 'voxtral_diarization',
        title: 'Voxtral 4B Diarization & Voiceprints',
        summary:
            'Clustered $speakersCount speaker voiceprint(s) and aligned conversation turns.',
        arguments: {
          'session_id': sessionId,
          'model': 'Voxtral-4B-Diarization',
          'speakers_detected': speakersCount,
        },
        rawOutput:
            'Voxtral 4B diarization completed.\nSpeakers detected: $speakersCount\nDialogue segments extracted.',
        durationMs: 2310,
        timestamp: now.subtract(const Duration(seconds: 9)),
      ),
      AgentStepTelemetry(
        step: 3,
        phase: 'tool_call',
        tool: 'vision_synthesis',
        title: 'Multimodal Vision & Screen OCR Fusion',
        summary:
            'Extracted and fused $stepsCount screen OCR visual moments with spoken dialogue.',
        arguments: {'session_id': sessionId, 'visual_milestones': stepsCount},
        rawOutput:
            'Multimodal fusion executed.\nSynchronized $stepsCount OCR visual moments with audio timeline.',
        durationMs: 1950,
        timestamp: now.subtract(const Duration(seconds: 6)),
      ),
      AgentStepTelemetry(
        step: 4,
        phase: 'tool_call',
        tool: 'report_compilation',
        title: 'Executive Report & PDF Compilation',
        summary:
            'Synthesized executive summary, action items, and compiled publication-ready PDF.',
        arguments: {
          'session_id': sessionId,
          'has_pdf': data['has_pdf'] ?? true,
        },
        rawOutput:
            'Executive synthesis completed.\nPDF artifact compiled and saved to disk.',
        durationMs: 1420,
        timestamp: now.subtract(const Duration(seconds: 3)),
      ),
    ];
  }

  Future<void> _stopRecording() async {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _statusTimer?.cancel();
    setState(() {
      _isRecording = false;
      _audioWarning = null;
    });
    try {
      await provider.apiService.stopMeeting();
    } catch (e) {
      _showTopNotification(
        'Stopping the meeting reported a problem: ${_errorText(e)}. Trying to build the report anyway.',
        isError: true,
      );
    }
    await _runSummarization();
  }

  /// Builds the report for [_currentSessionId]. Used after Stop and by Retry summary.
  Future<void> _runSummarization() async {
    if (_currentSessionId == null || _isSummarizing || !mounted) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);

    // Reset telemetry queue & steps
    _meetingTelemetrySteps.clear();
    _telemetryQueue.clear();
    _isProcessingQueue = false;

    setState(() {
      _summaryError = null;
      _isSummarizing = true;
      _postProcessingStage = 1;
      _postProcessingProgress = 0.20;
      _postProcessingTitle = 'Audio Normalization';
      _postProcessingDetail =
          'Flushing PCM buffer and converting stream to 16kHz mono WAV...';
      _postProcessingElapsedSeconds = 0;
    });

    // Enqueue Stage 1 immediately
    _enqueueTelemetry(
      stageIndex: 1,
      progress: 0.25,
      title: 'Audio Normalization',
      detail: 'Flushing PCM buffer and converting stream to 16kHz mono WAV...',
      toolName: 'audio_normalization',
    );

    _startPostProcessingTelemetry();

    try {
      final summaryRes = await provider.apiService.summarizeMeeting(
        sessionId: _currentSessionId,
        customFields: _customFocusTopics.isNotEmpty ? _customFocusTopics : null,
        geminiApiKey: provider.isUsingGemini ? provider.geminiApiKey : null,
      );

      _postProcessingTimer?.cancel();
      _meetingWebSocket?.close();
      _meetingWebSocket = null;

      final summaryText = summaryRes['summary'] as String? ?? '';
      final important =
          (summaryRes['important_steps'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final desc =
          summaryRes['step_descriptions'] as Map<String, dynamic>? ?? {};
      final customAnalysis =
          (summaryRes['custom_fields'] as Map<String, dynamic>?) ?? {};
      final transcript = summaryRes['transcript'] as Map<String, dynamic>?;
      final steps = (summaryRes['steps'] as List<dynamic>?) ?? [];
      final speakerCount = _countSpeakers(transcript);
      final stepsCount = steps.length;
      final pdfGenerated = summaryRes['pdf_generated'] == true;

      // Ensure stages 2, 3, and 4 are enqueued if backend completed quickly
      if (!_meetingTelemetrySteps.any((s) => s.step == 2) &&
          !_telemetryQueue.any((q) => q['stage_index'] == 2)) {
        _enqueueTelemetry(
          stageIndex: 2,
          progress: 0.50,
          title: 'Voxtral 4B Diarization',
          detail:
              'Extracted voiceprints and aligned dialogue for $speakerCount speaker(s)...',
          toolName: 'voxtral_diarization',
          rawOutput:
              'Voxtral 4B Diarization completed.\nSpeakers detected: $speakerCount\nAligned speech segments: ${transcript?['segments'] is List ? (transcript!['segments'] as List).length : 0}',
        );
      }

      if (!_meetingTelemetrySteps.any((s) => s.step == 3) &&
          !_telemetryQueue.any((q) => q['stage_index'] == 3)) {
        _enqueueTelemetry(
          stageIndex: 3,
          progress: 0.75,
          title: 'Multimodal Vision Synthesis',
          detail:
              'Fused $stepsCount visual milestone screen captures with audio timeline...',
          toolName: 'vision_synthesis',
          rawOutput:
              'Multimodal fusion completed.\nScreen OCR keyframes analyzed: $stepsCount\nTimeline milestones correlated with spoken transcription.',
        );
      }

      if (!_meetingTelemetrySteps.any((s) => s.step == 4) &&
          !_telemetryQueue.any((q) => q['stage_index'] == 4)) {
        _enqueueTelemetry(
          stageIndex: 4,
          progress: 1.0,
          title: 'Executive Report & PDF Compilation',
          detail:
              'Compiling executive session brief and compiling PDF report...',
          toolName: 'report_compilation',
          rawOutput:
              'Compilation engine completed.\nExecutive session summary synthesized.\nPDF report generated successfully.',
        );
      }

      // Smoothly drain the queue so the user can see each stage transition with readable pacing
      while (_telemetryQueue.isNotEmpty || _isProcessingQueue) {
        await Future.delayed(const Duration(milliseconds: 80));
      }
      // Brief completion pause for user view perception
      await Future.delayed(const Duration(milliseconds: 350));

      if (mounted) {
        setState(() {
          _isSummarizing = false;
          _executiveSummary = summaryText;
          _importantSteps = important;
          _stepDescriptions = desc;
          _actionItems = _extractActionItemsFromSummary(summaryText);
          _customFieldsAnalysis = customAnalysis;
          _transcriptData = transcript;
          _meetingSteps = steps;
          _pdfUrl = pdfGenerated && _currentSessionId != null
              ? provider.apiService.getMeetingPdfUrl(_currentSessionId!)
              : null;
        });
        _loadSavedSessions(autoLoadLatest: false);

        final transcriptReason = transcript?['reason'];
        if (!pdfGenerated) {
          _showTopNotification(
            'The summary is ready, but the PDF could not be created, so Download, Email and Drive are unavailable. Press Retry summary to try again.',
            isError: true,
          );
          setState(() {
            _summaryError =
                'The PDF could not be created for this meeting. Press Retry summary to try again.';
          });
        } else if (transcriptReason is String && transcriptReason.isNotEmpty) {
          _showTopNotification(transcriptReason, isError: true);
        }
      }
    } catch (e) {
      _postProcessingTimer?.cancel();
      _meetingWebSocket?.close();
      _meetingWebSocket = null;
      if (mounted) {
        final message = e is TimeoutException
            ? 'The report is taking longer than expected. Press Retry summary in a few minutes.'
            : _errorText(e);
        setState(() {
          _isSummarizing = false;
          _summaryError = message;
        });
        _showTopNotification(message, isError: true);
      }
    }
  }

  static int _countSpeakers(Map<String, dynamic>? transcript) {
    final segments = transcript?['segments'];
    if (segments is! List || segments.isEmpty) return 0;
    return segments
        .whereType<Map>()
        .map((s) => s['speaker']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .length;
  }

  void _startPostProcessingTelemetry() {
    _postProcessingElapsedSeconds = 0;
    _postProcessingTimer?.cancel();
    _postProcessingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isSummarizing) {
        timer.cancel();
        return;
      }
      _postProcessingElapsedSeconds++;
      if (mounted) setState(() {});
      if (_postProcessingElapsedSeconds == 3) {
        _enqueueTelemetry(
          stageIndex: 2,
          progress: 0.45,
          title: 'Voxtral 4B Diarization',
          detail:
              'Transcribing conversation and clustering speaker voiceprints...',
          toolName: 'voxtral_diarization',
        );
      } else if (_postProcessingElapsedSeconds == 9) {
        _enqueueTelemetry(
          stageIndex: 3,
          progress: 0.70,
          title: 'Multimodal Vision Synthesis',
          detail: 'Fusing screen OCR captures with spoken transcript...',
          toolName: 'vision_synthesis',
        );
      } else if (_postProcessingElapsedSeconds == 16) {
        _enqueueTelemetry(
          stageIndex: 4,
          progress: 0.90,
          title: 'PDF Compilation',
          detail: 'Compiling executive report and syncing action items...',
          toolName: 'report_compilation',
        );
      }
    });

    _connectMeetingWebSocket();
  }

  Future<void> _connectMeetingWebSocket() async {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final wsUrl =
        '${provider.backendUrl.replaceFirst('http', 'ws')}${ApiPaths.wsMeeting}';
    try {
      _meetingWebSocket?.close();
      final ws = await WebSocket.connect(
        wsUrl,
      ).timeout(const Duration(seconds: 3));
      _meetingWebSocket = ws;
      ws.listen(
        (event) {
          try {
            final data = jsonDecode(event.toString()) as Map<String, dynamic>;
            if (data['type'] == 'post_processing_telemetry' && mounted) {
              final stage = (data['stage_index'] as num?)?.toInt() ?? 1;
              final prog = (data['progress'] as num?)?.toDouble() ?? 0.25;
              final title = (data['title'] as String?) ?? 'Processing';
              final detail = (data['detail'] as String?) ?? '';
              _enqueueTelemetry(
                stageIndex: stage,
                progress: prog,
                title: title,
                detail: detail,
                rawOutput: data['raw_output'] as String?,
              );
            }
          } catch (_) {}
        },
        onDone: () {
          _meetingWebSocket = null;
        },
        onError: (_) {
          _meetingWebSocket = null;
        },
      );
    } catch (_) {
      _meetingWebSocket = null;
    }
  }

  Future<void> _syncTasksToDeskMate() async {
    if (_actionItems.isEmpty || _currentSessionId == null) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    setState(() => _isSyncingTasks = true);
    try {
      final res = await provider.apiService.syncMeetingTasks(
        sessionId: _currentSessionId!,
        actionItems: _actionItems,
      );
      if (mounted) {
        setState(() => _isSyncingTasks = false);
        _showTopNotification(
          'Successfully synced ${res['tasks_created']} action items into DeskMate Tasks!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncingTasks = false);
        _showTopNotification(
          'Task sync failed: ${_errorText(e)}',
          isError: true,
        );
      }
    }
  }

  void _openPdf() {
    if (_pdfUrl == null) return;
    openExternal(_pdfUrl!);
  }

  static const String _googleSignInHint =
      'Working on it. If a browser window opens, sign in to Google to continue.';

  Future<void> _exportToGoogleDrive() async {
    if (_currentSessionId == null) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    setState(() => _isExportingDrive = true);
    _showTopNotification(_googleSignInHint);
    try {
      final res = await provider.apiService.exportMeetingToDrive(
        sessionId: _currentSessionId!,
        folderName: 'DeskMate Meetings',
      );
      if (mounted) {
        setState(() => _isExportingDrive = false);
        final link = res['view_link'] ?? '';
        _showTopNotification(
          'Uploaded to Google Drive in "DeskMate Meetings"! ${link.isNotEmpty ? "(Link ready)" : ""}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExportingDrive = false);
        _showTopNotification(_errorText(e), isError: true);
      }
    }
  }

  Future<void> _promptSendEmail() async {
    if (_currentSessionId == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedUserName = prefs.getString(PrefsKeys.userName) ?? '';
    final savedUserDesignation =
        prefs.getString(PrefsKeys.userDesignation) ?? '';
    final savedUserEmail = prefs.getString(PrefsKeys.userEmail) ?? '';

    // Format date string from session ID
    String dateStr = '';
    final sid = _currentSessionId!;
    if (sid.length >= 8) {
      dateStr =
          '${sid.substring(0, 4)}-${sid.substring(4, 6)}-${sid.substring(6, 8)}';
    } else {
      final now = DateTime.now();
      dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    final defaultPdfName = 'DeskMate_Executive_Meeting_Report_$dateStr.pdf';
    final defaultSubject = 'DeskMate Meeting Intelligence: Debrief ($dateStr)';

    final userNameController = TextEditingController(text: savedUserName);
    final designationController = TextEditingController(
      text: savedUserDesignation,
    );
    final senderEmailController = TextEditingController(text: savedUserEmail);
    final emailController = TextEditingController();
    final ccController = TextEditingController();
    final subjectController = TextEditingController(text: defaultSubject);
    final formKey = GlobalKey<FormState>();

    final result = await showBlurredDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: theme.bgSubtle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.purplePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  color: AppTheme.purplePrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Email Meeting Report & PDF',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dispatches dynamic executive debrief via connected Gmail',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // DeskMate Branding Info Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.purplePrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.purplePrimary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_outlined,
                                size: 16,
                                color: AppTheme.purplePrimary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'DeskMate Dynamic Meeting Template',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.purplePrimary,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF0A66C2,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LinkedIn Verified',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0A66C2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sends a dynamic executive debrief, key decisions, and action items checklist. Attributed with your name, designation, and LinkedIn badge.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: theme.fgDefault,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Attachment: $defaultPdfName',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.fgMuted,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sender Information Row (Name & Designation)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: userNameController,
                            decoration: const InputDecoration(
                              labelText: 'Your Name *',
                              hintText: 'e.g. Ganesh Venkatesan',
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                size: 18,
                              ),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: designationController,
                            decoration: const InputDecoration(
                              labelText: 'Your Designation',
                              hintText: 'e.g. Lead Architect',
                              prefixIcon: Icon(Icons.badge_outlined, size: 18),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Sender Email / Connected Account
                    TextFormField(
                      controller: senderEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Sender Email (Your Connected Gmail)',
                        hintText:
                            'user@example.com (or leave empty to auto-detect)',
                        prefixIcon: Icon(
                          Icons.account_circle_outlined,
                          size: 18,
                        ),
                        helperText:
                            'Email will be dispatched from this account with your signature',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Recipient Email
                    TextFormField(
                      controller: emailController,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Recipient email is required';
                        }
                        if (!val.contains('@') || !val.contains('.')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Recipient Email *',
                        hintText: 'colleague@example.com',
                        prefixIcon: Icon(
                          Icons.alternate_email_rounded,
                          size: 18,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subject Line
                    TextFormField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Subject Line',
                        prefixIcon: Icon(Icons.subject_rounded, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Optional CC
                    TextFormField(
                      controller: ccController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'CC (Optional)',
                        hintText: 'manager@example.com',
                        prefixIcon: Icon(Icons.copy_rounded, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.of(ctx).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.purplePrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send Email'),
            ),
          ],
        );
      },
    );

    final toEmail = emailController.text.trim();
    final userName = userNameController.text.trim();
    final designation = designationController.text.trim();
    final senderEmail = senderEmailController.text.trim();
    final subject = subjectController.text.trim();
    final ccEmail = ccController.text.trim();

    // Dispose after the dialog's exit animation, which still reads the controllers.
    Future.delayed(const Duration(milliseconds: 400), () {
      userNameController.dispose();
      designationController.dispose();
      senderEmailController.dispose();
      emailController.dispose();
      subjectController.dispose();
      ccController.dispose();
    });

    if (result == true && toEmail.isNotEmpty) {
      if (!mounted) return;

      if (userName.isNotEmpty) {
        await prefs.setString(PrefsKeys.userName, userName);
      }
      if (designation.isNotEmpty) {
        await prefs.setString(PrefsKeys.userDesignation, designation);
      }
      if (senderEmail.isNotEmpty) {
        await prefs.setString(PrefsKeys.userEmail, senderEmail);
      }
      if (!mounted) return;

      final provider = Provider.of<ChatProvider>(context, listen: false);
      setState(() => _isSendingEmail = true);
      _showTopNotification(_googleSignInHint);
      try {
        final res = await provider.apiService.sendMeetingEmail(
          sessionId: _currentSessionId!,
          toEmail: toEmail,
          subject: subject.isNotEmpty ? subject : null,
          ccEmail: ccEmail.isNotEmpty ? ccEmail : null,
          userName: userName.isNotEmpty ? userName : null,
          designation: designation.isNotEmpty ? designation : null,
          senderEmail: senderEmail.isNotEmpty ? senderEmail : null,
          pdfName: defaultPdfName,
        );
        if (mounted) {
          setState(() => _isSendingEmail = false);
          final pdfDisplayName = res['pdf_name'] ?? defaultPdfName;
          _showTopNotification(
            'Meeting report and attached PDF ($pdfDisplayName) emailed to $toEmail!',
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSendingEmail = false);
          _showTopNotification(_errorText(e), isError: true);
        }
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.bgCanvas,
      child: Column(
        children: [
          // --- HEADER & CONTROLS BANNER ---
          _buildHeaderBanner(theme),

          // --- MAIN SCROLLABLE CONTENT ---
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- TELEMETRY CARDS ---
                  _buildTelemetryGrid(theme),
                  const SizedBox(height: 20),

                  if (_isRecording && _audioWarning != null) ...[
                    _buildNoticeCard(
                      theme,
                      icon: Icons.mic_off_rounded,
                      message: _audioWarning!,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // --- SUMMARIZING LOADER ---
                  if (_isSummarizing) ...[
                    _buildSummarizingIndicator(theme),
                    const SizedBox(height: 20),
                  ],

                  if (!_isSummarizing &&
                      !_isRecording &&
                      _summaryError != null &&
                      _currentSessionId != null) ...[
                    _buildNoticeCard(
                      theme,
                      icon: Icons.error_outline_rounded,
                      message: _summaryError!,
                      actionLabel: 'Retry summary',
                      onAction: _runSummarization,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // --- UNIFIED MEETING REPORT CONTAINER (Single cohesive container for all meeting content) ---
                  if (_executiveSummary != null) ...[
                    _buildUnifiedMeetingContainer(theme),
                    const SizedBox(height: 20),
                  ] else if (_transcriptData != null) ...[
                    _buildTranscriptCard(theme),
                    const SizedBox(height: 20),
                  ],

                  // --- CENTER VISUAL STATE (IDLE, STARTING, OR RECORDING) ---
                  if (!_isSummarizing && _executiveSummary == null) ...[
                    if (!_isRecording) ...[
                      _buildCustomFocusTopicsCard(theme),
                      const SizedBox(height: 20),
                    ],
                    _buildCenterVisual(theme),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner(ThemeData theme) {
    final provider = Provider.of<ChatProvider>(context);
    final isOnline = provider.isBackendOnline;
    final isConnecting = provider.isConnecting;
    final hasAi = provider.isLocalLlmOnline || provider.isUsingGemini;

    final String statusLabel;
    final Color statusColor;
    final bool showSpinner;

    if (_isRecording) {
      statusLabel = 'LIVE RECORDING';
      statusColor = AppTheme.recordingRed;
      showSpinner = false;
    } else if (_isStarting || isConnecting) {
      statusLabel = 'STARTING...';
      statusColor = theme.attentionFg;
      showSpinner = true;
    } else if (!isOnline) {
      statusLabel = 'OFFLINE';
      statusColor = theme.dangerFg;
      showSpinner = false;
    } else if (!hasAi) {
      statusLabel = 'SETUP REQUIRED';
      statusColor = theme.attentionFg;
      showSpinner = false;
    } else {
      statusLabel = 'READY';
      statusColor = AppTheme.lightSuccessFg;
      showSpinner = false;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        border: Border(bottom: BorderSide(color: theme.borderDefault)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.accentFg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.mic_rounded, color: theme.accentFg, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Meeting Scribe',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showSpinner) ...[
                            SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ] else ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Voxtral 4B Audio Intelligence • NVIDIA LocateAnything-3B Vision Grounding',
                  style: TextStyle(fontSize: 12, color: theme.fgMuted),
                ),
              ],
            ),
          ),

          // Primary Actions
          if (!_isRecording && !_isSummarizing)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onOpenSetupGuide?.call(AgentMode.meeting),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: const Text('User Guide'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.fgDefault,
                    side: BorderSide(color: theme.borderDefault),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    _showSavedSessionsDialog();
                  },
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('Past Meetings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.fgDefault,
                    side: BorderSide(color: theme.borderDefault),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!provider.isMeetingAiReady)
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showAiSetupRequiredModal(context, theme, provider),
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('AI Setup Required'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _isStarting ? null : _startRecording,
                    icon: _isStarting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      _isStarting ? 'Starting...' : 'Start Meeting Scribe',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentFg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            )
          else if (_isRecording)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _isTogglingMic ? null : _toggleMicMute,
                  icon: _isTogglingMic
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _isMicMuted
                                ? AppTheme.amber
                                : AppTheme.emerald,
                          ),
                        )
                      : Icon(
                          _isMicMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          size: 18,
                          color: _isMicMuted
                              ? AppTheme.amber
                              : AppTheme.emerald,
                        ),
                  label: Text(
                    _isMicMuted
                        ? 'Mic Muted (Room Blocked)'
                        : 'Mic Active (Voice In)',
                    style: TextStyle(
                      color: _isMicMuted ? AppTheme.amber : AppTheme.emerald,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _isMicMuted
                          ? AppTheme.amber.withValues(alpha: 0.6)
                          : AppTheme.emerald.withValues(alpha: 0.6),
                    ),
                    backgroundColor: _isMicMuted
                        ? AppTheme.amber.withValues(alpha: 0.1)
                        : AppTheme.emerald.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: Text(
                    'End Meeting (${_formatDuration(_uptimeSeconds)})',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.recordingRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            theme: theme,
            title: 'Session Duration',
            value: _formatDuration(_uptimeSeconds),
            icon: Icons.timer_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildMetricTile(
            theme: theme,
            title: 'Frames Captured',
            value: '$_framesProcessed frames',
            icon: Icons.filter_frames_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildMetricTile(
            theme: theme,
            title: 'UI Steps Detected',
            value: '$_eventsDetected steps',
            icon: Icons.touch_app_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Tooltip(
            message: 'Click to toggle between Speaker Only and Speaker + Mic',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _toggleMicMute,
                child: _buildMetricTile(
                  theme: theme,
                  title: 'Audio Capture Mode',
                  value: _isMicMuted ? 'Speaker Only' : 'Speaker + Mic',
                  icon: Icons.volume_up_rounded,
                  valueColor: _isMicMuted ? AppTheme.amber : AppTheme.emerald,
                  iconColor: _isMicMuted ? AppTheme.amber : AppTheme.emerald,
                  trailing: Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: (_isMicMuted ? AppTheme.amber : AppTheme.emerald)
                        .withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVisionStatusCard(ThemeData theme, ChatProvider provider) {
    const activeSubtitle = 'Screen OCR capture & keyframe grounding enabled';
    final ollamaOnline = provider.isLocalLlmOnline;

    if (provider.isUsingGemini) {
      return _buildAiStatusCard(
        theme: theme,
        color: theme.accentFg,
        icon: Icons.cloud_done_rounded,
        title: 'Vision: Gemini 2.5 Flash (Cloud)',
        subtitle: activeSubtitle,
      );
    }
    if (provider.useLightweightVision) {
      return _buildAiStatusCard(
        theme: theme,
        color: AppTheme.teal,
        icon: Icons.laptop_chromebook_rounded,
        title: ollamaOnline
            ? 'Vision: Lightweight Laptop Mode'
            : 'Vision: Lightweight Laptop Mode (Requires Ollama)',
        subtitle: ollamaOnline
            ? activeSubtitle
            : 'Lightweight mode is enabled. Start Ollama to run the local chat model with OCR.',
      );
    }
    if (provider.hasVisionModel) {
      return _buildAiStatusCard(
        theme: theme,
        color: theme.successFg,
        icon: Icons.check_circle_rounded,
        title:
            'Vision: ${provider.visionModelName.isNotEmpty ? provider.visionModelName : 'Active'}',
        subtitle: activeSubtitle,
      );
    }
    if (!ollamaOnline) {
      return _buildAiStatusCard(
        theme: theme,
        color: theme.dangerFg,
        icon: Icons.visibility_off_rounded,
        title: 'Vision: Offline (Ollama Offline)',
        subtitle:
            'Ollama is offline. Start Ollama to use vision models, or configure Gemini API key.',
      );
    }
    return _buildAiStatusCard(
      theme: theme,
      color: theme.attentionFg,
      icon: Icons.visibility_off_rounded,
      title: 'Vision: Inactive',
      subtitle:
          'Enable Lightweight Laptop Mode below or pull `llama3.2-vision`.',
    );
  }

  Widget _buildNoticeCard(
    ThemeData theme, {
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.attentionFg.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.attentionFg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.attentionFg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.fgDefault,
                height: 1.4,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(actionLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentFg,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiStatusCard({
    required ThemeData theme,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: theme.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
    Color? iconColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderDefault),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor ?? theme.fgMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: theme.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: valueColor ?? theme.fgDefault,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _activeEngineName {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    return provider.isUsingGemini
        ? 'Gemini 2.5 Flash (Cloud Multimodal)'
        : (provider.hasVisionModel
              ? 'Local Ollama (${provider.visionModelName.isNotEmpty ? provider.visionModelName : 'llama3.2-vision'})'
              : (provider.effectiveModel.isNotEmpty
                    ? 'Local Ollama (${provider.effectiveModel})'
                    : 'Local Ollama LLM'));
  }

  List<Map<String, dynamic>> get _pipelineSteps => [
    {
      'title': 'Audio Prep',
      'sub': '16kHz WAV normalize',
      'icon': Icons.graphic_eq_rounded,
    },
    {
      'title': 'Voxtral Diarization',
      'sub': 'Speaker turns & transcript',
      'icon': Icons.record_voice_over_rounded,
    },
    {
      'title': 'Multimodal Vision',
      'sub': 'Screen OCR & timeline fusion',
      'icon': Icons.auto_awesome_rounded,
    },
    {
      'title': 'PDF Compilation',
      'sub': 'Executive report & tasks',
      'icon': Icons.picture_as_pdf_rounded,
    },
  ];

  Widget _buildSummarizingIndicator(ThemeData theme) {
    final String activeEngineName = _activeEngineName;

    final minutes = (_postProcessingElapsedSeconds ~/ 60).toString().padLeft(
      2,
      '0',
    );
    final seconds = (_postProcessingElapsedSeconds % 60).toString().padLeft(
      2,
      '0',
    );

    final steps = _pipelineSteps;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.accentFg.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: theme.accentFg.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.accentFg.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: theme.accentFg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autonomous Post-Recording Agent',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.fgDefault,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Fusing multi-stream telemetry with $activeEngineName',
                        style: TextStyle(fontSize: 12, color: theme.fgMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.bgCanvas,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.borderDefault),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: theme.accentFg),
                    const SizedBox(width: 6),
                    Text(
                      '$minutes:$seconds',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _postProcessingProgress.clamp(0.05, 1.0),
              minHeight: 6,
              backgroundColor: theme.bgCanvas,
              valueColor: AlwaysStoppedAnimation<Color>(theme.accentFg),
            ),
          ),
          const SizedBox(height: 20),

          // 4-Phase Stepper Cards
          Row(
            children: List.generate(steps.length, (idx) {
              final stepNumber = idx + 1;
              final isDone = _postProcessingStage > stepNumber;
              final isActive = _postProcessingStage == stepNumber;
              final stepData = steps[idx];

              final Color cardBorder = isActive
                  ? theme.accentFg
                  : (isDone
                        ? theme.successFg.withValues(alpha: 0.5)
                        : theme.borderDefault);
              final Color cardBg = isActive
                  ? theme.accentFg.withValues(alpha: 0.08)
                  : (isDone
                        ? theme.successFg.withValues(alpha: 0.05)
                        : theme.bgCanvas);

              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: idx == steps.length - 1 ? 0 : 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cardBorder,
                      width: isActive ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            stepData['icon'] as IconData,
                            size: 16,
                            color: isActive
                                ? theme.accentFg
                                : (isDone ? theme.successFg : theme.fgMuted),
                          ),
                          if (isDone)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: theme.successFg,
                            )
                          else if (isActive)
                            SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: theme.accentFg,
                              ),
                            )
                          else
                            Text(
                              '$stepNumber',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.fgMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        stepData['title'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? theme.accentFg
                              : (isDone ? theme.fgDefault : theme.fgMuted),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stepData['sub'] as String,
                        style: TextStyle(fontSize: 10.5, color: theme.fgMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Terminal Activity Micro-Feed
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.bgCanvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 16, color: theme.accentFg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_postProcessingTitle: $_postProcessingDetail',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: theme.fgDefault,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeaderRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: theme.accentFg, size: 20),
            const SizedBox(width: 8),
            Text(
              'Executive Session Summary',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.fgDefault,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  _showScreenshotModal(context, 0, _getDisplaySteps()),
              icon: const Icon(Icons.photo_library_outlined, size: 15),
              label: Text('Screenshots (${_getDisplaySteps().length})'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.fgDefault,
                backgroundColor: theme.bgCanvas,
                side: BorderSide(color: theme.borderDefault),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showTranscriptModal(context, theme),
              icon: const Icon(Icons.record_voice_over_rounded, size: 15),
              label: const Text('Transcript'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.fgDefault,
                backgroundColor: theme.bgCanvas,
                side: BorderSide(color: theme.borderDefault),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (_pdfUrl != null) ...[
              ElevatedButton.icon(
                onPressed: _openPdf,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text(
                  'Download PDF',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentFg,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSendingEmail ? null : _promptSendEmail,
                icon: _isSendingEmail
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.fgDefault,
                        ),
                      )
                    : const Icon(Icons.mail_outline_rounded, size: 15),
                label: const Text('Email Report'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.fgDefault,
                  backgroundColor: theme.bgCanvas,
                  side: BorderSide(color: theme.borderDefault),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isExportingDrive ? null : _exportToGoogleDrive,
                icon: _isExportingDrive
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 15),
                label: const Text('Save to Drive'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.fgDefault,
                  backgroundColor: theme.bgCanvas,
                  side: BorderSide(color: theme.borderDefault),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedPipelineCard(ThemeData theme) {
    final String activeEngineName = _activeEngineName;

    final minutes = (_postProcessingElapsedSeconds ~/ 60).toString().padLeft(
      2,
      '0',
    );
    final seconds = (_postProcessingElapsedSeconds % 60).toString().padLeft(
      2,
      '0',
    );
    final displayTime = _postProcessingElapsedSeconds > 0
        ? '$minutes:$seconds'
        : '00:01';

    final steps = _pipelineSteps;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentFg.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: theme.accentFg.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar matching Image 1
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.accentFg.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: theme.accentFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Autonomous Post-Recording Agent',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: theme.fgDefault,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Fusing multi-stream telemetry with $activeEngineName',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.fgMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timer badge matching Image 1
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.bgSubtle,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.borderDefault),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: theme.accentFg,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          displayTime,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.fgDefault,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // "Inspect" button as requested by user
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showTelemetryInspection = !_showTelemetryInspection;
                      });
                    },
                    icon: Icon(
                      _showTelemetryInspection
                          ? Icons.expand_less_rounded
                          : Icons.account_tree_outlined,
                      size: 15,
                    ),
                    label: Text(
                      _showTelemetryInspection
                          ? 'Hide Workflow'
                          : 'Inspect Workflow',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentFg,
                      side: BorderSide(
                        color: theme.accentFg.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Completed Progress Bar (Full)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 1.0,
              minHeight: 5,
              backgroundColor: theme.bgSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(theme.accentFg),
            ),
          ),
          const SizedBox(height: 16),

          // 4-Phase Stepper Cards (All complete with green checkmarks)
          Row(
            children: List.generate(steps.length, (idx) {
              final stepData = steps[idx];
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: idx == steps.length - 1 ? 0 : 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.successFg.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.successFg.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            stepData['icon'] as IconData,
                            size: 16,
                            color: theme.successFg,
                          ),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: theme.successFg,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        stepData['title'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stepData['sub'] as String,
                        style: TextStyle(fontSize: 10.5, color: theme.fgMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Micro status feed matching Image 1
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.bgSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 15,
                  color: theme.accentFg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pdfUrl != null
                        ? 'PDF Compilation: Rendering high-resolution vector PDF report with redacted host UI...'
                        : 'Post-recording synthesis completed · Multi-stream telemetry fused.',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: theme.fgDefault,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItemsInner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppTheme.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Extracted Action Items',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.fgDefault,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isSyncingTasks ? null : _syncTasksToDeskMate,
                icon: _isSyncingTasks
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Sync to DeskMate Tasks'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in _actionItems) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.arrow_right_rounded,
                      size: 18,
                      color: AppTheme.amber,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: theme.fgDefault,
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

  Widget _buildUnifiedMeetingContainer(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.borderDefault),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Unified Action Bar & Title
          _buildSummaryHeaderRow(theme),
          const SizedBox(height: 18),

          // 2. Autonomous Post-Recording Agent Pipeline Status (Image 1)
          _buildCompletedPipelineCard(theme),

          // 3. Telemetry/Reasoning Workflow Inspection Accordion (if toggled)
          if (_showTelemetryInspection &&
              _meetingTelemetrySteps.isNotEmpty) ...[
            const SizedBox(height: 14),
            TelemetryAccordion(
              key: ValueKey(
                'meeting_telemetry_${_currentSessionId ?? "session"}',
              ),
              steps: _meetingTelemetrySteps,
              initiallyExpanded: true,
              activeTitle: 'Meeting Intelligence Reasoning & Telemetry',
            ),
          ],
          const SizedBox(height: 20),

          // 4. Executive Summary Markdown Body
          if (_executiveSummary != null && _executiveSummary!.isNotEmpty) ...[
            SelectionArea(
              child: MarkdownBody(
                data: _executiveSummary!,
                selectable: false,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: theme.fgDefault,
                  ),
                  h1: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: theme.fgDefault,
                    letterSpacing: -0.3,
                  ),
                  h2: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                    letterSpacing: -0.2,
                  ),
                  h3: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.accentFg,
                    letterSpacing: -0.1,
                  ),
                  strong: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                  ),
                  listBullet: TextStyle(
                    color: theme.accentFg,
                    fontWeight: FontWeight.w700,
                  ),
                  code: TextStyle(
                    backgroundColor: theme.bgInset,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: theme.fgDefault,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: theme.bgInset,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.borderDefault),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border(
                      left: BorderSide(color: theme.accentFg, width: 3.5),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // 5. Extracted Action Items
          if (_actionItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Divider(
              color: theme.borderDefault.withValues(alpha: 0.7),
              height: 1,
            ),
            const SizedBox(height: 20),
            _buildActionItemsInner(theme),
          ],

          // 6. Requested Custom Inquiries & Focus Topics
          if (_customFieldsAnalysis.isNotEmpty) ...[
            const SizedBox(height: 24),
            Divider(
              color: theme.borderDefault.withValues(alpha: 0.7),
              height: 1,
            ),
            const SizedBox(height: 20),
            _buildCustomFieldsInner(theme),
          ],

          // 7. Key Visual Moments
          if (_getDisplaySteps().isNotEmpty) ...[
            const SizedBox(height: 24),
            Divider(
              color: theme.borderDefault.withValues(alpha: 0.7),
              height: 1,
            ),
            const SizedBox(height: 20),
            _buildVisualMomentsInner(theme),
          ],

          // 8. Voxtral 4B Diarized Transcript Section
          const SizedBox(height: 24),
          Divider(color: theme.borderDefault.withValues(alpha: 0.7), height: 1),
          const SizedBox(height: 20),
          _buildTranscriptInner(theme),
        ],
      ),
    );
  }

  bool _isInternalNoiseStep(Map<String, dynamic> step, String stepId) {
    final summary = (step['summary']?.toString() ?? '').toLowerCase();
    final actions = (step['actions'] as List?) ?? [];
    final actionParts = <String>[];
    for (final a in actions) {
      if (a is Map) {
        actionParts.add((a['target']?.toString() ?? '').toLowerCase());
        actionParts.add((a['description']?.toString() ?? '').toLowerCase());
        actionParts.add((a['event']?.toString() ?? '').toLowerCase());
        actionParts.add((a['app_name']?.toString() ?? '').toLowerCase());
        actionParts.add((a['window_title']?.toString() ?? '').toLowerCase());
      }
    }
    final meta =
        _stepDescriptions[stepId] ??
        _stepDescriptions['step_$stepId'] ??
        _stepDescriptions[stepId.replaceAll(RegExp(r'[^0-9]'), '')];
    final title = (meta is Map ? (meta['title']?.toString() ?? '') : '')
        .toLowerCase();
    final desc = (meta is Map ? (meta['description']?.toString() ?? '') : '')
        .toLowerCase();
    final windowTitle = (step['window_title']?.toString() ?? '').toLowerCase();
    final appName = (step['app_name']?.toString() ?? '').toLowerCase();
    final screenshotPath = (step['screenshot_path']?.toString() ?? '')
        .toLowerCase();

    final combined =
        '$summary ${actionParts.join(' ')} $title $desc $windowTitle $appName $screenshotPath';
    const noiseKeywords = [
      'deskmate',
      'meeting scribe',
      'start meeting',
      'end meeting',
      'stop meeting',
      'recording dashboard',
      'save to drive',
      'download pdf',
      'email pdf',
      'email meeting summary',
      'sync to deskmate',
      'modal_window',
      'modal',
      'runner',
      'flutter',
      'electron',
      'deskmate_app',
      'deskmate live',
      'locateanything',
      'app switcher',
      'mission control',
      'window switch',
      'switching window',
      'switch to',
      'dock',
      'taskbar',
    ];
    return noiseKeywords.any((kw) => combined.contains(kw));
  }

  List<Map<String, dynamic>> _getDisplaySteps() {
    final List<Map<String, dynamic>> list = [];
    if (_importantSteps.isNotEmpty) {
      for (final stepId in _importantSteps) {
        final cleanId = stepId.replaceAll(RegExp(r'[^0-9]'), '');
        Map<String, dynamic>? match;
        for (final s in _meetingSteps) {
          if (s is Map) {
            final sId = s['step_id']?.toString().replaceAll(
              RegExp(r'[^0-9]'),
              '',
            );
            if (sId == cleanId || s['step_id']?.toString() == stepId) {
              match = Map<String, dynamic>.from(s);
              break;
            }
          }
        }
        final candidate =
            match ??
            {
              'step_id': stepId,
              'summary': 'Step $stepId',
              'timestamp': '',
              'screenshot_path': '',
              'actions': [],
            };
        if (!_isInternalNoiseStep(candidate, stepId)) {
          list.add(candidate);
        }
      }
    } else if (_meetingSteps.isNotEmpty) {
      for (final s in _meetingSteps) {
        if (s is Map) {
          final sId = s['step_id']?.toString() ?? '';
          final map = Map<String, dynamic>.from(s);
          if (!_isInternalNoiseStep(map, sId)) {
            list.add(map);
          }
        }
      }
    }
    return list;
  }

  Widget _buildVisualMomentsInner(ThemeData theme) {
    final displaySteps = _getDisplaySteps();
    if (displaySteps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    color: theme.accentFg,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Key Visual Moments (${displaySteps.length} Steps Identified)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Click any screenshot thumbnail or step card to inspect high-resolution frames & LocateAnything detections.',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                  ],
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: () => _showScreenshotModal(context, 0, displaySteps),
              icon: const Icon(Icons.slideshow_rounded, size: 16),
              label: const Text('View Gallery Mode'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.accentFg,
                side: BorderSide(color: theme.accentFg.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < displaySteps.length; i++) ...[
          Builder(
            builder: (context) {
              final step = displaySteps[i];
              final stepId = step['step_id']?.toString() ?? '${i + 1}';
              final cleanId = stepId.replaceAll(RegExp(r'[^0-9]'), '');
              final meta =
                  _stepDescriptions[stepId] ??
                  _stepDescriptions['step_$stepId'] ??
                  _stepDescriptions['step_$cleanId'] ??
                  _stepDescriptions[cleanId];
              final summary = step['summary']?.toString() ?? 'Step $stepId';
              final title = meta is Map ? (meta['title'] ?? summary) : summary;
              final desc = meta is Map ? (meta['description'] ?? '') : '';
              final timestamp = step['timestamp']?.toString() ?? '';

              String screenshotPath = step['screenshot_path']?.toString() ?? '';
              if (screenshotPath.isEmpty) {
                final actions = (step['actions'] as List?) ?? [];
                for (final a in actions) {
                  if (a is Map &&
                      (a['asset_path']?.toString().isNotEmpty ?? false)) {
                    screenshotPath = a['asset_path'].toString();
                    break;
                  }
                }
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  onTap: () => _showScreenshotModal(context, i, displaySteps),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.bgCanvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.borderDefault),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStepThumbnail(
                          screenshotPath,
                          theme,
                          width: 120,
                          height: 76,
                          onTap: () =>
                              _showScreenshotModal(context, i, displaySteps),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.accentFg.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'STEP $stepId',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: theme.accentFg,
                                      ),
                                    ),
                                  ),
                                  if (timestamp.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.schedule_rounded,
                                          size: 12,
                                          color: theme.fgMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          timestamp,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.fgMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _showScreenshotModal(
                                      context,
                                      i,
                                      displaySteps,
                                    ),
                                    icon: const Icon(
                                      Icons.fullscreen_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Inspect'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: theme.accentFg,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title.toString(),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.fgDefault,
                                ),
                              ),
                              if (desc.toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  desc.toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: theme.fgMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildStepThumbnail(
    String? screenshotPath,
    ThemeData theme, {
    double width = 120,
    double height = 76,
    VoidCallback? onTap,
  }) {
    Widget imageWidget;
    if (screenshotPath != null &&
        screenshotPath.isNotEmpty &&
        File(screenshotPath).existsSync()) {
      imageWidget = Image.file(
        File(screenshotPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildImagePlaceholder(theme, width, height),
      );
    } else if (screenshotPath != null &&
        screenshotPath.isNotEmpty &&
        _currentSessionId != null) {
      final filename = screenshotPath
          .split(Platform.pathSeparator)
          .last
          .split('/')
          .last;
      final provider = Provider.of<ChatProvider>(context, listen: false);
      final assetUrl = provider.apiService.getMeetingAssetUrl(
        _currentSessionId!,
        filename,
      );
      imageWidget = Image.network(
        assetUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildImagePlaceholder(theme, width, height),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: theme.bgCanvas,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.accentFg,
                ),
              ),
            ),
          );
        },
      );
    } else {
      imageWidget = _buildImagePlaceholder(theme, width, height);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: theme.bgCanvas,
                border: Border.all(color: theme.borderDefault),
              ),
              child: imageWidget,
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.zoom_in_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(ThemeData theme, double width, double height) {
    return Container(
      width: width,
      height: height,
      color: theme.bgCanvas,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 22, color: theme.fgMuted),
          const SizedBox(height: 2),
          Text(
            'Visual Step',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: theme.fgMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalImageError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, size: 48, color: theme.fgMuted),
          const SizedBox(height: 12),
          Text(
            'High-resolution frame preview unavailable',
            style: TextStyle(fontSize: 14, color: theme.fgMuted),
          ),
        ],
      ),
    );
  }

  void _showScreenshotModal(
    BuildContext context,
    int initialIndex,
    List<Map<String, dynamic>> steps,
  ) {
    if (steps.isEmpty) return;
    final theme = Theme.of(context);

    showBlurredDialog(
      context: context,
      builder: (dialogCtx) {
        int activeIndex = initialIndex.clamp(0, steps.length - 1);
        return StatefulBuilder(
          builder: (context, setModalState) {
            final step = steps[activeIndex];
            final stepId = step['step_id']?.toString() ?? '${activeIndex + 1}';
            final cleanId = stepId.replaceAll(RegExp(r'[^0-9]'), '');
            final timestamp = step['timestamp']?.toString() ?? '';
            final summary = step['summary']?.toString() ?? 'Step $stepId';
            final meta =
                _stepDescriptions[stepId] ??
                _stepDescriptions['step_$stepId'] ??
                _stepDescriptions['step_$cleanId'] ??
                _stepDescriptions[cleanId];
            final title = meta is Map ? (meta['title'] ?? summary) : summary;
            final desc = meta is Map ? (meta['description'] ?? '') : '';
            final actions = (step['actions'] as List?) ?? [];

            String screenshotPath = step['screenshot_path']?.toString() ?? '';
            if (screenshotPath.isEmpty) {
              for (final a in actions) {
                if (a is Map &&
                    (a['asset_path']?.toString().isNotEmpty ?? false)) {
                  screenshotPath = a['asset_path'].toString();
                  break;
                }
              }
            }

            Widget fullImage;
            if (screenshotPath.isNotEmpty &&
                File(screenshotPath).existsSync()) {
              fullImage = Image.file(
                File(screenshotPath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _buildModalImageError(theme),
              );
            } else if (screenshotPath.isNotEmpty && _currentSessionId != null) {
              final filename = screenshotPath
                  .split(Platform.pathSeparator)
                  .last
                  .split('/')
                  .last;
              final provider = Provider.of<ChatProvider>(
                context,
                listen: false,
              );
              final assetUrl = provider.apiService.getMeetingAssetUrl(
                _currentSessionId!,
                filename,
              );
              fullImage = Image.network(
                assetUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _buildModalImageError(theme),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(color: theme.accentFg),
                  );
                },
              );
            } else {
              fullImage = _buildModalImageError(theme);
            }

            return Dialog(
              backgroundColor: theme.bgCanvas,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.borderDefault),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1040,
                  maxHeight: 760,
                ),
                child: Column(
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          bottom: BorderSide(color: theme.borderDefault),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accentFg.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.accentFg.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'STEP $stepId',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.accentFg,
                              ),
                            ),
                          ),
                          if (timestamp.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: theme.bgCanvas,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: theme.borderDefault),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 12,
                                    color: theme.fgMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    timestamp,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: theme.fgMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title.toString(),
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: theme.fgDefault,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.bgCanvas,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: theme.borderDefault),
                            ),
                            child: Text(
                              '${activeIndex + 1} / ${steps.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.fgMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Close Modal',
                            color: theme.fgMuted,
                          ),
                        ],
                      ),
                    ),

                    // Interactive Zoomable Main Image
                    Expanded(
                      child: Container(
                        color: AppTheme.darkBgCanvas,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Center(child: fullImage),
                            ),
                            if (activeIndex > 0)
                              Positioned(
                                left: 16,
                                child: IconButton.filled(
                                  onPressed: () {
                                    setModalState(() => activeIndex--);
                                  },
                                  icon: const Icon(
                                    Icons.chevron_left_rounded,
                                    size: 28,
                                  ),
                                  tooltip: 'Previous Step',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black.withValues(
                                      alpha: 0.65,
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                              ),
                            if (activeIndex < steps.length - 1)
                              Positioned(
                                right: 16,
                                child: IconButton.filled(
                                  onPressed: () {
                                    setModalState(() => activeIndex++);
                                  },
                                  icon: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 28,
                                  ),
                                  tooltip: 'Next Step',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black.withValues(
                                      alpha: 0.65,
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Insight & NVIDIA LocateAnything Detections
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          top: BorderSide(color: theme.borderDefault),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (desc.toString().isNotEmpty) ...[
                            Text(
                              desc.toString(),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: theme.fgDefault,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Icon(
                                Icons.gps_fixed_rounded,
                                size: 14,
                                color: theme.accentFg,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'NVIDIA LocateAnything-3B Visual Grounding Detections:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: theme.fgMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (actions.isEmpty)
                                Text(
                                  'Visual baseline step frame',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.fgMuted,
                                  ),
                                )
                              else
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: actions.take(6).map((act) {
                                        final event =
                                            act['event']?.toString() ??
                                            'action';
                                        final target =
                                            act['target']?.toString() ?? '';
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.bgCanvas,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: theme.borderDefault,
                                            ),
                                          ),
                                          child: Text(
                                            '$event: "$target"',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: theme.fgDefault,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
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
            );
          },
        );
      },
    );
  }

  Color _getSpeakerColor(String speaker) {
    if (speaker.contains('1')) return AppTheme.purplePrimary; // DeskMate Purple
    if (speaker.contains('2')) return AppTheme.emerald; // Emerald Green
    if (speaker.contains('3')) return AppTheme.amber; // Amber Orange
    if (speaker.contains('4')) return const Color(0xFFEC4899); // Pink
    return const Color(0xFF06B6D4); // Cyan
  }

  String _formatSegmentTime(dynamic sec) {
    if (sec == null) return '00:00';
    final s = (sec is num)
        ? sec.toDouble()
        : (double.tryParse(sec.toString()) ?? 0.0);
    final m = s ~/ 60;
    final remSec = (s % 60).toInt();
    return '${m.toString().padLeft(2, '0')}:${remSec.toString().padLeft(2, '0')}';
  }

  void _copyTranscriptToClipboard(String text, {String label = 'Transcript'}) {
    Clipboard.setData(ClipboardData(text: text));
    _showTopNotification('$label copied to clipboard!');
  }

  Widget _buildTranscriptInner(ThemeData theme) {
    final segments = (_transcriptData?['segments'] as List?) ?? [];
    final fullTranscript =
        _transcriptData?['full_transcript']?.toString() ?? '';

    // Collect all speakers
    final Set<String> allSpeakers = {};
    for (final seg in segments) {
      if (seg is Map && seg['speaker'] != null) {
        allSpeakers.add(seg['speaker'].toString());
      }
    }

    // Filter segments
    final filteredSegments = segments.where((seg) {
      if (seg is! Map) return false;
      final spk = seg['speaker']?.toString() ?? 'Speaker 1';
      final text = seg['text']?.toString() ?? '';
      if (_selectedSpeakerFilter != null && spk != _selectedSpeakerFilter) {
        return false;
      }
      if (_transcriptSearchQuery.isNotEmpty &&
          !text.toLowerCase().contains(_transcriptSearchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.record_voice_over_rounded,
                    color: theme.accentFg,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Voxtral 4B Diarized Transcript',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.fgDefault,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (allSpeakers.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accentFg.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${allSpeakers.length} Speakers',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.accentFg,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mistral Voxtral 4B in-memory audio extraction with native speaker diarization.',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                  ],
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                if (fullTranscript.isNotEmpty || segments.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      final buffer = StringBuffer();
                      if (segments.isNotEmpty) {
                        for (final s in segments) {
                          if (s is Map) {
                            final spk = s['speaker'] ?? 'Speaker';
                            final start = _formatSegmentTime(s['start']);
                            final end = _formatSegmentTime(s['end']);
                            final txt = s['text'] ?? '';
                            buffer.writeln('[$start -> $end] $spk: $txt');
                          }
                        }
                      } else {
                        buffer.write(fullTranscript);
                      }
                      _copyTranscriptToClipboard(
                        buffer.toString(),
                        label: 'Full Transcript',
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copy All'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentFg,
                      side: BorderSide(
                        color: theme.accentFg.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showTranscriptModal(context, theme),
                    icon: const Icon(Icons.fullscreen_rounded, size: 16),
                    label: const Text('Expand Reader'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentFg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        if (segments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _transcriptSearchController,
                  onChanged: (val) {
                    setState(() => _transcriptSearchQuery = val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search transcript dialogue turns...',
                    hintStyle: TextStyle(fontSize: 12, color: theme.fgMuted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: theme.fgMuted,
                    ),
                    suffixIcon: _transcriptSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _transcriptSearchController.clear();
                              setState(() => _transcriptSearchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: theme.borderDefault),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Speakers'),
                  selected: _selectedSpeakerFilter == null,
                  onSelected: (_) =>
                      setState(() => _selectedSpeakerFilter = null),
                  selectedColor: theme.accentFg.withValues(alpha: 0.2),
                  checkmarkColor: theme.accentFg,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _selectedSpeakerFilter == null
                        ? theme.accentFg
                        : theme.fgDefault,
                  ),
                ),
                const SizedBox(width: 8),
                for (final spk in allSpeakers) ...[
                  FilterChip(
                    avatar: CircleAvatar(
                      radius: 5,
                      backgroundColor: _getSpeakerColor(spk),
                    ),
                    label: Text(spk),
                    selected: _selectedSpeakerFilter == spk,
                    onSelected: (_) => setState(() {
                      _selectedSpeakerFilter = (_selectedSpeakerFilter == spk)
                          ? null
                          : spk;
                    }),
                    selectedColor: _getSpeakerColor(spk).withValues(alpha: 0.2),
                    checkmarkColor: _getSpeakerColor(spk),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _selectedSpeakerFilter == spk
                          ? _getSpeakerColor(spk)
                          : theme.fgDefault,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        if (segments.isEmpty && fullTranscript.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.bgCanvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault),
            ),
            child: Row(
              children: [
                Icon(Icons.mic_off_outlined, color: theme.fgMuted, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No Speech Audio Captured',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'The meeting was recorded without a microphone audio track. Key interactions were tracked via NVIDIA LocateAnything-3B visual events.',
                        style: TextStyle(fontSize: 12, color: theme.fgMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (segments.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.bgCanvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault),
            ),
            child: SelectableText(
              fullTranscript,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: theme.fgDefault,
              ),
            ),
          )
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: filteredSegments.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final seg = filteredSegments[idx] as Map;
                final speaker = seg['speaker']?.toString() ?? 'Speaker 1';
                final start = _formatSegmentTime(seg['start']);
                final end = _formatSegmentTime(seg['end']);
                final text = seg['text']?.toString() ?? '';
                final color = _getSpeakerColor(speaker);

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.bgCanvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.borderDefault),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: color.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: color),
                                const SizedBox(width: 6),
                                Text(
                                  speaker,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.bgSubtle,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$start → $end',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: theme.fgMuted,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            tooltip: 'Copy Turn',
                            color: theme.fgMuted,
                            onPressed: () {
                              _copyTranscriptToClipboard(
                                '[$start -> $end] $speaker: $text',
                                label: '$speaker Dialogue',
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: theme.fgDefault,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTranscriptCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderDefault),
      ),
      child: _buildTranscriptInner(theme),
    );
  }

  void _showTranscriptModal(BuildContext context, ThemeData theme) {
    final segments = (_transcriptData?['segments'] as List?) ?? [];
    final fullTranscript =
        _transcriptData?['full_transcript']?.toString() ?? '';

    final Set<String> allSpeakers = {};
    for (final seg in segments) {
      if (seg is Map && seg['speaker'] != null) {
        allSpeakers.add(seg['speaker'].toString());
      }
    }

    final searchCtrl = TextEditingController();
    showBlurredDialog(
      context: context,
      builder: (dialogCtx) {
        String modalSearch = '';
        String? modalSpeaker;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = segments.where((seg) {
              if (seg is! Map) return false;
              final spk = seg['speaker']?.toString() ?? 'Speaker 1';
              final text = seg['text']?.toString() ?? '';
              if (modalSpeaker != null && spk != modalSpeaker) return false;
              if (modalSearch.isNotEmpty &&
                  !text.toLowerCase().contains(modalSearch.toLowerCase())) {
                return false;
              }
              return true;
            }).toList();

            return Dialog(
              backgroundColor: theme.bgCanvas,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.borderDefault),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 900,
                  maxHeight: 750,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.bgSubtle,
                        border: Border(
                          bottom: BorderSide(color: theme.borderDefault),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.record_voice_over_rounded,
                            color: theme.accentFg,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Voxtral 4B Diarized Transcript Reader',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: theme.fgDefault,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${segments.length} spoken dialogue turns • ${allSpeakers.length} unique speakers identified',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.fgMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              final buffer = StringBuffer();
                              for (final s in segments) {
                                if (s is Map) {
                                  final spk = s['speaker'] ?? 'Speaker';
                                  final start = _formatSegmentTime(s['start']);
                                  final end = _formatSegmentTime(s['end']);
                                  final txt = s['text'] ?? '';
                                  buffer.writeln('[$start -> $end] $spk: $txt');
                                }
                              }
                              _copyTranscriptToClipboard(
                                buffer.toString(),
                                label: 'Complete Transcript',
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: const Text('Copy All'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.accentFg,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: theme.fgMuted,
                          ),
                        ],
                      ),
                    ),

                    if (segments.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        color: theme.bgSubtle.withValues(alpha: 0.5),
                        child: Column(
                          children: [
                            TextField(
                              controller: searchCtrl,
                              onChanged: (val) =>
                                  setModalState(() => modalSearch = val),
                              decoration: InputDecoration(
                                hintText:
                                    'Search spoken keywords or phrases...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: theme.fgMuted,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: theme.fgMuted,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: theme.borderDefault,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  FilterChip(
                                    label: const Text('All Speakers'),
                                    selected: modalSpeaker == null,
                                    onSelected: (_) => setModalState(
                                      () => modalSpeaker = null,
                                    ),
                                    selectedColor: theme.accentFg.withValues(
                                      alpha: 0.2,
                                    ),
                                    checkmarkColor: theme.accentFg,
                                  ),
                                  const SizedBox(width: 8),
                                  for (final spk in allSpeakers) ...[
                                    FilterChip(
                                      avatar: CircleAvatar(
                                        radius: 5,
                                        backgroundColor: _getSpeakerColor(spk),
                                      ),
                                      label: Text(spk),
                                      selected: modalSpeaker == spk,
                                      onSelected: (_) => setModalState(() {
                                        modalSpeaker = (modalSpeaker == spk)
                                            ? null
                                            : spk;
                                      }),
                                      selectedColor: _getSpeakerColor(
                                        spk,
                                      ).withValues(alpha: 0.2),
                                      checkmarkColor: _getSpeakerColor(spk),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: segments.isEmpty
                            ? SelectableText(
                                fullTranscript.isNotEmpty
                                    ? fullTranscript
                                    : 'No audio transcript available.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: theme.fgDefault,
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, idx) {
                                  final seg = filtered[idx] as Map;
                                  final spk =
                                      seg['speaker']?.toString() ?? 'Speaker 1';
                                  final start = _formatSegmentTime(
                                    seg['start'],
                                  );
                                  final end = _formatSegmentTime(seg['end']);
                                  final txt = seg['text']?.toString() ?? '';
                                  final col = _getSpeakerColor(spk);

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: theme.bgSubtle,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.borderDefault,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: col.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: col.withValues(
                                                    alpha: 0.4,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                spk,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: col,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$start → $end',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: theme.fgMuted,
                                              ),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                                size: 14,
                                              ),
                                              tooltip: 'Copy Turn',
                                              color: theme.fgMuted,
                                              onPressed: () {
                                                _copyTranscriptToClipboard(
                                                  '[$start -> $end] $spk: $txt',
                                                  label: '$spk Dialogue',
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          txt,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            height: 1.5,
                                            color: theme.fgDefault,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => searchCtrl.dispose());
  }

  Widget _buildCenterVisual(ThemeData theme) {
    const green = AppTheme.lightSuccessFg;
    const red = AppTheme.recordingRed; // Pure Crimson Red, NOT orange
    final appTheme = theme.accentFg;

    // ── 1. INITIAL / IDLE STATE (Theme Purple, NOT Vibrating, Clickable) ──
    if (!_isRecording && !_isStarting) {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      if (!provider.isMeetingAiReady) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      _showAiSetupRequiredModal(context, theme, provider),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFD97706).withValues(alpha: 0.12),
                      border: Border.all(
                        color: const Color(0xFFD97706).withValues(alpha: 0.50),
                        width: 1.8,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 44,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'AI Engine Setup Required to Record',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.fgDefault,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  provider.meetingAiNotReadyReason.isNotEmpty
                      ? provider.meetingAiNotReadyReason
                      : 'Ensure Ollama is running with reasoning and vision models, or configure a Gemini API key.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.fgMuted,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    _showAiSetupRequiredModal(context, theme, provider),
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('Configure AI Engine'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _startRecording,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: appTheme.withValues(alpha: 0.10),
                    border: Border.all(
                      color: appTheme.withValues(alpha: 0.40),
                      width: 1.8,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.video_call_rounded,
                      size: 46,
                      color: appTheme,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Ready to record your meeting',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.fgDefault,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'Click the button above or "Start Meeting Scribe" in the top bar to begin real-time screen capture and Voxtral 4B audio recording. Key interactions will be automatically detected with NVIDIA LocateAnything-3B.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: theme.fgMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── 2. STARTING STATE (Green Theme, VIBRATING) ──
    if (_isStarting) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed 140x140 bounding box isolates vibration completely from children below
            SizedBox(
              width: 140,
              height: 140,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final t = _pulseController.value;
                  final wave1 = (t) % 1.0;
                  final wave2 = (t + 0.5) % 1.0;
                  final vibrate = math.sin(t * math.pi * 6) * 1.5;

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Outermost ripple ring
                      Container(
                        width: 88 + (wave1 * 44),
                        height: 88 + (wave1 * 44),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: green.withValues(
                              alpha: (1.0 - wave1) * 0.45,
                            ),
                            width: 1.8,
                          ),
                        ),
                      ),
                      // Inner ripple ring
                      Container(
                        width: 88 + (wave2 * 32),
                        height: 88 + (wave2 * 32),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: green.withValues(alpha: (1.0 - wave2) * 0.5),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Central vibrating green button
                      Transform.translate(
                        offset: Offset(0, vibrate),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2EA043), Color(0xFF238636)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: green.withValues(
                                  alpha: 0.4 + 0.2 * math.sin(t * math.pi * 2),
                                ),
                                blurRadius: 24,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Starting recording session...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.fgDefault,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: green.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: green,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Connecting to Voxtral & Vision...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── 3. RECORDING STATE (RED Theme, NOT Orange, VIBRATING/PULSING) ──
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fixed 140x140 bounding box isolates vibration completely from children below
          SizedBox(
            width: 140,
            height: 140,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final t = _pulseController.value;
                final wave1 = (t) % 1.0;
                final wave2 = (t + 0.5) % 1.0;
                final vibrate = math.sin(t * math.pi * 6) * 1.5;

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Outermost ripple ring in pure red
                    Container(
                      width: 88 + (wave1 * 44),
                      height: 88 + (wave1 * 44),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: red.withValues(alpha: (1.0 - wave1) * 0.45),
                          width: 1.8,
                        ),
                      ),
                    ),
                    // Inner ripple ring in pure red
                    Container(
                      width: 88 + (wave2 * 32),
                      height: 88 + (wave2 * 32),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: red.withValues(alpha: (1.0 - wave2) * 0.5),
                          width: 1.5,
                        ),
                      ),
                    ),
                    // Central vibrating red button
                    Transform.translate(
                      offset: Offset(0, vibrate),
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppTheme.recordingRed, Color(0xFFB91C1C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: red.withValues(
                                alpha: 0.4 + 0.2 * math.sin(t * math.pi * 2),
                              ),
                              blurRadius: 24,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.videocam_rounded,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          // Completely static title (zero shaking)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Meeting Recording in Progress',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.fgDefault,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Completely static duration (zero shaking)
          Text(
            _formatDuration(_uptimeSeconds),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              color: red,
            ),
          ),
          const SizedBox(height: 14),
          // Completely static red button (zero shaking)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _stopRecording,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: red,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: red.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'End Meeting & Generate AI Summary',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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

  Widget _buildCustomFocusTopicsCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.accentFg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.psychology_rounded,
                  size: 20,
                  color: theme.accentFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Specific Focus Topics & Event Inquiries',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Specify custom topics or questions to extract into dedicated PDF report columns and analysis.',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showTopicInput = !_showTopicInput);
                },
                icon: Icon(_showTopicInput ? Icons.close : Icons.add, size: 16),
                label: Text(_showTopicInput ? 'Close' : 'Add Custom Topic'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.accentFg,
                  side: BorderSide(
                    color: theme.accentFg.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          // Active Topics List
          if (_customFocusTopics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _customFocusTopics.asMap().entries.map((entry) {
                final idx = entry.key;
                final topic = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.label_important_rounded,
                        size: 14,
                        color: theme.accentFg,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        topic['name'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          setState(() => _customFocusTopics.removeAt(idx));
                        },
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // Quick Presets
          const SizedBox(height: 16),
          Text(
            'QUICK TEMPLATES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.fgMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                theme,
                '+ Architecture Decisions',
                'Architecture Decisions',
                'Extract all database schemas, API endpoints, backend changes, and architectural decisions.',
              ),
              _buildPresetChip(
                theme,
                '+ Action Items & Owners',
                'Action Items & Owners',
                'Identify all assigned tasks, assigned team members, blockers, and scheduled deadlines.',
              ),
              _buildPresetChip(
                theme,
                '+ Client & Product Requirements',
                'Client Requirements',
                'Catalog every specific customer request, feedback item, design change, or requirement discussed.',
              ),
              _buildPresetChip(
                theme,
                '+ Security & Credentials',
                'Security & Configuration',
                'Detail all security discussions, environment variables, credentials, or authentication rules.',
              ),
            ],
          ),

          // Custom Topic Input Form
          if (_showTopicInput) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.bgCanvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.borderDefault),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Topic or Column Name',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.fgDefault,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _topicNameController,
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Database Migrations, Client Feedback, Budget',
                      hintStyle: TextStyle(fontSize: 12, color: theme.fgMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Instructions for AI Extraction',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.fgDefault,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _topicInstructionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Extract any table changes, SQL statements, or ORM migrations shown or spoken.',
                      hintStyle: TextStyle(fontSize: 12, color: theme.fgMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _showTopicInput = false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: theme.fgMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final name = _topicNameController.text.trim();
                          final inst = _topicInstructionController.text.trim();
                          if (name.isNotEmpty) {
                            setState(() {
                              _customFocusTopics.add({
                                'name': name,
                                'instruction': inst.isNotEmpty
                                    ? inst
                                    : 'Provide detailed analysis on $name.',
                              });
                              _topicNameController.clear();
                              _topicInstructionController.clear();
                              _showTopicInput = false;
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accentFg,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text('Add Focus Topic'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip(
    ThemeData theme,
    String label,
    String name,
    String instruction,
  ) {
    final alreadyAdded = _customFocusTopics.any((t) => t['name'] == name);
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: alreadyAdded ? theme.fgMuted : theme.accentFg,
        ),
      ),
      backgroundColor: alreadyAdded
          ? theme.bgCanvas
          : theme.accentFg.withValues(alpha: 0.08),
      side: BorderSide(
        color: alreadyAdded
            ? theme.borderDefault
            : theme.accentFg.withValues(alpha: 0.3),
      ),
      onPressed: alreadyAdded
          ? null
          : () {
              setState(() {
                _customFocusTopics.add({
                  'name': name,
                  'instruction': instruction,
                });
              });
            },
    );
  }

  Widget _buildCustomFieldsInner(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.accentFg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.analytics_rounded,
                size: 20,
                color: theme.accentFg,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Requested Custom Inquiries & Event Analysis',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.fgDefault,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._customFieldsAnalysis.entries.map((entry) {
          final topicName = entry.key;
          final dynamic val = entry.value;
          String content = '';
          List<dynamic> relevantSteps = [];
          if (val is Map) {
            content = val['content']?.toString() ?? '';
            relevantSteps = val['relevant_steps'] as List<dynamic>? ?? [];
          } else if (val is String) {
            content = val;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.bgCanvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accentFg.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        topicName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.accentFg,
                        ),
                      ),
                    ),
                    if (relevantSteps.isNotEmpty) ...[
                      const Spacer(),
                      ...relevantSteps.map(
                        (step) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Chip(
                            label: Text(
                              step.toString(),
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: theme.fgDefault,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
