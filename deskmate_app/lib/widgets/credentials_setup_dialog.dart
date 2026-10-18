import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class CredentialsSetupDialog extends StatefulWidget {
  final VoidCallback onClose;
  final AgentMode mode;

  const CredentialsSetupDialog({
    super.key,
    required this.onClose,
    this.mode = AgentMode.personal,
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
        if (creds['configured'] == true && creds['client_id'] != null) {
          if (mounted && _clientIdController.text.isEmpty) {
            _clientIdController.text = creds['client_id'].toString();
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
    Clipboard.setData(ClipboardData(text: text));
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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        width: 260,
      ),
    );
  }

  Future<void> _launchExternalUrl(String url, String label) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opened $label in default web browser.'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            width: 320,
          ),
        );
      }
    } catch (_) {
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
            child: Text(
              text,
              style: TextStyle(
                fontFamily: isMonospace ? 'monospace' : null,
                fontSize: 11,
                color: textColor ?? theme.fgDefault,
              ),
            ),
          ),
          InkWell(
            onTap: () => _copy(text, keyId, label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    isCopied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 12,
                    color: isCopied ? const Color(0xFF2DA44E) : theme.accentFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isCopied ? 'Copied' : (copyButtonLabel ?? 'Copy'),
                    style: TextStyle(
                      fontSize: 10,
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
                            isPersonal
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
                            isPersonal
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
                            title: 'Personal Guide',
                            icon: Icons.person_rounded,
                            isSelected: isPersonal,
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
                            title: 'File Copilot & LLM',
                            icon: Icons.folder_open_rounded,
                            isSelected: !isPersonal,
                            onTap: () {
                              if (_currentMode != AgentMode.deskMate) {
                                setState(() {
                                  _currentMode = AgentMode.deskMate;
                                  _selectedTabIndex = 0;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
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
                    IconButton(
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: theme.fgMuted,
                      ),
                      hoverColor: theme.bgEmphasis,
                      splashRadius: 18,
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
                      if (isPersonal) ...[
                        _buildStatusPill(
                          theme,
                          'OAuth',
                          hasCreds ? 'Configured' : 'Missing',
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
                          provider.isLocalLlmOnline ? 'Online' : 'Offline',
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
              Divider(height: 1, color: theme.borderDefault),

              // ─── Navigation Tabs ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.isDark ? theme.bgCanvas : Colors.white,
                  border: Border(
                    bottom: BorderSide(color: theme.borderDefault, width: 1),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (isPersonal) ...[
                        _buildTabButton(0, '🚀 Quick Setup', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(1, '🔑 GCP OAuth Guide', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(2, '🔒 Offline Tools & SQLite', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(3, '⚙️ .env Configuration', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(
                          4,
                          '📖 Personal Assistant Guide',
                          theme,
                        ),
                      ] else ...[
                        _buildTabButton(0, '🦙 Ollama & Model Setup', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(1, '🧠 Vector DB & RAG Flow', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(2, '📁 File Copilot Tools', theme),
                        const SizedBox(width: 6),
                        _buildTabButton(
                          3,
                          '⚙️ File Agent Configuration',
                          theme,
                        ),
                        const SizedBox(width: 6),
                        _buildTabButton(4, '📖 File Copilot Guide', theme),
                      ],
                    ],
                  ),
                ),
              ),

              // ─── Tab Content Body ────────────────────────────────────────
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex.clamp(0, 4),
                  children: isPersonal
                      ? [
                          _buildQuickSetupTab(theme),
                          _buildGcpGuideTab(theme),
                          _buildOfflineToolsTab(theme),
                          _buildEnvConfigTab(theme),
                          _buildPersonalReadmeTab(theme),
                        ]
                      : [
                          _buildFileAgentGuideTab(theme),
                          _buildRagArchitectureTab(theme),
                          _buildFileCopilotToolsTab(theme),
                          _buildFileEnvConfigTab(theme),
                          _buildFileReadmeTab(theme),
                        ],
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
                    ElevatedButton(
                      onPressed: widget.onClose,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentFg,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
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
                  ],
                ),
              ),
            ],
          ),
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

  Widget _buildTabButton(int index, String title, ThemeData theme) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.accentFg.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: theme.accentFg.withValues(alpha: 0.4),
                  width: 1,
                )
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? theme.accentFg : theme.fgMuted,
          ),
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
              color: theme.isDark
                  ? const Color(0xFF161B22)
                  : const Color(0xFFF6F8FA),
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
                ElevatedButton.icon(
                  onPressed: () => setState(() => _selectedTabIndex = 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                  label: const Text('Open Guide'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentFg,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
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
              color: theme.isDark
                  ? const Color(0xFF161B22)
                  : const Color(0xFFF6F8FA),
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
        color: theme.isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
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
                          : (isLlmOnline
                                ? const Color(0xFF2DA44E)
                                : theme.dangerFg))
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    (isGemini
                            ? theme.accentFg
                            : (isLlmOnline
                                  ? const Color(0xFF2DA44E)
                                  : theme.dangerFg))
                        .withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Icon(
              isGemini ? Icons.cloud_done_rounded : Icons.memory_rounded,
              color: isGemini
                  ? theme.accentFg
                  : (isLlmOnline ? const Color(0xFF2DA44E) : theme.dangerFg),
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
                      isGemini ? 'Gemini 2.5 Flash' : modelName,
                      style: TextStyle(
                        fontFamily: isGemini ? null : 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isGemini
                            ? theme.accentFg
                            : (theme.isDark
                                  ? const Color(0xFF7EE787)
                                  : const Color(0xFF1A7F37)),
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
          OutlinedButton.icon(
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
            actionButton: OutlinedButton.icon(
              onPressed: () => _launchExternalUrl(
                'https://console.cloud.google.com/',
                'Google Cloud Console',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 12),
              label: const Text('Open Console'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accentFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ),
          ),

          // Step 2
          _buildStepCard(
            theme: theme,
            stepNumber: '2',
            title: 'Enable Required Google Workspace APIs',
            description:
                'Under "APIs & Services" > "Library", search for and enable these 4 essential Google Workspace APIs:',
            actionButton: OutlinedButton.icon(
              onPressed: () => _launchExternalUrl(
                'https://console.cloud.google.com/apis/library',
                'API Library',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 12),
              label: const Text('Open Library'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accentFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                ],
              ),
            ),
          ),

          // Step 3
          _buildStepCard(
            theme: theme,
            stepNumber: '3',
            title: 'Configure OAuth Consent Screen',
            description:
                'Go to "APIs & Services" > "OAuth consent screen" to configure permissions for your user account:',
            actionButton: OutlinedButton.icon(
              onPressed: () => _launchExternalUrl(
                'https://console.cloud.google.com/apis/credentials/consent',
                'Consent Screen',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 12),
              label: const Text('Open Consent'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accentFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                    'User Type:',
                    'Select "External" (free for personal use, no Google Workspace domain required).',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    'App Information:',
                    'Set App Name to "DeskMate" and enter your email for Developer Contact.',
                  ),
                  const SizedBox(height: 5),
                  _buildBulletPoint(
                    theme,
                    'Test Users (Crucial):',
                    'Under "Test users", click "+ Add Users" and enter your Google account email. DeskMate needs this permission while in development mode.',
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
                'Go to "APIs & Services" > "Credentials" > "+ Create Credentials" > "OAuth client ID".',
            actionButton: OutlinedButton.icon(
              onPressed: () => _launchExternalUrl(
                'https://console.cloud.google.com/apis/credentials',
                'Credentials Page',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 12),
              label: const Text('Open Credentials'),
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
                        'Select "Desktop App" (NOT Web Application or iOS/Android).',
                      ),
                      const SizedBox(height: 5),
                      _buildBulletPoint(
                        theme,
                        'Name:',
                        'Enter "DeskMate Client" and click "Create".',
                      ),
                      const SizedBox(height: 5),
                      _buildBulletPoint(
                        theme,
                        'Generated Keys:',
                        'Google Cloud will display your Client ID and Client Secret.',
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
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedTabIndex = 0;
                          _isEditing = true;
                        });
                      },
                      icon: const Icon(Icons.input_rounded, size: 14),
                      label: const Text('Enter Keys in Quick Setup Tab →'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentFg,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
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
                        const SizedBox(width: 4),
                        Text(
                          'OR configure in Settings Drawer (⚙️ ➔ Google Workspace OAuth)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.accentFg,
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
                color: const Color(0xFF2DA44E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF2DA44E).withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 13,
                    color: Color(0xFF2DA44E),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Automatic',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.isDark
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF1A7F37),
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
              color: theme.isDark
                  ? const Color(0xFF161B22)
                  : const Color(0xFFF6F8FA),
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
                        color:
                            (isLlmOnline
                                    ? const Color(0xFF2DA44E)
                                    : theme.dangerFg)
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              (isLlmOnline
                                      ? const Color(0xFF2DA44E)
                                      : theme.dangerFg)
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
                                  ? const Color(0xFF2DA44E)
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
                                  ? (theme.isDark
                                        ? const Color(0xFF7EE787)
                                        : const Color(0xFF1A7F37))
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
                color: const Color(0xFF2DA44E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF2DA44E).withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 13,
                    color: Color(0xFF2DA44E),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Auto-Configured',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.isDark
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF1A7F37),
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
                        child: RichText(
                          text: TextSpan(
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
                          color: const Color(
                            0xFF2DA44E,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: Color(0xFF2DA44E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
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
                onTap: () => _copy(cmd, keyId, 'Command'),
                child: Row(
                  children: [
                    Icon(
                      _copiedKey == keyId
                          ? Icons.check_rounded
                          : Icons.copy_rounded,
                      size: 12,
                      color: _copiedKey == keyId
                          ? const Color(0xFF2DA44E)
                          : theme.accentFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _copiedKey == keyId ? 'Copied' : 'Copy',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _copiedKey == keyId
                            ? const Color(0xFF2DA44E)
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
        color: theme.isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
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
            color: const Color(0xFF2DA44E).withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2DA44E).withValues(alpha: 0.06),
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
                    color: const Color(0xFF2DA44E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF2DA44E).withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF2DA44E),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ACTIVE & CONFIGURED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: theme.isDark
                              ? const Color(0xFF7EE787)
                              : const Color(0xFF1A7F37),
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
                color: theme.isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 0.8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    size: 14,
                    color: Color(0xFF2DA44E),
                  ),
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
                                  ? const Color(0xFF2DA44E)
                                  : theme.accentFg,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _copiedKey == 'active_cid' ? 'Copied' : 'Copy',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _copiedKey == 'active_cid'
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
                color: theme.isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFF6F8FA),
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
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditing = true;
                    _inlineError = null;
                    if (_clientIdController.text.isEmpty &&
                        activeClientId.isNotEmpty) {
                      _clientIdController.text = activeClientId;
                    }
                    _clientSecretController.clear();
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
          ],
        ),
      );
    }

    // ─── EDITING OR FIRST-TIME SETUP VIEW ─────────────────────────────────
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF0D1117) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isEditing
              ? const Color(0xFFD29922).withValues(alpha: 0.5)
              : theme.accentFg.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          if (_isEditing)
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
                  'Configure Google OAuth 2.0 Credentials: Enter your Client ID and Secret below. DeskMate will validate and permanently activate them in .env and credentials.json.',
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
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 14),
                      onPressed: () =>
                          setState(() => _clientIdController.clear()),
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
              suffixIcon: IconButton(
                icon: Icon(
                  _isSecretObscured
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                  color: theme.fgMuted,
                ),
                onPressed: () =>
                    setState(() => _isSecretObscured = !_isSecretObscured),
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
              if (_isEditing) ...[
                OutlinedButton(
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
                const SizedBox(width: 10),
              ],
              ElevatedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _handleSave(provider, theme, isReplace: _isEditing),
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
                        _isEditing
                            ? Icons.published_with_changes_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 15,
                      ),
                label: Text(
                  _isSaving
                      ? 'Validating...'
                      : _isEditing
                      ? 'Validate & Replace Old Credentials'
                      : 'Validate & Activate Credentials',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isEditing
                      ? const Color(0xFFD29922)
                      : theme.accentFg,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
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
                  actionButton,
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
        const Icon(
          Icons.check_circle_rounded,
          size: 14,
          color: Color(0xFF2DA44E),
        ),
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
          child: RichText(
            text: TextSpan(
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
            'If you prefer environment variables over a credentials.json file, you can place a .env file inside terminal-ai-agent/ or your DeskMate directory.',
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
                        color: isCopied
                            ? const Color(0xFF2DA44E)
                            : theme.accentFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCopied ? 'Copied' : 'Copy Template',
                        style: TextStyle(
                          fontSize: 10.5,
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
              color: const Color(0xFF2DA44E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF2DA44E).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF2DA44E),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No Google Account? No problem! These tools run 100% locally and offline out-of-the-box with ZERO credentials required.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: theme.isDark
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF1A7F37),
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

  // ─── TAB 4 (Personal): Personal Assistant Guide (README) ───────────────
  Widget _buildPersonalReadmeTab(ThemeData theme) {
    const markdownData = """# DeskMate — Personal Workspace Assistant Guide

DeskMate's **Personal Workspace Assistant** connects your desktop directly to your Google Workspace and local productivity databases with strict privacy guarantees.

---

### 🛡️ Privacy & Security Architecture
- **Zero Cloud Data Leakage**: Your SQLite tasks, notes, and local vector memory (`deskmate_agent.db`) are stored 100% on your device.
- **Direct OAuth Communication**: DeskMate never routes your emails, calendar events, or documents through intermediary servers. All requests communicate directly between your machine and official Google API endpoints.
- **Local Credential Storage**: OAuth client credentials and tokens are stored in your user configuration directory and never transmitted elsewhere.

---

### 👤 Core Personal Assistant Capabilities

#### 1. Google Workspace Suite (OAuth Required)
- **Gmail Automation**: Search recent threads, summarize unread messages, draft replies, and send emails securely.
- **Google Calendar Management**: List today's agenda, check availability, create new calendar events with attendees, and calculate relative scheduling.
- **Google Drive & Docs Search**: Search Drive files by keyword, download and summarize document contents, and query shared files.
- **Google Tasks Sync**: Create, list, check off, and synchronize task lists.

#### 2. Offline Productivity Suite (Zero Setup)
- **Local SQLite Tasks (`deskmate_agent.db`)**: Add, complete, and track local to-dos without requiring any internet connection.
- **Tagged Markdown Notes**: Save quick ideas, meeting minutes, and code snippets with full-text search.
- **FAISS L2 Semantic Memory**: Persistent vector memory allows the assistant to remember your project preferences and context across days.
- **Live Weather & Web Research**: Real-time DuckDuckGo searches and wttr.in weather forecasts without requiring an API key.

#### 3. Smart Multi-Turn Conversations (Zero-Bloat Contextualizer)
- **Natural Dynamic Follow-ups**: Ask follow-up queries naturally (e.g. *"What is the weather in SF this weekend?"* → *"in chennai"* or *"what about tomorrow?"*).
- **Zero Token Bloat**: The assistant dynamically resolves follow-ups into standalone commands using sub-80ms models instead of injecting raw conversation logs, saving >85% tokens and preventing tool hallucinations.
- **Strict Session Isolation**: Resetting conversation via "New Chat" completely isolates your session with zero context bleeding.

#### 4. In-App Credentials & Settings Management
- **One-Click Configuration**: Enter your Google OAuth Client ID & Secret in the **Quick Setup Tab** or via the **Settings Drawer (Gear Icon ⚙️)**.
- **Permanent Sync**: Credentials persist in your local `.env` and `credentials.json` with automatic token refresh.
- **Unified Purple Theme**: Clean aesthetics with matching purple accents across both light and dark modes.

---

### 🚀 Example Personal Assistant Prompts

- *"What's the weather forecast for San Francisco this weekend?"*
- *(Follow-up)* *"in chennai"* → automatically resolves to *"What is the weather in Chennai this weekend?"*
- *(Follow-up)* *"what about tomorrow?"*
- *"What is on my calendar for tomorrow afternoon?"*
- *"Check my unread emails from the last 24 hours and summarize anything urgent."*
- *"Schedule a meeting called 'Sprint Retro' for Friday at 3 PM."*
- *"Add a task to my local list: 'Review pull request #42 before EOD'."*
- *"Save a note tagged #meeting: Team agreed on adopting Qdrant for local vector indexing."*
""";

    return _buildMarkdownViewer(theme, markdownData);
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
              color: theme.isDark
                  ? const Color(0xFF161B22)
                  : const Color(0xFFF6F8FA),
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
              color: theme.isDark
                  ? const Color(0xFF161B22)
                  : const Color(0xFFF6F8FA),
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
            color: const Color(0xFF2DA44E),
            textColor: theme.isDark
                ? const Color(0xFF7EE787)
                : const Color(0xFF1A7F37),
          ),
          const SizedBox(height: 16),
          for (final t in tools) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFF6F8FA),
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
            'You can configure custom Ollama host endpoints, local model names, and vector chunk parameters in terminal-ai-agent/.env:',
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
                        color: isCopied
                            ? const Color(0xFF2DA44E)
                            : theme.accentFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCopied ? 'Copied' : 'Copy Template',
                        style: TextStyle(
                          fontSize: 10.5,
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

  // ─── TAB 4 (File Explorer): File Copilot Guide (README) ───────────────────
  Widget _buildFileReadmeTab(ThemeData theme) {
    const markdownData = """# DeskMate — File Explorer Copilot Guide

DeskMate's **File Explorer Copilot** provides an air-gapped, privacy-first coding assistant executing locally on your device via Ollama.

---

### 🏛️ Architecture & Air-Gap Guarantee
- **100% Offline Execution**: All model inference is processed on your local CPU/GPU by Ollama (`http://127.0.0.1:11434`).
- **No Cloud Code Transmissions**: Your proprietary source files, sensitive configs, and tokens are never sent over the internet.
- **Embedded Vector Database**: FastEmbed and Qdrant store codebase representations in `~/.deskmate/.qdrant_data`.

---

### 🦙 Quick Setup in 2 Commands
1. **Install Ollama**:
   - macOS: `brew install ollama`
   - Windows: Download from `https://ollama.com/download/windows`
   - Linux: `curl -fsSL https://ollama.com/install.sh | sh`
2. **Download Model**:
   - Fast 3B: `ollama run llama3.2`
   - Code-specialized 7B: `ollama run qwen2.5-coder`
   - Reasoning 8B: `ollama run deepseek-r1:8b`

---

### 🎛️ Interactive Resizable Sidebar & Settings Drawer
- **Draggable Sidebar**: Drag the vertical splitter on the right edge of the sidebar to widen or narrow your view anytime (min 255px, max 450px). Double-click to reset.
- **Model Switcher**: When multiple Ollama models are installed, hot-swap between models instantly with zero application restart.
- **Settings Drawer (Gear Icon ⚙️)**: Inspect FastAPI backend URL, verify local LLM engine status, and configure theme preferences.

---

### 💬 Smart Multi-Turn File Exploration (Zero-Bloat Contextualizer)
- **Natural Directory Navigation**: Explore files and directories conversationally without retyping long paths.
  - Turn 1: *"What files are in the core directory?"*
  - Turn 2: *"and in services?"* → dynamically resolves to *"What files are in the services directory?"*
  - Turn 3: *"read telemetry.py"* → dynamically resolves to *"Read the content of telemetry.py"*
  - Turn 4: *"what is inside it?"*
- **100% Local Inference & Sub-80ms Latency**: Contextualization runs on fast local Ollama models (`qwen2.5-coder:1.5b`, `llama3.2:1b/3b`) with \$0 token cost and zero cloud reliance.

---

### 📁 Supported Code & Text Formats
File Explorer Copilot supports reading, writing, and semantic indexing for:
- **Languages**: Python (`.py`), Dart/Flutter (`.dart`), TypeScript/JavaScript (`.ts`, `.js`), Rust (`.rs`), Go (`.go`), C/C++ (`.c`, `.cpp`), SQL (`.sql`).
- **Configs & Markup**: JSON, YAML, TOML, Markdown (`.md`), HTML, CSS, `.env`.

---

### 💡 Example File Copilot Prompts
- *"What files are in the core directory?"*
- *(Follow-up)* *"and in services?"*
- *(Follow-up)* *"read telemetry.py and explain how streaming works."*
- *"List all files in the current repository and show the folder layout."*
- *"Search for all files defining API routers."*
- *"Index backend.py into Qdrant vector database."*
- *"Search the vector DB for how local LLM tags are discovered."*
""";

    return _buildMarkdownViewer(theme, markdownData);
  }

  Widget _buildMarkdownViewer(ThemeData theme, String markdownData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Markdown(
        data: markdownData,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: TextStyle(fontSize: 12, height: 1.5, color: theme.fgDefault),
          h1: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: theme.fgDefault,
          ),
          h2: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: theme.fgDefault,
          ),
          h3: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: theme.fgDefault,
          ),
          h4: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: theme.fgDefault,
          ),
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: theme.accentFg,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.isDark
                ? const Color(0xFF161B22)
                : const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault),
          ),
          tableBody: TextStyle(fontSize: 11, color: theme.fgDefault),
          tableHead: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.fgDefault,
          ),
          tableBorder: TableBorder.all(color: theme.borderDefault, width: 0.5),
          blockquote: TextStyle(
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
            color: theme.fgMuted,
          ),
          blockquoteDecoration: BoxDecoration(
            color: theme.isDark
                ? const Color(0xFF161B22)
                : const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: theme.accentFg, width: 3)),
          ),
        ),
      ),
    );
  }
}
