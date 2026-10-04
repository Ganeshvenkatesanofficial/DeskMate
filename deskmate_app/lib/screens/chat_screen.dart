import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/sidebar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSettingsOpen = false;
  final TextEditingController _geminiKeyController = TextEditingController();
  final FocusNode _geminiKeyFocusNode = FocusNode();
  late TextEditingController _backendUrlController;
  late FocusNode _backendUrlFocusNode;

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
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _geminiKeyController.dispose();
    _geminiKeyFocusNode.dispose();
    _backendUrlController.dispose();
    _backendUrlFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _openSettings() {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _backendUrlController.text = provider.backendUrl;
    setState(() {
      _isSettingsOpen = true;
    });
  }

  void _closeSettings() {
    setState(() {
      _isSettingsOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final theme = Theme.of(context);

    // Auto-scroll on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event.logicalKey.keyLabel == 'Escape' && _isSettingsOpen) {
          _closeSettings();
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
                    icon: Icon(Icons.settings_outlined, color: theme.fgMuted),
                  ),
                  IconButton(
                    onPressed: () => provider.resetChat(),
                    icon: Icon(Icons.refresh, color: theme.fgMuted),
                  ),
                ],
              ),
        drawer: isDesktop
            ? null
            : Drawer(child: Sidebar(onOpenSettings: _openSettings)),
        body: Stack(
          children: [
            Row(
              children: [
                if (isDesktop) Sidebar(onOpenSettings: _openSettings),
                Expanded(
                  child: Container(
                    color: theme.bgCanvas,
                    child: Column(
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
                                    if (index == provider.messages.length) {
                                      return _buildTypingIndicator(theme);
                                    }
                                    return ChatBubble(
                                      message: provider.messages[index],
                                    );
                                  },
                                ),
                        ),
                        _buildInputArea(provider, theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (provider.showModelSelectionDialog &&
                provider.availableLocalModels.length > 1)
              Positioned.fill(
                child: Container(
                  color: const Color(0xB3010409), // rgba(1, 4, 9, 0.70)
                  child: Center(
                    child: _buildModelSelectionPopup(context, provider, theme),
                  ),
                ).animate().fadeIn(duration: 200.ms),
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
                width: 420,
                child: _buildSettingsPanel(provider, theme).animate().slideX(
                  begin: 1.0,
                  end: 0.0,
                  duration: 200.ms,
                  curve: Curves.easeOut,
                ),
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
        boxShadow: [
          BoxShadow(
            color: const Color(0x40010409),
            blurRadius: 24,
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Panel Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: theme.fgDefault,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage your DeskMate preferences',
                        style: TextStyle(fontSize: 12, color: theme.fgMuted),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: _closeSettings,
                    icon: Icon(Icons.close, color: theme.fgMuted, size: 20),
                    hoverColor: theme.bgEmphasis,
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            Divider(color: theme.borderDefault, height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- SECTION 1: APPEARANCE ---
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose how DeskMate looks.',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Theme Mode',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildThemeSelectorInSettings(provider, theme),

                    const SizedBox(height: 28),
                    Divider(color: theme.borderDefault, height: 1),
                    const SizedBox(height: 28),

                    // --- SECTION 2: AI CONFIGURATION ---
                    Text(
                      'AI Configuration',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure your AI provider.',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Gemini API Key',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _geminiKeyController,
                        obscureText: !_geminiKeyFocusNode.hasFocus,
                        focusNode: _geminiKeyFocusNode,
                        style: TextStyle(fontSize: 13, color: theme.fgDefault),
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.vpn_key_outlined,
                            size: 16,
                            color: theme.fgMuted,
                          ),
                          hintText: 'Enter Gemini API Key',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          provider.setGeminiApiKey(_geminiKeyController.text);
                          _geminiKeyController.clear();
                          FocusScope.of(context).unfocus();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Gemini API Key loaded for this session.',
                              ),
                              duration: const Duration(seconds: 2),
                              backgroundColor: theme.successFg,
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
                        icon: const Icon(Icons.vpn_key, size: 15),
                        label: const Text('Load Gemini API'),
                      ),
                    ),

                    const SizedBox(height: 28),
                    Divider(color: theme.borderDefault, height: 1),
                    const SizedBox(height: 28),

                    // --- SECTION 3: BACKEND ---
                    Text(
                      'Backend',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Connect DeskMate to your backend.',
                      style: TextStyle(fontSize: 12, color: theme.fgMuted),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Backend URL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.fgDefault,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _backendUrlController,
                        focusNode: _backendUrlFocusNode,
                        style: TextStyle(fontSize: 13, color: theme.fgDefault),
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.link,
                            size: 16,
                            color: theme.fgMuted,
                          ),
                          hintText: 'Enter Backend URL',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: (value) {
                          provider.setBackendUrl(value);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          provider.setBackendUrl(_backendUrlController.text);
                          FocusScope.of(context).unfocus();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Backend URL saved.'),
                              duration: const Duration(seconds: 2),
                              backgroundColor: theme.accentEmphasis,
                            ),
                          );
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
                        icon: const Icon(Icons.save, size: 15),
                        label: const Text('Save URL'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
      child: GestureDetector(
        onTap: () => provider.setThemeMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
    );
  }

  Widget _buildModelSelectionPopup(
    BuildContext context,
    ChatProvider provider,
    ThemeData theme,
  ) {
    String tempSelected = provider.selectedLocalModel.isNotEmpty
        ? provider.selectedLocalModel
        : provider.availableLocalModels.first;

    return StatefulBuilder(
      builder: (context, setPopupState) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: theme.borderDefault, width: 1),
          ),
          elevation: 8,
          backgroundColor: theme.bgOverlay,
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.isDark ? theme.bgEmphasis : theme.bgSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.borderDefault,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.memory_rounded,
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
                            'Multiple Local Models Detected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.fgDefault,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select which Ollama model to use for your AI queries:',
                            style: TextStyle(
                              fontSize: 12,
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
                const SizedBox(height: 14),
                Text(
                  'AVAILABLE MODELS ON THIS LAPTOP (${provider.availableLocalModels.length}):',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                    color: theme.fgMuted,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      children: provider.availableLocalModels.map((modelName) {
                        final isSelected = tempSelected == modelName;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (theme.isDark
                                      ? theme.bgEmphasis
                                      : theme.bgSubtle)
                                : theme.bgCanvas,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                  ? theme.accentFg
                                  : theme.borderDefault,
                              width: 1,
                            ),
                          ),
                          child: RadioListTile<String>(
                            value: modelName,
                            // ignore: deprecated_member_use
                            groupValue: tempSelected,
                            activeColor: theme.accentFg,
                            title: Text(
                              modelName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: theme.fgDefault,
                              ),
                            ),
                            subtitle: Text(
                              isSelected
                                  ? 'Active Selection'
                                  : 'Click to select',
                              style: TextStyle(
                                fontSize: 11,
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
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                        side: BorderSide(color: theme.borderDefault, width: 1),
                        foregroundColor: theme.fgDefault,
                      ),
                      child: const Text('Use Default'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        provider.setSelectedLocalModel(tempSelected);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentEmphasis,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Proceed with Selected Model'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final isPersonal = provider.mode == AgentMode.personal;

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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.isDark ? theme.bgSubtle : theme.bgSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.borderDefault, width: 1),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 32,
                  color: theme.accentFg,
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.4,
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

  Widget _buildTypingIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.accentFg,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Assistant is thinking...',
            style: TextStyle(
              fontSize: 12,
              color: theme.fgMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 150.ms),
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
                  OutlinedButton.icon(
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
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: TextStyle(color: theme.fgDefault, fontSize: 13),
                    onSubmitted: (val) {
                      if (val.isNotEmpty) {
                        provider.sendMessage(val);
                        _messageController.clear();
                      }
                    },
                    decoration: InputDecoration(
                      hintText:
                          (!provider.isLocalLlmOnline &&
                              !provider.isUsingGemini)
                          ? 'Please configure your Gemini API Key in Settings to continue...'
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
                  child: ElevatedButton(
                    onPressed:
                        provider.isSending ||
                            (!provider.isLocalLlmOnline &&
                                !provider.isUsingGemini)
                        ? null
                        : () {
                            if (_messageController.text.isNotEmpty) {
                              provider.sendMessage(_messageController.text);
                              _messageController.clear();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: theme.accentEmphasis,
                      disabledBackgroundColor: theme.bgEmphasis,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
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
              ],
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Powered by DeskMate AI • Open Source Edition',
                style: TextStyle(fontSize: 10, color: theme.fgMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
