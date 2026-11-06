import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_manager.dart';
import 'constants.dart';

enum EngineState { starting, online, offline }

/// App-level settings and engine connection for DeskMate:
/// which engine URL is live, whether Ollama is up, the chosen chat model
/// (an Ollama model or Gemini), the Gemini key, and the theme.
class AppSettings extends ChangeNotifier {
  AppSettings() {
    _init();
  }

  // ── engine ────────────────────────────────────────────────────────────────
  String backendUrl = BackendManager.backendUrl;
  EngineState engine = EngineState.starting;
  bool isLocalLlmOnline = false;
  Timer? _poll;
  int _misses = 0;

  // ── models ────────────────────────────────────────────────────────────────
  List<String> availableLocalModels = const [];
  String _selectedModel = '';
  String geminiApiKey = '';

  /// The raw saved choice (an Ollama model id, [AppConstants.geminiModelId], or '').
  String get selectedModel => _selectedModel;
  bool get hasGeminiKey => geminiApiKey.isNotEmpty;
  bool get isGeminiSelected => _selectedModel == AppConstants.geminiModelId;
  bool get isUsingGemini => hasGeminiKey && isGeminiSelected;

  /// The Ollama model turns run on ('' when Gemini is selected or nothing is installed).
  String get selectedLocalModel {
    if (isGeminiSelected) return '';
    if (_selectedModel.isNotEmpty && availableLocalModels.contains(_selectedModel)) return _selectedModel;
    return availableLocalModels.isNotEmpty ? availableLocalModels.first : _selectedModel;
  }

  // ── theme ─────────────────────────────────────────────────────────────────
  ThemeMode themeMode = ThemeMode.system;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(PrefsKeys.backendUrl);
    if (saved != null && saved.isNotEmpty && !AppConstants.isBuiltInUrl(saved)) backendUrl = saved;
    _selectedModel = prefs.getString(PrefsKeys.selectedModel) ?? '';
    geminiApiKey = prefs.getString(PrefsKeys.geminiApiKey) ?? '';
    final themeIndex = prefs.getInt(PrefsKeys.themeMode);
    if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      themeMode = ThemeMode.values[themeIndex];
    }
    notifyListeners();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkEngine());
    unawaited(_checkEngine());
  }

  Future<Map<String, dynamic>?> _health(String url) async {
    try {
      final res = await http.get(Uri.parse('$url/api/health')).timeout(const Duration(milliseconds: 1500));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map<String, dynamic> && BackendManager.isDeskMateHealth(body) ? body : null;
    } catch (_) {
      return null;
    }
  }

  /// Find the live engine (the launcher may move it to another port) and refresh LLM status.
  Future<void> _checkEngine() async {
    Map<String, dynamic>? health = await _health(backendUrl);
    if (health == null) {
      for (final url in AppConstants.candidateUrls(BackendManager.backendUrl)) {
        if (url == backendUrl) continue;
        health = await _health(url);
        if (health != null) {
          backendUrl = url;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.backendUrl, url);
          break;
        }
      }
    }
    if (health == null) {
      // Keep "starting" for the first minute so a cold engine isn't reported as down.
      _misses++;
      final next = _misses > 20 ? EngineState.offline : engine;
      if (next != engine) {
        engine = next;
        notifyListeners();
      }
      return;
    }
    _misses = 0;
    final llmOnline = health['local_llm'] == 'online';
    final models = ((health['models'] as List?) ?? const []).map((e) => '$e').toList();
    final changed =
        engine != EngineState.online || llmOnline != isLocalLlmOnline || !_sameList(models, availableLocalModels);
    engine = EngineState.online;
    isLocalLlmOnline = llmOnline;
    availableLocalModels = models;
    if (changed) notifyListeners();
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  /// Re-read installed Ollama models now (after a pull finishes).
  Future<void> fetchAvailableModels() => _checkEngine();

  Future<void> setSelectedLocalModel(String model) async {
    _selectedModel = model.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.selectedModel, _selectedModel);
    notifyListeners();
  }

  Future<void> setGeminiApiKey(String key) async {
    geminiApiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.geminiApiKey, geminiApiKey);
    if (geminiApiKey.isEmpty && isGeminiSelected) _selectedModel = '';
    notifyListeners();
  }

  /// Choose the chat model and, for Gemini, the key in one step.
  Future<void> saveAiConfiguration({required String model, required String geminiApiKey}) async {
    await setGeminiApiKey(geminiApiKey);
    await setSelectedLocalModel(model);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.themeMode, mode.index);
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
