import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class Sidebar extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  const Sidebar({super.key, this.onOpenSettings});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final theme = Theme.of(context);

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        border: Border(right: BorderSide(color: theme.borderDefault, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BRAND HEADER ---
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.isDark ? theme.bgEmphasis : theme.bgCanvas,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.borderDefault, width: 1),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: theme.accentFg, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DeskMate',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Open Source AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.fgMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- MODE SELECTOR ---
            _buildModeSelector(provider, theme),
            const SizedBox(height: 14),

            // --- STATUS CARD ---
            _buildStatusCard(provider, theme),

            if (provider.mode == AgentMode.personal) ...[
              const SizedBox(height: 14),
              _buildPersonalHealthCard(provider, theme),
            ],

            const Spacer(),

            // --- SETTINGS BUTTON AT BOTTOM ---
            const SizedBox(height: 12),
            _buildSettingsButton(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(ChatProvider provider, ThemeData theme) {
    final isDeskMate = provider.mode == AgentMode.deskMate;
    final isPersonal = provider.mode == AgentMode.personal;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => provider.switchMode(AgentMode.deskMate),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
              decoration: BoxDecoration(
                color: isDeskMate
                    ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: isDeskMate
                    ? Border.all(color: theme.borderDefault, width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 15,
                    color: isDeskMate ? theme.accentFg : theme.fgMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'File Explorer',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDeskMate ? theme.fgDefault : theme.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          GestureDetector(
            onTap: () => provider.switchMode(AgentMode.personal),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
              decoration: BoxDecoration(
                color: isPersonal
                    ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: isPersonal
                    ? Border.all(color: theme.borderDefault, width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 15,
                    color: isPersonal ? theme.accentFg : theme.fgMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Personal Agent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPersonal ? theme.fgDefault : theme.fgMuted,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isOnline ? theme.successFg : theme.dangerFg,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isOnline ? 'Backend Online' : 'Backend Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isOnline ? theme.fgDefault : theme.dangerFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: provider.isUsingGemini
                      ? theme.accentFg
                      : (provider.isLocalLlmOnline ? theme.successFg : theme.dangerFg),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.isUsingGemini
                      ? 'Gemini (Flash) Active'
                      : (provider.isLocalLlmOnline
                          ? (provider.selectedLocalModel.isNotEmpty ? 'Local: ${provider.selectedLocalModel}' : 'Local LLM Active')
                          : 'Local LLM Offline'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: provider.isUsingGemini
                        ? theme.accentFg
                        : (provider.isLocalLlmOnline ? theme.successFg : theme.dangerFg),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (provider.availableLocalModels.length > 1 && !provider.isUsingGemini) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: BoxDecoration(
                color: theme.bgSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderDefault, width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: provider.selectedLocalModel.isNotEmpty && provider.availableLocalModels.contains(provider.selectedLocalModel)
                      ? provider.selectedLocalModel
                      : provider.availableLocalModels.first,
                  isExpanded: true,
                  dropdownColor: theme.bgOverlay,
                  icon: Icon(Icons.arrow_drop_down, size: 16, color: theme.fgMuted),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.fgDefault),
                  onChanged: (val) {
                    if (val != null) {
                      provider.setSelectedLocalModel(val);
                    }
                  },
                  items: provider.availableLocalModels.map((m) {
                    return DropdownMenuItem<String>(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
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
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.accentFg))),
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
                style: TextStyle(fontSize: 11, color: theme.dangerFg, fontWeight: FontWeight.w600),
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

  Widget _buildHealthRow(ThemeData theme, String label, bool isOk) {
    return Row(
      children: [
        Icon(
          isOk ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 13,
          color: isOk ? theme.successFg : theme.fgMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isOk ? theme.fgDefault : theme.fgMuted,
              fontWeight: isOk ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsButton(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpenSettings,
        borderRadius: BorderRadius.circular(6),
        hoverColor: theme.bgEmphasis,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 16, color: theme.fgMuted),
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
}
