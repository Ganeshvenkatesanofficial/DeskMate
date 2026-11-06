/// App-wide constants for DeskMate (Folder Agent).
abstract final class AppConstants {
  static const String version = '2.0.0';
  static const String appName = 'DeskMate';
  static const int defaultPort = 2026;
  static const List<int> legacyPorts = [8080, 2026, 8000];
  static const String defaultHost = '127.0.0.1';

  /// Model-picker value meaning "use Google Gemini (cloud)" instead of Ollama.
  static const String geminiModelId = 'gemini-2.5-flash';
  static const String geminiLiteLlmId = 'gemini/gemini-2.5-flash';
  static const String geminiModelLabel = 'Gemini 2.5 Flash (Cloud)';

  static String urlFor(int port) => 'http://$defaultHost:$port';
  static String get defaultUrl => urlFor(defaultPort);

  /// Where to look for a running engine: the launcher's port first, then the legacy ones.
  static List<String> candidateUrls(String primaryUrl) => {primaryUrl, for (final p in legacyPorts) urlFor(p)}.toList();

  static bool isBuiltInUrl(String url) => legacyPorts.any((p) => url == urlFor(p));
}

/// SharedPreferences keys (kept stable across releases so settings survive upgrades).
abstract final class PrefsKeys {
  static const String backendUrl = 'deskmate_backend_url';
  static const String selectedModel = 'deskmate_selected_model';
  static const String geminiApiKey = 'deskmate_gemini_api_key';
  static const String themeMode = 'deskmate_theme_mode';
}
