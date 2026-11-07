import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../state/fa_controller.dart';
import 'messages.dart';

/// Ask AI state: the open conversation, the live agent log of the turn in
/// flight, saved chats, and the `/ws/folder-agent` socket.
///
/// The engine owns the model, the Gemini key, the conversation history and the
/// system prompt; a turn sends only what the user typed and the explorer
/// context, and receives the engine's `AgentTelemetry` events.
class FolderChatController extends ChangeNotifier {
  final FaController app;

  FolderChatController(this.app);

  // ── conversation ─────────────────────────────────────────────────────────
  String? chatId;
  final List<ChatMessage> messages = [];

  /// Steps of the turn in flight (live reasoning replaces its slot).
  final List<AgentStepTelemetry> liveTelemetry = [];
  String liveTitle = '';
  bool sending = false;
  String? error;

  /// The user message being edited in the composer; sending replaces it and
  /// every message after it (here and in the engine's saved chat).
  ChatMessage? editing;

  List<ChatSummary> history = const [];

  /// Ids of questions the engine hasn't saved yet (saved ids are hex).
  static const _localPrefix = 'u';

  /// What turns run on, per the engine's configuration.
  AiConfig get _config => app.aiConfig;
  String get modelLabel => _config.effectiveModel ?? 'No model';
  bool get hasModel => _config.hasModel;
  bool get usesGemini => _config.usesGemini;

  // ── socket ───────────────────────────────────────────────────────────────
  WebSocket? _socket;
  StreamSubscription? _sub;
  Completer<void>? _turn;

  Future<WebSocket> _connect() async {
    if (_socket != null && _socket!.readyState == WebSocket.open) return _socket!;
    final url = '${app.api.baseUrl.replaceFirst(RegExp('^http'), 'ws')}/ws/folder-agent';
    final socket = await WebSocket.connect(url).timeout(const Duration(seconds: 8));
    _socket = socket;
    _sub = socket.listen(
      (raw) {
        try {
          final evt = jsonDecode(raw as String);
          if (evt is Map<String, dynamic>) _onEvent(evt);
        } catch (_) {}
      },
      onDone: _onClosed,
      onError: (_) => _onClosed(),
    );
    return socket;
  }

  void _onClosed() {
    _socket = null;
    _sub?.cancel();
    if (sending) _endTurn(_localError('Lost connection to the DeskMate engine.'));
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'chat':
        chatId = e['chat_id'] as String? ?? chatId;
        // Adopt the saved id for the question just sent, so it can be edited later.
        final saved = e['message_id'] as String?;
        final i = messages.lastIndexWhere((m) => m.role == MessageRole.user);
        if (saved != null && i >= 0) messages[i] = messages[i].withId(saved);
      case 'status':
        liveTitle = e['title']?.toString() ?? liveTitle;
      case 'telemetry':
        final step = AgentStepTelemetry.fromJson(e);
        final i = step.isReasoning ? liveTelemetry.lastIndexWhere(step.sameSlot) : -1;
        if (i >= 0) {
          liveTelemetry[i] = step;
        } else {
          liveTelemetry.add(step);
        }
      case 'done':
      case 'error':
        final message = ChatMessage.fromTurnEnd(e);
        if (message.isError) error = message.content;
        _endTurn(message.telemetry.isEmpty && liveTelemetry.isNotEmpty ? _withLive(message) : message);
        unawaited(refreshHistory());
        return;
      default:
        return; // run start / pong: nothing to show
    }
    notifyListeners();
  }

  ChatMessage _withLive(ChatMessage m) => ChatMessage(
    id: m.id,
    role: m.role,
    content: m.content,
    telemetry: liveTelemetry.where((s) => !s.partial).toList(),
    stats: m.stats,
    isError: m.isError,
  );

  ChatMessage _localError(String message) => ChatMessage.fromTurnEnd({'type': 'error', 'error': message});

  void _endTurn(ChatMessage reply) {
    messages.add(reply);
    sending = false;
    liveTelemetry.clear();
    liveTitle = '';
    _turn?.complete();
    _turn = null;
    notifyListeners();
  }

  // ── actions ──────────────────────────────────────────────────────────────
  /// Send what the user typed (slash commands included). [files] are `@file`
  /// attachments, [folders] `#folder` ones.
  Future<void> send(String text, {List<String> files = const [], List<String> folders = const []}) async {
    final message = text.trim();
    if (message.isEmpty || sending) return;
    error = null;
    final editOf = _takeEdit();
    messages.add(
      ChatMessage(id: '$_localPrefix${DateTime.now().microsecondsSinceEpoch}', role: MessageRole.user, content: message),
    );
    sending = true;
    liveTitle = 'Thinking…';
    notifyListeners();
    try {
      final socket = await _connect();
      _turn = Completer<void>();
      socket.add(
        jsonEncode({
          'action': 'chat',
          'message': message,
          'chat_id': chatId,
          'edit_of': ?editOf,
          'context': {'cwd': app.currentFolder, 'files': files, 'folders': folders},
        }),
      );
      await _turn!.future;
    } catch (_) {
      if (sending) _endTurn(_localError('Couldn\'t reach the DeskMate engine. Is it still starting?'));
    }
  }

  /// Load a sent question back into the composer to change and resend it.
  void startEdit(ChatMessage message) {
    if (sending || message.role != MessageRole.user) return;
    editing = message;
    notifyListeners();
  }

  void cancelEdit() {
    if (editing == null) return;
    editing = null;
    notifyListeners();
  }

  /// Drop the edited question and what followed it; returns its saved id.
  String? _takeEdit() {
    final edited = editing;
    editing = null;
    if (edited == null) return null;
    final i = messages.indexWhere((m) => m.id == edited.id);
    if (i >= 0) messages.removeRange(i, messages.length);
    return edited.id.startsWith(_localPrefix) ? null : edited.id; // not saved yet: nothing to replace
  }

  void stop() {
    if (!sending) return;
    try {
      _socket?.add(jsonEncode({'action': 'stop', 'chat_id': chatId}));
    } catch (_) {}
  }

  void newChat() {
    if (sending) return;
    chatId = null;
    messages.clear();
    editing = null;
    error = null;
    notifyListeners();
  }

  Future<void> refreshHistory() async {
    final r = await app.api.chats();
    if (r.ok) {
      history = r.value!;
      notifyListeners();
    }
  }

  Future<void> openChat(String id) async {
    if (sending) return;
    final r = await app.api.chatMessages(id);
    if (!r.ok) return app.toastError(r.error);
    chatId = id;
    editing = null;
    messages
      ..clear()
      ..addAll(r.value!.map(ChatMessage.fromStored));
    notifyListeners();
  }

  Future<void> renameChat(String id, String title) async {
    await app.api.renameChat(id, title);
    await refreshHistory();
  }

  Future<void> deleteChat(String id) async {
    await app.api.removeChat(id);
    if (chatId == id) newChat();
    await refreshHistory();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.close();
    super.dispose();
  }
}
