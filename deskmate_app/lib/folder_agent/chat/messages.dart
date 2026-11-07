// Ask AI data: chat messages and the agent's telemetry, exactly as the
// engine's AgentTelemetry emits and persists them (one parser for live
// events and saved chats).

enum MessageRole { user, assistant }

double _seconds(Object? v) => (v as num?)?.toDouble() ?? 0;

/// One recorded agent step: phase is `reasoning`, `tool_call` or `observation`.
class AgentStepTelemetry {
  final int step;
  final String phase;
  final String? tool;
  final Map<String, dynamic>? arguments;
  final String? summary;
  final String? rawOutput;
  final String? title;
  final int? durationMs;

  /// Tool results only: false when the tool reported an error or refusal.
  final bool? ok;

  /// Live reasoning tokens (replaced by the step's final reasoning).
  final bool partial;
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
    this.ok,
    this.partial = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AgentStepTelemetry.fromJson(Map<String, dynamic> j) => AgentStepTelemetry(
    step: (j['step'] as num?)?.toInt() ?? 1,
    phase: j['phase']?.toString() ?? 'reasoning',
    tool: j['tool']?.toString(),
    arguments: switch (j['arguments']) {
      final Map m => Map<String, dynamic>.from(m),
      null => null,
      final other => {'raw': other.toString()}, // models sometimes emit unparsed arguments
    },
    summary: j['summary']?.toString(),
    rawOutput: j['raw_output']?.toString(),
    title: j['title']?.toString(),
    durationMs: (j['duration_ms'] as num?)?.toInt(),
    ok: j['ok'] as bool?,
    partial: j['partial'] == true,
    timestamp: j['timestamp'] is num
        ? DateTime.fromMillisecondsSinceEpoch((_seconds(j['timestamp']) * 1000).round())
        : null,
  );

  bool get isToolCall => phase == 'tool_call';
  bool get isResult => phase == 'observation';
  bool get isReasoning => !isToolCall && !isResult;

  /// Live reasoning updates the same step instead of adding a row.
  bool sameSlot(AgentStepTelemetry other) => step == other.step && phase == other.phase && tool == other.tool;
}

/// Run-level numbers the engine reports with every reply or error.
class RunStats {
  final int steps;
  final int toolCalls;
  final int toolErrors;
  final String? model;
  final int durationMs;
  const RunStats({this.steps = 0, this.toolCalls = 0, this.toolErrors = 0, this.model, this.durationMs = 0});

  factory RunStats.fromJson(Map<String, dynamic>? j) => j == null
      ? const RunStats()
      : RunStats(
          steps: (j['steps'] as num?)?.toInt() ?? 0,
          toolCalls: (j['tool_calls'] as num?)?.toInt() ?? 0,
          toolErrors: (j['tool_errors'] as num?)?.toInt() ?? 0,
          model: j['model'] as String?,
          durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        );
}

List<AgentStepTelemetry> parseSteps(Object? raw) => ((raw as List?) ?? const [])
    .whereType<Map>()
    .map((m) => AgentStepTelemetry.fromJson(m.cast<String, dynamic>()))
    .toList();

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final List<AgentStepTelemetry> telemetry;
  final RunStats stats;
  final bool isError;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.telemetry = const [],
    this.stats = const RunStats(),
    this.isError = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// This message under the id the engine saved it with.
  ChatMessage withId(String newId) => ChatMessage(
    id: newId,
    role: role,
    content: content,
    telemetry: telemetry,
    stats: stats,
    isError: isError,
    timestamp: timestamp,
  );

  /// A saved message from `/api/fa/chats/{id}/messages`.
  factory ChatMessage.fromStored(Map<String, dynamic> m) => ChatMessage(
    id: m['id'] as String? ?? '',
    role: m['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
    content: m['content'] as String? ?? '',
    telemetry: parseSteps(m['telemetry']),
    stats: RunStats.fromJson((m['stats'] as Map?)?.cast<String, dynamic>()),
    isError: m['error'] == true,
    timestamp: DateTime.fromMillisecondsSinceEpoch((_seconds(m['created_at']) * 1000).round()),
  );

  /// The reply (`done`) or failure (`error`) event that ends a live turn.
  factory ChatMessage.fromTurnEnd(Map<String, dynamic> e) {
    final failed = e['type'] == 'error';
    return ChatMessage(
      id: '${e['run_id'] ?? DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: (failed ? e['error'] : e['reply'])?.toString() ?? '',
      telemetry: parseSteps(e['telemetry']),
      stats: RunStats.fromJson((e['stats'] as Map?)?.cast<String, dynamic>()),
      isError: failed,
    );
  }
}
