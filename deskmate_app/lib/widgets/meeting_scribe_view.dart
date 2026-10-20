import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../utils/open_external.dart';

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

  // Summary result state
  String? _executiveSummary;
  List<String> _importantSteps = [];
  Map<String, dynamic> _stepDescriptions = {};
  List<String> _actionItems = [];
  String? _pdfUrl;
  Map<String, dynamic> _customFieldsAnalysis = {};
  Map<String, dynamic>? _transcriptData;
  List<dynamic> _meetingSteps = [];

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
    _pulseController.dispose();
    _statusTimer?.cancel();
    _topicNameController.dispose();
    _topicInstructionController.dispose();
    _transcriptSearchController.dispose();
    super.dispose();
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
        }
      }
    } catch (_) {}
  }

  void _startPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      try {
        final status = await provider.apiService.getMeetingStatus();
        if (mounted) {
          setState(() {
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
      } catch (_) {}
    });
  }

  Future<void> _startRecording() async {
    if (_isStarting || _isRecording) return;
    setState(() => _isStarting = true);
    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final startFuture = provider.apiService.startMeeting(
        monitor: 1,
        fps: 2.0,
      );
      final delayFuture = Future.delayed(const Duration(milliseconds: 1200));
      final results = await Future.wait([startFuture, delayFuture]);
      final res = results[0] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _isRecording = true;
          _isStarting = false;
          _isMicMuted = false;
          _currentSessionId = res['session_id'];
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
        });
        _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start meeting: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleMicMute() async {
    if (_isTogglingMic || !_isRecording) return;
    setState(() => _isTogglingMic = true);
    final targetMuted = !_isMicMuted;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    try {
      await provider.apiService.setMeetingMicMuted(targetMuted);
      if (mounted) {
        setState(() {
          _isMicMuted = targetMuted;
          _isTogglingMic = false;
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  targetMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    targetMuted
                        ? 'Mic Muted — Ambient room noise blocked (Earphones / System audio only)'
                        : 'Mic Active — Mixed Earphones/System Audio + User Speech',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: targetMuted
                ? const Color(0xFFD97706)
                : AppTheme.emerald,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTogglingMic = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update mic mute state: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _statusTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isSummarizing = true;
    });

    try {
      await provider.apiService.stopMeeting();
      final summaryRes = await provider.apiService.summarizeMeeting(
        sessionId: _currentSessionId,
        customFields: _customFocusTopics.isNotEmpty ? _customFocusTopics : null,
      );

      if (mounted) {
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

        // Extract action items
        final extractedActions = <String>[];
        for (final line in summaryText.split('\n')) {
          if (line.contains('[ACTION ITEM]') ||
              line.contains('[HIGH PRIORITY]')) {
            extractedActions.add(line.replaceAll('**', '').trim());
          }
        }

        setState(() {
          _isSummarizing = false;
          _executiveSummary = summaryText;
          _importantSteps = important;
          _stepDescriptions = desc;
          _actionItems = extractedActions;
          _customFieldsAnalysis = customAnalysis;
          _transcriptData = transcript;
          _meetingSteps = steps;
          if (_currentSessionId != null) {
            _pdfUrl = provider.apiService.getMeetingPdfUrl(_currentSessionId!);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSummarizing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Summarization error: $e')));
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully synced ${res['tasks_created']} action items into DeskMate Tasks!',
            ),
            backgroundColor: AppTheme.emerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncingTasks = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Task sync failed: $e')));
      }
    }
  }

  void _openPdf() {
    if (_pdfUrl == null) return;
    openExternal(_pdfUrl!);
  }

  Future<void> _exportToGoogleDrive() async {
    if (_currentSessionId == null) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    setState(() => _isExportingDrive = true);
    try {
      final res = await provider.apiService.exportMeetingToDrive(
        sessionId: _currentSessionId!,
        folderName: 'DeskMate Meetings',
      );
      if (mounted) {
        setState(() => _isExportingDrive = false);
        final link = res['view_link'] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Uploaded to Google Drive in "DeskMate Meetings"! ${link.isNotEmpty ? "(Link ready)" : ""}',
            ),
            backgroundColor: AppTheme.emerald,
            action: link.isNotEmpty
                ? SnackBarAction(
                    label: 'Open Drive',
                    textColor: Colors.white,
                    onPressed: () {
                      openExternal(link);
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExportingDrive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Drive export failed: $e')),
        );
      }
    }
  }

  Future<void> _promptSendEmail() async {
    if (_currentSessionId == null) return;
    final emailController = TextEditingController();

    final send =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.email_outlined,
                  color: AppTheme.purplePrimary,
                  size: 22,
                ),
                SizedBox(width: 8),
                Text('Email Meeting Summary & PDF'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter recipient email. DeskMate will send the executive summary with the generated PDF attached via your connected Gmail.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Recipient Email',
                    hintText: 'colleague@example.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.purplePrimary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Send Email'),
              ),
            ],
          ),
        ).then((value) {
          emailController.dispose();
          return value;
        });

    if (send == true && emailController.text.trim().isNotEmpty) {
      if (!mounted) return;
      final toEmail = emailController.text.trim();
      final provider = Provider.of<ChatProvider>(context, listen: false);
      setState(() => _isSendingEmail = true);
      try {
        await provider.apiService.sendMeetingEmail(
          sessionId: _currentSessionId!,
          toEmail: toEmail,
        );
        if (mounted) {
          setState(() => _isSendingEmail = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Meeting report and PDF emailed to $toEmail!'),
              backgroundColor: AppTheme.emerald,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSendingEmail = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to send email: $e')));
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

                  // --- SUMMARIZING LOADER ---
                  if (_isSummarizing) _buildSummarizingIndicator(theme),

                  // --- EXECUTIVE SUMMARY SECTION ---
                  if (_executiveSummary != null) ...[
                    _buildSummaryCard(theme),
                    const SizedBox(height: 20),
                  ],

                  // --- ACTION ITEMS CHECKLIST ---
                  if (_actionItems.isNotEmpty) ...[
                    _buildActionItemsCard(theme),
                    const SizedBox(height: 20),
                  ],

                  // --- REQUESTED CUSTOM INQUIRIES & EVENT ANALYSIS ---
                  if (_customFieldsAnalysis.isNotEmpty) ...[
                    _buildCustomFieldsAnalysisCard(theme),
                    const SizedBox(height: 20),
                  ],

                  // --- KEY VISUAL MOMENTS ---
                  if (_importantSteps.isNotEmpty ||
                      _meetingSteps.isNotEmpty) ...[
                    _buildVisualMomentsCard(theme),
                    const SizedBox(height: 20),
                  ],

                  // --- VOXTRAL 4B DIARIZED TRANSCRIPT ---
                  if (_transcriptData != null ||
                      (_executiveSummary != null &&
                          _executiveSummary!.isNotEmpty)) ...[
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
                        color: _isRecording
                            ? AppTheme.recordingRed.withValues(alpha: 0.12)
                            : AppTheme.lightSuccessFg.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isRecording
                              ? AppTheme.recordingRed
                              : AppTheme.lightSuccessFg,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isRecording) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.recordingRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ] else if (_isStarting) ...[
                            const SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.lightSuccessFg,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ] else ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.lightSuccessFg,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            _isRecording
                                ? 'LIVE RECORDING'
                                : (_isStarting ? 'STARTING...' : 'READY'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: _isRecording
                                  ? AppTheme.recordingRed
                                  : AppTheme.lightSuccessFg,
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
          child: _buildMetricTile(
            theme: theme,
            title: 'Audio Capture Mode',
            value: _isMicMuted ? 'Earphones Only' : 'Earphones + Mic',
            icon: _isMicMuted
                ? Icons.headset_rounded
                : Icons.headset_mic_rounded,
            valueColor: _isMicMuted ? AppTheme.amber : AppTheme.emerald,
            iconColor: _isMicMuted ? AppTheme.amber : AppTheme.emerald,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
    Color? iconColor,
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
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: theme.fgMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? theme.fgDefault,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarizingIndicator(ThemeData theme) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final String modelName;
    if (provider.isUsingGemini) {
      modelName = 'Gemini 2.5 Flash';
    } else if (provider.effectiveModel.isNotEmpty) {
      modelName = 'Ollama (${provider.effectiveModel})';
    } else {
      modelName = 'Local Ollama LLM';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentFg.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          CircularProgressIndicator(strokeWidth: 2.5, color: theme.accentFg),
          const SizedBox(height: 16),
          Text(
            'Analyzing Meeting Intelligence...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.fgDefault,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fusing Voxtral 4B speaker diarization with NVIDIA LocateAnything-3B visual events via $modelName.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.fgMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.accentFg,
                    size: 20,
                  ),
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
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: Text(
                      'Inspect Screenshots (${_getDisplaySteps().length})',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentFg,
                      side: BorderSide(
                        color: theme.accentFg.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showTranscriptModal(context, theme),
                    icon: const Icon(Icons.record_voice_over_rounded, size: 16),
                    label: const Text('View Transcript'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentFg,
                      side: BorderSide(
                        color: theme.accentFg.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                  if (_pdfUrl != null) ...[
                    OutlinedButton.icon(
                      onPressed: _openPdf,
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                      label: const Text('Download PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.accentFg,
                        side: BorderSide(color: theme.accentFg),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isExportingDrive
                          ? null
                          : _exportToGoogleDrive,
                      icon: _isExportingDrive
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 16),
                      label: const Text('Save to Drive'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.purplePrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSendingEmail ? null : _promptSendEmail,
                      icon: _isSendingEmail
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.mail_outline_rounded, size: 16),
                      label: const Text('Email PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF161B22),
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
          const SizedBox(height: 14),
          SelectionArea(
            child: MarkdownBody(
              data: _executiveSummary!,
              selectable: false,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: TextStyle(fontSize: 14, height: 1.6, color: theme.fgDefault),
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
      ),
    );
  }

  Widget _buildActionItemsCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
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

  bool _isInternalNoiseStep(Map<String, dynamic> step, String stepId) {
    final summary = (step['summary']?.toString() ?? '').toLowerCase();
    final meta =
        _stepDescriptions[stepId] ??
        _stepDescriptions['step_$stepId'] ??
        _stepDescriptions[stepId.replaceAll(RegExp(r'[^0-9]'), '')];
    final title = (meta is Map ? (meta['title']?.toString() ?? '') : '')
        .toLowerCase();
    final desc = (meta is Map ? (meta['description']?.toString() ?? '') : '')
        .toLowerCase();
    final combined = '$summary $title $desc';
    const noiseKeywords = [
      'deskmate',
      'meeting scribe',
      'start meeting',
      'end meeting',
      'stop meeting',
      'recording dashboard',
      'app switcher',
      'mission control',
      'window switch',
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

  Widget _buildVisualMomentsCard(ThemeData theme) {
    final displaySteps = _getDisplaySteps();
    if (displaySteps.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderDefault),
      ),
      child: Column(
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
                final title = meta is Map
                    ? (meta['title'] ?? summary)
                    : summary;
                final desc = meta is Map ? (meta['description'] ?? '') : '';
                final timestamp = step['timestamp']?.toString() ?? '';

                String screenshotPath =
                    step['screenshot_path']?.toString() ?? '';
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
      ),
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

    showDialog(
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
                        color: const Color(0xFF0D1117),
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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: AppTheme.emerald,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTranscriptCard(ThemeData theme) {
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderDefault),
      ),
      child: Column(
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
                      selectedColor: _getSpeakerColor(
                        spk,
                      ).withValues(alpha: 0.2),
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
                                  CircleAvatar(
                                    radius: 4,
                                    backgroundColor: color,
                                  ),
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
      ),
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
    showDialog(
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

  Widget _buildCustomFieldsAnalysisCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
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
      ),
    );
  }
}
