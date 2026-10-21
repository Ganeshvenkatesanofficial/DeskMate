import 'package:intl/intl.dart';

enum MessageRole { user, assistant }

class AgentStepTelemetry {
  final int step;
  final String
  phase; // 'tool_call', 'observation', 'thought', 'reasoning', 'status'
  final String? tool;
  final Map<String, dynamic>? arguments;
  final String? summary;
  final String? rawOutput;
  final String? title;
  final int? durationMs;
  final DateTime timestamp;

  AgentStepTelemetry({
    required this.step,
    required this.phase,
    this.tool,
    this.arguments,
    this.summary,
    this.rawOutput,
    this.title,
    this.durationMs,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'step': step,
    'phase': phase,
    'tool': tool,
    'arguments': arguments,
    'summary': summary,
    'raw_output': rawOutput,
    'title': title,
    'duration_ms': durationMs,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AgentStepTelemetry.fromJson(Map<String, dynamic> json) =>
      AgentStepTelemetry(
        step: (json['step'] as num?)?.toInt() ?? 1,
        phase: json['phase']?.toString() ?? 'status',
        tool: json['tool']?.toString(),
        arguments: switch (json['arguments']) {
          final Map m => Map<String, dynamic>.from(m),
          null => null,
          // Agents sometimes emit raw (unparsed) tool arguments as a string.
          final other => {'raw': other.toString()},
        },
        summary: json['summary']?.toString(),
        rawOutput: json['raw_output']?.toString(),
        title: json['title']?.toString(),
        durationMs: (json['duration_ms'] as num?)?.toInt(),
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'].toString())
            : null,
      );
}

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final List<AgentStepTelemetry> telemetry;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.telemetry = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'telemetry': telemetry.map((t) => t.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    var rawTelemetry = json['telemetry'] as List<dynamic>? ?? [];
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
      content: json['content'] as String? ?? '',
      telemetry: rawTelemetry
          .whereType<Map<String, dynamic>>()
          .map((t) => AgentStepTelemetry.fromJson(t))
          .toList(),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String get formattedTime => DateFormat('HH:mm').format(timestamp);
}
