import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard_utils.dart';
import '../utils/open_external.dart';

class CredentialsSetupDialog extends StatefulWidget {
  final VoidCallback onClose;
  final AgentMode mode;

  const CredentialsSetupDialog({
    super.key,
    required this.onClose,
    this.mode = AgentMode.deskMate,
  });

  @override
  State<CredentialsSetupDialog> createState() => _CredentialsSetupDialogState();
}

class _CredentialsSetupDialogState extends State<CredentialsSetupDialog> {
  late AgentMode _currentMode;
  int _selectedTabIndex = 0;
  String? _copiedKey;
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientSecretController = TextEditingController();
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isSecretObscured = true;
  bool _isFullScreen = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      provider.fetchPersonalCredentials().then((_) {
        final creds = provider.personalCredentials;
        if (creds['configured'] == true) {
          if (creds['client_id'] != null && _clientIdController.text.isEmpty) {
            _clientIdController.text = creds['client_id'].toString();
          }
          final secret = creds['client_secret']?.toString() ?? '';
          if (secret.isNotEmpty && _clientSecretController.text.isEmpty) {
            _clientSecretController.text = secret;
          }
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant CredentialsSetupDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      setState(() {
        _currentMode = widget.mode;
        _selectedTabIndex = 0;
      });
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  void _copy(String text, String key, String label) {
    copyWithFeedback(context, text, label: '$label copied to clipboard');
    setState(() {
      _copiedKey = key;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          if (_copiedKey == key) {
            _copiedKey = null;
          }
        });
      }
    });
  }

  Future<void> _launchExternalUrl(String url, String label) async {
    final opened = await openExternal(url);
    if (opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opened $label in default web browser.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
    } else if (!opened) {
      _copy(url, 'url_$label', label);
    }
  }

  String _getTargetCredentialsPath() {
    return 'DeskMate/credentials.json';
  }

