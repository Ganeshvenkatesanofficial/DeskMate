import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/telemetry_accordion.dart';
import '../widgets/sidebar.dart';
import '../widgets/credentials_setup_dialog.dart';
import '../widgets/database_explorer_dialog.dart';
import '../widgets/meeting_scribe_view.dart';
import '../widgets/circular_close_button.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int? _editingMessageIndex;

  bool _isSettingsOpen = false;
  bool _isSetupGuideOpen = false;
  bool _isDatabaseExplorerOpen = false;
  AgentMode? _guideOverrideMode;
  bool _isGeminiKeyObscured = true;
  String? _settingsSelectedModel;
  bool _isSettingsModelDropdownOpen = false;
  final TextEditingController _geminiKeyController = TextEditingController();
  final FocusNode _geminiKeyFocusNode = FocusNode();
  late final FocusNode _shortcutFocusNode = FocusNode();
  final TextEditingController _googleClientIdController =
      TextEditingController();
  final TextEditingController _googleClientSecretController =
      TextEditingController();
  bool _isGoogleClientSecretObscured = true;
  bool _isSavingAllSettings = false;
  String? _googleCredsError;
  final TextEditingController _tempGeminiCtrl = TextEditingController();
  late TextEditingController _backendUrlController;
  late FocusNode _backendUrlFocusNode;

  OverlayEntry? _topToastOverlayEntry;
  Timer? _topToastTimer;

  void _showTopNotification(String message) {
    if (!mounted) return;
    _topToastTimer?.cancel();
    _topToastOverlayEntry?.remove();
    _topToastOverlayEntry = null;

    final overlayState = Overlay.of(context, rootOverlay: true);
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 768;

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
                color: theme.isDark
                    ? const Color(0xFF0F2D1A)
                    : const Color(0xFFEAFBF0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.isDark
                      ? const Color(0xFF1E6038)
                      : const Color(0xFF8CE4AC),
                  width: 1,
                ),
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
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: theme.successFg,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.successText,
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

  void _syncGoogleClientId(Map<String, dynamic> creds) {
    if (creds['configured'] == true &&
        creds['client_id'] != null &&
        (creds['client_id'] as String).isNotEmpty) {
      _googleClientIdController.text = creds['client_id'] as String;
    } else {
      _googleClientIdController.clear();
    }
  }

  String _formatAiConfigSummary({
    required String model,
    required bool hasGeminiKey,
    String? oauthMessage,
  }) {
    if (oauthMessage != null) {
      return 'Configuration updated: AI Model ($model) + $oauthMessage';
    }
    if (hasGeminiKey) {
      return 'Configuration updated: Gemini Cloud + Model ($model)';
    }
    return 'Configuration updated: 100% Offline with Model ($model)';
  }

  @override
  void initState() {
    super.initState();
    _backendUrlFocusNode = FocusNode();
    _backendUrlFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _geminiKeyFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _backendUrlController = TextEditingController(text: provider.backendUrl);
    _geminiKeyController.text = provider.geminiApiKey;
    _syncGoogleClientId(provider.personalCredentials);
  }

  @override
  void dispose() {
    _topToastTimer?.cancel();
    _topToastOverlayEntry?.remove();
    _topToastOverlayEntry = null;
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _geminiKeyController.dispose();
    _geminiKeyFocusNode.dispose();
    _googleClientIdController.dispose();
    _googleClientSecretController.dispose();
    _backendUrlController.dispose();
    _tempGeminiCtrl.dispose();
    _backendUrlFocusNode.dispose();
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      Future.delayed(const Duration(milliseconds: 60), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _openSettings() {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _backendUrlController.text = provider.backendUrl;
    _geminiKeyController.text = provider.geminiApiKey;
    _settingsSelectedModel = provider.effectiveModel.isNotEmpty
        ? provider.effectiveModel
        : null;
    _syncGoogleClientId(provider.personalCredentials);
    _googleCredsError = null;
    provider.fetchPersonalCredentials();
    setState(() {
      _isSettingsModelDropdownOpen = false;
      _isSettingsOpen = true;
    });
  }

  void _closeSettings() {
    setState(() {
      _isSettingsModelDropdownOpen = false;
      _isSettingsOpen = false;
    });
  }

  void _onEditMessage(int index, String content) {
    setState(() {
      _editingMessageIndex = index;
      _messageController.text = content;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
    _messageFocusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageIndex = null;
      _messageController.clear();
    });
  }

  void _handleSendMessage(ChatProvider provider) {
    final text = _messageController.text.trim();
    if (text.isEmpty || provider.isSending) return;

    if (_editingMessageIndex != null) {
      final idx = _editingMessageIndex!;
      setState(() => _editingMessageIndex = null);
      _messageController.clear();
      provider.editAndResendMessage(idx, text);
    } else {
      _messageController.clear();
      provider.sendMessage(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final theme = Theme.of(context);

    // Auto-scroll on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return KeyboardListener(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey.keyLabel == 'Escape') {
          if (_editingMessageIndex != null) {
            _cancelEditing();
          } else if (_isDatabaseExplorerOpen) {
            setState(() => _isDatabaseExplorerOpen = false);
          } else if (_isSetupGuideOpen) {
            setState(() => _isSetupGuideOpen = false);
          } else if (_isSettingsOpen) {
            _closeSettings();
          }
        }
      },
      child: Scaffold(
        backgroundColor: theme.bgCanvas,
        appBar: isDesktop
            ? null
            : AppBar(
                backgroundColor: theme.bgSubtle,
                elevation: 0,
                title: Text(
                  'DeskMate',
                  style: TextStyle(
                    color: theme.fgDefault,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: _openSettings,
                    icon: Icon(Icons.settings_outlined, color: theme.accentFg),
                  ),
                  IconButton(
                    onPressed: () => provider.resetChat(),
                    icon: Icon(Icons.refresh, color: theme.fgMuted),
                  ),
                ],
              ),
        drawer: isDesktop
            ? null
            : Drawer(
                child: Sidebar(
                  onOpenSettings: _openSettings,
                  onOpenDatabaseExplorer: () {
                    setState(() => _isDatabaseExplorerOpen = true);
                  },
                  onOpenSetupGuide: ([mode]) {
                    setState(() {
                      if (mode != null) _guideOverrideMode = mode;
                      _isSetupGuideOpen = true;
                    });
                  },
                  onShowTopNotification: _showTopNotification,
                ),
              ),
        body: Stack(
          children: [
            Row(
              children: [
                if (isDesktop)
                  IgnorePointer(
                    ignoring: provider.showModelSelectionDialog,
                    child: Sidebar(
                      onOpenSettings: _openSettings,
                      onOpenDatabaseExplorer: () {
                        setState(() => _isDatabaseExplorerOpen = true);
                      },
                      onOpenSetupGuide: ([mode]) {
                        setState(() {
                          if (mode != null) _guideOverrideMode = mode;
                          _isSetupGuideOpen = true;
                        });
                      },
                      onShowTopNotification: _showTopNotification,
                    ),
                  ),
                Expanded(
                  child: Container(
                    color: theme.bgCanvas,
                    child: Stack(
                      children: [
                        if (provider.mode == AgentMode.meeting)
                          MeetingScribeView(
                            onOpenSetupGuide: ([mode]) {
                              setState(() {
                                _guideOverrideMode = mode ?? AgentMode.meeting;
                                _isSetupGuideOpen = true;
                              });
                            },
                          )
                        else
                          Column(
                            children: [
                              Expanded(
                                child: provider.messages.isEmpty
                                    ? _buildEmptyState(theme)
                                    : ListView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 24,
                                        ),
                                        itemCount:
                                            provider.messages.length +
                                            (provider.isSending ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index ==
                                              provider.messages.length) {
                                            return _buildTypingIndicator(
                                              provider,
                                              theme,
                                            );
                                          }
                                          return ChatBubble(
                                            message: provider.messages[index],
                                            index: index,
                                            isSending: provider.isSending,
                                            onEdit: () {
                                              _onEditMessage(
                                                index,
                                                provider
                                                    .messages[index]
                                                    .content,
                                              );
                                            },
                                          );
                                        },
                                      ),
                              ),
                              _buildInputArea(provider, theme),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_isSettingsOpen) ...[
              // Solid Overlay
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeSettings,
                  child: Container(
                    color: theme.isDark
                        ? const Color(0x73010409)
                        : const Color(0x1A1F2328),
                  ),
                ).animate().fadeIn(duration: 150.ms),
              ),
              // Right Settings Drawer Panel
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 320,
                child: _buildSettingsPanel(provider, theme).animate().slideX(
                  begin: 1.0,
                  end: 0.0,
                  duration: 200.ms,
                  curve: Curves.easeOut,
                ),
              ),
            ],
            // Centered High-Tech Personal Agent Setup Guide Modal
            if (_isSetupGuideOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _isSetupGuideOpen = false),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                    child: Container(
                      color: theme.isDark
                          ? const Color(0x66010409)
                          : const Color(0x401F2328),
                    ),
                  ),
                ).animate().fadeIn(duration: 150.ms),
              ),
              Positioned.fill(
                child:
                    Center(
                      child: CredentialsSetupDialog(
                        mode: _guideOverrideMode ?? provider.mode,
                        onClose: () => setState(() {
                          _isSetupGuideOpen = false;
                          _guideOverrideMode = null;
                        }),
                      ),
                    ).animate().scale(
                      begin: const Offset(0.95, 0.95),
                      end: const Offset(1.0, 1.0),
                      duration: 200.ms,
                      curve: Curves.easeOutCubic,
                    ),
              ),
            ],

            // Database Explorer Modal Overlay
            if (_isDatabaseExplorerOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _isDatabaseExplorerOpen = false),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                    child: Container(
                      color: theme.isDark
                          ? const Color(0x66010409)
                          : const Color(0x401F2328),
                    ),
                  ),
                ).animate().fadeIn(duration: 150.ms),
              ),
              Positioned.fill(
                child:
                    Center(
                      child: DatabaseExplorerDialog(
                        onClose: () =>
                            setState(() => _isDatabaseExplorerOpen = false),
                      ),
                    ).animate().scale(
                      begin: const Offset(0.95, 0.95),
                      end: const Offset(1.0, 1.0),
                      duration: 200.ms,
                      curve: Curves.easeOutCubic,
                    ),
              ),
            ],

            // Centered DeskMate AI & Model Configuration Modal (Always on top of EVERYTHING, including User Guide)
            if (provider.showModelSelectionDialog) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => provider.dismissModelSelectionDialog(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                    child: Container(
                      color: theme.isDark
                          ? const Color(0x66010409)
                          : const Color(0x401F2328),
                    ),
                  ),
                ).animate().fadeIn(duration: 150.ms),
              ),
              Positioned.fill(
                child: Center(
                  child: _buildModelSelectionPopup(context, provider, theme),
                ),
              ).animate().scale(
                begin: const Offset(0.95, 0.95),
                end: const Offset(1.0, 1.0),
                duration: 200.ms,
                curve: Curves.easeOutCubic,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel(ChatProvider provider, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgSubtle : theme.bgCanvas,
        border: Border(left: BorderSide(color: theme.borderDefault, width: 1)),
        boxShadow: const [
          BoxShadow(color: Color(0x40010409), blurRadius: 24, spreadRadius: 0),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ─── Compact, Modern Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
              decoration: BoxDecoration(
                color: theme.isDark ? theme.bgCanvas : Colors.white,
                border: Border(
                  bottom: BorderSide(color: theme.borderDefault, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.accentFg.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.accentFg.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.settings_rounded,
                      color: theme.accentFg,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: theme.fgDefault,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Preferences & Engine Configuration',
                          style: TextStyle(fontSize: 11, color: theme.fgMuted),
                        ),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: IconButton(
                      mouseCursor: SystemMouseCursors.click,
                      onPressed: _closeSettings,
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.fgMuted,
                        size: 18,
                      ),
                      hoverColor: theme.bgEmphasis,
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Content ────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── SECTION 1: AI ENGINE & LOCAL MODEL ────────────────
                    _buildSettingsSectionHeader(
                      theme: theme,
                      icon: Icons.memory_rounded,
                      title: 'AI ENGINE & LOCAL MODEL',
                    ),
                    const SizedBox(height: 9),
                    _buildAiEngineCard(provider, theme),

                    const SizedBox(height: 18),

                    // ─── SECTION 2: GOOGLE WORKSPACE OAUTH ─────────────────
                    _buildSettingsSectionHeader(
                      theme: theme,
                      icon: Icons.vpn_key_rounded,
                      title: 'GOOGLE WORKSPACE OAUTH 2.0',
                    ),
                    const SizedBox(height: 9),
                    _buildOAuthCard(provider, theme),

                    const SizedBox(height: 18),

                    // ─── SECTION 3: BACKEND SERVER ─────────────────────────
                    _buildSettingsSectionHeader(
                      theme: theme,
                      icon: Icons.dns_rounded,
                      title: 'BACKEND SERVER',
                    ),
                    const SizedBox(height: 9),
                    _buildBackendCard(provider, theme),

                    const SizedBox(height: 18),

                    // ─── SECTION 4: APPEARANCE ─────────────────────────────
                    _buildSettingsSectionHeader(
                      theme: theme,
                      icon: Icons.palette_outlined,
                      title: 'APPEARANCE',
                    ),
                    const SizedBox(height: 9),
                    _buildThemeSelectorInSettings(provider, theme),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ─── PINNED FOOTER: UNIFIED SAVE BUTTON & BUILD INFO ───────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.isDark ? theme.bgCanvas : Colors.white,
                border: Border(
                  top: BorderSide(color: theme.borderDefault, width: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.isDark ? 0.25 : 0.05,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: MouseRegion(
                      cursor: _isSavingAllSettings
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: ElevatedButton.icon(
                        onPressed: _isSavingAllSettings
                            ? null
                            : () => _handleSaveAllSettings(provider, theme),
                        style: ButtonStyle(
                          elevation: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return 2.0;
                            }
                            return 0.0;
                          }),
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.disabled)) {
                              return theme.bgEmphasis;
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return theme.accentHover;
                            }
                            if (states.contains(WidgetState.pressed)) {
                              return AppTheme.purpleActive;
                            }
                            return theme.accentEmphasis;
                          }),
                          foregroundColor: WidgetStateProperty.all(
                            Colors.white,
                          ),
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        icon: _isSavingAllSettings
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 16),
                        label: Text(
                          _isSavingAllSettings
                              ? 'Validating & Saving...'
                              : 'Save Configuration',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '${AppConstants.appName} • v${AppConstants.version}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.fgMuted.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                      'Open Source AI Copilot & Personal Agent',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: theme.fgMuted.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsInputField({
    required ThemeData theme,
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    FocusNode? focusNode,
    bool isMonospace = false,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        style: TextStyle(
          fontFamily: isMonospace ? 'monospace' : null,
          fontSize: 12,
          color: theme.fgDefault,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(prefixIcon, size: 15, color: theme.fgMuted),
          suffixIcon: suffixIcon,
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 11, color: theme.fgMuted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
      ),
    );
  }

  Widget _buildAiEngineCard(ChatProvider provider, ThemeData theme) {
    final allModels = List<String>.from(provider.availableLocalModels);
    if (provider.selectedLocalModel.isNotEmpty &&
        !allModels.contains(provider.selectedLocalModel)) {
      allModels.add(provider.selectedLocalModel);
    }

    final effectiveModel =
        (_settingsSelectedModel != null &&
            allModels.contains(_settingsSelectedModel))
        ? _settingsSelectedModel
        : (allModels.contains(provider.selectedLocalModel)
              ? provider.selectedLocalModel
              : (allModels.isNotEmpty ? allModels.first : null));

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgCanvas : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.bgPanel,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.borderDefault, width: 0.8),
            ),
            child: Builder(
              builder: (context) {
                final isUsingLocal =
                    provider.isLocalLlmOnline &&
                    provider.selectedLocalModel.isNotEmpty;
                final isGemini = provider.isUsingGemini;
                final activeIcon = isUsingLocal
                    ? Icons.memory_rounded
                    : (isGemini
                          ? Icons.cloud_done_rounded
                          : Icons.memory_rounded);
                final activeColor = isUsingLocal
                    ? theme.statusOk
                    : (isGemini
                          ? theme.accentFg
                          : (provider.isLocalLlmOnline
                                ? theme.statusOk
                                : theme.dangerFg));
                final activeLabel = isUsingLocal
                    ? 'Active: ${provider.selectedLocalModel} (Offline)'
                    : (isGemini
                          ? 'Active: Gemini 1.5 Flash Cloud'
                          : (provider.isLocalLlmOnline
                                ? 'Active: Local Ollama Model'
                                : 'Local Ollama: Offline'));

                return Row(
                  children: [
                    Icon(activeIcon, size: 14, color: activeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        activeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.fgDefault,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 11),

          // Local Model label
          Text(
            'Local Model (Ollama)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.fgDefault,
            ),
          ),
          const SizedBox(height: 5),

          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.isDark ? theme.bgSubtle : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isSettingsModelDropdownOpen
                      ? theme.accentFg
                      : theme.borderDefault,
                  width: _isSettingsModelDropdownOpen ? 1.0 : 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          _isSettingsModelDropdownOpen =
                              !_isSettingsModelDropdownOpen;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.memory_rounded,
                              size: 15,
                              color: effectiveModel != null
                                  ? const Color(0xFF8250DF)
                                  : theme.fgMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                effectiveModel ??
                                    (provider.isLocalLlmOnline
                                        ? 'No models detected'
                                        : (provider
                                                  .selectedLocalModel
                                                  .isNotEmpty
                                              ? 'Active: ${provider.selectedLocalModel} (Offline)'
                                              : 'Ollama Offline (127.0.0.1:11434)')),
                                style: TextStyle(
                                  fontFamily: effectiveModel != null
                                      ? 'monospace'
                                      : null,
                                  fontSize: 12,
                                  fontWeight: effectiveModel != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: effectiveModel != null
                                      ? theme.fgDefault
                                      : theme.fgMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              _isSettingsModelDropdownOpen
                                  ? Icons.arrow_drop_up_rounded
                                  : Icons.arrow_drop_down_rounded,
                              size: 20,
                              color: theme.fgMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_isSettingsModelDropdownOpen) ...[
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      color: theme.borderDefault,
                    ),
                    if (allModels.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: allModels.map((m) {
                              final isOfflineModel = !provider
                                  .availableLocalModels
                                  .contains(m);
                              final isSel =
                                  (m ==
                                  (effectiveModel ??
                                      provider.selectedLocalModel));
                              return Material(
                                color: isSel
                                    ? theme.accentFg.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                child: InkWell(
                                  mouseCursor: SystemMouseCursors.click,
                                  onTap: () {
                                    setState(() {
                                      _settingsSelectedModel = m;
                                      _isSettingsModelDropdownOpen = false;
                                    });
                                  },
                                  hoverColor: theme.isDark
                                      ? const Color(0xFF1F242C)
                                      : const Color(0xFFF1F4F8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.memory_rounded,
                                          size: 13,
                                          color: isSel
                                              ? theme.accentFg
                                              : theme.fgMuted,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            isOfflineModel
                                                ? '$m (Saved / Offline)'
                                                : m,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11.5,
                                              fontWeight: isSel
                                                  ? FontWeight.w700
                                                  : FontWeight.normal,
                                              color: isSel
                                                  ? theme.accentFg
                                                  : theme.fgDefault,
                                            ),
                                          ),
                                        ),
                                        if (isSel)
                                          Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: theme.accentFg,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.isLocalLlmOnline
                                  ? 'No models detected on Ollama.'
                                  : 'Ollama Offline on http://127.0.0.1:11434',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.fgMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Run "ollama run llama3.2" to install.',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: theme.accentFg,
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
          const SizedBox(height: 11),

          // Gemini Key
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gemini API Key (Optional BYOK)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
              if (_geminiKeyController.text.isNotEmpty)
                InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => setState(() => _geminiKeyController.clear()),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.dangerFg,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          _buildSettingsInputField(
            theme: theme,
            controller: _geminiKeyController,
            hintText: 'Enter Gemini key',
            prefixIcon: Icons.vpn_key_outlined,
            obscureText: _isGeminiKeyObscured,
            suffixIcon: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                mouseCursor: SystemMouseCursors.click,
                icon: Icon(
                  _isGeminiKeyObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 14,
                  color: theme.fgMuted,
                ),
                onPressed: () => setState(
                  () => _isGeminiKeyObscured = !_isGeminiKeyObscured,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Center(
            child: Text(
              '(or leave empty for offline)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: theme.fgMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final isOAuthConfigured =
        (provider.personalCredentials['configured'] == true) &&
        (checks['google_credentials_file'] == true);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgCanvas : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Security badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: theme.accentFg.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: theme.accentFg.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 13, color: theme.accentFg),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Saved locally in .env & credentials.json',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.fgMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Text(
            'Client ID',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.fgDefault,
            ),
          ),
          const SizedBox(height: 5),
          _buildSettingsInputField(
            theme: theme,
            controller: _googleClientIdController,
            hintText: 'Google Client ID',
            prefixIcon: Icons.badge_outlined,
            isMonospace: true,
          ),
          const SizedBox(height: 9),

          Text(
            'Client Secret',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.fgDefault,
            ),
          ),
          const SizedBox(height: 5),
          _buildSettingsInputField(
            theme: theme,
            controller: _googleClientSecretController,
            hintText: 'Google Client Secret',
            prefixIcon: Icons.key_outlined,
            isMonospace: true,
            obscureText: _isGoogleClientSecretObscured,
            suffixIcon: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                mouseCursor: SystemMouseCursors.click,
                icon: Icon(
                  _isGoogleClientSecretObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 14,
                  color: theme.fgMuted,
                ),
                onPressed: () => setState(
                  () => _isGoogleClientSecretObscured =
                      !_isGoogleClientSecretObscured,
                ),
              ),
            ),
          ),

          if (_googleCredsError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.dangerFg.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.dangerFg.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 13,
                    color: theme.dangerFg,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _googleCredsError!,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.dangerFg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (isOAuthConfigured) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.statusOk.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.statusOk.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 11,
                    color: theme.statusOk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Active in .env',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.successText,
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

  Widget _buildBackendCard(ChatProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgCanvas : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderDefault, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FastAPI Server URL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: provider.isBackendOnline
                          ? theme.statusOk
                          : theme.dangerFg,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    provider.isBackendOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: provider.isBackendOnline
                          ? theme.successText
                          : theme.dangerFg,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          _buildSettingsInputField(
            theme: theme,
            controller: _backendUrlController,
            focusNode: _backendUrlFocusNode,
            hintText: 'http://127.0.0.1:8000',
            prefixIcon: Icons.link,
            isMonospace: true,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveAllSettings(
    ChatProvider provider,
    ThemeData theme,
  ) async {
    setState(() {
      _googleCredsError = null;
      _isSavingAllSettings = true;
    });

    final modelToSave = _settingsSelectedModel ?? provider.effectiveModel;

    // 1. Save AI Configuration (Model & Gemini Key)
    await provider.saveAiConfiguration(
      model: modelToSave,
      geminiApiKey: _geminiKeyController.text,
    );

    // 2. Save Backend URL if modified
    final backendUrl = _backendUrlController.text.trim();
    if (backendUrl.isNotEmpty && backendUrl != provider.backendUrl) {
      provider.setBackendUrl(backendUrl);
    }

    // 3. Save Google OAuth Credentials if provided
    final cid = _googleClientIdController.text.trim();
    final sec = _googleClientSecretController.text.trim();

    String? oauthMessage;
    if (cid.isNotEmpty && sec.isNotEmpty) {
      if (!cid.endsWith('.apps.googleusercontent.com') || cid.length < 25) {
        if (mounted) {
          setState(() {
            _googleCredsError =
                'Client ID must end with .apps.googleusercontent.com';
            _isSavingAllSettings = false;
          });
        }
        return;
      }
      if (sec.length < 8) {
        if (mounted) {
          setState(() {
            _googleCredsError =
                'Client Secret must be at least 8 characters long.';
            _isSavingAllSettings = false;
          });
        }
        return;
      }
      final credResult = await provider.saveGoogleCredentials(cid, sec);
      if (credResult['success'] == true) {
        _googleClientSecretController.clear();
        oauthMessage = 'Google OAuth credentials activated';
      } else {
        if (mounted) {
          setState(() {
            _googleCredsError =
                credResult['message'] ??
                'Failed to activate OAuth credentials.';
            _isSavingAllSettings = false;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isSavingAllSettings = false;
      });
      FocusScope.of(context).unfocus();
      final summary = _formatAiConfigSummary(
        model: modelToSave,
        hasGeminiKey: _geminiKeyController.text.isNotEmpty,
        oauthMessage: oauthMessage,
      );
      _showTopNotification(summary);
    }
  }

  Widget _buildSettingsSectionHeader({
    required ThemeData theme,
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: theme.fgMuted),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.fgMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSelectorInSettings(ChatProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Row(
        children: [
          _buildThemeOptionInSettings(
            provider: provider,
            theme: theme,
            mode: ThemeMode.light,
            icon: Icons.light_mode_outlined,
            label: 'Light',
          ),
          _buildThemeOptionInSettings(
            provider: provider,
            theme: theme,
            mode: ThemeMode.dark,
            icon: Icons.dark_mode_outlined,
            label: 'Dark',
          ),
          _buildThemeOptionInSettings(
            provider: provider,
            theme: theme,
            mode: ThemeMode.system,
            icon: Icons.desktop_windows_outlined,
            label: 'System',
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOptionInSettings({
    required ChatProvider provider,
    required ThemeData theme,
    required ThemeMode mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = provider.themeMode == mode;
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => provider.setThemeMode(mode),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: isSelected
                  ? Border.all(color: theme.borderDefault, width: 1)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? theme.accentFg : theme.fgMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? theme.fgDefault : theme.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDynamicModelCapability(String modelName) {
    final lower = modelName.toLowerCase();
    if (lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('vl')) {
      return 'Multimodal Vision & Visual Intelligence';
    }
    if (lower.contains('coder') ||
        lower.contains('code') ||
        lower.contains('starcoder')) {
      return 'Optimized for Fast Coding & Development';
    }
    if (lower.contains('r1') ||
        lower.contains('reason') ||
        lower.contains('deepseek')) {
      return 'Advanced Step-by-Step Reasoning & Logic';
    }
    final paramRegex = RegExp(r':?(\d+(?:\.\d+)?b)\b');
    final match = paramRegex.firstMatch(lower);
    if (match != null) {
      final param = match.group(1)!.toUpperCase();
      return 'General Intelligence & Reasoning ($param)';
    }
    if (lower.contains('llama') ||
        lower.contains('gpt') ||
        lower.contains('mistral') ||
        lower.contains('qwen') ||
        lower.contains('phi') ||
        lower.contains('gemma')) {
      return 'General Purpose Chat & Knowledge Reasoning';
    }
    return 'Local Air-Gapped LLM Inference';
  }

  Widget _buildModelSelectionPopup(
    BuildContext context,
    ChatProvider provider,
    ThemeData theme,
  ) {
    String tempSelected = provider.effectiveModel;
    _tempGeminiCtrl.text = provider.geminiApiKey;
    bool obscureGemini = true;

    return StatefulBuilder(
      builder: (context, setPopupState) {
        final hasModels = provider.availableLocalModels.isNotEmpty;
        final screenWidth = MediaQuery.of(context).size.width;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.borderDefault, width: 1),
          ),
          elevation: 12,
          backgroundColor: theme.bgOverlay,
          child: Container(
            width: math.min(540.0, screenWidth * 0.94),
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.accentFg.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.accentFg.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
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
                              'DeskMate AI & Model Configuration',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: theme.fgDefault,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Select your local model and optionally set your Gemini cloud key.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.fgMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: theme.borderDefault, height: 1),
                  const SizedBox(height: 16),

                  // Section 1: Local Model Selection
                  Row(
                    children: [
                      Icon(
                        Icons.memory_rounded,
                        size: 15,
                        color: theme.accentFg,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '1. LOCAL LLM MODEL (OFFLINE & AIR-GAPPED)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: theme.fgMuted,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (provider.isLocalLlmOnline
                                      ? theme.statusOk
                                      : theme.dangerFg)
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color:
                                (provider.isLocalLlmOnline
                                        ? theme.statusOk
                                        : theme.dangerFg)
                                    .withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          provider.isLocalLlmOnline
                              ? '${provider.availableLocalModels.length} Models Found'
                              : 'Ollama Offline',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: provider.isLocalLlmOnline
                                ? theme.successText
                                : theme.dangerFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (hasModels) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Column(
                          children: provider.availableLocalModels.map((
                            modelName,
                          ) {
                            final isSelected = tempSelected == modelName;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (theme.isDark
                                            ? theme.bgEmphasis
                                            : const Color(0xFFEAEEF2))
                                      : (theme.isDark
                                            ? theme.bgCanvas
                                            : Colors.white),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.accentFg
                                        : theme.borderDefault,
                                    width: isSelected ? 1.4 : 0.8,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: RadioListTile<String>(
                                    mouseCursor: SystemMouseCursors.click,
                                    value: modelName,
                                    // ignore: deprecated_member_use
                                    groupValue: tempSelected,
                                    dense: true,
                                    activeColor: theme.accentFg,
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            modelName,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.normal,
                                              color: theme.fgDefault,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.accentFg.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: theme.accentFg
                                                    .withValues(alpha: 0.35),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              'SELECTED',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.5,
                                                color: theme.accentFg,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      _getDynamicModelCapability(modelName),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isSelected
                                            ? theme.accentFg
                                            : theme.fgMuted,
                                      ),
                                    ),
                                    // ignore: deprecated_member_use
                                    onChanged: (val) {
                                      if (val != null) {
                                        setPopupState(() {
                                          tempSelected = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.bgCode,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.borderDefault,
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No local Ollama models detected on http://127.0.0.1:11434.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.fgDefault,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'To run completely offline, install Ollama and run:',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.fgMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(5),
                              mouseCursor: SystemMouseCursors.click,
                              onTap: () {
                                Clipboard.setData(
                                  const ClipboardData(
                                    text: 'ollama run llama3.2',
                                  ),
                                );
                                _showTopNotification(
                                  'Copied to clipboard: ollama run llama3.2',
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.isDark
                                      ? Colors.black
                                      : const Color(0xFFEAEEF2),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: theme.borderDefault,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'ollama run llama3.2',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: theme.isDark
                                            ? const Color(0xFF7EE787)
                                            : const Color(0xFF116329),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Copy command',
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                        color: theme.fgMuted,
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
                  ],

                  const SizedBox(height: 16),

                  // Section 2: Gemini Cloud Key
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        size: 15,
                        color: theme.accentFg,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '2. GEMINI CLOUD API KEY (OPTIONAL BYOK)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: theme.fgMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Optional cloud reasoning key for personal assistant. Leave blank for 100% offline mode:',
                    style: TextStyle(fontSize: 11, color: theme.fgMuted),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _tempGeminiCtrl,
                      obscureText: obscureGemini,
                      style: TextStyle(fontSize: 12.5, color: theme.fgDefault),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.vpn_key_outlined,
                          size: 15,
                          color: theme.fgMuted,
                        ),
                        suffixIcon: IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          icon: Icon(
                            obscureGemini
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 15,
                            color: theme.fgMuted,
                          ),
                          onPressed: () {
                            setPopupState(() {
                              obscureGemini = !obscureGemini;
                            });
                          },
                        ),
                        hintText: 'Enter Gemini API Key (e.g. AIzaSy...)',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: theme.fgMuted,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: theme.borderDefault, height: 1),
                  const SizedBox(height: 14),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          provider.dismissModelSelectionDialog();
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: theme.isDark
                              ? theme.bgEmphasis
                              : theme.bgSubtle,
                          side: BorderSide(
                            color: theme.borderDefault,
                            width: 1,
                          ),
                          foregroundColor: theme.fgDefault,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          provider.hasConfiguredAi ? 'Cancel' : 'Skip for Now',
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final modelToSave = tempSelected.isNotEmpty
                              ? tempSelected
                              : provider.effectiveModel;
                          await provider.saveAiConfiguration(
                            model: modelToSave,
                            geminiApiKey: _tempGeminiCtrl.text,
                          );
                          _showTopNotification(
                            _formatAiConfigSummary(
                              model: modelToSave,
                              hasGeminiKey: _tempGeminiCtrl.text.isNotEmpty,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accentEmphasis,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 15,
                        ),
                        label: const Text('Save & Continue'),
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
  }

  Widget _buildEmptyState(ThemeData theme) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final isPersonal = provider.mode == AgentMode.personal;
    final isCompact = MediaQuery.of(context).size.width < 620;

    final title = isPersonal
        ? 'DeskMate Personal Agent'
        : 'Welcome to DeskMate';
    final subtitle = isPersonal
        ? 'Your free offline & cloud assistant. Manage tasks, notes, weather, emails, and calendar.'
        : 'Search, analyze, and manage your local files with smart AI capability.';

    final examples = isPersonal
        ? [
            {
              'icon': Icons.task_alt_rounded,
              'text': 'Add task to my Google Tasks: Prep demo',
              'label': 'Google Tasks',
            },
            {
              'icon': Icons.insert_drive_file_outlined,
              'text':
                  'Create a Google Doc named Project Outline containing scope',
              'label': 'Google Docs',
            },
            {
              'icon': Icons.mail_outline_rounded,
              'text': 'Search my sent emails',
              'label': 'Gmail Search',
            },
            {
              'icon': Icons.calendar_today_rounded,
              'text': 'List my calendar events for tomorrow',
              'label': 'Google Calendar',
            },
          ]
        : [
            {
              'icon': Icons.search_rounded,
              'text': 'Find PDF files larger than 10MB',
              'label': 'Find Files',
            },
            {
              'icon': Icons.analytics_outlined,
              'text': 'Summarize recent financial reports',
              'label': 'Summarize',
            },
            {
              'icon': Icons.find_in_page_outlined,
              'text': 'Search "react" inside folder',
              'label': 'Grep Search',
            },
            {
              'icon': Icons.info_outline,
              'text': 'Show details of requirements.txt',
              'label': 'Metadata',
            },
          ];

    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                theme.isDark
                    ? 'assets/app_icon.png'
                    : 'assets/app_icon_light.png',
                key: ValueKey(theme.isDark),
                width: 68,
                height: 68,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 68,
                  height: 68,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.isDark ? theme.bgEmphasis : theme.bgCanvas,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.borderDefault, width: 1),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.accentFg,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.fgMuted,
                  height: 1.5,
                ),
              ),
              if (isPersonal) ...[
                const SizedBox(height: 16),
                InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => setState(() {
                    _guideOverrideMode = AgentMode.personal;
                    _isSetupGuideOpen = true;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accentFg.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.accentFg.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.vpn_key_rounded,
                          size: 15,
                          color: theme.accentFg,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Setting up Personal Assistant? View Credentials & Setup Guide',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.fgDefault,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Open Guide ➔',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.accentFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => setState(() {
                    _guideOverrideMode = AgentMode.deskMate;
                    _isSetupGuideOpen = true;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accentFg.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.accentFg.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 15,
                          color: theme.accentFg,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Need help setting up Local LLM or Ollama? View File Agent & LLM Guide',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.fgDefault,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Open Guide ➔',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.accentFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Text(
                    'TRY THESE EXAMPLES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.fgMuted,
                      letterSpacing: 0.08,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isCompact ? 1 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isCompact ? 4.2 : 2.4,
                ),
                itemCount: examples.length,
                itemBuilder: (context, index) {
                  final ex = examples[index];
                  return _buildExampleCard(
                    theme,
                    ex['icon'] as IconData,
                    ex['label'] as String,
                    ex['text'] as String,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExampleCard(
    ThemeData theme,
    IconData icon,
    String label,
    String text,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgSubtle : theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              _messageController.text = text;
            });
          },
          hoverColor: theme.bgEmphasis,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: theme.accentFg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.accentFg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.fgDefault,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(ChatProvider provider, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.bgSubtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.borderDefault, width: 1),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              color: theme.accentFg,
              size: 16,
            ),
          ).animate().scale(duration: 200.ms, curve: Curves.easeOut),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: TelemetryAccordion(
                steps: provider.activeTelemetry,
                isActive: true,
                activeTitle: provider.activeStatusTitle,
                initiallyExpanded: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ChatProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        border: Border(top: BorderSide(color: theme.borderDefault, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.errorMessage.isNotEmpty &&
              !provider.isConnecting &&
              provider.isBackendOnline)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.dangerBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dangerBorder, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.dangerFg, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.errorMessage,
                        style: TextStyle(color: theme.dangerFg, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (provider.isConnecting)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.accentFg),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Initializing local AI service & loading models...',
                    style: TextStyle(
                      color: theme.accentFg,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else if (!provider.isBackendOnline)
            Container(
              decoration: BoxDecoration(
                color: theme.bgEmphasis,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.attentionFg, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.attentionFg,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI Service is offline. Please wait or retry connecting.',
                      style: TextStyle(
                        color: theme.attentionFg,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        provider.retryConnecting();
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.attentionFg, width: 1),
                        foregroundColor: theme.attentionFg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (_editingMessageIndex != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.isDark
                      ? AppTheme.darkBgCanvas
                      : AppTheme.lightBgCanvas,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.accentEmphasis, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 14, color: theme.accentFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing query — update and press Enter to send & continue',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.accentFg,
                        ),
                      ),
                    ),
                    CircularCloseButton(
                      size: 15,
                      tooltip: 'Cancel editing (Esc)',
                      onTap: _cancelEditing,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: TextStyle(color: theme.fgDefault, fontSize: 13),
                    onSubmitted: (val) => _handleSendMessage(provider),
                    decoration: InputDecoration(
                      hintText: _editingMessageIndex != null
                          ? 'Edit your message...'
                          : (!provider.isLocalLlmOnline &&
                                !provider.isUsingGemini)
                          ? 'Start Ollama locally or configure Gemini API Key in Settings to continue...'
                          : provider.mode == AgentMode.personal
                          ? 'Ask about Tasks, Drive Docs, Gmail, Calendar...'
                          : 'Ask about your files...',
                      hintStyle: TextStyle(color: theme.fgMuted, fontSize: 13),
                      enabled:
                          !provider.isSending &&
                          (provider.isLocalLlmOnline || provider.isUsingGemini),
                      fillColor: theme.bgCanvas,
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 40,
                  width: 42,
                  child: Tooltip(
                    message:
                        (!provider.isLocalLlmOnline && !provider.isUsingGemini)
                        ? 'Start Ollama locally or configure Gemini in Settings to send messages'
                        : (provider.isSending
                              ? 'Sending...'
                              : 'Send message (Enter)'),
                    child: MouseRegion(
                      cursor:
                          (provider.isSending ||
                              (!provider.isLocalLlmOnline &&
                                  !provider.isUsingGemini))
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: ElevatedButton(
                        onPressed:
                            provider.isSending ||
                                (!provider.isLocalLlmOnline &&
                                    !provider.isUsingGemini)
                            ? null
                            : () => _handleSendMessage(provider),
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(EdgeInsets.zero),
                          elevation: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return 2.0;
                            }
                            return 0.0;
                          }),
                          mouseCursor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.disabled)) {
                              return SystemMouseCursors.basic;
                            }
                            return SystemMouseCursors.click;
                          }),
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.disabled)) {
                              return theme.bgEmphasis;
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return theme.accentHover;
                            }
                            if (states.contains(WidgetState.pressed)) {
                              return AppTheme.purpleActive;
                            }
                            return theme.accentEmphasis;
                          }),
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        child: provider.isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
