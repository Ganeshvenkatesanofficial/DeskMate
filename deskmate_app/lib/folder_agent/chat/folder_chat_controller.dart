import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/chat_message.dart';
import '../../providers/chat_provider.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';

/// Ask AI state: the open conversation, live agent telemetry, saved chats and
/// the `/ws/folder-agent` socket.
///
/// Messages reuse DeskMate's [ChatMessage] / [AgentStepTelemetry] so the
/// shared telemetry accordion renders the agent's logs unchanged.
class FolderChatController extends ChangeNotifier {
  final FaController app;
  final ChatProvider provider;

  FolderChatController(this.app, this.provider);

  // ── conversation ─────────────────────────────────────────────────────────
  String? chatId;
  final List<ChatMessage> messages = [];

  /// Steps streamed for the turn in flight (rendered live, then attached to the reply).
  final List<AgentStepTelemetry> liveTelemetry = [];
  String liveTitle = '';
  bool sending = false;
  String? error;

  List<ChatSummary> history = const [];

  /// Model used for turns: DeskMate's global selection (Ollama model or Gemini).
  String get modelLabel => provider.isUsingGemini
      ? 'Gemini 2.5 Flash'
      : (provider.selectedLocalModel.isNotEmpty
            ? provider.selectedLocalModel
            : (provider.availableLocalModels.firstOrNull ?? 'No model'));
  bool get hasModel => provider.isUsingGemini || provider.availableLocalModels.isNotEmpty;

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
    if (sending) _fail('Lost connection to the DeskMate engine.');
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'chat':
        chatId = e['chat_id'] as String?;
      case 'status':
        liveTitle = (e['title'] ?? e['message'] ?? liveTitle).toString();
      case 'telemetry':
        final step = AgentStepTelemetry.fromJson(e);
        // Reasoning tokens arrive as repeated updates of the same step: replace, don't append.
        final i = liveTelemetry.lastIndexWhere(
          (t) => t.step == step.step && t.phase == step.phase && t.tool == step.tool,
        );
        if (i >= 0 && (step.phase == 'reasoning' || step.phase == 'thought')) {
          liveTelemetry[i] = step;
        } else {
          liveTelemetry.add(step);
        }
        if (step.title != null) liveTitle = step.title!;
      case 'done':
        final steps = ((e['telemetry'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => AgentStepTelemetry.fromJson(m.cast<String, dynamic>()))
            .toList();
        messages.add(
          ChatMessage(
            id: 'a${DateTime.now().microsecondsSinceEpoch}',
            role: MessageRole.assistant,
            content: (e['reply'] ?? '').toString(),
            telemetry: steps.isNotEmpty ? steps : List.of(liveTelemetry),
          ),
        );
        _finish();
        unawaited(refreshHistory());
      case 'error':
        _fail((e['error'] ?? 'The agent hit an error.').toString());
    }
    notifyListeners();
  }

  void _finish() {
    sending = false;
    liveTelemetry.clear();
    liveTitle = '';
    _turn?.complete();
    _turn = null;
  }

  void _fail(String message) {
    error = message;
    messages.add(
      ChatMessage(
        id: 'e${DateTime.now().microsecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: '⚠️ $message',
        telemetry: List.of(liveTelemetry),
      ),
    );
    _finish();
    notifyListeners();
  }

  // ── actions ──────────────────────────────────────────────────────────────
  /// Send a message. [files] are `@file` attachments, [folders] `#folder` ones.
  Future<void> send(String text, {List<String> files = const [], List<String> folders = const []}) async {
    final message = text.trim();
    if (message.isEmpty || sending) return;
    error = null;
    final history = messages
        .where((m) => !m.content.startsWith('⚠️'))
        .map((m) => {'role': m.role == MessageRole.user ? 'user' : 'assistant', 'content': m.content})
        .toList();
    messages.add(
      ChatMessage(id: 'u${DateTime.now().microsecondsSinceEpoch}', role: MessageRole.user, content: message),
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
          'history': history,
          if (provider.isUsingGemini) 'api_key': provider.geminiApiKey,
          if (provider.isUsingGemini)
            'model': 'gemini/gemini-2.5-flash'
          else if (provider.selectedLocalModel.isNotEmpty)
            'model': provider.selectedLocalModel,
          'context': {'cwd': app.currentFolder, 'files': files, 'folders': folders},
        }),
      );
      await _turn!.future;
    } catch (_) {
      if (sending) _fail('Couldn\'t reach the DeskMate engine. Is it still starting?');
    }
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
    messages
      ..clear()
      ..addAll(
        r.value!.map(
          (m) => ChatMessage(
            id: m['id'] as String,
            role: m['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
            content: m['content'] as String? ?? '',
            telemetry: ((m['telemetry'] as List?) ?? const [])
                .whereType<Map>()
                .map((t) => AgentStepTelemetry.fromJson(t.cast<String, dynamic>()))
                .toList(),
            timestamp: DateTime.fromMillisecondsSinceEpoch(((m['created_at'] as num) * 1000).round()),
          ),
        ),
      );
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
