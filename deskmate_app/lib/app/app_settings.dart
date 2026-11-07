import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_manager.dart';
import 'constants.dart';

/// `outdated`: only an older DeskMate engine (without this app's Folder Agent API) answers.
enum EngineState { starting, online, offline, outdated }

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

  /// Where the older engine answers, while [engine] is `outdated`.
  String? outdatedEngineUrl;
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

  /// Follow the live engine across ports; never adopt an engine this app can't
  /// talk to; report it offline only after a grace period.
  Future<void> _checkEngine() async {
    var url = backendUrl;
    var fit = await BackendManager.probe(url);
    String? outdated = fit == EngineFit.outdated ? url : null;
    if (fit != EngineFit.compatible) {
      for (final candidate in AppConstants.candidateUrls(BackendManager.backendUrl)) {
        if (candidate == url) continue;
        final f = await BackendManager.probe(candidate);
        if (f == EngineFit.compatible) {
          url = candidate;
          fit = f;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.backendUrl, candidate);
          break;
        }
        if (f == EngineFit.outdated) outdated ??= candidate;
      }
    }
    final ok = fit == EngineFit.compatible;
    if (ok) _misses = 0;
    final next = ok
        ? EngineState.online
        : outdated != null
        ? EngineState.outdated
        : (++_misses > _offlineAfterMisses ? EngineState.offline : engine);
    final nextOutdated = next == EngineState.outdated ? outdated : null;
    if (next != engine || url != backendUrl || nextOutdated != outdatedEngineUrl) {
      engine = next;
      backendUrl = url;
      outdatedEngineUrl = nextOutdated;
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
