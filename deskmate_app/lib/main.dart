import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _DeskMateAppState extends State<DeskMateApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await BackendManager.stop();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    BackendManager.stop();
    super.dispose();
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
