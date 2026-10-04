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
      decoration: const BoxDecoration(
        color: AppTheme.bgSubtle,
        border: Border(right: BorderSide(color: AppTheme.borderDefault, width: 1)),
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
                            color: AppTheme.bgEmphasis,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.borderDefault, width: 1),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.accentFg, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'DeskMate',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.fgDefault,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              'Open Source AI',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.fgMuted,
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
                    const Text(
                      'CONFIGURATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.08,
                        color: AppTheme.fgMuted,
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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgCanvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderDefault, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => provider.switchMode(AgentMode.deskMate),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: provider.mode == AgentMode.deskMate ? AppTheme.bgEmphasis : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: provider.mode == AgentMode.deskMate
                      ? Border.all(color: AppTheme.borderDefault, width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 15,
                      color: provider.mode == AgentMode.deskMate ? AppTheme.accentFg : AppTheme.fgMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'File Explorer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: provider.mode == AgentMode.deskMate ? AppTheme.fgDefault : AppTheme.fgMuted,
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
                  color: provider.mode == AgentMode.personal ? AppTheme.bgEmphasis : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: provider.mode == AgentMode.personal
                      ? Border.all(color: AppTheme.borderDefault, width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_rounded,
                      size: 15,
                      color: provider.mode == AgentMode.personal ? AppTheme.accentFg : AppTheme.fgMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Personal Agent',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: provider.mode == AgentMode.personal ? AppTheme.fgDefault : AppTheme.fgMuted,
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
        child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentFg))),
      );
    }

    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.dangerBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.dangerBorder, width: 1),
        ),
        child: Row(
          children: const [
            Icon(Icons.error_outline_rounded, color: AppTheme.dangerFg, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Personal Agent server unreachable.',
                style: TextStyle(fontSize: 11, color: AppTheme.dangerFg, fontWeight: FontWeight.w600),
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
        color: AppTheme.bgSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderDefault, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PERSONAL SERVICES HEALTH',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.fgMuted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 10),
          _buildHealthRow('Credentials JSON', hasCredsFile),
          const SizedBox(height: 6),
          _buildHealthRow('Gmail Access', hasGmailToken),
          const SizedBox(height: 6),
          _buildHealthRow('Calendar Access', hasCalToken),
          const SizedBox(height: 6),
          _buildHealthRow('Drive Access', hasDriveToken),
        ],
      ),
    );
  }

  Widget _buildHealthRow(String label, bool isOk) {
    return Row(
      children: [
        Icon(
          isOk ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isOk ? AppTheme.successFg : AppTheme.fgMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isOk ? AppTheme.fgDefault : AppTheme.fgMuted,
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
        color: AppTheme.bgSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderDefault, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? AppTheme.successFg : AppTheme.dangerFg,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isOnline ? 'Backend Online' : 'Backend Offline',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.fgDefault,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.history_edu_outlined, size: 15, color: AppTheme.fgMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  provider.conversationId.isEmpty 
                      ? 'No active session' 
                      : 'Session: ${provider.conversationId.substring(0, 8)}...',
                  style: const TextStyle(fontSize: 12, color: AppTheme.fgMuted),
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
                    ? AppTheme.accentFg 
                    : (provider.isLocalLlmOnline ? AppTheme.successFg : AppTheme.dangerFg),
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
                        ? AppTheme.accentFg 
                        : (provider.isLocalLlmOnline ? AppTheme.successFg : AppTheme.dangerFg),
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
                color: AppTheme.bgCanvas,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderDefault, width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: provider.selectedLocalModel.isNotEmpty && provider.availableLocalModels.contains(provider.selectedLocalModel)
                      ? provider.selectedLocalModel
                      : provider.availableLocalModels.first,
                  isExpanded: true,
                  dropdownColor: AppTheme.bgOverlay,
                  icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.fgMuted),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.fgDefault),
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
        const Text('Gemini API Key', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.fgDefault)),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _geminiKeyController,
            obscureText: !_geminiKeyFocusNode.hasFocus,
            focusNode: _geminiKeyFocusNode,
            style: const TextStyle(fontSize: 13, color: AppTheme.fgDefault),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.vpn_key_outlined, size: 16, color: AppTheme.fgMuted),
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
        const Text('Backend URL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.fgDefault)),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _backendUrlController,
            focusNode: _backendUrlFocusNode,
            style: const TextStyle(fontSize: 13, color: AppTheme.fgDefault),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.link, size: 16, color: AppTheme.fgMuted),
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
        const Text(
          'THEME MODE',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.fgDefault),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppTheme.bgCanvas,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.borderDefault, width: 1),
          ),
          child: Row(
            children: [
              _buildThemeOption(
                provider: provider,
                mode: ThemeMode.light,
                icon: Icons.light_mode_outlined,
                label: 'Light',
              ),
              _buildThemeOption(
                provider: provider,
                mode: ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                label: 'Dark',
              ),
              _buildThemeOption(
                provider: provider,
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
            color: isSelected ? AppTheme.bgEmphasis : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: AppTheme.borderDefault, width: 1) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppTheme.fgDefault : AppTheme.fgMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.fgDefault : AppTheme.fgMuted,
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
        const Divider(color: AppTheme.borderDefault, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('Powered by DeskMate AI • Open Source Edition', style: TextStyle(fontSize: 10, color: AppTheme.fgMuted)),
            SizedBox(width: 6),
            Text('v1.0.0', style: TextStyle(fontSize: 10, color: AppTheme.fgMuted)),
          ],
        ),
      ],
    );
  }
}
