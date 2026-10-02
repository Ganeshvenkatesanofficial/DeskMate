import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'screens/chat_screen.dart';
import 'theme/app_theme.dart';
import 'services/backend_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Start the background python backend silently
  await BackendManager.start();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const DeskMateApp(),
    ),
  );
}

class DeskMateApp extends StatefulWidget {
  const DeskMateApp({super.key});

  @override
  State<DeskMateApp> createState() => _DeskMateAppState();
}

class _DeskMateAppState extends State<DeskMateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackendManager.stop(); // Stop the backend when Flutter widget is disposed
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Force shutdown backend when app is closed / detached on desktop
      BackendManager.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeskMate - AI Desktop Copilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const ChatScreen(),
    );
  }
}
