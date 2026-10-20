abstract final class AppConstants {
  static const String version = '2.0.0';
  static const String appName = 'DeskMate AI';
  static const int defaultPort = 2026;
  static const List<int> legacyPorts = [8080, 2026, 8000];
  static const String defaultHost = '127.0.0.1';

  static String urlFor(int port) => 'http://$defaultHost:$port';
  static String get defaultUrl => urlFor(defaultPort);

  static List<String> candidateUrls(String primaryUrl) {
    final seen = <String>{};
    final urls = <String>[];
    for (final u in [
      'http://$defaultHost:8080',
      primaryUrl,
      'http://$defaultHost:2026',
      'http://$defaultHost:8000',
    ]) {
      if (seen.add(u)) urls.add(u);
    }
    return urls;
  }

  static bool isBuiltInUrl(String url) =>
      legacyPorts.any((p) => url == urlFor(p));
}

abstract final class PrefsKeys {
  static const String conversationId = 'deskmate_conversation_id';
  static const String personalConversationId =
      'deskmate_personal_conversation_id';
  static const String backendUrl = 'deskmate_backend_url';
  static const String selectedModel = 'deskmate_selected_model';
  static const String geminiApiKey = 'deskmate_gemini_api_key';
  static const String hasConfiguredAi = 'deskmate_has_configured_ai';
  static const String themeMode = 'deskmate_theme_mode';
  static const String agentMode = 'deskmate_agent_mode';
}

abstract final class ApiPaths {
  static const String health = '/api/health';
  static const String models = '/api/models';
  static const String chat = '/api/chat';
  static const String personal = '/api/personal';
  static const String fileHealth = '/api/file/health';
  static const String personalHealth = '/api/personal/health';
  static const String personalCredentials = '/api/personal/credentials';
  static String resetChat(String id) => '/api/reset/$id';
  static const String dbOverview = '/api/database/overview';
  static String dbTable(String name) => '/api/database/table/$name';
  static const String dbQuery = '/api/database/query';

  static const String meetingStart = '/api/meeting/start';
  static const String meetingStop = '/api/meeting/stop';
  static const String meetingMute = '/api/meeting/mute';
  static const String meetingStatus = '/api/meeting/status';
  static const String meetingSummarize = '/api/meeting/summarize';
  static const String meetingSyncTasks = '/api/meeting/sync-tasks';
  static String meetingPdf(String id) => '/api/meeting/pdf/$id';
  static String meetingAsset(String sid, String file) =>
      '/api/meeting/asset/$sid/$file';
  static const String meetingExportDrive = '/api/meeting/export-drive';
  static const String meetingSendEmail = '/api/meeting/send-email';

  static const String wsFileAgent = '/ws/file-agent';
  static const String wsPersonalAgent = '/ws/personal-agent';
}

abstract final class AppTimeouts {
  static const Duration healthCheck = Duration(milliseconds: 1500);
  static const Duration wsConnect = Duration(seconds: 10);
  static const Duration wsExecution = Duration(minutes: 5);
  static const Duration restShort = Duration(seconds: 5);
  static const Duration restMedium = Duration(seconds: 15);
  static const Duration restLong = Duration(minutes: 5);
  static const Duration geminiRequest = Duration(seconds: 30);
  static const Duration meetingPoll = Duration(seconds: 3);
  static const Duration healthPoll = Duration(seconds: 3);
}
