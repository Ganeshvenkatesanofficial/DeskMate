import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';
import '../models/chat_message.dart';

enum WebSocketAgentType { fileCopilot, personalAssistant }

/// The socket never connected, so the request was never sent and is safe to
/// retry over REST.
class AgentConnectionException implements Exception {
  final String message;
  const AgentConnectionException(this.message);
  @override
  String toString() => message;
}

/// The request reached the agent and then failed. It must NOT be retried:
/// the agent may already have sent an email or created an event.
class AgentRunException implements Exception {
  final String message;
  const AgentRunException(this.message);
  @override
  String toString() => message;
}

class AgentCancelledException implements Exception {
  const AgentCancelledException();
  @override
  String toString() => 'Stopped.';
}

class AgentWebSocketClient {
  final String baseUrl;
  WebSocket? _activeSocket;
  Completer<Map<String, dynamic>>? _activeCompleter;

  AgentWebSocketClient({required this.baseUrl});

  String _getWsUrl(WebSocketAgentType type) {
    var wsBase = baseUrl;
    if (wsBase.startsWith('http://')) {
      wsBase = 'ws://${wsBase.substring(7)}';
    } else if (wsBase.startsWith('https://')) {
      wsBase = 'wss://${wsBase.substring(8)}';
    } else if (!wsBase.startsWith('ws://') && !wsBase.startsWith('wss://')) {
      wsBase = 'ws://$wsBase';
    }
    while (wsBase.endsWith('/')) {
      wsBase = wsBase.substring(0, wsBase.length - 1);
    }
    final path = type == WebSocketAgentType.fileCopilot
        ? ApiPaths.wsFileAgent
        : ApiPaths.wsPersonalAgent;
    return '$wsBase$path';
  }

  /// Stops waiting for the current reply and closes the socket.
  void cancel() {
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const AgentCancelledException());
    }
    try {
      _activeSocket?.close(WebSocketStatus.normalClosure);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> sendMessageStream({
    required WebSocketAgentType agentType,
    required String message,
    List<Map<String, String>> history = const [],
    String? conversationId,
    String? geminiApiKey,
    String? model,
    Function(String title, String? message)? onStatus,
    Function(AgentStepTelemetry step)? onTelemetry,
  }) async {
    final wsUrl = _getWsUrl(agentType);
    final completer = Completer<Map<String, dynamic>>();
    _activeCompleter = completer;
    final List<AgentStepTelemetry> telemetrySteps = [];
    StreamSubscription? subscription;

    final WebSocket webSocket;
    try {
      webSocket = await WebSocket.connect(wsUrl).timeout(AppTimeouts.wsConnect);
    } catch (e) {
      _activeCompleter = null;
      // Stop was pressed while connecting: report the cancel, never a
      // connection error (that would trigger the REST fallback).
      if (completer.isCompleted) return completer.future;
      throw AgentConnectionException('Could not connect to $wsUrl: $e');
    }
    _activeSocket = webSocket;
    if (completer.isCompleted) {
      // Cancelled while connecting.
      webSocket.close(WebSocketStatus.normalClosure);
      _activeSocket = null;
      _activeCompleter = null;
      return completer.future;
    }

    final timer = Timer(AppTimeouts.wsExecution, () {
      if (!completer.isCompleted) {
        completer.completeError(
          AgentRunException(
            'The assistant took longer than ${AppTimeouts.wsExecution.inMinutes} minutes, so DeskMate stopped waiting. Try a simpler request.',
          ),
        );
      }
      try {
        webSocket.close(WebSocketStatus.normalClosure);
      } catch (_) {}
    });

    try {
      webSocket.add(
        jsonEncode({
          'action': 'chat',
          'message': message,
          'history': history,
          if (conversationId != null && conversationId.isNotEmpty)
            'conversation_id': conversationId,
          if (geminiApiKey != null && geminiApiKey.isNotEmpty)
            'api_key': geminiApiKey,
          if (model != null && model.isNotEmpty) 'model': model,
        }),
      );

      subscription = webSocket.listen(
        (data) {
          final Map<String, dynamic> event;
          try {
            final jsonStr = data is String
                ? data
                : utf8.decode(data as List<int>);
            event = jsonDecode(jsonStr) as Map<String, dynamic>;
          } catch (_) {
            return; // Skip a malformed frame instead of failing the request.
          }
          final type = event['type'] as String? ?? '';

          if (type == 'status') {
            onStatus?.call(
              event['title'] as String? ?? 'Thinking...',
              event['message'] as String?,
            );
          } else if (type == 'telemetry') {
            final AgentStepTelemetry step;
            try {
              step = AgentStepTelemetry.fromJson(event);
            } catch (_) {
              return;
            }
            final existingIndex = telemetrySteps.indexWhere(
              (s) => s.step == step.step && s.phase == 'reasoning',
            );
            if (existingIndex != -1 && step.phase == 'reasoning') {
              telemetrySteps[existingIndex] = step;
            } else {
              telemetrySteps.add(step);
            }
            onTelemetry?.call(step);
          } else if (type == 'done') {
            if (!completer.isCompleted) {
              completer.complete({
                'reply': event['reply'] as String? ?? 'Task completed.',
                'conversation_id': event['conversation_id'] as String? ?? '',
                'telemetry': telemetrySteps,
              });
            }
            webSocket.close(WebSocketStatus.normalClosure);
          } else if (type == 'error') {
            if (!completer.isCompleted) {
              completer.completeError(
                AgentRunException(
                  event['error'] as String? ?? 'Unknown agent error.',
                ),
              );
            }
            webSocket.close(WebSocketStatus.normalClosure);
          }
        },
        onError: (err) {
          if (!completer.isCompleted) {
            completer.completeError(
              AgentRunException('The connection to the assistant broke: $err'),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              const AgentRunException(
                'The assistant closed the connection before replying.',
              ),
            );
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } finally {
      timer.cancel();
      await subscription?.cancel();
      if (identical(_activeCompleter, completer)) {
        _activeCompleter = null;
        _activeSocket = null;
      }
    }
  }
}
