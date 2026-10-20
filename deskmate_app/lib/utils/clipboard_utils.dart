import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void copyWithFeedback(
  BuildContext context,
  String text, {
  String label = 'Copied to clipboard',
}) {
  Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(label, style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        width: 220,
      ),
    );
}
