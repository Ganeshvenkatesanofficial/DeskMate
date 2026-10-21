import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../providers/chat_provider.dart';
import '../utils/clipboard_utils.dart';
import '../theme/app_theme.dart';
import 'database_explorer_dialog.dart';

class Sidebar extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  final void Function([AgentMode? mode])? onOpenSetupGuide;
  final VoidCallback? onOpenDatabaseExplorer;
  final void Function(String message)? onShowTopNotification;
  const Sidebar({
    super.key,
    this.onOpenSettings,
    this.onOpenSetupGuide,
    this.onOpenDatabaseExplorer,
    this.onShowTopNotification,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  double _sidebarWidth = 292.0;
  bool _isDragging = false;
  bool _isHoveringResizer = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final theme = Theme.of(context);

    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        border: Border(
          right: BorderSide(
            color: _isDragging
                ? theme.accentFg
                : (_isHoveringResizer
                      ? theme.accentFg.withValues(alpha: 0.6)
                      : theme.borderDefault),
            width: _isDragging ? 1.5 : 1,
          ),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 14),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- BRAND HEADER ---
                            SizedBox(
                              width: double.infinity,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    theme.isDark
                                        ? 'assets/app_icon.png'
                                        : 'assets/app_icon_light.png',
                                    key: ValueKey(theme.isDark),
                                    width: 68,
                                    height: 68,
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: 68,
                                              height: 68,
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: theme.isDark
                                                    ? theme.bgEmphasis
                                                    : theme.bgCanvas,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: theme.borderDefault,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.auto_awesome_rounded,
                                                color: theme.accentFg,
                                                size: 32,
                                              ),
                                            ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'DeskMate',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: theme.fgDefault,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Open Source AI',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: theme.fgMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // --- MODE SELECTOR ---
                            _buildModeSelector(provider, theme),
                            const SizedBox(height: 10),

                            // --- NEW CONVERSATION BUTTON ---
                            _buildNewChatButton(provider, theme),
                            const SizedBox(height: 12),

                            // --- STATUS CARD ---
                            _buildStatusCard(provider, theme),

                            if (provider.mode == AgentMode.deskMate) ...[
                              const SizedBox(height: 12),
                              _buildFileAgentHealthCard(provider, theme),
                            ] else if (provider.mode == AgentMode.personal) ...[
                              const SizedBox(height: 12),
                              _buildPersonalHealthCard(provider, theme),
                            ] else if (provider.mode == AgentMode.meeting) ...[
                              const SizedBox(height: 12),
                              _buildMeetingHealthCard(provider, theme),
                            ],

                            const SizedBox(height: 12),

                            // --- AGENT GUIDES & DOCUMENTATION ---
                            _buildAgentGuidesSection(provider, theme),

                            const Spacer(),

                            // --- DATABASE EXPLORER & SETTINGS ---
                            if (provider.mode == AgentMode.personal) ...[
                              const SizedBox(height: 12),
                              _buildDatabaseExplorerButton(theme),
                            ],
                            const SizedBox(height: 8),
                            _buildSettingsButton(theme),
                            const SizedBox(height: 10),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${AppConstants.appName} • v${AppConstants.version}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: theme.fgMuted.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Open Source AI Copilot & Personal Agent',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: theme.fgMuted.withValues(
                                        alpha: 0.6,
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
                },
              ),
            ),
          ),
          // Draggable splitter handle along the right border
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) => setState(() => _isHoveringResizer = true),
              onExit: (_) => setState(() => _isHoveringResizer = false),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) =>
                    setState(() => _isDragging = true),
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(
                      255.0,
                      450.0,
                    );
                  });
                },
                onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
                onDoubleTap: () {
                  setState(() {
                    _sidebarWidth = 292.0; // Reset to optimal default width
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(ChatProvider provider, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        children: [
          _buildModeItem(
            theme: theme,
            title: 'File Explorer',
            icon: Icons.folder_open_rounded,
            isSelected: provider.mode == AgentMode.deskMate,
            onTap: () => provider.switchMode(AgentMode.deskMate),
          ),
          const SizedBox(height: 4),
          _buildModeItem(
            theme: theme,
            title: 'Personal Agent',
            icon: Icons.person_rounded,
            isSelected: provider.mode == AgentMode.personal,
            onTap: () => provider.switchMode(AgentMode.personal),
          ),
          const SizedBox(height: 4),
          _buildModeItem(
            theme: theme,
            title: 'Meeting Scribe',
            icon: Icons.mic_rounded,
            isSelected: provider.mode == AgentMode.meeting,
            onTap: () => provider.switchMode(AgentMode.meeting),
          ),
        ],
      ),
    );
  }

  Widget _buildModeItem({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
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
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? theme.accentFg : theme.fgMuted,
              ),
              const SizedBox(width: 8),
              Text(
                title,
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
    );
  }

  Widget _buildStatusCard(ChatProvider provider, ThemeData theme) {
    final isOnline = provider.isBackendOnline;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STATUS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.08,
              color: theme.fgMuted,
            ),
          ),
          const SizedBox(height: 6),
          // Backend Server Row with DNS/Server Icon
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (isOnline
                            ? theme.successFg
                            : (provider.isConnecting
                                ? theme.accentFg
                                : theme.dangerFg))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (isOnline
                              ? theme.successFg
                              : (provider.isConnecting
                                  ? theme.accentFg
                                  : theme.dangerFg))
                          .withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: provider.isConnecting
                      ? SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.accentFg,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.dns_rounded,
                          size: 13,
                          color: isOnline ? theme.successFg : theme.dangerFg,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOnline
                        ? 'Backend: Online'
                        : (provider.isConnecting
                            ? 'Backend: Starting...'
                            : 'Backend: Offline'),
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
          const SizedBox(height: 2),

          // 1. Reasoning Model Row (Local Chat LLM or Gemini)
          Builder(
            builder: (context) {
              final isGemini = provider.isUsingGemini;
              final isLlmOnline = provider.isLocalLlmOnline;
              final hasSelectedLocal = provider.selectedLocalModel.isNotEmpty;
              final isUsingLocalReasoning = isLlmOnline && hasSelectedLocal;

              final Color llmColor = isUsingLocalReasoning
                  ? theme.successFg
                  : (isGemini
                        ? theme.accentFg
                        : (isLlmOnline ? theme.successFg : theme.dangerFg));
              final IconData llmIcon = isUsingLocalReasoning
                  ? Icons.memory_rounded
                  : (isGemini
                        ? Icons.cloud_done_rounded
                        : Icons.memory_rounded);

              final reasoningText = isUsingLocalReasoning
                  ? 'Reasoning: ${provider.selectedLocalModel}'
                  : (isGemini
                        ? 'Reasoning: Gemini 1.5 Flash (Cloud)'
                        : (isLlmOnline
                              ? (provider.effectiveModel.isNotEmpty
                                    ? 'Reasoning: ${provider.effectiveModel}'
                                    : 'Reasoning: Local LLM')
                              : 'Reasoning: Offline'));

              return Tooltip(
                message: 'Click to configure AI reasoning chat model',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () {
                      provider.openModelSelectionDialog();
                    },
                    borderRadius: BorderRadius.circular(5),
                    hoverColor: theme.accentFg.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: llmColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: llmColor.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Icon(llmIcon, size: 13, color: llmColor),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reasoningText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.fgDefault,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.tune_rounded,
                            size: 13,
                            color: theme.fgMuted.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // 2. Vision Model Row (Shown only in Meeting Scribe mode)
          if (provider.mode == AgentMode.meeting) ...[
            const SizedBox(height: 2),
            Builder(
              builder: (context) {
                final hasVision = provider.hasVisionModel;
                final isGemini = provider.isUsingGemini;
                final isLightweight = provider.useLightweightVision;
                final isVisionActive = isLightweight || hasVision || isGemini;

                final Color visionColor = isVisionActive
                    ? (isLightweight
                          ? AppTheme.teal
                          : (hasVision ? theme.successFg : theme.accentFg))
                    : theme.attentionFg;
                final IconData visionIcon = isLightweight
                    ? Icons.laptop_chromebook_rounded
                    : (hasVision
                          ? Icons.visibility_rounded
                          : (isGemini
                                ? Icons.cloud_done_rounded
                                : Icons.visibility_off_rounded));

                final String visionModelText;
                if (isLightweight) {
                  final name = provider.effectiveModel.isNotEmpty
                      ? provider.effectiveModel
                      : 'Chat LLM';
                  visionModelText = 'Vision: Lightweight ($name)';
                } else if (hasVision) {
                  final name = provider.visionModelName.isNotEmpty
                      ? provider.visionModelName
                      : 'llama3.2-vision';
                  visionModelText = 'Vision: $name';
                } else if (isGemini) {
                  visionModelText = 'Vision: Gemini 1.5 Flash (Cloud)';
                } else {
                  visionModelText = 'Vision: Setup Required';
                }

                return Tooltip(
                  message: isGemini
                      ? 'Gemini Multimodal Cloud Active — No local vision model required. Click to manage.'
                      : (hasVision
                            ? 'Llama Vision active in Ollama. Click to view settings.'
                            : (isLightweight
                                  ? 'Lightweight Laptop Mode: Using ${provider.effectiveModel} + OCR for small laptops. Click to manage.'
                                  : 'Click to setup: Pull llama3.2-vision, enable Lightweight Mode, or configure Gemini.')),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () {
                        _showVisionHelperDialog(context, theme, provider);
                      },
                      borderRadius: BorderRadius.circular(5),
                      hoverColor: visionColor.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: visionColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: visionColor.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Icon(
                                visionIcon,
                                size: 13,
                                color: visionColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                visionModelText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isVisionActive
                                      ? theme.fgDefault
                                      : theme.attentionFg,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.tune_rounded,
                              size: 13,
                              color: theme.fgMuted.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
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

  void _showVisionHelperDialog(
    BuildContext context,
    ThemeData theme,
    ChatProvider provider,
  ) {
    final geminiInputController = TextEditingController(
      text: provider.geminiApiKey,
    );
    bool showGeminiInput = false;
    bool obscureGemini = true;
    bool isRechecking = false;

    showBlurredDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isLightweight = provider.useLightweightVision;
          final hasVision = provider.hasVisionModel;
          final isGemini = provider.isUsingGemini;
          final isReady = isLightweight || hasVision || isGemini;

          final Color badgeColor = isReady
              ? (isLightweight ? AppTheme.teal : theme.successFg)
              : theme.attentionFg;

          return AlertDialog(
            backgroundColor: theme.bgSubtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.borderDefault),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isReady
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: badgeColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visual Intelligence Options',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.fgDefault,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose how DeskMate processes slides & screen content',
                        style: TextStyle(fontSize: 11.5, color: theme.fgMuted),
                      ),
                    ],
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
                    // Status summary banner (dynamically updates when re-checked or switched)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isReady
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            size: 15,
                            color: badgeColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isGemini
                                  ? 'Active: Using Google Gemini Cloud Vision'
                                  : (isLightweight
                                        ? 'Active: Using Lightweight Laptop Mode (${provider.effectiveModel.isNotEmpty ? provider.effectiveModel : "Chat LLM"})'
                                        : (hasVision
                                              ? 'Active: Using Ollama Vision (${provider.visionModelName.isNotEmpty ? provider.visionModelName : "llama3.2-vision"})'
                                              : 'Action Required: Choose an option below to enable recording')),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Option 1: Lightweight Laptop Mode (Ideal for low-spec laptops)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLightweight
                            ? AppTheme.teal.withValues(alpha: 0.08)
                            : theme.bgCanvas,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isLightweight
                              ? AppTheme.teal.withValues(alpha: 0.5)
                              : theme.borderDefault,
                          width: isLightweight ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.laptop_chromebook_rounded,
                                size: 18,
                                color: AppTheme.teal,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Lightweight Laptop Mode',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: theme.fgDefault,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isLightweight
                                      ? theme.successFg.withValues(alpha: 0.12)
                                      : (theme.isDark
                                            ? const Color(
                                                0xFF7C2D12,
                                              ).withValues(alpha: 0.28)
                                            : const Color(0xFFFFF7ED)),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isLightweight
                                        ? theme.successFg.withValues(alpha: 0.3)
                                        : (theme.isDark
                                              ? const Color(
                                                  0xFF9A3412,
                                                ).withValues(alpha: 0.55)
                                              : const Color(0xFFFED7AA)),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isLightweight
                                      ? '✓ CURRENTLY IN USE'
                                      : 'Small Laptop / 8-16GB RAM',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isLightweight
                                        ? theme.successFg
                                        : (theme.isDark
                                              ? const Color(0xFFFDBA74)
                                              : const Color(0xFFC2410C)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Does not require downloading multi-gigabyte vision weights! Uses your active local chat model (${provider.effectiveModel.isNotEmpty ? provider.effectiveModel : 'Ollama chat model'}) with screen OCR and Voxtral speech diarization to generate complete meeting minutes and action items.',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.fgMuted,
                              height: 1.4,
                            ),
                          ),
                          if (!isLightweight) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.bolt_rounded, size: 16),
                                label: const Text(
                                  'Switch to Lightweight Laptop Mode',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: () async {
                                  await provider.setUseLightweightVision(true);
                                  if (!context.mounted) return;
                                  setDialogState(() {});
                                  widget.onShowTopNotification?.call(
                                    'Active: Lightweight Laptop Mode enabled',
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 2: Pull Local Multimodal Vision Model
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasVision && !isLightweight && !isGemini
                            ? theme.successFg.withValues(alpha: 0.08)
                            : theme.bgCanvas,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasVision && !isLightweight && !isGemini
                              ? theme.successFg.withValues(alpha: 0.5)
                              : (hasVision
                                    ? theme.successFg.withValues(alpha: 0.3)
                                    : theme.borderDefault),
                          width: (hasVision && !isLightweight && !isGemini)
                              ? 1.5
                              : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.visibility_rounded,
                                size: 18,
                                color: hasVision
                                    ? theme.successFg
                                    : theme.accentFg,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Full Vision: ${provider.visionModelName.isNotEmpty ? provider.visionModelName : "llama3.2-vision"}',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: theme.fgDefault,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (hasVision && !isLightweight && !isGemini
                                              ? theme.successFg
                                              : (hasVision
                                                    ? theme.successFg
                                                    : theme.accentFg))
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  hasVision && !isLightweight && !isGemini
                                      ? '✓ CURRENTLY IN USE'
                                      : (hasVision
                                            ? '✓ INSTALLED IN OLLAMA'
                                            : 'High-End Laptops / 16GB+ RAM'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: hasVision
                                        ? theme.successFg
                                        : theme.accentFg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hasVision
                                ? '${provider.visionModelName.isNotEmpty ? provider.visionModelName : "llama3.2-vision"} is installed in Ollama for 100% offline pixel-by-pixel screen analysis.'
                                : 'Inspects raw screenshots pixel-by-pixel. Pull and run this model in Ollama via your Mac terminal:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.fgMuted,
                              height: 1.4,
                            ),
                          ),
                          if (hasVision) ...[
                            if (isLightweight || isGemini) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Select ${provider.visionModelName.isNotEmpty ? provider.visionModelName : "llama3.2-vision"} as Active Mode',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.successFg,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () async {
                                    await provider.setUseLightweightVision(
                                      false,
                                    );
                                    if (!context.mounted) return;
                                    setDialogState(() {});
                                    widget.onShowTopNotification?.call(
                                      'Active: Full Vision Mode (${provider.visionModelName.isNotEmpty ? provider.visionModelName : "llama3.2-vision"})',
                                    );
                                  },
                                ),
                              ),
                            ],
                          ] else ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.bgSubtle,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: theme.borderDefault),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      'ollama run llama3.2-vision',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: theme.accentFg,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                    ),
                                    tooltip: 'Copy Command',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      copyWithFeedback(
                                        context,
                                        'ollama run llama3.2-vision',
                                        label: 'Command copied',
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 3: Gemini Cloud Vision (with tune icon and API key setup)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isGemini
                            ? theme.successFg.withValues(alpha: 0.08)
                            : theme.bgCanvas,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isGemini
                              ? theme.successFg.withValues(alpha: 0.5)
                              : theme.borderDefault,
                          width: isGemini ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.cloud_done_rounded,
                                size: 18,
                                color: isGemini
                                    ? theme.successFg
                                    : theme.accentFg,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Google Gemini Cloud Vision',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: theme.fgDefault,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isGemini
                                      ? theme.successFg.withValues(alpha: 0.12)
                                      : (theme.isDark
                                            ? const Color(
                                                0xFF581C87,
                                              ).withValues(alpha: 0.28)
                                            : const Color(0xFFF3E8FF)),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isGemini
                                        ? theme.successFg.withValues(alpha: 0.3)
                                        : (theme.isDark
                                              ? const Color(
                                                  0xFF7E22CE,
                                                ).withValues(alpha: 0.55)
                                              : const Color(0xFFE9D5FF)),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isGemini
                                      ? '✓ CURRENTLY IN USE'
                                      : 'Zero RAM / Cloud',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isGemini
                                        ? theme.successFg
                                        : (theme.isDark
                                              ? const Color(0xFFD8B4FE)
                                              : const Color(0xFF7E22CE)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Zero local RAM used. Multimodal vision is processed natively via Gemini 1.5 Flash in Google Cloud.',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.fgMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (showGeminiInput) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.bgSubtle,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.borderDefault),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.tune_rounded, size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Google Gemini API Key',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: theme.fgDefault,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: geminiInputController,
                                    obscureText: obscureGemini,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Enter API Key (AIzaSy...)',
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        color: theme.fgMuted,
                                      ),
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(
                                          color: theme.borderDefault,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          obscureGemini
                                              ? Icons.visibility_rounded
                                              : Icons.visibility_off_rounded,
                                          size: 16,
                                        ),
                                        onPressed: () {
                                          setDialogState(
                                            () =>
                                                obscureGemini = !obscureGemini,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setDialogState(
                                            () => showGeminiInput = false,
                                          );
                                        },
                                        child: Text(
                                          'Cancel',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: theme.fgMuted,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'Save & Activate',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.accentFg,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                        ),
                                        onPressed: () async {
                                          final key = geminiInputController.text
                                              .trim();
                                          if (key.isNotEmpty) {
                                            await provider.saveAiConfiguration(
                                              model:
                                                  provider.selectedLocalModel,
                                              geminiApiKey: key,
                                            );
                                            if (!context.mounted) return;
                                            setDialogState(() {
                                              showGeminiInput = false;
                                            });
                                            widget.onShowTopNotification?.call(
                                              'Active: Google Gemini Cloud Vision activated',
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.tune_rounded,
                                      size: 15,
                                    ),
                                    label: Text(
                                      isGemini
                                          ? 'Configure / Edit Gemini API Key'
                                          : 'Setup Gemini API Key',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isGemini
                                          ? theme.bgSubtle
                                          : theme.accentFg,
                                      foregroundColor: isGemini
                                          ? theme.fgDefault
                                          : Colors.white,
                                      side: isGemini
                                          ? BorderSide(
                                              color: theme.borderDefault,
                                            )
                                          : BorderSide.none,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    onPressed: () {
                                      setDialogState(
                                        () => showGeminiInput = true,
                                      );
                                    },
                                  ),
                                ),
                                if (isGemini) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                    ),
                                    tooltip: 'Remove Gemini Key',
                                    onPressed: () async {
                                      await provider.saveAiConfiguration(
                                        model: provider.selectedLocalModel,
                                        geminiApiKey: '',
                                      );
                                      if (!context.mounted) return;
                                      geminiInputController.text = '';
                                      setDialogState(() {});
                                      widget.onShowTopNotification?.call(
                                        'Gemini API key removed',
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Close', style: TextStyle(color: theme.fgMuted)),
              ),
              ElevatedButton.icon(
                onPressed: isRechecking
                    ? null
                    : () async {
                        setDialogState(() {
                          isRechecking = true;
                        });
                        try {
                          await provider.retryConnecting();
                          await provider.fetchAvailableModels();
                        } catch (e) {
                          // ignore error
                        } finally {
                          final isLightweight = provider.useLightweightVision;
                          final hasVision = provider.hasVisionModel;
                          final isGemini = provider.isUsingGemini;
                          final String statusText;
                          if (isGemini) {
                            statusText =
                                'Active: Google Gemini 1.5 Flash Cloud Vision';
                          } else if (isLightweight) {
                            statusText =
                                'Active: Lightweight Laptop Mode (${provider.effectiveModel.isNotEmpty ? provider.effectiveModel : "Local Chat LLM"})';
                          } else if (hasVision) {
                            statusText =
                                'Active: Local Ollama Vision (${provider.visionModelName.isNotEmpty ? provider.visionModelName : "llama3.2-vision"})';
                          } else {
                            statusText =
                                '${provider.availableLocalModels.length} models detected. Vision model setup needed.';
                          }

                          setDialogState(() {
                            isRechecking = false;
                          });
                          widget.onShowTopNotification?.call(
                            'Refreshed: $statusText',
                          );
                        }
                      },
                icon: isRechecking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(isRechecking ? 'Checking...' : 'Re-check Status'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentFg,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) => geminiInputController.dispose());
  }

  Widget _buildNewChatButton(ChatProvider provider, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => provider.resetChat(),
        borderRadius: BorderRadius.circular(6),
        hoverColor: theme.bgEmphasis,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: theme.bgCanvas,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_comment_outlined, size: 13, color: theme.fgMuted),
              const SizedBox(width: 6),
              Text(
                'New Conversation',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentGuidesSection(ChatProvider provider, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 12, color: theme.fgMuted),
            const SizedBox(width: 6),
            Text(
              'AGENT GUIDE & DOCS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: theme.fgMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (provider.mode == AgentMode.deskMate) ...[
          // File Explorer & Local LLM Guide
          _buildSidebarGuideCard(
            theme: theme,
            icon: Icons.folder_open_rounded,
            title: 'File Copilot & LLM Guide',
            subtitle: 'Local models, RAG vector DB & Ollama',
            badge: '100% Offline',
            onTap: () => widget.onOpenSetupGuide?.call(AgentMode.deskMate),
          ),
        ] else if (provider.mode == AgentMode.personal) ...[
          // Personal Agent Setup Guide
          _buildSidebarGuideCard(
            theme: theme,
            icon: Icons.person_rounded,
            title: 'Personal Agent Guide',
            subtitle: 'Google OAuth, Gmail, Calendar, Drive',
            badge: 'Workspace',
            onTap: () => widget.onOpenSetupGuide?.call(AgentMode.personal),
          ),
        ] else if (provider.mode == AgentMode.meeting) ...[
          // Meeting Scribe Setup Guide
          _buildSidebarGuideCard(
            theme: theme,
            icon: Icons.mic_rounded,
            title: 'Meeting Scribe Guide',
            subtitle: 'Voxtral 4B, Drive PDF & Gmail Sync',
            badge: 'Intelligence',
            onTap: () => widget.onOpenSetupGuide?.call(AgentMode.meeting),
          ),
        ],
      ],
    );
  }

  Widget _buildSidebarGuideCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: theme.bgEmphasis,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8.5),
          decoration: BoxDecoration(
            color: theme.isDark ? theme.bgCanvas : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: theme.accentFg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, size: 14, color: theme.accentFg),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.fgDefault,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4.5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.isDark
                                ? theme.bgSubtle
                                : const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: theme.fgMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: theme.fgMuted,
                        height: 1.3,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: theme.fgMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthCard({
    required ThemeData theme,
    required String status,
    required String title,
    required String offlineLabel,
    required List<Widget> rows,
  }) {
    if (status == 'loading') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.fgMuted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildFileAgentHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.fileAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final isOnline = provider.isBackendOnline;
    final hasFs = isOnline && (checks['filesystem_access'] ?? true);
    final hasQdrant = isOnline && (checks['qdrant_db'] ?? true);
    final isPrivacy = isOnline && (checks['privacy_mode'] ?? true);

    return _buildHealthCard(
      theme: theme,
      status: isOnline ? 'online' : 'offline',
      title: 'FILE EXPLORER HEALTH',
      offlineLabel: 'File Explorer offline',
      rows: [
        _buildHealthRow(theme, 'Filesystem Access', hasFs),
        const SizedBox(height: 4),
        _buildHealthRow(theme, 'Qdrant Vector DB', hasQdrant),
        const SizedBox(height: 4),
        _buildHealthRow(theme, 'Privacy Mode', isPrivacy),
      ],
    );
  }

  Widget _buildPersonalHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final isOnline = provider.isBackendOnline;

    return _buildHealthCard(
      theme: theme,
      status: isOnline ? 'online' : 'offline',
      title: 'PERSONAL AGENT HEALTH',
      offlineLabel: 'Personal Agent offline',
      rows: [
        _buildHealthRow(
          theme,
          'Credentials JSON',
          isOnline && (checks['google_credentials_file'] ?? false),
        ),
        const SizedBox(height: 4),
        _buildHealthRow(
          theme,
          'Gmail Access',
          isOnline && (checks['gmail_token'] ?? false),
        ),
        const SizedBox(height: 4),
        _buildHealthRow(
          theme,
          'Calendar Access',
          isOnline && (checks['calendar_token'] ?? false),
        ),
        const SizedBox(height: 4),
        _buildHealthRow(
          theme,
          'Drive Access',
          isOnline && (checks['drive_token'] ?? false),
        ),
      ],
    );
  }

  Widget _buildMeetingHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final isOnline = provider.isBackendOnline;
    final status = isOnline
        ? (health['status'] as String? ?? 'online')
        : 'offline';

    return _buildHealthCard(
      theme: theme,
      status: status,
      title: 'MEETING SCRIBE HEALTH',
      offlineLabel: 'Meeting Scribe offline',
      rows: [
        _buildHealthRow(
          theme,
          'Google OAuth',
          isOnline && (checks['google_credentials_file'] ?? false),
        ),
        const SizedBox(height: 4),
        _buildHealthRow(
          theme,
          'Drive Cloud Sync',
          isOnline && (checks['drive_token'] ?? false),
        ),
        const SizedBox(height: 4),
        _buildHealthRow(
          theme,
          'Gmail Dispatch',
          isOnline && (checks['gmail_token'] ?? false),
        ),
        const SizedBox(height: 4),
        _buildHealthRow(theme, 'Voxtral 4B Audio', isOnline),
        const SizedBox(height: 4),
        _buildHealthRow(theme, 'LocateAnything-3B', isOnline),
      ],
    );
  }

  Widget _buildHealthRow(
    ThemeData theme,
    String label,
    bool isOk, [
    String? statusText,
  ]) {
    final displayStatus = statusText ?? (isOk ? 'Online' : 'Offline');
    return Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: isOk ? theme.successFg : theme.dangerFg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            isOk ? Icons.check_rounded : Icons.close_rounded,
            size: 9.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.fgDefault,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          displayStatus,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: isOk ? theme.successFg : theme.dangerFg,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsButton(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: widget.onOpenSettings,
        borderRadius: BorderRadius.circular(6),
        hoverColor: theme.bgEmphasis,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.isDark ? theme.bgCanvas : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.settings_outlined, size: 16, color: theme.accentFg),
              const SizedBox(width: 8),
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.fgDefault,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatabaseExplorerButton(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () {
          if (widget.onOpenDatabaseExplorer != null) {
            widget.onOpenDatabaseExplorer!();
          } else {
            showBlurredDialog(
              context: context,
              builder: (ctx) => DatabaseExplorerDialog(
                onClose: () => Navigator.of(ctx).pop(),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(6),
        hoverColor: theme.bgEmphasis,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: theme.isDark ? theme.bgCanvas : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.storage_rounded, size: 16, color: theme.accentFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Database Explorer',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: theme.fgDefault,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: theme.accentMuted,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SQLite',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: theme.accentFg,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
