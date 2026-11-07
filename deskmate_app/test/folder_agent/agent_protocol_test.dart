import 'package:deskmate_app/folder_agent/chat/messages.dart';
import 'package:deskmate_app/folder_agent/core/format.dart';
import 'package:deskmate_app/folder_agent/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent telemetry protocol', () {
    final steps = [
      {'step': 1, 'phase': 'reasoning', 'summary': 'Plan', 'timestamp': 1793950000.5},
      {
        'step': 1,
        'phase': 'tool_call',
        'tool': 'read_file',
        'arguments': {'file_path': 'todo.txt'},
      },
      {
        'step': 1,
        'phase': 'observation',
        'tool': 'read_file',
        'raw_output': 'Error: nope',
        'ok': false,
        'duration_ms': 8,
      },
    ];
    final stats = {'steps': 1, 'tool_calls': 1, 'tool_errors': 1, 'model': 'gemma4:e4b', 'duration_ms': 2500};

    test('a done event becomes a reply with its steps and run stats', () {
      final m = ChatMessage.fromTurnEnd({
        'type': 'done',
        'run_id': 'run_1',
        'reply': 'Hi',
        'telemetry': steps,
        'stats': stats,
      });
      expect(m.isError, isFalse);
      expect(m.content, 'Hi');
      expect(m.telemetry.map((s) => s.phase), ['reasoning', 'tool_call', 'observation']);
      expect(m.telemetry.last.ok, isFalse);
      expect(m.stats.durationMs, 2500);
      expect(m.stats.model, 'gemma4:e4b');
    });

    test('an error event is flagged, never matched by text', () {
      final m = ChatMessage.fromTurnEnd({'type': 'error', 'error': 'No chat model yet.', 'telemetry': []});
      expect(m.isError, isTrue);
      expect(m.content, 'No chat model yet.');
    });

    test('saved messages parse with the same rules', () {
      final m = ChatMessage.fromStored({
        'id': 'x',
        'role': 'assistant',
        'content': 'Stopped.',
        'telemetry': steps,
        'stats': stats,
        'error': true,
        'created_at': 1793950000.0,
      });
      expect(m.isError, isTrue);
      expect(m.telemetry, hasLength(3));
      expect(m.stats.toolErrors, 1);
    });

    test('a sent question adopts the id the engine saved it under', () {
      final local = ChatMessage(id: 'u1', role: MessageRole.user, content: 'find taxes');
      final saved = local.withId('3f2a');
      expect(saved.id, '3f2a');
      expect(saved.role, MessageRole.user);
      expect(saved.content, 'find taxes');
      expect(saved.timestamp, local.timestamp);
    });

    test('live reasoning replaces its slot; tool calls are new rows', () {
      final a = AgentStepTelemetry.fromJson({'step': 2, 'phase': 'reasoning', 'summary': 'thi', 'partial': true});
      final b = AgentStepTelemetry.fromJson({'step': 2, 'phase': 'reasoning', 'summary': 'thinking'});
      final t = AgentStepTelemetry.fromJson({'step': 2, 'phase': 'tool_call', 'tool': 'list_folder'});
      expect(a.partial, isTrue);
      expect(a.sameSlot(b), isTrue);
      expect(t.sameSlot(b), isFalse);
      expect(t.isToolCall && !t.isReasoning, isTrue);
    });
  });

  group('engine-owned AI config', () {
    test('parses what turns run on', () {
      final c = AiConfig.fromJson({
        'chatModel': 'qwen3:4b',
        'effectiveModel': 'gemma4:e4b',
        'provider': 'ollama',
        'hasGeminiKey': true,
        'installedModels': ['gemma4:e4b'],
      });
      expect(c.hasModel, isTrue);
      expect(c.usesGemini, isFalse);
      expect(c.isChosen('qwen3:4b'), isTrue);
      expect(AiConfig.none.hasModel, isFalse);
    });
  });

  group('FilDOS formats', () {
    test('sizes are base 1024 with one decimal', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1 MB');
    });

    test('deep folders compact to their last two parts', () {
      expect(compactDir('/Users/me/Documents', '/Users/me'), '~/Documents');
      expect(compactDir('/Users/me/a/b/c/d', '/Users/me'), '…/c/d');
    });
  });
}
