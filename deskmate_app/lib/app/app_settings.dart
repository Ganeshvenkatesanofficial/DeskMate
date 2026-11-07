import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_manager.dart';
import 'constants.dart';

enum EngineState { starting, online, offline }

/// App-shell state: which engine URL is live (the launcher may move it) and
/// the theme. AI settings (chat model, Gemini key) are owned by the engine and
/// managed through `FaController`.
class AppSettings extends ChangeNotifier {
  AppSettings() {
    _init();
  }

  String backendUrl = BackendManager.backendUrl;
  EngineState engine = EngineState.starting;
  ThemeMode themeMode = ThemeMode.system;
  Timer? _poll;
  int _misses = 0;

  /// Polls before a missing engine is reported offline (~1 min: cold starts are slow).
  static const _offlineAfterMisses = 20;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(PrefsKeys.backendUrl);
    if (saved != null && saved.isNotEmpty && !AppConstants.isBuiltInUrl(saved)) backendUrl = saved;
    final themeIndex = prefs.getInt(PrefsKeys.themeMode);
    if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      themeMode = ThemeMode.values[themeIndex];
    }
    notifyListeners();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkEngine());
    unawaited(_checkEngine());
  }

  Future<bool> _healthy(String url) async {
    try {
      final res = await http.get(Uri.parse('$url/api/health')).timeout(const Duration(milliseconds: 1500));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body);
      return body is Map && BackendManager.isDeskMateHealth(body);
    } catch (_) {
      return false;
    }
  }

  /// Follow the live engine across ports; report it offline only after a grace period.
  Future<void> _checkEngine() async {
    var url = backendUrl;
    var ok = await _healthy(url);
    if (!ok) {
      for (final candidate in AppConstants.candidateUrls(BackendManager.backendUrl)) {
        if (candidate != url && await _healthy(candidate)) {
          url = candidate;
          ok = true;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.backendUrl, candidate);
          break;
        }
      }
    }
    final next = ok ? EngineState.online : (++_misses > _offlineAfterMisses ? EngineState.offline : engine);
    if (ok) _misses = 0;
    if (next != engine || url != backendUrl) {
      engine = next;
      backendUrl = url;
      notifyListeners();
    }
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
