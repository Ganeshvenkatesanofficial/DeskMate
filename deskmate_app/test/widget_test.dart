// This is a basic Flutter widget test for DeskMate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:deskmate_app/providers/chat_provider.dart';
import 'package:deskmate_app/main.dart';

void main() {
  testWidgets('Smoke test DeskMateApp builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider()),
        ],
        child: const DeskMateApp(),
      ),
    );

    // Verify that the MaterialApp is built successfully
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
