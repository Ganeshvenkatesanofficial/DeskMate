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

/// Distance from the bottom (px) within which the conversation still counts
/// as "stuck" and follows new content (FilDOS `Conversation`'s STICK_THRESHOLD).
const _stickThreshold = 48.0;

/// The page column: FilDOS `mx-auto max-w-3xl` (768px) for the conversation and the composer.
const _columnWidth = 768.0;

class _AskAiViewState extends State<AskAiView> {
  final _scroll = ScrollController();
  final _composerKey = GlobalKey<AskAiComposerState>();
  late final FolderChatController _chat = context.read<FolderChatController>();
  late final AskAiSession _session = AskAiSession.of(_chat);

  /// Pinned to the newest content; released the moment the user scrolls up.
  bool _stuck = true;
  int _lastCount = 0;

  /// Built message widgets, reused while the message is unchanged so a log
  /// step arriving for the live turn never rebuilds the finished turns.
  final _views = <String, (ChatMessage, Widget)>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _lastCount = _chat.messages.length;
    _chat.refreshHistory();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final stuck = p.maxScrollExtent - p.pixels <= _stickThreshold;
    if (stuck != _stuck) setState(() => _stuck = stuck);
  }

  /// Content or viewport changed size: follow it to the bottom while stuck.
  /// (A jump, as FilDOS sets scrollTop — no animation to fight new content.)
  bool _onMetrics(ScrollMetricsNotification n) {
    if (_stuck && _scroll.hasClients) {
      final p = _scroll.position;
      if (p.pixels != p.maxScrollExtent) p.jumpTo(p.maxScrollExtent);
    }
    return false;
  }

  void _jumpToLatest() {
    setState(() => _stuck = true);
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  /// A new conversation, a reopened one, or a message the user just sent
  /// re-attaches to the bottom.
  void _restick() {
    _stuck = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _toggleHistory() {
    setState(() => _session.showHistory = !_session.showHistory);
    if (_session.showHistory) {
      _chat.refreshHistory();
    } else {
      _restick();
    }
  }

  void _newChat() {
    _chat.newChat();
    _restick();
    setState(() => _session.showHistory = false);
  }

  Future<void> _openChat(String id) async {
    setState(() => _session.showHistory = false);
    await _chat.openChat(id);
    if (mounted) setState(_restick);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final chat = context.watch<FolderChatController>();
    final app = context.watch<FaController>();
    final provider = context.watch<AppSettings>();
    final showHistory = _session.showHistory;
    final title = chat.chatId == null ? null : chat.history.where((h) => h.id == chat.chatId).firstOrNull?.title;
    final count = chat.messages.length;
    if (count != _lastCount) {
      if (count > _lastCount && chat.messages.last.role == MessageRole.user) _restick();
      _lastCount = count;
    }

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
              icon: Icons.schedule_rounded,
              tooltip: 'Conversation history',
              active: showHistory,
              onPressed: _toggleHistory,
            ),
            FaIconButton(
              icon: Icons.add_rounded,
              tooltip: 'New conversation',
              onPressed: chat.sending ? null : _newChat,
            ),
            FaIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close Ask AI',
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
              constraints: const BoxConstraints(maxWidth: _columnWidth),
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

  Widget _messageView(ChatMessage m) {
    final cached = _views[m.id];
    if (cached != null && identical(cached.$1, m)) return cached.$2;
    final view = ChatMessageView(
      key: ValueKey(m.id),
      message: m,
      mentions: m.role == MessageRole.user ? (_session.sentMentions[m.content.trim()] ?? const []) : const [],
    );
    _views[m.id] = (m, view);
    return view;
  }

  /// FilDOS `Conversation` › `flex flex-col gap-4 px-4 mx-auto max-w-3xl py-6`,
  /// pinned to the bottom while stuck, with a "Latest" pill once released.
  Widget _conversation(FolderChatController chat) {
    if (_views.length > chat.messages.length) {
      final ids = {for (final m in chat.messages) m.id};
      _views.removeWhere((id, _) => !ids.contains(id));
    }
    final items = <Widget>[
      for (final m in chat.messages) _messageView(m),
      if (chat.sending) LiveTelemetry(steps: chat.liveTelemetry, title: chat.liveTitle),
    ];
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: _onMetrics,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _columnWidth - 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 16), items[i]],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!_stuck)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(child: _LatestPill(onTap: _jumpToLatest)),
          ),
      ],
    );
  }
}

/// FilDOS "Jump to latest": `h-6 rounded-full border material px-2.5 text-2xs
/// font-medium shadow-md`, fading/zooming in (`zoom-in-95`, 150ms snappy).
class _LatestPill extends StatelessWidget {
  final VoidCallback onTap;
  const _LatestPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      curve: FaMotion.snappy,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
      ),
      child: Tooltip(
        message: 'Jump to latest',
        child: Hoverable(
          onTap: onTap,
          builder: (context, hover) => Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hover ? c.accent : c.popover,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  spreadRadius: -1,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_downward_rounded, size: 11, color: c.foreground),
                const SizedBox(width: 4),
                Text(
                  'Latest',
                  style: FaText.sans(size: 11, weight: FontWeight.w500, color: c.foreground, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