  Widget _buildCopyableSnippet({
    required ThemeData theme,
    required String text,
    required String keyId,
    required String label,
    String? copyButtonLabel,
    Color? textColor,
    bool isMonospace = true,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 7,
    ),
  }) {
    final isCopied = _copiedKey == keyId;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.isDark
            ? const Color(0xFF0D1117)
            : (isMonospace ? Colors.white : const Color(0xFFF6F8FA)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: isMonospace ? 'monospace' : null,
                fontSize: 11,
                color: textColor ?? theme.fgDefault,
              ),
            ),
          ),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _copy(text, keyId, label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    isCopied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 12,
                    color: isCopied ? theme.statusOk : theme.accentFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isCopied ? 'Copied' : (copyButtonLabel ?? 'Copy'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isCopied ? theme.statusOk : theme.accentFg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeBanner({
    required ThemeData theme,
    required String text,
    required IconData icon,
    required Color color,
    Color? textColor,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color:
                    textColor ??
                    (theme.isDark
                        ? const Color(0xFFE3B341)
                        : const Color(0xFF9E6A03)),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final theme = Theme.of(context);
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};

    final hasCreds = checks['google_credentials_file'] ?? false;
    final hasGmail = checks['gmail_token'] ?? false;
    final hasCal = checks['calendar_token'] ?? false;
    final hasDrive = checks['drive_token'] ?? false;

    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final screenHeight = size.height;

    final double dialogWidth = _isFullScreen
        ? screenWidth
        : math.min(1060.0, screenWidth * 0.96);
    final double dialogHeight = _isFullScreen
        ? screenHeight
        : math.min(940.0, screenHeight * 0.95);

    final isPersonal = _currentMode == AgentMode.personal;
    final isMeeting = _currentMode == AgentMode.meeting;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          margin: _isFullScreen
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: theme.isDark ? theme.bgCanvas : Colors.white,
            borderRadius: BorderRadius.circular(_isFullScreen ? 0 : 12),
            border: _isFullScreen
                ? null
                : Border.all(color: theme.borderDefault, width: 1),
            boxShadow: _isFullScreen
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: theme.isDark ? 0.6 : 0.15,
                      ),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Row(
                  children: [
                    Image.asset(
                      theme.isDark
                          ? 'assets/app_icon.png'
                          : 'assets/app_icon_light.png',
                      key: ValueKey(theme.isDark),
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: theme.accentFg.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.accentFg.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          isPersonal
                              ? Icons.vpn_key_rounded
                              : Icons.folder_special_rounded,
                          color: theme.accentFg,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMeeting
                                ? 'Meeting Scribe & Audio Intelligence Guide'
                                : isPersonal
                                ? 'Personal Assistant Credentials & Setup Guide'
                                : 'File Explorer & Local LLM Setup Guide',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.fgDefault,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isMeeting
                                ? 'Voxtral 4B Audio Extraction, LocateAnything-3B Vision Grounding, Google Drive Cloud PDF Export & Gmail Dispatch.'
                                : isPersonal
                                ? 'Configure Google Workspace OAuth (Gmail, Calendar, Drive), local SQLite storage, and personal tools.'
                                : 'Install Ollama, configure local models, understand Vector RAG search, and explore offline tools.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.fgMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // In-Dialog Guide Mode Switcher
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: theme.isDark
                            ? const Color(0xFF161B22)
                            : const Color(0xFFF1F3F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.borderDefault,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDialogModeButton(
                            theme: theme,
                            title: 'File Copilot & LLM',
                            icon: Icons.folder_open_rounded,
                            isSelected: _currentMode == AgentMode.deskMate,
                            onTap: () {
                              if (_currentMode != AgentMode.deskMate) {
                                setState(() {
                                  _currentMode = AgentMode.deskMate;
                                  _selectedTabIndex = 0;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 3),
                          _buildDialogModeButton(
                            theme: theme,
                            title: 'Personal Guide',
                            icon: Icons.person_rounded,
                            isSelected: _currentMode == AgentMode.personal,
                            onTap: () {
                              if (_currentMode != AgentMode.personal) {
                                setState(() {
                                  _currentMode = AgentMode.personal;
                                  _selectedTabIndex = 0;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 3),
                          _buildDialogModeButton(
                            theme: theme,
                            title: 'Meeting Scribe Guide',
                            icon: Icons.mic_rounded,
                            isSelected: _currentMode == AgentMode.meeting,
                            onTap: () {
                              if (_currentMode != AgentMode.meeting) {
                                setState(() {
                                  _currentMode = AgentMode.meeting;
                                  _selectedTabIndex = 0;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        mouseCursor: SystemMouseCursors.click,
                        onPressed: () =>
                            setState(() => _isFullScreen = !_isFullScreen),
                        icon: Icon(
                          _isFullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          size: 20,
                          color: theme.fgMuted,
                        ),
                        tooltip: _isFullScreen
                            ? 'Exit Full Screen'
                            : 'Full Screen',
                        hoverColor: theme.bgEmphasis,
                        splashRadius: 18,
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        mouseCursor: SystemMouseCursors.click,
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: theme.fgMuted,
                        ),
                        hoverColor: theme.bgEmphasis,
                        splashRadius: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.borderDefault),

              // ─── Live Health Status Bar ──────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: theme.isDark ? theme.bgSubtle : const Color(0xFFF6F8FA),
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (isMeeting) ...[
                              _buildStatusPill(
                                theme,
                                'Google Config',
                                hasCreds
                                    ? 'Configured Online'
                                    : 'Not Configured (Offline)',
                                hasCreds,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Drive Export',
                                hasDrive
                                    ? 'Connected Online'
                                    : 'Offline / Setup Needed',
                                hasDrive,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Gmail Dispatch',
                                hasGmail
                                    ? 'Connected Online'
                                    : 'Offline / Setup Needed',
                                hasGmail,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Voxtral 4B',
                                'In-Memory (16kHz)',
                                true,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'LocateAnything',
                                'Vision Grounding',
                                true,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Audio Gating',
                                'Active Room Silence',
                                true,
                              ),
                            ] else if (isPersonal) ...[
                              _buildStatusPill(
                                theme,
                                'Google Config',
                                hasCreds
                                    ? 'Configured Online'
                                    : 'Not Configured (Offline)',
                                hasCreds,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Gmail',
                                hasGmail ? 'Connected' : 'Offline',
                                hasGmail,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Calendar',
                                hasCal ? 'Connected' : 'Offline',
                                hasCal,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Drive',
                                hasDrive ? 'Connected' : 'Offline',
                                hasDrive,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Local DB',
                                'Ready (SQLite)',
                                true,
                              ),
                            ] else ...[
                              _buildStatusPill(
                                theme,
                                'Backend',
                                provider.isBackendOnline ? 'Online' : 'Offline',
                                provider.isBackendOnline,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Local LLM',
                                provider.isLocalLlmOnline
                                    ? 'Online'
                                    : 'Offline',
                                provider.isLocalLlmOnline,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Active Model',
                                provider.selectedLocalModel.isNotEmpty
                                    ? provider.selectedLocalModel
                                    : (provider.availableLocalModels.isNotEmpty
                                          ? provider.availableLocalModels.first
                                          : 'None'),
                                provider.selectedLocalModel.isNotEmpty,
                              ),
                              const SizedBox(width: 6),
                              _buildStatusPill(
                                theme,
                                'Vector DB',
                                'Ready (Qdrant & FastEmbed)',
                                true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.borderDefault),

              // ─── Navigation Tabs ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: theme.isDark ? theme.bgCanvas : Colors.white,
                  border: Border(
                    bottom: BorderSide(color: theme.borderDefault, width: 1),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: theme.isDark
                                  ? const Color(0xFF161B22)
                                  : const Color(0xFFF1F3F5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.borderDefault,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMeeting) ...[
                                  _buildTabButton(
                                    0,
                                    'Quick Start & Pipeline',
                                    Icons.rocket_launch_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    1,
                                    'Google Drive Export',
                                    Icons.add_to_drive_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    2,
                                    'Gmail Summary Dispatch',
                                    Icons.mark_email_read_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    3,
                                    'Audio Loopback & Gating',
                                    Icons.headset_mic_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    4,
                                    'Master Reference & API',
                                    Icons.menu_book_rounded,
                                    theme,
                                  ),
                                ] else if (isPersonal) ...[
                                  _buildTabButton(
                                    0,
                                    'Quick Setup',
                                    Icons.rocket_launch_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    1,
                                    'GCP OAuth Guide',
                                    Icons.key_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    2,
                                    'Offline Tools & SQLite',
                                    Icons.lock_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    3,
                                    '.env Configuration',
                                    Icons.settings_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    4,
                                    'Personal Assistant Guide',
                                    Icons.menu_book_rounded,
                                    theme,
                                  ),
                                ] else ...[
                                  _buildTabButton(
                                    0,
                                    'Ollama & Model Setup',
                                    Icons.smart_toy_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    1,
                                    'Vector DB & RAG Flow',
                                    Icons.hub_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    2,
                                    'File Copilot Tools',
                                    Icons.folder_copy_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    3,
                                    'File Agent Configuration',
                                    Icons.tune_rounded,
                                    theme,
                                  ),
                                  const SizedBox(width: 3),
                                  _buildTabButton(
                                    4,
                                    'File Copilot Guide',
                                    Icons.menu_book_rounded,
                                    theme,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ─── Tab Content Body ────────────────────────────────────────
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('$_currentMode-$_selectedTabIndex'),
                  child: SelectionArea(
                    child: _buildActiveTabContent(
                      theme: theme,
                      isMeeting: isMeeting,
                      isPersonal: isPersonal,
                      hasDrive: hasDrive,
                      hasGmail: hasGmail,
                      hasCreds: hasCreds,
                    ),
                  ),
                ),
              ),

              // ─── Footer ──────────────────────────────────────────────────
              Divider(height: 1, color: theme.borderDefault),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 15,
                      color: theme.accentFg,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPersonal
                            ? 'Tip: Once credentials.json is placed, asking "What is on my calendar tomorrow?" auto-opens OAuth.'
                            : 'Tip: Run "ollama run llama3.2" in your terminal to download and start your local LLM engine immediately.',
                        style: TextStyle(fontSize: 11, color: theme.fgMuted),
                      ),
                    ),
                    SelectionContainer.disabled(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: ElevatedButton(
                          onPressed: widget.onClose,
                          style: ButtonStyle(
                            elevation: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.hovered)) {
                                return 2.0;
                              }
                              return 0.0;
                            }),
                            mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click,
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.hovered)) {
                                return theme.accentHover;
                              }
                              if (states.contains(WidgetState.pressed)) {
                                return AppTheme.purpleActive;
                              }
                              return theme.accentFg;
                            }),
                            foregroundColor: WidgetStateProperty.all(
                              Colors.white,
                            ),
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
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
    );
  }

  Widget _buildActiveTabContent({
    required ThemeData theme,
    required bool isMeeting,
    required bool isPersonal,
    required bool hasDrive,
    required bool hasGmail,
    required bool hasCreds,
  }) {
    final tabIndex = _selectedTabIndex.clamp(0, 4);
    if (isMeeting) {
      switch (tabIndex) {
        case 0:
          return _buildMeetingQuickStartTab(theme);
        case 1:
          return _buildMeetingDriveExportTab(theme, hasDrive, hasCreds);
        case 2:
          return _buildMeetingGmailDispatchTab(theme, hasGmail, hasCreds);
        case 3:
          return _buildMeetingAudioGatingTab(theme);
        case 4:
        default:
          return _buildMeetingMasterReferenceTab(theme);
      }
    } else if (isPersonal) {
      switch (tabIndex) {
        case 0:
          return _buildQuickSetupTab(theme);
        case 1:
          return _buildGcpGuideTab(theme);
        case 2:
          return _buildOfflineToolsTab(theme);
        case 3:
          return _buildEnvConfigTab(theme);
        case 4:
        default:
          return _buildPersonalReadmeTab(theme);
      }
    } else {
      switch (tabIndex) {
        case 0:
          return _buildFileAgentGuideTab(theme);
        case 1:
          return _buildRagArchitectureTab(theme);
        case 2:
          return _buildFileCopilotToolsTab(theme);
        case 3:
          return _buildFileEnvConfigTab(theme);
        case 4:
        default:
          return _buildFileReadmeTab(theme);
      }
    }
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
            ? theme.statusOk.withValues(alpha: 0.15)
            : const Color(0xFFCF222E).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOk
              ? theme.statusOk.withValues(alpha: 0.45)
              : const Color(0xFFCF222E).withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOk ? theme.statusOk : const Color(0xFFCF222E),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $state',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isOk
                  ? theme.successText
                  : (theme.isDark
                        ? const Color(0xFFFFA198)
                        : const Color(0xFFCF222E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    int index,
    String title,
    IconData icon,
    ThemeData theme,
  ) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => setState(() => _selectedTabIndex = index),
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
    );
  }

  Widget _buildDialogModeButton({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
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
    );
  }

  // ─── TAB 0: Quick Setup ─────────────────────────────────────────────────
  Widget _buildQuickSetupTab(ThemeData theme) {
    final provider = Provider.of<ChatProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Credentials Configuration Card (Active View vs Edit Form)
          _buildCredentialsCard(theme, provider),

          const SizedBox(height: 12),

          // 2. Guide Navigator Card (Structured & Bordered)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.borderDefault, width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: theme.accentFg,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need to generate Google Cloud credentials?',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Follow our 5-step walkthrough and use direct Google Cloud Console links in the dedicated guide tab.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SelectionContainer.disabled(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _selectedTabIndex = 1),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                      label: const Text('Open Guide'),
                      style: ButtonStyle(
                        elevation: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return 2.0;
                          }
                          return 0.0;
                        }),
                        mouseCursor: WidgetStateProperty.all(
                          SystemMouseCursors.click,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.hovered)) {
                            return theme.accentHover;
                          }
                          if (states.contains(WidgetState.pressed)) {
                            return AppTheme.purpleActive;
                          }
                          return theme.accentFg;
                        }),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 3. Alternative: File Drop Card (Structured & Bordered)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.borderDefault, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_zip_outlined,
                      size: 15,
                      color: theme.accentFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ALTERNATIVE: DIRECT FILE DROP (credentials.json)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: theme.fgDefault,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'If you downloaded credentials.json directly from Google Cloud Console, you can also drop it into the DeskMate app data directory:',
                  style: TextStyle(fontSize: 11, color: theme.fgMuted),
                ),
                const SizedBox(height: 8),
                _buildCopyableSnippet(
                  theme: theme,
                  text: _getTargetCredentialsPath(),
                  keyId: 'quick_target_path',
                  label: 'Path',
                  copyButtonLabel: 'Copy Path',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiModelStatusCard(ThemeData theme, ChatProvider provider) {
    final isGemini = provider.isUsingGemini;
    final isLlmOnline = provider.isLocalLlmOnline;
    final modelName = provider.selectedLocalModel.isNotEmpty
        ? provider.selectedLocalModel
        : (provider.availableLocalModels.isNotEmpty
              ? provider.availableLocalModels.first
              : 'Default Model');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderDefault, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  (isGemini
                          ? theme.accentFg
                          : (isLlmOnline ? theme.statusOk : theme.dangerFg))
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    (isGemini
                            ? theme.accentFg
                            : (isLlmOnline ? theme.statusOk : theme.dangerFg))
                        .withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Icon(
              isGemini ? Icons.cloud_done_rounded : Icons.memory_rounded,
              color: isGemini
                  ? theme.accentFg
                  : (isLlmOnline ? theme.statusOk : theme.dangerFg),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Engine: ',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                    Text(
                      isGemini ? 'Gemini 1.5 Flash' : modelName,
                      style: TextStyle(
                        fontFamily: isGemini ? null : 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isGemini ? theme.accentFg : theme.successText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isGemini
                      ? 'Cloud reasoning enabled for multi-step tasks. Change key or switch to local model anytime.'
                      : (isLlmOnline
                            ? '100% offline & air-gapped on Ollama (${provider.availableLocalModels.length} models detected).'
                            : 'Ollama is offline. Start Ollama to run offline local models.'),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: theme.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: OutlinedButton.icon(
              onPressed: () {
                provider.openModelSelectionDialog();
              },
              icon: const Icon(Icons.tune_rounded, size: 13),
              label: const Text('Change Model / Key'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accentFg,
                side: BorderSide(color: theme.accentFg.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 1: Get Credentials Guide ───────────────────────────────────────
  Widget _buildGcpGuideTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Google Cloud Console Direct Access Quick Bar
          _buildGcpDirectLinksBar(theme),

          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 16,
                color: theme.accentFg,
              ),
              const SizedBox(width: 8),
              Text(
                'GOOGLE CLOUD SETUP WALKTHROUGH',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgDefault,
                ),
              ),
              const Spacer(),
              Text(
                '5 Easy Steps',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Step 1
          _buildStepCard(
            theme: theme,
            stepNumber: '1',
            title: 'Open Google Cloud Console & Create Project',
            description:
                'Visit the Google Cloud Console. Select an existing project or click "New Project" (e.g. name it "DeskMate") from the top navigation dropdown.',
            actionButton: _buildStepActionButton(
              theme: theme,
              url: 'https://console.cloud.google.com/',
              label: 'Open Console',
            ),
          ),

          // Step 2
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Enable Required Google Workspace APIs',
            description:
                'Under "APIs & Services" > "Library", search for and enable these 4 essential Google Workspace APIs:',
            actionButton: _buildStepActionButton(
              theme: theme,
              url: 'https://console.cloud.google.com/apis/library',
              label: 'Open Library',
            ),
            customContent: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Column(
                children: [
                  _buildApiCheckItem(
                    theme,
                    'Gmail API',
                    'Read, search, draft, and organize emails',
                  ),
                  const SizedBox(height: 6),
                  _buildApiCheckItem(
                    theme,
                    'Google Calendar API',
                    'Query events, agenda, and schedule appointments',
                  ),
                  const SizedBox(height: 6),
                  _buildApiCheckItem(
                    theme,
                    'Google Drive API',
                    'Search, read, and organize Drive documents',
                  ),
                  const SizedBox(height: 6),
                  _buildApiCheckItem(
                    theme,
                    'Tasks API',
                    'Manage to-do items and checklists',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accentFg.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.accentFg.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 13,
                          color: theme.accentFg,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Note: When enabled, Google redirects to the API details page showing "Methods: 17 options selected". All API methods are enabled automatically by default—leave them as-is.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: theme.fgDefault,
                              height: 1.3,
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

          // Step 3
          _buildStepCard(
            theme: theme,
            stepNumber: '3',
            title: 'Configure Google Auth Platform / Branding',
            description:
                'Go to "Google Auth Platform" > "Create branding" (or "APIs & Services" > "OAuth consent screen") and complete the 4-step wizard:',
            actionButton: _buildStepActionButton(
              theme: theme,
              url: 'https://console.cloud.google.com/apis/credentials/consent',
              label: 'Open Consent',
            ),
            customContent: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBulletPoint(
                    theme,
                    '1. App Information:',
                    'Enter App Name "DeskMate" (required; cannot be empty). Select your email in User support email dropdown. Click "Next".',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    '2. Audience (Crucial):',
                    'What is Audience? It controls who can log in. Select "External" so your personal @gmail.com account can authenticate ("Internal" is only for Workspace organizations). Click "Next".',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    '3. Contact Information:',
                    'Enter your personal email for Developer contact information. Click "Next".',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    '4. Finish:',
                    'Check "I agree to the Google API services user data policy", click "Continue", and click "Create".',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    '5. Test Users (MANDATORY):',
                    'Under "Audience" > "Test users" (or OAuth consent screen), click "+ ADD USERS" and add your Gmail. Because unverified apps are in "Testing" mode, Google strictly blocks login with 403 access_denied unless your email is added here!',
                  ),
                ],
              ),
            ),
          ),

          // Step 4
          _buildStepCard(
            theme: theme,
            stepNumber: '4',
            title: 'Create Desktop OAuth 2.0 Credentials',
            description:
                'Go to "Clients" (or "APIs & Services" > "Credentials" > "+ Create Credentials" > "OAuth client ID"):',
            actionButton: _buildStepActionButton(
              theme: theme,
              url: 'https://console.cloud.google.com/apis/credentials',
              label: 'Open Credentials',
            ),
            customContent: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.isDark
                        ? const Color(0xFF0D1117)
                        : const Color(0xFFF6F8FA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.borderDefault, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBulletPoint(
                        theme,
                        'Application Type:',
                        'Select "Desktop App" (CRITICAL: NOT Web Application, Android, or iOS).',
                      ),
                      const SizedBox(height: 5),
                      _buildBulletPoint(
                        theme,
                        'Name:',
                        'Enter "DeskMate Desktop Client" and click "Create".',
                      ),
                      const SizedBox(height: 5),
                      _buildBulletPoint(
                        theme,
                        'OAuth Client Created Modal:',
                        'Google displays your Client ID and Client Secret with copy buttons, and a "Download JSON" button.',
                      ),
                      const SizedBox(height: 5),
                      _buildBulletPoint(
                        theme,
                        'Quick Setup:',
                        'Copy your Client ID & Secret directly into the Quick Setup tab below, or download the JSON and rename to credentials.json.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelectionContainer.disabled(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final provider = Provider.of<ChatProvider>(
                              context,
                              listen: false,
                            );
                            final credsStatus = provider.personalCredentials;
                            final hasCreds =
                                (credsStatus['configured'] == true) ||
                                (provider
                                        .personalAgentHealth['checks']?['google_credentials_file'] ??
                                    false);
                            setState(() {
                              _selectedTabIndex = 0;
                              _isEditing = hasCreds;
                            });
                          },
                          icon: const Icon(Icons.input_rounded, size: 14),
                          label: const Text('Enter Keys in Quick Setup Tab →'),
                          style: ButtonStyle(
                            elevation: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.hovered)) {
                                return 2.0;
                              }
                              return 0.0;
                            }),
                            mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click,
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.hovered)) {
                                return theme.accentHover;
                              }
                              if (states.contains(WidgetState.pressed)) {
                                return AppTheme.purpleActive;
                              }
                              return theme.accentFg;
                            }),
                            foregroundColor: WidgetStateProperty.all(
                              Colors.white,
                            ),
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 13,
                          color: theme.accentFg,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'OR configure in Settings Drawer ➔ Google Workspace OAuth',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.fgDefault,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'OR drop downloaded JSON file into your app data directory:',
                  style: TextStyle(fontSize: 11, color: theme.fgMuted),
                ),
                const SizedBox(height: 6),
                _buildCopyableSnippet(
                  theme: theme,
                  text: _getTargetCredentialsPath(),
                  keyId: 'guide_target_path',
                  label: 'Credentials path',
                  copyButtonLabel: 'Copy Path',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ],
            ),
          ),

          // Step 5
          _buildStepCard(
            theme: theme,
            stepNumber: '5',
            title: 'One-Click Instant Authorization',
            description:
                'Ask DeskMate any question in chat (e.g. "Summarize my unread emails" or "What is on my calendar tomorrow?"). Your browser will automatically open Google\'s authorization screen once, and cache your token permanently on this device!',
            actionButton: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.statusOk.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.statusOk.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 13, color: theme.statusOk),
                  const SizedBox(width: 4),
                  Text(
                    'Automatic',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.successText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 2: File Agent & Local LLM Guide ────────────────────────────────
  Widget _buildFileAgentGuideTab(ThemeData theme) {
    final provider = Provider.of<ChatProvider>(context);
    final isLlmOnline = provider.isLocalLlmOnline;
    final activeModel = provider.selectedLocalModel;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Current AI Engine & Model Selector
          _buildAiModelStatusCard(theme, provider),
          const SizedBox(height: 14),

          // 2. Direct Quick Access Bar for Ollama
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.borderDefault, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory_rounded, size: 16, color: theme.accentFg),
                    const SizedBox(width: 7),
                    Text(
                      'OLLAMA LOCAL LLM DIRECT ACCESS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: theme.fgDefault,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (isLlmOnline ? theme.statusOk : theme.dangerFg)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (isLlmOnline ? theme.statusOk : theme.dangerFg)
                              .withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isLlmOnline
                                  ? theme.statusOk
                                  : theme.dangerFg,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isLlmOnline
                                ? (activeModel.isNotEmpty
                                      ? 'Active: $activeModel'
                                      : 'Ollama Online')
                                : 'Ollama Offline (127.0.0.1:11434)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isLlmOnline
                                  ? theme.successText
                                  : theme.dangerFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'File Copilot operates 100% offline and air-gapped on your computer. Download Ollama to run local inference:',
                  style: TextStyle(fontSize: 11.5, color: theme.fgMuted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildGcpLinkChip(
                      label: 'Download Ollama',
                      url: 'https://ollama.com/download',
                      icon: Icons.download_rounded,
                      theme: theme,
                    ),
                    _buildGcpLinkChip(
                      label: 'Ollama Models Library',
                      url: 'https://ollama.com/library',
                      icon: Icons.auto_awesome_rounded,
                      theme: theme,
                    ),
                    _buildGcpLinkChip(
                      label: 'Qdrant Vector Engine',
                      url: 'https://qdrant.tech/',
                      icon: Icons.hub_outlined,
                      theme: theme,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 16, color: theme.accentFg),
              const SizedBox(width: 8),
              Text(
                'LOCAL LLM & FILE COPILOT SETUP GUIDE',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgDefault,
                ),
              ),
              const Spacer(),
              Text(
                '5 Easy Steps',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Step 1: Install Ollama
          _buildStepCard(
            theme: theme,
            stepNumber: '1',
            title: 'Download & Install Ollama Engine',
            description:
                'Download the official Ollama installer for macOS or Windows. If you are on macOS with Homebrew installed, run:',
            actionButton: OutlinedButton.icon(
              onPressed: () => _launchExternalUrl(
                'https://ollama.com/download',
                'Download Ollama',
              ),
              icon: const Icon(Icons.download_rounded, size: 12),
              label: const Text('Download Ollama'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accentFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ),
            customContent: _buildCopyableSnippet(
              theme: theme,
              text: 'brew install ollama',
              keyId: 'brew_ollama',
              label: 'Command',
              textColor: theme.isDark
                  ? const Color(0xFF7EE787)
                  : const Color(0xFF116329),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),

          // Step 2: Pull Model
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Pull a Recommended Local LLM Model',
            description:
                'Open your terminal and pull one of the recommended models. Ollama downloads and caches the weights locally:',
            actionButton: OutlinedButton.icon(
              onPressed: () => _launchExternalUrl(
                'https://ollama.com/library',
                'Ollama Models',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 12),
              label: const Text('Browse Models'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accentFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ),
            customContent: Column(
              children: [
                _buildModelCommandRow(
                  theme: theme,
                  cmd: 'ollama run llama3.2',
                  tag: 'llama3.2',
                  keyId: 'model_llama',
                  desc:
                      'Fast, lightweight 3B model. Excellent for general coding & speed.',
                ),
                const SizedBox(height: 6),
                _buildModelCommandRow(
                  theme: theme,
                  cmd: 'ollama run qwen2.5-coder',
                  tag: 'qwen2.5-coder',
                  keyId: 'model_qwen',
                  desc:
                      'Specialized coding model. Exceptional for codebase edits & AST refactoring.',
                ),
                const SizedBox(height: 6),
                _buildModelCommandRow(
                  theme: theme,
                  cmd: 'ollama run mistral',
                  tag: 'mistral',
                  keyId: 'model_mistral',
                  desc:
                      'General reasoning model with strong contextual comprehension.',
                ),
              ],
            ),
          ),

          // Step 3: Zero-Config Detection
          _buildStepCard(
            theme: theme,
            stepNumber: '3',
            title: 'Zero-Config Automatic Detection',
            description:
                'DeskMate automatically connects to Ollama on http://127.0.0.1:11434. Once Ollama starts, DeskMate immediately detects your models with zero manual configuration:',
            actionButton: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.statusOk.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.statusOk.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 13, color: theme.statusOk),
                  const SizedBox(width: 4),
                  Text(
                    'Auto-Configured',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.successText,
                    ),
                  ),
                ],
              ),
            ),
            customContent: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBulletPoint(
                    theme,
                    'Sidebar Status & Splitter:',
                    'The microchip icon turns 🟢 Green with your active local model name. You can resize the sidebar anytime by dragging the right splitter edge.',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    'Model Switcher:',
                    'If you have multiple models installed, a model dropdown automatically appears in the sidebar for 1-click switching.',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    'Settings Drawer (⚙️):',
                    'Inspect the FastAPI backend status, customize the backend URL, and check installed Ollama models in the right Settings drawer.',
                  ),
                ],
              ),
            ),
          ),

          // Step 4: Capabilities
          _buildStepCard(
            theme: theme,
            stepNumber: '4',
            title: 'File Copilot Core Capabilities (Privacy-First)',
            description:
                'File Copilot is powered entirely by your local model. No code, filenames, or prompts leave your computer:',
            customContent: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Column(
                children: [
                  _buildApiCheckItem(
                    theme,
                    'Directory Inspection',
                    'list_directory, search_files to discover workspace trees',
                  ),
                  const SizedBox(height: 6),
                  _buildApiCheckItem(
                    theme,
                    'Qdrant Vector Search',
                    'index_document, search_qdrant for semantic codebase recall',
                  ),
                  const SizedBox(height: 6),
                  _buildApiCheckItem(
                    theme,
                    'Safe File Editing',
                    'read_file, write_to_file for precision edits and code drafts',
                  ),
                  const SizedBox(height: 6),
                  _buildApiCheckItem(
                    theme,
                    'Air-Gapped Privacy',
                    '100% offline inference on your GPU/CPU with zero cloud reliance',
                  ),
                ],
              ),
            ),
          ),

          // Step 5: Separation
          _buildStepCard(
            theme: theme,
            stepNumber: '5',
            title: 'Clear Agent Separation: File Agent vs Personal Agent',
            description:
                'DeskMate maintains a strict, secure division between the two agents:',
            customContent: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.accentFg.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: theme.accentFg,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: theme.fgDefault,
                            ),
                            children: [
                              const TextSpan(
                                text: 'File Copilot: ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text:
                                    'Dedicated to your local workspace, project code, and documents. Uses your Local LLM. Does NOT touch or require your Google Workspace credentials.',
                                style: TextStyle(color: theme.fgMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    color: theme.borderDefault.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.statusOk.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: theme.statusOk,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: theme.fgDefault,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Personal Assistant: ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text:
                                    'Dedicated to your digital life (Gmail, Calendar, Drive, SQLite checklists, notes, weather). Does NOT touch your project files and does NOT require a local LLM to run offline tools.',
                                style: TextStyle(color: theme.fgMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCommandRow({
    required ThemeData theme,
    required String cmd,
    required String tag,
    required String keyId,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF0D1117) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cmd,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: theme.isDark
                        ? const Color(0xFF7EE787)
                        : const Color(0xFF116329),
                  ),
                ),
              ),
              InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _copy(cmd, keyId, 'Command'),
                child: Row(
                  children: [
                    Icon(
                      _copiedKey == keyId
                          ? Icons.check_rounded
                          : Icons.copy_rounded,
                      size: 12,
                      color: _copiedKey == keyId
                          ? theme.statusOk
                          : theme.accentFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _copiedKey == keyId ? 'Copied' : 'Copy',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _copiedKey == keyId
                            ? theme.statusOk
                            : theme.accentFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(desc, style: TextStyle(fontSize: 10.5, color: theme.fgMuted)),
        ],
      ),
    );
  }

  Widget _buildGcpDirectLinksBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_outlined,
                size: 14,
                color: theme.accentFg,
              ),
              const SizedBox(width: 6),
              Text(
                'GOOGLE CLOUD CONSOLE DIRECT ACCESS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgDefault,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Quick-open Google Cloud Console directly from DeskMate to generate or manage your keys:',
            style: TextStyle(fontSize: 11, color: theme.fgMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildGcpLinkChip(
                label: 'Credentials Console',
                url: 'https://console.cloud.google.com/apis/credentials',
                icon: Icons.key_rounded,
                theme: theme,
              ),
              _buildGcpLinkChip(
                label: 'OAuth Consent Screen',
                url:
                    'https://console.cloud.google.com/apis/credentials/consent',
                icon: Icons.shield_outlined,
                theme: theme,
              ),
              _buildGcpLinkChip(
                label: 'Google APIs Library',
                url: 'https://console.cloud.google.com/apis/library',
                icon: Icons.library_add_check_outlined,
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGcpLinkChip({
    required String label,
    required String url,
    required IconData icon,
    required ThemeData theme,
  }) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => _launchExternalUrl(url, label),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.isDark ? const Color(0xFF21262D) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.borderDefault, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.accentFg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.fgDefault,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.open_in_new_rounded, size: 11, color: theme.fgMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsCard(ThemeData theme, ChatProvider provider) {
    final credsStatus = provider.personalCredentials;
    final hasCreds =
        (credsStatus['configured'] == true) ||
        (provider.personalAgentHealth['checks']?['google_credentials_file'] ??
            false);
    final activeClientId = credsStatus['client_id']?.toString() ?? '';

    if (hasCreds && !_isEditing) {
      // ─── ACTIVE & CONFIGURED VIEW ──────────────────────────────────────
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.isDark ? const Color(0xFF0D1117) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.statusOk.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.statusOk.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.statusOk.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.statusOk.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.statusOk,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ACTIVE & CONFIGURED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: theme.successText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Permanent storage in .env & credentials.json',
                  style: TextStyle(fontSize: 10.5, color: theme.fgMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Caution Banner
            _buildNoticeBanner(
              theme: theme,
              text:
                  'Caution: DeskMate has active Google credentials saved. If you need to change your Google project or rotate keys, click "Edit Credentials". Saving new keys will replace the existing configuration in .env and reset active authorizations.',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFD29922),
            ),
            const SizedBox(height: 14),

            // Readonly Client ID Display
            Text(
              'ACTIVE CLIENT ID',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: theme.fgMuted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.bgPanel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, size: 14, color: theme.statusOk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activeClientId.isNotEmpty
                          ? activeClientId
                          : 'Google OAuth Client Credentials Configured',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: theme.fgDefault,
                      ),
                    ),
                  ),
                  if (activeClientId.isNotEmpty)
                    InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () =>
                          _copy(activeClientId, 'active_cid', 'Client ID'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _copiedKey == 'active_cid'
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                              size: 12,
                              color: _copiedKey == 'active_cid'
                                  ? theme.statusOk
                                  : theme.accentFg,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _copiedKey == 'active_cid' ? 'Copied' : 'Copy',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _copiedKey == 'active_cid'
                                    ? theme.statusOk
                                    : theme.accentFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Masked Secret Display
            Text(
              'CLIENT SECRET',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: theme.fgMuted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.bgPanel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: theme.fgMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '••••••••••••••••••••••••••••••••',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: theme.fgMuted,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? const Color(0xFF21262D)
                          : const Color(0xFFEAEEF2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'SECURED & PERSISTED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: theme.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Edit Action Button
            Align(
              alignment: Alignment.centerRight,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditing = true;
                      _inlineError = null;
                      if (_clientIdController.text.isEmpty &&
                          activeClientId.isNotEmpty) {
                        _clientIdController.text = activeClientId;
                      }
                      final secret =
                          credsStatus['client_secret']?.toString() ?? '';
                      if (secret.isNotEmpty) {
                        _clientSecretController.text = secret;
                      } else {
                        _clientSecretController.clear();
                      }
                    });
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Edit / Replace Credentials'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.accentFg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ─── EDITING OR FIRST-TIME SETUP VIEW ─────────────────────────────────
    final isReplacing = hasCreds && _isEditing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF0D1117) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isReplacing
              ? const Color(0xFFD29922).withValues(alpha: 0.5)
              : theme.accentFg.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          if (isReplacing)
            _buildNoticeBanner(
              theme: theme,
              margin: const EdgeInsets.only(bottom: 12),
              text:
                  'Modifying Credentials: Saving new keys will replace the existing configuration in .env and reset active authorizations.',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFD29922),
            )
          else
            _buildNoticeBanner(
              theme: theme,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              text:
                  'Configure Google OAuth 2.0 Credentials: Enter your Client ID and Secret below. DeskMate will validate and activate them in .env and credentials.json.',
              icon: Icons.vpn_key_rounded,
              color: theme.accentFg,
              textColor: theme.fgDefault,
            ),

          // Client ID Field
          TextField(
            controller: _clientIdController,
            style: TextStyle(fontSize: 12, color: theme.fgDefault),
            decoration: InputDecoration(
              labelText: 'Google Client ID',
              hintText: 'xxxx.apps.googleusercontent.com',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              prefixIcon: Icon(
                Icons.badge_outlined,
                size: 16,
                color: theme.fgMuted,
              ),
              suffixIcon: _clientIdController.text.isNotEmpty
                  ? MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 14),
                        onPressed: () =>
                            setState(() => _clientIdController.clear()),
                      ),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),

          // Client Secret Field
          TextField(
            controller: _clientSecretController,
            obscureText: _isSecretObscured,
            style: TextStyle(fontSize: 12, color: theme.fgDefault),
            decoration: InputDecoration(
              labelText: 'Google Client Secret',
              hintText: 'GOCSPX-xxxx',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              prefixIcon: Icon(
                Icons.key_outlined,
                size: 16,
                color: theme.fgMuted,
              ),
              suffixIcon: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IconButton(
                  icon: Icon(
                    _isSecretObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                    color: theme.fgMuted,
                  ),
                  onPressed: () =>
                      setState(() => _isSecretObscured = !_isSecretObscured),
                ),
              ),
            ),
          ),

          // Inline validation error if any
          if (_inlineError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.dangerFg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.dangerFg.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: theme.dangerFg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inlineError!,
                      style: TextStyle(fontSize: 11, color: theme.dangerFg),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isReplacing) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = false;
                        _inlineError = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.fgMuted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              SelectionContainer.disabled(
                child: MouseRegion(
                  cursor: _isSaving
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _handleSave(
                            provider,
                            theme,
                            isReplace: isReplacing,
                          ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isReplacing
                                ? Icons.published_with_changes_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 15,
                          ),
                    label: Text(
                      _isSaving
                          ? 'Validating...'
                          : isReplacing
                          ? 'Validate & Replace Old Credentials'
                          : 'Validate & Activate Credentials',
                    ),
                    style: ButtonStyle(
                      elevation: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return 2.0;
                        }
                        return 0.0;
                      }),
                      mouseCursor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return SystemMouseCursors.basic;
                        }
                        return SystemMouseCursors.click;
                      }),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (isReplacing) {
                          if (states.contains(WidgetState.hovered)) {
                            return const Color(0xFFE3A638);
                          }
                          return const Color(0xFFD29922);
                        }
                        if (states.contains(WidgetState.disabled)) {
                          return theme.bgEmphasis;
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return theme.accentHover;
                        }
                        if (states.contains(WidgetState.pressed)) {
                          return AppTheme.purpleActive;
                        }
                        return theme.accentFg;
                      }),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave(
    ChatProvider provider,
    ThemeData theme, {
    required bool isReplace,
  }) async {
    final cid = _clientIdController.text.trim();
    final sec = _clientSecretController.text.trim();

    if (cid.isEmpty || sec.isEmpty) {
      setState(
        () => _inlineError = 'Please enter both Client ID and Client Secret.',
      );
      return;
    }
    if (!cid.endsWith('.apps.googleusercontent.com') || cid.length < 25) {
      setState(
        () => _inlineError =
            'Client ID must end with .apps.googleusercontent.com (e.g. 12345-xxx.apps.googleusercontent.com)',
      );
      return;
    }
    if (sec.length < 8) {
      setState(
        () =>
            _inlineError = 'Client Secret must be at least 8 characters long.',
      );
      return;
    }

    setState(() {
      _inlineError = null;
      _isSaving = true;
    });

    final result = await provider.saveGoogleCredentials(cid, sec);

    if (mounted) {
      setState(() => _isSaving = false);
      if (result['success'] == true) {
        setState(() {
          _isEditing = false;
          _inlineError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ??
                  'Credentials validated, saved to .env, and activated!',
            ),
            backgroundColor: theme.successFg,
            behavior: SnackBarBehavior.floating,
            width: 380,
          ),
        );
      } else {
        setState(() {
          _inlineError = result['message'] ?? 'Failed to save credentials.';
        });
      }
    }
  }

  Widget _buildStepActionButton({
    required ThemeData theme,
    required String url,
    required String label,
    IconData icon = Icons.open_in_new_rounded,
  }) {
    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: OutlinedButton.icon(
          onPressed: () => _launchExternalUrl(url, label),
          icon: Icon(icon, size: 12),
          label: Text(label),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return Colors.white;
              }
              return theme.accentFg;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return theme.accentFg;
              }
              return Colors.transparent;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return BorderSide(color: theme.accentFg, width: 1.2);
              }
              return BorderSide(
                color: theme.accentFg.withValues(alpha: 0.5),
                width: 1.0,
              );
            }),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required ThemeData theme,
    required String stepNumber,
    required String title,
    required String description,
    Widget? actionButton,
    Widget? customContent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderDefault, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF1C2128)
                  : const Color(0xFFF6F8FA),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(color: theme.borderDefault, width: 0.8),
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
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'STEP $stepNumber',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: theme.accentFg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: theme.fgDefault,
                    ),
                  ),
                ),
                if (actionButton != null) ...[
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: actionButton,
                  ),
                ],
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.fgMuted,
                  ),
                ),
                if (customContent != null) ...[
                  const SizedBox(height: 10),
                  customContent,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiCheckItem(ThemeData theme, String name, String purpose) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 14, color: theme.statusOk),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.fgDefault,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            purpose,
            style: TextStyle(fontSize: 11, color: theme.fgMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(ThemeData theme, String boldPrefix, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.accentFg,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: theme.fgDefault,
              ),
              children: [
                TextSpan(
                  text: '$boldPrefix ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: text,
                  style: TextStyle(color: theme.fgMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── TAB 2: .env Configuration ──────────────────────────────────────────
  Widget _buildEnvConfigTab(ThemeData theme) {
    const envTemplate = """# DeskMate Personal Agent Environment Credentials
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-your-client-secret

# Optional GitHub Personal Access Token (for repo search & issue creation)
GITHUB_TOKEN=ghp_your_github_token_here

# Local SQLite Database Path (Optional, defaults to DeskMate App Data)
# LOCAL_AGENT_DB=deskmate_agent.db
""";
    final isCopied = _copiedKey == 'env_template';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alternative: Environment Variables (.env)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.fgDefault,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'If you prefer environment variables over a credentials.json file, you can place a .env file inside deskmate_engine/ or your DeskMate directory.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: theme.fgMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Template .env Configuration',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
              const Spacer(),
              InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () =>
                    _copy(envTemplate, 'env_template', '.env template'),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCopied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 12,
                        color: isCopied ? theme.statusOk : theme.accentFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCopied ? 'Copied' : 'Copy Template',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isCopied ? theme.statusOk : theme.accentFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF0D1117)
                  : const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: SelectionArea(
              child: Text(
                envTemplate,
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
      ),
    );
  }

  // ─── TAB 3: Offline Tools ───────────────────────────────────────────────
  Widget _buildOfflineToolsTab(ThemeData theme) {
    final offlineTools = [
      {
        'title': 'Local Tasks & Checklists',
        'desc':
            'Create, list, and complete to-do items stored in local SQLite.',
        'tools': 'list_tasks, add_task, complete_task',
        'icon': Icons.checklist_rounded,
      },
      {
        'title': 'Personal Notes with Tags',
        'desc': 'Capture snippets and markdown notes with full-text search.',
        'tools': 'save_note, search_notes',
        'icon': Icons.note_alt_outlined,
      },
      {
        'title': 'FAISS Semantic Memory',
        'desc': 'Remembers personal facts and preferences with vector recall.',
        'tools': 'save_to_memory, search_memory',
        'icon': Icons.psychology_rounded,
      },
      {
        'title': 'Free Web Research',
        'desc': 'Live DuckDuckGo search queries with zero API keys required.',
        'tools': 'duckduckgo_search',
        'icon': Icons.travel_explore_rounded,
      },
      {
        'title': 'Weather Forecasts',
        'desc': 'Live weather forecasts for any city or region worldwide.',
        'tools': 'get_weather',
        'icon': Icons.cloud_outlined,
      },
      {
        'title': 'System Clock & Calendar Math',
        'desc': 'Date, time, day-of-week, and relative scheduling calculation.',
        'tools': 'get_datetime',
        'icon': Icons.access_time_rounded,
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.statusOk.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.statusOk.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: theme.statusOk,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No Google Account? No problem! These tools run 100% locally and offline out-of-the-box with ZERO credentials required.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: theme.successText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final tool in offlineTools) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Row(
                children: [
                  Icon(
                    tool['icon'] as IconData,
                    size: 18,
                    color: theme.accentFg,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool['title'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.fgDefault,
                          ),
                        ),
                        Text(
                          tool['desc'] as String,
                          style: TextStyle(fontSize: 11, color: theme.fgMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? const Color(0xFF21262D)
                          : const Color(0xFFEAEEF2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tool['tools'] as String,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: theme.fgMuted,
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

  // ─── TAB 4 (Personal): Personal Assistant Guide ────────────────────────
  Widget _buildPersonalReadmeTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: theme.isDark
                    ? [const Color(0xFF1C2128), const Color(0xFF161B22)]
                    : [const Color(0xFFF0F7FF), const Color(0xFFE8F4FD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.accentFg.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: theme.accentFg,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Workspace Assistant Guide',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Direct desktop integration with Google Workspace and local SQLite productivity database with strict zero-cloud-leakage privacy guarantees.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Privacy & Security Section
          Row(
            children: [
              Icon(Icons.shield_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'PRIVACY & SECURITY GUARANTEES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingEngineRow(
            theme,
            icon: Icons.storage_rounded,
            color: const Color(0xFF1F883D),
            label: 'Zero Cloud Data Leakage',
            badge: '100% Local Device',
            desc:
                'Your SQLite tasks, notes, and local vector memory (deskmate_agent.db) are stored 100% on your device with no external telemetry.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.sync_alt_rounded,
            color: const Color(0xFF0969DA),
            label: 'Direct Google OAuth',
            badge: 'Direct End-to-End',
            desc:
                'DeskMate never routes your emails, calendar events, or documents through intermediary servers. All requests communicate directly between your machine and official Google API endpoints.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.lock_rounded,
            color: const Color(0xFF8957E5),
            label: 'Local Credential Storage',
            badge: 'Secure Environment',
            desc:
                'OAuth client credentials and tokens are stored in your user configuration directory (~/.deskmate/.env) and never transmitted elsewhere.',
          ),

          const SizedBox(height: 16),

          // Google Workspace Automation Section
          Row(
            children: [
              Icon(Icons.cloud_done_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'GOOGLE WORKSPACE SUITE (OAUTH REQUIRED)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingInfoCard(
            theme,
            icon: Icons.mark_email_read_rounded,
            title: 'Gmail Automation',
            desc:
                'Search recent threads, summarize unread messages, draft replies, and send emails securely directly from the chat prompt.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.calendar_today_rounded,
            title: 'Google Calendar Management',
            desc:
                'List today\'s agenda, check availability, create new calendar events with attendees, and calculate relative scheduling automatically.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.add_to_drive_rounded,
            title: 'Google Drive & Docs Search',
            desc:
                'Search Drive files by keyword, download and summarize document contents, and query shared files across your organization.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.task_alt_rounded,
            title: 'Google Tasks Sync',
            desc:
                'Create, list, check off, and synchronize task lists across Google devices in real-time.',
          ),

          const SizedBox(height: 16),

          // Offline Productivity Suite Section
          Row(
            children: [
              Icon(Icons.offline_bolt_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'OFFLINE PRODUCTIVITY SUITE (ZERO SETUP)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingInfoCard(
            theme,
            icon: Icons.checklist_rounded,
            title: 'Local SQLite Tasks (deskmate_agent.db)',
            desc:
                'Add, complete, and track local to-dos without requiring an internet connection. Stored permanently in SQLite.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.note_alt_outlined,
            title: 'Tagged Markdown Notes',
            desc:
                'Save quick ideas, meeting minutes, and code snippets with full-text search and category tags.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.psychology_rounded,
            title: 'FAISS L2 Semantic Memory',
            desc:
                'Persistent vector memory allows the assistant to remember your project preferences and context across days.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.travel_explore_rounded,
            title: 'Live Weather & Web Research',
            desc:
                'Real-time DuckDuckGo searches and wttr.in weather forecasts without requiring any API key or subscription.',
          ),

          const SizedBox(height: 16),

          // Smart Multi-Turn Section
          Row(
            children: [
              Icon(Icons.forum_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'SMART MULTI-TURN CONVERSATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zero-Bloat Contextualizer transforms follow-up queries into complete standalone prompts in sub-80ms:',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.fgMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMultiTurnStep(
                  theme,
                  'Turn 1',
                  '"What is the weather in SF this weekend?"',
                  'Assistant answers with San Francisco forecast.',
                ),
                _buildMultiTurnStep(
                  theme,
                  'Turn 2',
                  '"in chennai"',
                  'Auto-resolved to: "What is the weather in Chennai this weekend?"',
                ),
                _buildMultiTurnStep(
                  theme,
                  'Turn 3',
                  '"what about tomorrow?"',
                  'Auto-resolved to: "What is the weather in Chennai tomorrow?"',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Example Prompts Section
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'EXAMPLE PERSONAL ASSISTANT PROMPTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildExampleInquiry(
                  theme,
                  '"Weather Forecast"',
                  'What\'s the weather forecast for San Francisco this weekend?',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Follow-up Query"',
                  'in chennai  (dynamically resolves without conversational bloat)',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Calendar Agenda"',
                  'What is on my calendar for tomorrow afternoon?',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Email Digest"',
                  'Check my unread emails from the last 24 hours and summarize anything urgent.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Meeting Schedule"',
                  'Schedule a meeting called "Sprint Retro" for Friday at 3 PM.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Local Task"',
                  'Add a task to my local list: "Review pull request #42 before EOD".',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Tagged Note"',
                  'Save a note tagged #meeting: Team agreed on adopting Qdrant for local vector indexing.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 1 (File Explorer): Vector DB & RAG Architecture ───────────────
  Widget _buildRagArchitectureTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Notice
          _buildNoticeBanner(
            theme: theme,
            text:
                'Why Vector RAG? Repositories are too large for an LLM context window. Local Vector RAG indexes your code offline using high-dimensional embeddings, allowing File Copilot to locate the exact relevant files and logic in milliseconds.',
            icon: Icons.hub_rounded,
            color: theme.accentFg,
            textColor: theme.isDark
                ? const Color(0xFF79C0FF)
                : const Color(0xFF0969DA),
          ),
          const SizedBox(height: 16),

          // 1. Why Do We Need a Vector DB?
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.borderDefault, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      size: 16,
                      color: theme.accentFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'WHY DO WE NEED A VECTOR DB IN FILE COPILOT?',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: theme.fgDefault,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildRagReasonItem(
                  theme,
                  icon: Icons.memory_rounded,
                  title: '1. Overcoming LLM Context Limitations',
                  desc:
                      'A typical codebase has 10,000+ lines of code. Local 3B or 7B models have finite context windows. Rather than passing entire directories, the Vector DB finds and provides only the 3-5 snippets needed.',
                ),
                const SizedBox(height: 8),
                _buildRagReasonItem(
                  theme,
                  icon: Icons.psychology_alt_rounded,
                  title: '2. Semantic Concept Matching vs. Keyword Grep',
                  desc:
                      'Standard "grep" only finds exact character matches. If you ask "Where is token verification handled?", grep fails if the code is named "def validate_session()". Vector search maps words by meaning, finding conceptual matches instantly.',
                ),
                const SizedBox(height: 8),
                _buildRagReasonItem(
                  theme,
                  icon: Icons.security_rounded,
                  title: '3. 100% Offline Air-Gapped Privacy',
                  desc:
                      'DeskMate uses an embedded Qdrant vector store located at ~/.deskmate/.qdrant_data with local FastEmbed in-memory embeddings. Zero code vectors or documents are ever uploaded to cloud servers.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. The 6-Step RAG Execution Flow
          Row(
            children: [
              Icon(Icons.route_rounded, size: 16, color: theme.accentFg),
              const SizedBox(width: 8),
              Text(
                'THE 6-STEP RAG EXECUTION FLOW',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgDefault,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildStepCard(
            theme: theme,
            stepNumber: '1',
            title: 'Document Ingestion & Text Chunking (index_document)',
            description:
                'When you index a file, DeskMate reads the content and splits it into 1,000-character segments with 200-character overlapping sliding windows to preserve syntax and avoid breaking functions midway.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Generating Dense Mathematical Embeddings (FastEmbed)',
            description:
                'Each chunk is converted by an in-memory local embedding model into a 384-dimensional dense numerical vector representing its semantic meaning in high-dimensional latent space.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '3',
            title: 'Local Vector Storage & Indexing (Qdrant)',
            description:
                'The vectors along with chunk metadata (source file path, line numbers) are stored in the local Qdrant collection named "local_documents".',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '4',
            title: 'User Query Vectorization',
            description:
                'When you ask a question like "Where are WebSocket events handled?", your query text is passed through the same local embedding model to produce a matching 384-dimensional vector.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '5',
            title: 'Cosine Similarity Search (search_qdrant)',
            description:
                'Qdrant performs mathematical Cosine Distance comparisons between your query vector and all chunk vectors, extracting the Top-3 closest code segments in under 5 milliseconds.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '6',
            title: 'Context Grounding & Local LLM Synthesis',
            description:
                'The retrieved code chunks are injected into your local Ollama prompt as verified ground truth. The local LLM synthesizes an accurate answer with exact file names and line references.',
          ),

          const SizedBox(height: 16),

          // 3. Command Examples Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.borderDefault, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRY RAG TOOLS IN CHAT:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.fgDefault,
                  ),
                ),
                const SizedBox(height: 8),
                _buildCopyableSnippet(
                  theme: theme,
                  text: 'Index this file into vector storage: backend.py',
                  keyId: 'rag_cmd_1',
                  label: 'Prompt',
                  copyButtonLabel: 'Copy',
                ),
                const SizedBox(height: 6),
                _buildCopyableSnippet(
                  theme: theme,
                  text:
                      'Search vector DB for where WebSocket messages are handled',
                  keyId: 'rag_cmd_2',
                  label: 'Prompt',
                  copyButtonLabel: 'Copy',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRagReasonItem(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: theme.accentFg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: theme.accentFg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.fgDefault,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── TAB 2 (File Explorer): File Copilot Tools Catalog ───────────────────
  Widget _buildFileCopilotToolsTab(ThemeData theme) {
    final tools = [
      {
        'name': 'read_file(file_path)',
        'desc':
            'Safely inspect source code and configuration files with automatic line numbering and encoding detection.',
        'icon': Icons.description_outlined,
      },
      {
        'name': 'write_to_file(file_path, content)',
        'desc':
            'Create or modify local files directly. Supports code generation, patch application, and atomic updates.',
        'icon': Icons.edit_note_rounded,
      },
      {
        'name': 'list_directory(directory_path)',
        'desc':
            'Explore directory contents, file hierarchies, and project architectures recursively or at the root level.',
        'icon': Icons.folder_open_rounded,
      },
      {
        'name': 'search_files(query, extension)',
        'desc':
            'Fast recursive pattern matching across file names and extensions in the current project or workspace.',
        'icon': Icons.search_rounded,
      },
      {
        'name': 'index_document(file_path)',
        'desc':
            'Chunks text documents and embeds them into the local Qdrant vector database using FastEmbed ONNX.',
        'icon': Icons.hub_outlined,
      },
      {
        'name': 'search_qdrant(query, limit)',
        'desc':
            'Performs offline semantic vector similarity search across previously indexed documents to answer questions.',
        'icon': Icons.saved_search_rounded,
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNoticeBanner(
            theme: theme,
            text:
                'All File Copilot tools execute 100% locally on your computer with zero external network transmission.',
            icon: Icons.shield_outlined,
            color: theme.statusOk,
            textColor: theme.successText,
          ),
          const SizedBox(height: 16),
          for (final t in tools) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.bgPanel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.accentFg.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      t['icon'] as IconData,
                      size: 16,
                      color: theme.accentFg,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['name'] as String,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.fgDefault,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          t['desc'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: theme.fgMuted,
                          ),
                        ),
                      ],
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

  // ─── TAB 3 (File Explorer): File Agent .env Configuration ────────────────
  Widget _buildFileEnvConfigTab(ThemeData theme) {
    const envTemplate =
        """# DeskMate File Explorer & Local LLM Environment Configuration
OLLAMA_BASE_URL=http://127.0.0.1:11434
LOCAL_MODEL_NAME=llama3.2
QDRANT_STORAGE_PATH=.qdrant_data
RAG_CHUNK_SIZE=1000
RAG_CHUNK_OVERLAP=200
""";
    final isCopied = _copiedKey == 'file_env_template';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'File Agent Environment Variables (.env)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.fgDefault,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You can configure custom Ollama host endpoints, local model names, and vector chunk parameters in deskmate_engine/.env:',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: theme.fgMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Template .env Configuration',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
              const Spacer(),
              InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _copy(
                  envTemplate,
                  'file_env_template',
                  'File .env template',
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCopied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 12,
                        color: isCopied ? theme.statusOk : theme.accentFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCopied ? 'Copied' : 'Copy Template',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isCopied ? theme.statusOk : theme.accentFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF0D1117)
                  : const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: SelectionArea(
              child: Text(
                envTemplate,
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
      ),
    );
  }

  // ─── TAB 4 (File Explorer): File Copilot Guide ──────────────────────────
  Widget _buildFileReadmeTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: theme.isDark
                    ? [const Color(0xFF1C2128), const Color(0xFF161B22)]
                    : [const Color(0xFFF0F7FF), const Color(0xFFE8F4FD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.accentFg.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.folder_special_rounded,
                    color: theme.accentFg,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File Explorer Copilot & Local LLM Guide',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Air-gapped, privacy-first coding assistant and local repository intelligence executing on your device via Ollama and FastEmbed vector RAG.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Architecture & Air-Gap Section
          Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 14,
                color: theme.accentFg,
              ),
              const SizedBox(width: 6),
              Text(
                'AIR-GAP & ARCHITECTURE GUARANTEES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingEngineRow(
            theme,
            icon: Icons.wifi_off_rounded,
            color: const Color(0xFF1F883D),
            label: '100% Offline Execution',
            badge: 'Local CPU / GPU',
            desc:
                'All model inference is processed on your local device by Ollama (http://127.0.0.1:11434). Zero internet required for inference.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.lock_rounded,
            color: const Color(0xFF0969DA),
            label: 'No Cloud Code Transmission',
            badge: '100% Air-Gapped',
            desc:
                'Your proprietary source files, sensitive configs, and tokens are never sent over the internet or logged to third-party providers.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.hub_rounded,
            color: const Color(0xFF8957E5),
            label: 'Embedded Vector Database',
            badge: 'Qdrant & FastEmbed',
            desc:
                'FastEmbed and Qdrant store codebase representations in ~/.deskmate/.qdrant_data with sub-second hybrid semantic search.',
          ),

          const SizedBox(height: 16),

          // Quick Terminal Setup Section
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'QUICK TERMINAL SETUP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildStepCard(
            theme: theme,
            stepNumber: '1',
            title: 'Install Ollama Locally',
            description:
                'Download and install Ollama for your operating system:',
            customContent: Column(
              children: [
                _buildCommandRow(
                  theme,
                  'macOS',
                  'brew install ollama',
                  'ollama_mac',
                ),
                const SizedBox(height: 6),
                _buildCommandRow(
                  theme,
                  'Linux',
                  'curl -fsSL https://ollama.com/install.sh | sh',
                  'ollama_linux',
                ),
                const SizedBox(height: 6),
                _buildCommandRow(
                  theme,
                  'Windows',
                  'https://ollama.com/download/windows',
                  'ollama_win',
                  isUrl: true,
                ),
              ],
            ),
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Pull Your Preferred Local Model',
            description:
                'Run any of the following models in your terminal to start coding immediately:',
            customContent: Column(
              children: [
                _buildCommandRow(
                  theme,
                  'Fast 3B (General)',
                  'ollama run llama3.2',
                  'model_llama',
                ),
                const SizedBox(height: 6),
                _buildCommandRow(
                  theme,
                  'Code 7B (Specialized)',
                  'ollama run qwen2.5-coder',
                  'model_qwen',
                ),
                const SizedBox(height: 6),
                _buildCommandRow(
                  theme,
                  'Reasoning 8B',
                  'ollama run deepseek-r1:8b',
                  'model_deepseek',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Workspace & Controls Section
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'WORKSPACE & CONTROLS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingInfoCard(
            theme,
            icon: Icons.view_sidebar_rounded,
            title: 'Draggable Resizable Sidebar',
            desc:
                'Drag the vertical splitter on the right edge of the sidebar to widen or narrow your view anytime (min 255px, max 450px). Double-click to reset.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.swap_horiz_rounded,
            title: 'Instant Model Switcher',
            desc:
                'When multiple Ollama models are installed, hot-swap between models instantly with zero application restart.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.settings_rounded,
            title: 'Settings Drawer (Gear Icon ⚙️)',
            desc:
                'Inspect FastAPI backend URL, verify local LLM engine status, and configure theme preferences with live telemetry.',
          ),

          const SizedBox(height: 16),

          // Smart Multi-Turn Section
          Row(
            children: [
              Icon(Icons.forum_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'ZERO-BLOAT MULTI-TURN EXPLORATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explore repositories conversationally without retyping long paths. Contextualizer resolves follow-ups locally in sub-80ms:',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.fgMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMultiTurnStep(
                  theme,
                  'Turn 1',
                  '"What files are in the core directory?"',
                  'Lists directory contents.',
                ),
                _buildMultiTurnStep(
                  theme,
                  'Turn 2',
                  '"and in services?"',
                  'Auto-resolved to: "What files are in the services directory?"',
                ),
                _buildMultiTurnStep(
                  theme,
                  'Turn 3',
                  '"read telemetry.py"',
                  'Auto-resolved to: "Read the content of telemetry.py"',
                ),
                _buildMultiTurnStep(
                  theme,
                  'Turn 4',
                  '"what is inside it?"',
                  'Auto-resolved to: "Explain the implementation in telemetry.py"',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Supported Code & Text Formats
          Row(
            children: [
              Icon(Icons.code_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'SUPPORTED CODE & TEXT FORMATS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File Copilot supports reading, editing, and semantic indexing for:',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.fgMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildFormatBadge(
                      theme,
                      'Python (.py)',
                      const Color(0xFF8957E5),
                    ),
                    _buildFormatBadge(
                      theme,
                      'Dart / Flutter (.dart)',
                      const Color(0xFF0969DA),
                    ),
                    _buildFormatBadge(
                      theme,
                      'TypeScript / JavaScript',
                      const Color(0xFFD29922),
                    ),
                    _buildFormatBadge(
                      theme,
                      'Rust (.rs)',
                      const Color(0xFFCF222E),
                    ),
                    _buildFormatBadge(
                      theme,
                      'Go (.go)',
                      const Color(0xFF1F883D),
                    ),
                    _buildFormatBadge(
                      theme,
                      'C / C++ (.c, .cpp)',
                      const Color(0xFF0969DA),
                    ),
                    _buildFormatBadge(
                      theme,
                      'SQL (.sql)',
                      const Color(0xFF8957E5),
                    ),
                    _buildFormatBadge(
                      theme,
                      'JSON / YAML / TOML',
                      const Color(0xFF57606A),
                    ),
                    _buildFormatBadge(
                      theme,
                      'Markdown (.md)',
                      const Color(0xFF1F883D),
                    ),
                    _buildFormatBadge(
                      theme,
                      'HTML / CSS',
                      const Color(0xFFD29922),
                    ),
                    _buildFormatBadge(
                      theme,
                      'Environment (.env)',
                      const Color(0xFFCF222E),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Example Prompts Section
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'EXAMPLE FILE COPILOT PROMPTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildExampleInquiry(
                  theme,
                  '"Directory Listing"',
                  'What files are in the core directory?',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Follow-up Exploration"',
                  'and in services?  (dynamically resolves without conversational bloat)',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Code Inspection"',
                  'read telemetry.py and explain how streaming works.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Repository Layout"',
                  'List all files in the current repository and show the folder layout.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Router Search"',
                  'Search for all files defining API routers.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Vector Indexing"',
                  'Index backend.py into Qdrant vector database.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Semantic RAG Search"',
                  'Search the vector DB for how local LLM tags are discovered.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── MEETING SCRIBE TABS ───────────────────────────────────────────────────

  Widget _buildMeetingQuickStartTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: theme.isDark
                    ? [const Color(0xFF1C2128), const Color(0xFF161B22)]
                    : [const Color(0xFFF0F7FF), const Color(0xFFE8F4FD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.accentFg.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentFg.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    color: theme.accentFg,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meeting Scribe & Audio Intelligence',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Enterprise-grade live visual & audio intelligence. Runs 100% on your local machine.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Neural Architecture Section
          Row(
            children: [
              Icon(Icons.psychology_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'CORE NEURAL PIPELINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingEngineRow(
            theme,
            icon: Icons.graphic_eq_rounded,
            color: const Color(0xFF8957E5),
            label: 'Mistral Voxtral 4B',
            badge: 'Speech Extraction',
            desc:
                'Native speaker diarization — no Whisper dependency. Runs in-memory on MPS/CUDA.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.grid_on_rounded,
            color: const Color(0xFF1F883D),
            label: 'NVIDIA LocateAnything-3B',
            badge: 'Live GUI Grounding',
            desc:
                'Runs during live recording: Sub-second UI element localization and bounding-box coordinates for clicks, slides, and dialogs via Parallel Box Decoding (PBD).',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.visibility_rounded,
            color: const Color(0xFFD97706),
            label: 'Llama 3.2 Vision (Ollama)',
            badge: 'Local Vision (Compulsory if No API Key)',
            desc:
                'Runs post-recording for 100% offline vision synthesis. Required before recording unless a Gemini API key is configured.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.auto_awesome_rounded,
            color: theme.accentFg,
            label: 'Gemini 1.5 Flash (Cloud Alternative)',
            badge: 'Zero Local Vision Needed',
            desc:
                'If you add a Google Gemini API Key in Settings, cloud multimodal vision is used natively—llama3.2-vision is NOT required.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.headphones_rounded,
            color: const Color(0xFF0969DA),
            label: 'macOS Loopback + Mic',
            badge: 'Audio Routing',
            desc:
                'Simultaneous earphone loopback + microphone capture at native 16,000 Hz Mono PCM.',
          ),
          _buildMeetingEngineRow(
            theme,
            icon: Icons.block_rounded,
            color: const Color(0xFFCF222E),
            label: 'Real-Time Buffer Gating',
            badge: 'Room Noise Block',
            desc:
                'When mic is muted, buffer frames are zeroed at hardware level. Room chatter cannot enter the recording.',
          ),

          const SizedBox(height: 16),

          // Quick Start Steps
          Row(
            children: [
              Icon(
                Icons.rocket_launch_rounded,
                size: 14,
                color: theme.accentFg,
              ),
              const SizedBox(width: 6),
              Text(
                'QUICK START',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildStepCard(
            theme: theme,
            stepNumber: '1',
            title: 'Add Custom Focus Topics (Optional)',
            description:
                'Before starting, click "Add Inquiry / Column" to track specific topics like "Engineering Roadblocks", "Budget Decisions", or "Actions for Sarah". Each topic becomes a dedicated section in your summary.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Verify Vision & Start Meeting Scribe',
            description:
                'Ensure either "llama3.2-vision" is active in Ollama or a Google Gemini API Key is saved in Settings. Click "Start Meeting Scribe" to begin.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '3',
            title: 'Control Room Noise with Mic Toggle',
            description:
                'Use the Mic Active / Mic Muted button in the header:\n• Mic Active (green): User voice is mixed with earphone audio.\n• Mic Muted (orange): Surrounding room chatter and background noise are mathematically zeroed. Attendee audio from earphones continues recording cleanly.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '4',
            title: 'End Meeting & Agentic Telemetry Processing',
            description:
                'Click End Meeting. Watch the live 4-phase agentic stepper as DeskMate normalizes audio, runs Voxtral 4B diarization, performs multimodal OCR synthesis, and compiles an executive PDF report ready for export.',
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingEngineRow(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String label,
    required String badge,
    required String desc,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: color.withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingDriveExportTab(
    ThemeData theme,
    bool hasDrive,
    bool hasCreds,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Banner
          _buildGoogleConfigBanner(
            theme: theme,
            isOnline: hasDrive,
            onlineTitle: 'Google Drive: Online & Ready',
            offlineTitle: 'Google Drive: Not Configured (Offline)',
            onlineDesc:
                'Your Google Drive OAuth token is verified. One-click export uploads full meeting PDFs to your Google Drive automatically.',
            offlineDesc:
                'Google Drive is offline. Configure your Google OAuth credentials in the Personal Guide to enable one-click cloud PDF export.',
            icon: Icons.add_to_drive_rounded,
          ),

          const SizedBox(height: 16),

          // Section: How it Works
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'HOW DRIVE EXPORT WORKS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildStepCard(
            theme: theme,
            stepNumber: '1',
            title: 'Shared Google OAuth Credentials',
            description:
                'Meeting Scribe reuses the same credentials.json and OAuth tokens as the Personal Assistant. You do not need a separate Google Cloud project for meeting exports.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Dedicated "DeskMate Meeting Summaries" Folder',
            description:
                'On first export, DeskMate automatically creates a folder named "DeskMate Meeting Summaries" in your Google Drive root. All subsequent meeting PDFs are organized there.',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '3',
            title: 'Multi-Page Executive PDF Contents',
            description:
                'The exported PDF includes:\n• Complete executive summary and meeting takeaways\n• High-resolution visual screenshots with LocateAnything-3B bounding boxes\n• Diarized speaker transcript with exact timestamps\n• Action items checklist with assignees and due dates',
          ),
          _buildStepCard(
            theme: theme,
            stepNumber: '4',
            title: 'Instant Shareable Link',
            description:
                'Once uploaded, DeskMate generates a direct shareable Google Drive link so you can immediately share the report with meeting stakeholders.',
          ),

          const SizedBox(height: 4),

          // OAuth Scope Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: theme.accentFg),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Required Google OAuth Scope',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'drive.file',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: theme.accentFg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Allows DeskMate to create and upload meeting PDFs without access to your entire Drive.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasDrive) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _currentMode = AgentMode.personal;
                      _selectedTabIndex = 0;
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentFg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Setup OAuth'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingGmailDispatchTab(
    ThemeData theme,
    bool hasGmail,
    bool hasCreds,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Banner
          _buildGoogleConfigBanner(
            theme: theme,
            isOnline: hasGmail,
            onlineTitle: 'Gmail: Online & Ready',
            offlineTitle: 'Gmail: Not Configured (Offline)',
            onlineDesc:
                'Gmail integration is live. Email formatted executive summaries, diarized transcripts, and action items directly to attendees with one click.',
            offlineDesc:
                'Gmail is offline. Set up your Google Workspace credentials in the Personal Guide to enable automated meeting email dispatch.',
            icon: Icons.mark_email_read_rounded,
          ),

          const SizedBox(height: 16),

          // Section: Email Contents
          Row(
            children: [
              Icon(Icons.drafts_outlined, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'AUTOMATED EMAIL FORMAT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildMeetingInfoCard(
            theme,
            icon: Icons.table_rows_outlined,
            title: 'Dynamic Executive Briefing',
            desc:
                'Real-time meeting synopsis, key decisions, and prioritized action items synthesized dynamically from screen interactions and Voxtral 4B diarized audio.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.badge_outlined,
            title: 'Sender Attribution & Designation',
            desc:
                'Dispatched directly from your connected Gmail address, prominently displaying your verified Name, official Designation / Role, and contact email.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.hide_image_outlined,
            title: 'Application Screenshot Redaction',
            desc:
                'DeskMate automatically detects and filters out its own host application windows and UI dialogs, ensuring only external meeting slides, tools, and code are captured.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.workspace_premium_outlined,
            title: 'Open Source & LinkedIn Branding',
            desc:
                'Responsive HTML layout featuring DeskMate AI signature branding, Ganesh Venkatesan creator attribution, and direct LinkedIn profile badge verification.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.picture_as_pdf_rounded,
            title: 'Properly-Named PDF Attachment',
            desc:
                'Multi-page executive report attached with professional formatting (e.g. DeskMate_Executive_Meeting_Report_YYYY-MM-DD.pdf).',
          ),

          const SizedBox(height: 4),

          // Security & Scopes
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outlined, size: 13, color: theme.accentFg),
                    const SizedBox(width: 6),
                    Text(
                      'Security & OAuth Scopes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildOAuthScopeRow(
                  theme,
                  'gmail.send',
                  'Send summary emails directly via your Google account.',
                ),
                const SizedBox(height: 4),
                _buildOAuthScopeRow(
                  theme,
                  'gmail.readonly',
                  'Optional: look up attendee email addresses for auto-fill.',
                ),
                const SizedBox(height: 6),
                Text(
                  'Emails are never proxied through third-party servers. Zero hallucination dispatch — emails only send when you confirm.',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                    color: theme.fgMuted,
                  ),
                ),
                if (!hasGmail) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() {
                        _currentMode = AgentMode.personal;
                        _selectedTabIndex = 0;
                      }),
                      icon: const Icon(Icons.vpn_key_rounded, size: 14),
                      label: const Text('Configure OAuth in Personal Guide'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentFg,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingAudioGatingTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0969DA).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF0969DA).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0969DA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: Color(0xFF0969DA),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'macOS Audio Loopback & Room Noise Gating',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Captures earphone audio from remote attendees while mathematically blocking ambient room noise when muted.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Section 1: Loopback
          _buildMeetingSection(
            theme,
            '1',
            Icons.router_rounded,
            'Automated System Audio (Earphone Loopback)',
            const Color(0xFF0969DA),
          ),
          const SizedBox(height: 8),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.settings_input_composite_rounded,
            title: 'Virtual Loopback Devices',
            desc:
                'DeskMate scans for BlackHole 2ch, Loopback (Rogue Amoeba), or custom Aggregate Devices to capture system/earphone audio.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.device_hub_rounded,
            title: 'Native Hardware Fallback',
            desc:
                'If no virtual loopback driver is found, falls back cleanly to the default macOS system input with no configuration needed.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.graphic_eq_rounded,
            title: 'Target Specification',
            desc:
                'Records at native 16,000 Hz, 16-bit Mono PCM — matching Voxtral 4B training weights for zero-resampling, maximum accuracy.',
          ),

          const SizedBox(height: 12),

          // Section 2: Mic Gating
          _buildMeetingSection(
            theme,
            '2',
            Icons.mic_off_rounded,
            'Real-Time Microphone Gating (Room Noise Rejection)',
            const Color(0xFFCF222E),
          ),
          const SizedBox(height: 8),

          // State table as structured cards
          Container(
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              children: [
                _buildMicStateRow(
                  theme,
                  isActive: true,
                  label: 'Mic Active',
                  badge: 'Earphones + Microphone',
                  desc:
                      'User speech is recorded and diarized alongside remote attendee audio.',
                ),
                Divider(height: 1, color: theme.borderDefault),
                _buildMicStateRow(
                  theme,
                  isActive: false,
                  label: 'Mic Muted',
                  badge: 'Earphone Audio Only',
                  desc:
                      'Microphone buffer frames are zeroed at hardware level. Room chatter, background music, and echo CANNOT enter the recording.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Section 3: DeskMate Noise Filter
          _buildMeetingSection(
            theme,
            '3',
            Icons.filter_alt_rounded,
            'DeskMate Host App Noise Filtering',
            const Color(0xFF8957E5),
          ),
          const SizedBox(height: 8),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.timer_outlined,
            title: '2.0-Second Grace Period',
            desc:
                'When you click "Start Meeting Scribe" inside DeskMate, recording is suppressed for the first 2 seconds so DeskMate UI interactions are never captured.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.filter_list_rounded,
            title: 'Heuristic Keyword Filter',
            desc:
                'DeskMate UI clicks ("Meeting Scribe", "End Meeting", "Mic Muted") and macOS Dock / Alt-Tab switcher frames are automatically rejected from visual moments and transcripts.',
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingMasterReferenceTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.borderDefault, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.accentFg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.api_rounded,
                    color: theme.accentFg,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meeting Scribe REST API',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'All endpoints are available at http://127.0.0.1:2026 (port-forwarded from backend :8080).',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // API Endpoints
          Row(
            children: [
              Icon(
                Icons.cloud_circle_outlined,
                size: 14,
                color: theme.accentFg,
              ),
              const SizedBox(width: 6),
              Text(
                'REST ENDPOINTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildApiEndpointCard(
            theme,
            method: 'POST',
            endpoint: '/api/meeting/start',
            title: 'Start Meeting Recording',
            description:
                'Launches non-blocking screen capture (MSS at 2.0 FPS) and initializes the 8-stage computer vision detection thread.',
            curlCommand:
                'curl -X POST "http://127.0.0.1:2026/api/meeting/start" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"monitor": 1, "fps": 2.0}\'',
            responseJson:
                '{\n  "status": "recording",\n  "session_id": "20261020_113000",\n  "fps": 2.0,\n  "monitor": 1\n}',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'GET',
            endpoint: '/api/meeting/status',
            title: 'Live Telemetry Metrics',
            description:
                'Returns real-time recording metrics including session uptime, total frames processed, unique events detected, and steps count. Polled by the UI timer card every second.',
            curlCommand:
                'curl -X GET "http://127.0.0.1:2026/api/meeting/status"',
            responseJson:
                '{\n  "state": "running",\n  "session_id": "20261020_113000",\n  "uptime_seconds": 124.5,\n  "frames_processed": 248,\n  "frames_skipped": 192,\n  "events_detected": 14,\n  "steps_count": 5\n}',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'POST',
            endpoint: '/api/meeting/mute',
            title: 'Mic Mute Gating',
            description:
                'Toggles real-time microphone audio capture. When muted, silence is piped into the audio pipeline to protect confidential room discussions.',
            curlCommand:
                'curl -X POST "http://127.0.0.1:2026/api/meeting/mute" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"muted": true}\'',
            responseJson: '{\n  "status": "success",\n  "muted": true\n}',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'POST',
            endpoint: '/api/meeting/stop',
            title: 'Finalize Session Recording',
            description:
                'Halts screen capture, joins consumer threads, finalizes chronological steps in StepBuilder, and saves session_{session_id}.json.',
            curlCommand:
                'curl -X POST "http://127.0.0.1:2026/api/meeting/stop"',
            responseJson:
                '{\n  "status": "completed",\n  "session_id": "20261020_113000",\n  "steps_count": 6,\n  "duration_seconds": 132.8\n}',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'POST',
            endpoint: '/api/meeting/summarize',
            title: 'Multimodal Summarization & PDF',
            description:
                'Executes the multimodal reasoning pipeline: Voxtral 4B speaker diarization, LocateAnything-3B vision grounding, Gemini / Ollama timeline fusion, and executive PDF generation.',
            curlCommand:
                'curl -X POST "http://127.0.0.1:2026/api/meeting/summarize" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"session_id": "20261020_113000", "purge_raw_assets_after": true}\'',
            responseJson:
                '{\n  "session_id": "20261020_113000",\n  "summary": "### Executive Overview\\nDiscussed Q4 roadmap and architecture...",\n  "important_steps": ["step_1", "step_4"],\n  "pdf_generated": true,\n  "pdf_url": "/api/meeting/pdf/20261020_113000"\n}',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'GET',
            endpoint: '/api/meeting/pdf/{session_id}',
            title: 'Download Compiled Meeting PDF',
            description:
                'Streams the compiled DeskMate executive PDF report directly to the client for local viewing, archival, or sharing.',
            curlCommand:
                'curl -X GET "http://127.0.0.1:2026/api/meeting/pdf/20261020_113000" -O',
            responseJson:
                '// Binary Application/PDF Stream\n// Saved as: deskmate_report_20261020_113000.pdf',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'POST',
            endpoint: '/api/meeting/export-drive',
            title: 'Upload to Google Drive',
            description:
                'Automatically locates or creates "DeskMate Meeting Summaries" folder in Google Drive root, uploads the executive PDF report, and returns a direct shareable link.',
            curlCommand:
                'curl -X POST "http://127.0.0.1:2026/api/meeting/export-drive" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"session_id": "20261020_113000"}\'',
            responseJson:
                '{\n  "status": "success",\n  "file_id": "1A2B3C4D5E...",\n  "file_name": "DeskMate_Report_20261020_113000.pdf",\n  "view_link": "https://drive.google.com/file/d/1A2B3C4D5E.../view"\n}',
          ),
          _buildApiEndpointCard(
            theme,
            method: 'POST',
            endpoint: '/api/meeting/send-email',
            title: 'Email Summary & PDF Dispatch',
            description:
                'Dispatches dynamic executive debrief via Gmail API with author name, designation, sender email, and properly-named attached PDF report.',
            curlCommand:
                'curl -X POST "http://127.0.0.1:2026/api/meeting/send-email" \\\n  -H "Content-Type: application/json" \\\n  -d \'{\n    "session_id": "20261020_113000",\n    "to_email": "team@example.com",\n    "user_name": "Ganesh Venkatesan",\n    "designation": "Lead Architect",\n    "sender_email": "user@gmail.com"\n  }\'',
            responseJson:
                '{\n  "status": "success",\n  "message_id": "18f2d5e9b7a4c102",\n  "recipient": "team@example.com",\n  "sender": "\\"Ganesh Venkatesan (Lead Architect)\\" <user@gmail.com>",\n  "pdf_name": "DeskMate_Executive_Meeting_Report_2026-10-20.pdf"\n}',
          ),

          const SizedBox(height: 14),

          // Custom Columns
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'CUSTOM FOCUS INQUIRIES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add inquiry columns before starting a session to track specific topics:',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.fgMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _buildExampleInquiry(
                  theme,
                  '"Technical Blockers"',
                  'Extract any mentioned timeline delays or server capacity constraints.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Budget Approval"',
                  'Identify any numbers, approvals, or sign-off decisions discussed.',
                ),
                _buildExampleInquiry(
                  theme,
                  '"Actions for Sarah"',
                  'List all tasks or follow-ups assigned to or mentioned for Sarah.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // macOS Permissions
          Row(
            children: [
              Icon(Icons.security_rounded, size: 14, color: theme.accentFg),
              const SizedBox(width: 6),
              Text(
                'MACOS PERMISSIONS REQUIRED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.screen_share_rounded,
            title: 'Screen & System Audio Recording',
            desc:
                'System Settings > Privacy & Security > Screen Recording. Grant access to DeskMate to enable visual frame capture.',
          ),
          _buildMeetingInfoCard(
            theme,
            icon: Icons.mic_rounded,
            title: 'Microphone Access',
            desc:
                'System Settings > Privacy & Security > Microphone. Grant access to DeskMate to capture user voice for speaker diarization.',
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleConfigBanner({
    required ThemeData theme,
    required bool isOnline,
    required String onlineTitle,
    required String offlineTitle,
    required String onlineDesc,
    required String offlineDesc,
    required IconData icon,
  }) {
    final color = isOnline ? theme.statusOk : const Color(0xFFCF222E);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isOnline ? onlineTitle : offlineTitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: theme.isDark
                              ? (isOnline
                                    ? const Color(0xFF7EE787)
                                    : const Color(0xFFFFA198))
                              : color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isOnline ? onlineDesc : offlineDesc,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingInfoCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: theme.accentFg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingSection(
    ThemeData theme,
    String number,
    IconData icon,
    String title,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.fgDefault,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMicStateRow(
    ThemeData theme, {
    required bool isActive,
    required String label,
    required String badge,
    required String desc,
  }) {
    final color = isActive ? theme.statusOk : const Color(0xFFCF222E);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: color.withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleInquiry(
    ThemeData theme,
    String name,
    String instruction,
  ) {
    final keyId = 'inquiry_${name}_${instruction.hashCode}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.label_outline_rounded, size: 12, color: theme.accentFg),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$name  ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: theme.fgDefault,
                    ),
                  ),
                  TextSpan(
                    text: instruction,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.fgMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _copy(instruction, keyId, name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _copiedKey == keyId
                        ? Icons.check_rounded
                        : Icons.copy_rounded,
                    size: 11,
                    color: _copiedKey == keyId
                        ? theme.statusOk
                        : theme.accentFg,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _copiedKey == keyId ? 'Copied' : 'Copy',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _copiedKey == keyId
                          ? theme.statusOk
                          : theme.accentFg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandRow(
    ThemeData theme,
    String label,
    String command,
    String keyId, {
    bool isUrl = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.accentFg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: theme.accentFg,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              command,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: theme.isDark
                    ? const Color(0xFF7EE787)
                    : const Color(0xFF116329),
              ),
            ),
          ),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _copy(command, keyId, label),
            child: Row(
              children: [
                Icon(
                  _copiedKey == keyId
                      ? Icons.check_rounded
                      : (isUrl
                            ? Icons.open_in_new_rounded
                            : Icons.copy_rounded),
                  size: 11,
                  color: _copiedKey == keyId ? theme.statusOk : theme.accentFg,
                ),
                const SizedBox(width: 4),
                Text(
                  _copiedKey == keyId ? 'Copied' : (isUrl ? 'Open' : 'Copy'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _copiedKey == keyId
                        ? theme.statusOk
                        : theme.accentFg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiTurnStep(
    ThemeData theme,
    String step,
    String prompt,
    String resolution,
  ) {
    final cleanPrompt = prompt.replaceAll('"', '');
    final keyId = 'step_${step}_${cleanPrompt.hashCode}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.accentFg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.accentFg.withValues(alpha: 0.35),
                width: 0.6,
              ),
            ),
            child: Text(
              step,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: theme.accentFg,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$prompt  ➔  ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.fgDefault,
                    ),
                  ),
                  TextSpan(
                    text: resolution,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.fgMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _copy(cleanPrompt, keyId, step),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _copiedKey == keyId
                        ? Icons.check_rounded
                        : Icons.copy_rounded,
                    size: 11,
                    color: _copiedKey == keyId
                        ? theme.statusOk
                        : theme.accentFg,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _copiedKey == keyId ? 'Copied' : 'Copy',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _copiedKey == keyId
                          ? theme.statusOk
                          : theme.accentFg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatBadge(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: theme.isDark ? color.withValues(alpha: 0.9) : color,
        ),
      ),
    );
  }

  Widget _buildApiEndpointCard(
    ThemeData theme, {
    required String method,
    required String endpoint,
    required String title,
    required String description,
    String? curlCommand,
    String? responseJson,
  }) {
    final isPost = method == 'POST';
    final methodColor = isPost
        ? const Color(0xFF8957E5)
        : const Color(0xFF0969DA);
    final keyId = 'curl_$endpoint';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.borderDefault, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF1C2128)
                  : const Color(0xFFF6F8FA),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(color: theme.borderDefault, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: methodColor.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    method,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: methodColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  endpoint,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.fgDefault,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '— $title',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: theme.fgMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.fgDefault,
                  ),
                ),
                if (curlCommand != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CURL REQUEST',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: theme.fgMuted,
                        ),
                      ),
                      InkWell(
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => _copy(curlCommand, keyId, 'cURL command'),
                        child: Row(
                          children: [
                            Icon(
                              _copiedKey == keyId
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                              size: 11,
                              color: _copiedKey == keyId
                                  ? theme.statusOk
                                  : theme.accentFg,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _copiedKey == keyId ? 'Copied' : 'Copy cURL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _copiedKey == keyId
                                    ? theme.statusOk
                                    : theme.accentFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? const Color(0xFF0D1117)
                          : const Color(0xFFF6F8FA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.borderDefault,
                        width: 0.8,
                      ),
                    ),
                    child: SelectableText(
                      curlCommand,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                        color: theme.isDark
                            ? const Color(0xFF7EE787)
                            : const Color(0xFF116329),
                      ),
                    ),
                  ),
                ],
                if (responseJson != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'SAMPLE RESPONSE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: theme.fgMuted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? const Color(0xFF0D1117)
                          : const Color(0xFFF6F8FA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.borderDefault,
                        width: 0.8,
                      ),
                    ),
                    child: SelectableText(
                      responseJson,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                        color: theme.isDark
                            ? const Color(0xFF79C0FF)
                            : const Color(0xFF0550AE),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthScopeRow(ThemeData theme, String scope, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.accentFg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            scope,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: theme.accentFg,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            desc,
            style: TextStyle(fontSize: 11, height: 1.35, color: theme.fgMuted),
          ),
        ),
      ],
    );
  }
}
