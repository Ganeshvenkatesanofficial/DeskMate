import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final TextEditingController _geminiKeyController = TextEditingController();
  final FocusNode _geminiKeyFocusNode = FocusNode();
  late TextEditingController _backendUrlController;
  late FocusNode _backendUrlFocusNode;

  @override
  void initState() {
    super.initState();
    _backendUrlFocusNode = FocusNode();
    _backendUrlFocusNode.addListener(() {
      setState(() {});
    });
    _geminiKeyFocusNode.addListener(() {
      setState(() {});
    });
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _backendUrlController = TextEditingController(text: provider.backendUrl);
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _backendUrlFocusNode.dispose();
    _geminiKeyController.dispose();
    _geminiKeyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final theme = Theme.of(context);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        border: Border(right: BorderSide(color: theme.borderDefault, width: 1)),
      ),
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: theme.isDark ? theme.bgEmphasis : theme.bgCanvas,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: theme.borderDefault, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accentEmphasis.withValues(alpha: 0.25),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Icon(Icons.auto_awesome_rounded, color: theme.accentFg, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DeskMate',
                              style: TextStyle(
                                fontSize: 16,
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
                    const SizedBox(height: 20),
                    _buildStatusCard(provider, theme),
                    const SizedBox(height: 16),
                    _buildModeSelector(provider, theme),
                    if (provider.mode == AgentMode.personal) ...[
                      const SizedBox(height: 16),
                      _buildPersonalHealthCard(provider, theme),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'CONFIGURATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.08,
                        color: theme.fgMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildThemeSelector(provider, theme),
                    const SizedBox(height: 16),
                    _buildGeminiInput(provider, theme),
                    const SizedBox(height: 16),
                    _buildBackendUrlInput(provider, theme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildFooter(theme),
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
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => provider.switchMode(AgentMode.deskMate),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isDeskMate
                      ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isDeskMate
                      ? Border.all(color: theme.borderDefault, width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 15,
                      color: isDeskMate ? theme.accentFg : theme.fgMuted,
                    ),
                    const SizedBox(width: 6),
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
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => provider.switchMode(AgentMode.personal),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isPersonal
                      ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isPersonal
                      ? Border.all(color: theme.borderDefault, width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_rounded,
                      size: 15,
                      color: isPersonal ? theme.accentFg : theme.fgMuted,
                    ),
                    const SizedBox(width: 6),
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
          ),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.accentFg))),
      );
    }

    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.dangerBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.dangerBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.dangerFg, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Personal Agent server unreachable.',
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgSubtle : theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERSONAL SERVICES HEALTH',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.fgMuted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 10),
          _buildHealthRow(theme, 'Credentials JSON', hasCredsFile),
          const SizedBox(height: 6),
          _buildHealthRow(theme, 'Gmail Access', hasGmailToken),
          const SizedBox(height: 6),
          _buildHealthRow(theme, 'Calendar Access', hasCalToken),
          const SizedBox(height: 6),
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
          size: 14,
          color: isOk ? theme.successFg : theme.fgMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isOk ? theme.fgDefault : theme.fgMuted,
              fontWeight: isOk ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(ChatProvider provider, ThemeData theme) {
    final isOnline = provider.isBackendOnline;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.bgSubtle : theme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.borderDefault, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? theme.successFg : theme.dangerFg,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isOnline ? 'Backend Online' : 'Backend Offline',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isOnline ? (theme.isDark ? theme.fgDefault : theme.fgDefault) : theme.dangerFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.history_edu_outlined, size: 15, color: theme.fgMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  provider.conversationId.isEmpty 
                      ? 'No active session' 
                      : 'Session: ${provider.conversationId.substring(0, 8)}...',
                  style: TextStyle(fontSize: 12, color: theme.fgMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                provider.isUsingGemini ? Icons.auto_awesome : Icons.memory,
                size: 15,
                color: provider.isUsingGemini 
                    ? theme.accentFg 
                    : (provider.isLocalLlmOnline ? theme.successFg : theme.dangerFg),
              ),
              const SizedBox(width: 10),
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
                ),
              ),
            ],
          ),
          if (provider.availableLocalModels.length > 1 && !provider.isUsingGemini) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              decoration: BoxDecoration(
                color: theme.bgCanvas,
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
                  icon: Icon(Icons.arrow_drop_down, size: 18, color: theme.fgMuted),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.fgDefault),
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

  Widget _buildGeminiInput(ChatProvider provider, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gemini API Key', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.fgDefault)),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _geminiKeyController,
            obscureText: !_geminiKeyFocusNode.hasFocus,
            focusNode: _geminiKeyFocusNode,
            style: TextStyle(fontSize: 13, color: theme.fgDefault),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.vpn_key_outlined, size: 16, color: theme.fgMuted),
              hintText: 'Enter Gemini API Key',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton.icon(
            onPressed: () {
              provider.setGeminiApiKey(_geminiKeyController.text);
              _geminiKeyController.clear();
              FocusScope.of(context).unfocus();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentEmphasis,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.vpn_key, size: 15),
            label: const Text('Load Gemini API'),
          ),
        ),
      ],
    );
  }

  Widget _buildBackendUrlInput(ChatProvider provider, ThemeData theme) {
    if (!_backendUrlFocusNode.hasFocus && _backendUrlController.text != provider.backendUrl) {
      _backendUrlController.text = provider.backendUrl;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Backend URL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.fgDefault)),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _backendUrlController,
            focusNode: _backendUrlFocusNode,
            style: TextStyle(fontSize: 13, color: theme.fgDefault),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.link, size: 16, color: theme.fgMuted),
              hintText: 'Enter Backend URL',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onSubmitted: (value) {
              provider.setBackendUrl(value);
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: OutlinedButton.icon(
            onPressed: () {
              provider.setBackendUrl(_backendUrlController.text);
              FocusScope.of(context).unfocus();
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: theme.isDark ? theme.bgEmphasis : theme.bgSubtle,
              side: BorderSide(color: theme.borderDefault, width: 1),
              foregroundColor: theme.fgDefault,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.save, size: 15),
            label: const Text('Save URL'),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSelector(ChatProvider provider, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'THEME MODE',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.fgDefault),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: theme.bgCanvas,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderDefault, width: 1),
          ),
          child: Row(
            children: [
              _buildThemeOption(
                provider: provider,
                theme: theme,
                mode: ThemeMode.light,
                icon: Icons.light_mode_outlined,
                label: 'Light',
              ),
              _buildThemeOption(
                provider: provider,
                theme: theme,
                mode: ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                label: 'Dark',
              ),
              _buildThemeOption(
                provider: provider,
                theme: theme,
                mode: ThemeMode.system,
                icon: Icons.desktop_windows_outlined,
                label: 'System',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required ChatProvider provider,
    required ThemeData theme,
    required ThemeMode mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = provider.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => provider.setThemeMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? (theme.isDark ? theme.bgEmphasis : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: theme.borderDefault, width: 1) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? theme.accentFg : theme.fgMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
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

  Widget _buildFooter(ThemeData theme) {
    return Column(
      children: [
        Divider(color: theme.borderDefault, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Powered by DeskMate AI • Open Source Edition', style: TextStyle(fontSize: 10, color: theme.fgMuted)),
            const SizedBox(width: 6),
            Text('v1.0.0', style: TextStyle(fontSize: 10, color: theme.fgMuted)),
          ],
        ),
      ],
    );
  }
}
