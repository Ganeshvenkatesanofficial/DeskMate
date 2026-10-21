import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/chat_message.dart';

enum WebSocketAgentType { fileCopilot, personalAssistant }

class AgentWebSocketClient {
  final String baseUrl;

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
    // Remove trailing slash
    while (wsBase.endsWith('/')) {
      wsBase = wsBase.substring(0, wsBase.length - 1);
    }
    final path = type == WebSocketAgentType.fileCopilot
        ? '/ws/file-agent'
        : '/ws/personal-agent';
    return '$wsBase$path';
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
    final List<AgentStepTelemetry> telemetrySteps = [];
    WebSocket? webSocket;
    StreamSubscription? subscription;

    final timer = Timer(const Duration(minutes: 5), () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Agent execution timed out after 5 minutes.'),
        );
        try {
          webSocket?.close(WebSocketStatus.normalClosure);
        } catch (_) {}
      }
    });

    try {
      webSocket = await WebSocket.connect(wsUrl).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw SocketException('Failed to establish WebSocket to $wsUrl');
        },
      );

      final payload = {
        'action': 'chat',
        'message': message,
        'history': history,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
        if (geminiApiKey != null && geminiApiKey.isNotEmpty)
          'api_key': geminiApiKey,
        if (model != null && model.isNotEmpty) 'model': model,
      };

      webSocket.add(jsonEncode(payload));

      subscription = webSocket.listen(
        (data) {
          try {
            final jsonStr = data is String
                ? data
                : utf8.decode(data as List<int>);
            final event = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = event['type'] as String? ?? '';

            if (type == 'status') {
              final title = event['title'] as String? ?? 'Thinking...';
              final msg = event['message'] as String?;
              onStatus?.call(title, msg);
            } else if (type == 'telemetry') {
              final step = AgentStepTelemetry.fromJson(event);
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
              timer.cancel();
              final reply = event['reply'] as String? ?? 'Task completed.';
              final convId = event['conversation_id'] as String? ?? '';

              if (!completer.isCompleted) {
                completer.complete({
                  'reply': reply,
                  'conversation_id': convId,
                  'telemetry': telemetrySteps,
                });
              }
              webSocket?.close(WebSocketStatus.normalClosure);
            } else if (type == 'error') {
              timer.cancel();
              final errorMsg =
                  event['error'] as String? ?? 'Unknown agent error.';
              if (!completer.isCompleted) {
                completer.completeError(Exception(errorMsg));
              }
              webSocket?.close(WebSocketStatus.normalClosure);
            }
          } catch (err) {
            // Error parsing message frame
            if (!completer.isCompleted) {
              completer.completeError(err);
            }
          }
        },
        onError: (err) {
          timer.cancel();
          if (!completer.isCompleted) {
            completer.completeError(err);
          }
        },
        onDone: () {
          timer.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              const SocketException('WebSocket closed prematurely by server.'),
            );
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } finally {
      timer.cancel();
      await subscription?.cancel();
    }
  }
}
