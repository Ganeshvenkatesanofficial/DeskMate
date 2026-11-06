import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'messages.dart';
import '../../app/app_settings.dart';
import '../core/fa_theme.dart';
import '../shell/pane_header.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';
import 'chat_message_view.dart';
import 'chat_widgets.dart';
import 'composer.dart';
import 'composer_logic.dart';
import 'folder_chat_controller.dart';

/// Ask AI — the chat with the Folder Agent (port of FilDOS's research page).
///
/// The agent's live logs (reasoning, tool calls, observations, timings) are
/// shown with DeskMate's shared telemetry accordion: expanded and live while a
/// turn runs, then collapsed above each finished answer.
class AskAiView extends StatefulWidget {
  const AskAiView({super.key});
  @override
  State<AskAiView> createState() => _AskAiViewState();
}

class _AskAiViewState extends State<AskAiView> {
  final _scroll = ScrollController();
  final _composerKey = GlobalKey<AskAiComposerState>();
  late final FolderChatController _chat = context.read<FolderChatController>();
  late final AskAiSession _session = AskAiSession.of(_chat);
  Object? _lastSignature;

  @override
  void initState() {
    super.initState();
    _chat.refreshHistory();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggleHistory() {
    setState(() => _session.showHistory = !_session.showHistory);
    if (_session.showHistory) _chat.refreshHistory();
  }

  void _newChat() {
    _chat.newChat();
    setState(() => _session.showHistory = false);
  }

  Future<void> _openChat(String id) async {
    setState(() => _session.showHistory = false);
    await _chat.openChat(id);
    _lastSignature = null;
  }

  /// Keep the newest content in view whenever a message or log step arrives.
  void _autoScroll(FolderChatController chat) {
    final last = chat.liveTelemetry.lastOrNull;
    final sig = (chat.messages.length, chat.liveTelemetry.length, last?.summary?.length, chat.liveTitle, chat.sending);
    if (sig == _lastSignature) return;
    _lastSignature = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: FaMotion.medium, curve: FaMotion.snappy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final chat = context.watch<FolderChatController>();
    final app = context.watch<FaController>();
    final provider = context.watch<AppSettings>();
    final showHistory = _session.showHistory;
    final title = chat.chatId == null ? null : chat.history.where((h) => h.id == chat.chatId).firstOrNull?.title;

    return Column(
      children: [
        PaneHeader(
          title: Row(
            children: [
              const DeskMateMark(size: 18),
              const SizedBox(width: 8),
              Text(
                'Ask AI',
                style: FaText.sans(size: 13, weight: FontWeight.w600, color: c.foreground),
              ),
              if (showHistory || title != null) ...[
                const SizedBox(width: 8),
                Text('/', style: FaText.sans(size: 13, color: c.border)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    showHistory ? 'History' : title!,
                    style: FaText.sans(size: 13, color: c.mutedForeground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FaIconButton(
              icon: Icons.history_rounded,
              tooltip: 'History',
              active: showHistory,
              onPressed: _toggleHistory,
            ),
            FaIconButton(icon: Icons.add_rounded, tooltip: 'New chat', onPressed: chat.sending ? null : _newChat),
            FaIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: () => app.showSection(FaSection.browse),
            ),
          ],
        ),
        Expanded(
          child: showHistory
              ? AskAiHistory(chat: chat, onOpen: _openChat)
              : (chat.messages.isEmpty && !chat.sending)
              ? AskAiEmptyState(
                  cloud: provider.isUsingGemini,
                  onPick: (id) => _composerKey.currentState?.applySuggestion(id),
                )
              : _conversation(chat),
        ),
        if (!showHistory)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 784),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._callouts(chat, app, provider),
                  AskAiComposer(key: _composerKey, chat: chat),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _callouts(FolderChatController chat, FaController app, AppSettings provider) {
    void toSettings() => app.showSection(FaSection.settings);
    if (!chat.hasModel) {
      return [
        AskAiCallout(
          icon: Icons.download_rounded,
          tint: Scoop.mint,
          title: 'No chat model yet — install one in Settings',
          detail: 'Ask AI runs on a local model through Ollama, or Gemini with your own key.',
          actionLabel: 'Open Settings',
          onAction: toSettings,
        ),
      ];
    }
    if (!provider.isUsingGemini && !provider.isLocalLlmOnline) {
      return [
        AskAiCallout(
          icon: Icons.power_off_outlined,
          tint: Scoop.mango,
          title: 'The local model server isn’t running',
          detail: 'Start Ollama to chat — /find still works without it.',
          actionLabel: 'Settings',
          onAction: toSettings,
        ),
      ];
    }
    if ((!app.aiEnabled || app.index.indexed == 0) && !_session.indexHintDismissed) {
      return [
        AskAiCallout(
          icon: Icons.manage_search_rounded,
          tint: Scoop.blueberry,
          title: 'Answers about file contents need indexing',
          detail: !app.aiEnabled
              ? 'Turn on search by meaning so the agent can find what your files say.'
              : 'Nothing is indexed yet — add folders to index in Settings.',
          actionLabel: 'Settings',
          onAction: toSettings,
          onDismiss: () => setState(() => _session.indexHintDismissed = true),
        ),
      ];
    }
    return const [];
  }

  Widget _conversation(FolderChatController chat) {
    _autoScroll(chat);
    final items = <Widget>[
      for (final m in chat.messages)
        ChatMessageView(
          key: ValueKey(m.id),
          message: m,
          mentions: m.role == MessageRole.user ? (_session.sentMentions[m.content.trim()] ?? const []) : const [],
        ),
      if (chat.sending) LiveTelemetry(steps: chat.liveTelemetry, title: chat.liveTitle),
    ];
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, i) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(padding: const EdgeInsets.only(bottom: 18), child: items[i]),
        ),
      ),
    );
  }
}
