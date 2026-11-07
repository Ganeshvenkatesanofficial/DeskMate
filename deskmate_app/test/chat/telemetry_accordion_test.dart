import 'package:deskmate_app/chat/messages.dart';
import 'package:deskmate_app/chat/telemetry_accordion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final steps = parseSteps([
    {'step': 1, 'phase': 'reasoning', 'summary': 'I should read todo.txt'},
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
      'raw_output': 'Acme wants the demo',
      'ok': true,
      'duration_ms': 5,
    },
    {'step': 2, 'phase': 'reasoning', 'summary': 'Answer from the file'},
  ]);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('a saved turn shows DeskMate\'s step summary, collapsed', (tester) async {
    await tester.pumpWidget(host(TelemetryAccordion(steps: steps)));
    expect(find.text('4 steps · 1 Action, 1 Result, 2 Thoughts'), findsOneWidget);
    expect(find.text('View process'), findsOneWidget);
    expect(find.text('Document Reader'), findsNothing);
  });

  testWidgets('View process opens the timeline; Inspect shows the arguments JSON', (tester) async {
    await tester.pumpWidget(host(TelemetryAccordion(steps: steps)));
    await tester.tap(find.text('View process'));
    await tester.pump();
    expect(find.text('TOOL CALL'), findsOneWidget);
    expect(find.text('Document Reader'), findsOneWidget);
    expect(find.text('OBSERVATION'), findsOneWidget);
    expect(find.text('AI REASONING'), findsNWidgets(2));
    expect(find.text('5ms'), findsOneWidget);
    await tester.tap(find.text('Inspect all'));
    await tester.pump();
    expect(find.text('Input Arguments Payload'), findsOneWidget);
    expect(find.textContaining('"file_path": "todo.txt"'), findsOneWidget);
    expect(find.text('Acme wants the demo'), findsNWidgets(2)); // inline preview + inspector
  });

  testWidgets('a live run is open with its status; it folds up when the run ends', (tester) async {
    await tester.pumpWidget(host(TelemetryAccordion(steps: steps, isActive: true, activeTitle: 'Calling read_file')));
    expect(find.text('Calling read_file'), findsOneWidget);
    expect(find.text('Hide process'), findsOneWidget);
    await tester.pumpWidget(host(TelemetryAccordion(steps: steps)));
    expect(find.text('View process'), findsOneWidget);
  });
}
