import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'database_explorer_dialog.dart';

class Sidebar extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  final void Function([AgentMode? mode])? onOpenSetupGuide;
  final VoidCallback? onOpenDatabaseExplorer;
  const Sidebar({
    super.key,
    this.onOpenSettings,
    this.onOpenSetupGuide,
    this.onOpenDatabaseExplorer,
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
                                    'DeskMate AI • v1.0.0',
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
        color: theme.isDark ? theme.bgCanvas : theme.bgCanvas,
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
                    color: (isOnline ? theme.successFg : theme.dangerFg)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (isOnline ? theme.successFg : theme.dangerFg)
                          .withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.dns_rounded,
                    size: 13,
                    color: isOnline ? theme.successFg : theme.dangerFg,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOnline ? 'Backend Online' : 'Backend Offline',
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

          // Processor / Chip Icon for Local LLM or Cloud Icon for Gemini (Clickable to open Model Configuration)
          Builder(
            builder: (context) {
              final isGemini = provider.isUsingGemini;
              final isLlmOnline = provider.isLocalLlmOnline;
              final Color llmColor = isGemini
                  ? theme.accentFg
                  : (isLlmOnline ? theme.successFg : theme.dangerFg);
              final IconData llmIcon = isGemini
                  ? Icons.cloud_done_rounded
                  : Icons.memory_rounded; // Microchip / Processor icon

              final modelText = isGemini
                  ? 'Gemini (Flash) Active'
                  : (isLlmOnline
                        ? (provider.selectedLocalModel.isNotEmpty
                              ? 'Local: ${provider.selectedLocalModel}'
                              : 'Local LLM Active')
                        : 'Local LLM Offline');

              return Tooltip(
                message: 'Click to configure AI model & Gemini key',
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
                              modelText,
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
        ],
      ),
    );
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

  Widget _buildFileAgentHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.fileAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final status = health['status'] as String? ?? 'loading';

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

    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.dangerBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.dangerBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.dangerFg, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'File Copilot offline',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.dangerFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasFs = checks['filesystem_access'] ?? false;
    final hasQdrant = checks['qdrant_db'] ?? false;
    final hasPrivacy = checks['privacy_mode'] ?? true;

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
            'FILE COPILOT HEALTH',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.fgMuted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 8),
          _buildHealthRow(theme, 'Filesystem Access', hasFs),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Qdrant Vector DB', hasQdrant),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Privacy Mode', hasPrivacy),
        ],
      ),
    );
  }

  Widget _buildPersonalHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final status = health['status'] as String? ?? 'loading';

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

    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.dangerBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.dangerBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.dangerFg, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Personal Agent offline',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.dangerFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasCredsFile = checks['google_credentials_file'] ?? false;
    final hasGmailToken = checks['gmail_token'] ?? false;
    final hasCalToken = checks['calendar_token'] ?? false;
    final hasDriveToken = checks['drive_token'] ?? false;

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
            'PERSONAL HEALTH',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.fgMuted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 8),
          _buildHealthRow(theme, 'Credentials JSON', hasCredsFile),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Gmail Access', hasGmailToken),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Calendar Access', hasCalToken),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Drive Access', hasDriveToken),
        ],
      ),
    );
  }

  Widget _buildMeetingHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final status = health['status'] as String? ?? 'loading';

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

    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.dangerBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.dangerBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.dangerFg, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Meeting Scribe offline',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.dangerFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasCredsFile = checks['google_credentials_file'] ?? false;
    final hasGmailToken = checks['gmail_token'] ?? false;
    final hasDriveToken = checks['drive_token'] ?? false;

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
            'MEETING SCRIBE HEALTH',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.fgMuted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 8),
          _buildHealthRow(theme, 'Google OAuth', hasCredsFile),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Drive Cloud Sync', hasDriveToken),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Gmail Dispatch', hasGmailToken),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'Voxtral 4B Audio', true),
          const SizedBox(height: 4),
          _buildHealthRow(theme, 'LocateAnything-3B', true),
        ],
      ),
    );
  }

  Widget _buildHealthRow(ThemeData theme, String label, bool isOk, [String? statusText]) {
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
              color: isOk
                  ? theme.fgDefault
                  : (theme.isDark ? const Color(0xFFFFA198) : theme.dangerFg),
              fontWeight: isOk ? FontWeight.w600 : FontWeight.w500,
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
            showDialog(
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
