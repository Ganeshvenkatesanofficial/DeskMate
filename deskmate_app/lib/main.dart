import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_settings.dart';
import 'app/backend_manager.dart';
import 'folder_agent/core/fa_theme.dart';
import 'folder_agent/folder_agent_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => AppSettings(), child: const DeskMateApp()));

  // Start the bundled engine in the background; the window renders immediately.
  BackendManager.start().catchError((e) => debugPrint('Failed to start the DeskMate engine: $e'));
}

class DeskMateApp extends StatefulWidget {
  const DeskMateApp({super.key});
  @override
  State<DeskMateApp> createState() => _DeskMateAppState();
}

class _DeskMateAppState extends State<DeskMateApp> {
  late final AppLifecycleListener _lifecycle;
  static final _light = faTheme(Brightness.light);
  static final _dark = faTheme(Brightness.dark);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await BackendManager.stop();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    BackendManager.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppSettings, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'DeskMate',
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      // Swap themes instantly: a cross-fade repaints every surface (visible flicker).
      themeAnimationDuration: Duration.zero,
      home: const Scaffold(body: FolderAgentShell()),
    );
  }
}
