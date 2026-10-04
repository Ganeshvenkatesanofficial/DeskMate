import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/chat_provider.dart';
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final theme = Theme.of(context);

    // Auto-scroll on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('DeskMate'),
              actions: [
                IconButton(
                  onPressed: () => provider.resetChat(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      drawer: isDesktop ? null : const Drawer(child: Sidebar()),
      body: Stack(
        children: [
          Row(
            children: [
              if (isDesktop) const Sidebar(),
              Expanded(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      Expanded(
                        child: provider.messages.isEmpty
                            ? _buildEmptyState(theme)
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                                itemCount: provider.messages.length + (provider.isSending ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == provider.messages.length) {
                                    return _buildTypingIndicator(theme);
                                  }
                                  return ChatBubble(message: provider.messages[index]);
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
          if (provider.showModelSelectionDialog && provider.availableLocalModels.length > 1)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: _buildModelSelectionPopup(context, provider, theme),
                ),
              ).animate().fadeIn(duration: 250.ms),
            ),
        ],
      ),
    );
  }

  Widget _buildModelSelectionPopup(BuildContext context, ChatProvider provider, ThemeData theme) {
    String tempSelected = provider.selectedLocalModel.isNotEmpty
        ? provider.selectedLocalModel
        : provider.availableLocalModels.first;

    return StatefulBuilder(
      builder: (context, setPopupState) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 12,
          backgroundColor: theme.scaffoldBackgroundColor,
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.memory_rounded, color: theme.colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Multiple Local Models Detected',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Select which Ollama model to use for your AI queries:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'AVAILABLE MODELS ON THIS LAPTOP (${provider.availableLocalModels.length}):',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.hintColor,
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
                                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                                : theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.dividerColor,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: RadioListTile<String>(
                            value: modelName,
                            groupValue: tempSelected,
                            activeColor: theme.colorScheme.primary,
                            title: Text(
                              modelName,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              isSelected ? 'Active Selection' : 'Click to select',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected ? theme.colorScheme.primary : theme.hintColor,
                              ),
                            ),
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
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        provider.dismissModelSelectionDialog();
                      },
                      child: const Text('Use Default'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        provider.setSelectedLocalModel(tempSelected);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Proceed with Selected Model'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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

    final title = isPersonal ? 'DeskMate Personal Agent' : 'Welcome to DeskMate';
    final subtitle = isPersonal
        ? 'Your free offline & cloud assistant. Manage tasks, notes, weather, emails, and calendar.'
        : 'Search, analyze, and manage your local files with smart AI capability.';

    final examples = isPersonal
        ? [
            {'icon': Icons.task_alt_rounded, 'text': 'Add task to my Google Tasks: Prep demo', 'label': 'Google Tasks'},
            {'icon': Icons.insert_drive_file_outlined, 'text': 'Create a Google Doc named Project Outline containing scope', 'label': 'Google Docs'},
            {'icon': Icons.mail_outline_rounded, 'text': 'Search my sent emails', 'label': 'Gmail Search'},
            {'icon': Icons.calendar_today_rounded, 'text': 'List my calendar events for tomorrow', 'label': 'Google Calendar'},
          ]
        : [
            {'icon': Icons.search_rounded, 'text': 'Find PDF files larger than 10MB', 'label': 'Find Files'},
            {'icon': Icons.analytics_outlined, 'text': 'Summarize recent financial reports', 'label': 'Summarize'},
            {'icon': Icons.find_in_page_outlined, 'text': 'Search "react" inside folder', 'label': 'Grep Search'},
            {'icon': Icons.info_outline, 'text': 'Show details of requirements.txt', 'label': 'Metadata'},
          ];

    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[700]!, Colors.indigo[800]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),
              Text(
                'TRY THESE EXAMPLES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 1.5),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.3,
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

  Widget _buildExampleCard(ThemeData theme, IconData icon, String label, String text) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _messageController.text = text;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue[700], letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3),
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
          CircleAvatar(
            backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.1),
            radius: 12,
            child: const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Assistant is thinking...',
            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ).animate().fadeIn(),
    );
  }

  Widget _buildInputArea(ChatProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.errorMessage.isNotEmpty && !provider.isConnecting && provider.isBackendOnline)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.errorMessage,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (provider.isConnecting)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Initializing local AI service & loading models...',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fadeIn(duration: 400.ms)
              .shimmer(color: Colors.blue[100], duration: 1500.ms),
            )
          else if (!provider.isBackendOnline)
            Container(
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'AI Service is offline. Please wait or retry connecting.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      provider.retryConnecting();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    style: const TextStyle(color: Colors.black),
                    onSubmitted: (val) {
                      if (val.isNotEmpty) {
                        provider.sendMessage(val);
                        _messageController.clear();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: (!provider.isLocalLlmOnline && !provider.isUsingGemini)
                          ? 'Please enter your Gemini API Key in the sidebar to continue...'
                          : provider.mode == AgentMode.personal
                              ? 'Ask about Tasks, Drive Docs, Gmail, Calendar...'
                              : 'Ask about your files...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      enabled: !provider.isSending && (provider.isLocalLlmOnline || provider.isUsingGemini),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  onPressed: provider.isSending || (!provider.isLocalLlmOnline && !provider.isUsingGemini)
                      ? null
                      : () {
                          if (_messageController.text.isNotEmpty) {
                            provider.sendMessage(_messageController.text);
                            _messageController.clear();
                          }
                        },
                  elevation: 0,
                  backgroundColor: provider.isSending || (!provider.isLocalLlmOnline && !provider.isUsingGemini) ? Colors.grey : Colors.blue[700],
                  child: provider.isSending
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Powered by DeskMate AI • Open Source Edition',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
