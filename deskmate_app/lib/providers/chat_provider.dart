import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/agent_websocket_client.dart';
import '../services/backend_manager.dart';
import 'package:http/http.dart' as http;

enum AgentMode { deskMate, personal, meeting }

enum EngineStatus { starting, ready, degraded, failed }

class ChatProvider extends ChangeNotifier {
  List<ChatMessage> _fileMessages = [];
  List<ChatMessage> _personalMessages = [];
  bool _isSending = false;
  String _errorMessage = '';
  String _fileConversationId = '';
  String _personalConversationId = '';
  String _backendUrl = AppConstants.defaultUrl;
  bool _isConnecting = true;
  bool _isBackendOnline = false;
  bool _isLocalLlmOnline = false;
  String _localLlmStatus = 'offline';
  EngineStatus _engineStatus = EngineStatus.starting;
  int _initElapsedSeconds = 0;
  String _engineStatusMessage = 'Starting DeskMate local engine';
  Timer? _startupTimer;
  ThemeMode _themeMode = ThemeMode.light;
  AgentMode _mode = AgentMode.deskMate;
  Map<String, dynamic> _personalAgentHealth = {'status': 'loading'};
  Map<String, dynamic> _fileAgentHealth = {'status': 'loading'};
  Map<String, dynamic> _personalCredentials = {'configured': false};
  Timer? _healthTimer;

  // Real-time telemetry streaming state
  List<AgentStepTelemetry> _activeTelemetry = [];
  String _activeStatusTitle = 'Thinking...';

  // Local Ollama Models state
  List<String> _availableLocalModels = [];
  String _selectedModel = '';
  bool _showModelSelectionDialog = false;
  bool _hasConfiguredAi = false;
  bool _hasVisionModel = false;
  String _visionModelName = '';
  bool _useLightweightVision = false;

  // Gemini API key – persisted in SharedPreferences so it survives app restarts.
  String _geminiApiKey = '';

  List<ChatMessage> get messages {
    if (_mode == AgentMode.personal) return _personalMessages;
    return _fileMessages;
  }

  bool get isSending => _isSending;
  String get errorMessage => _errorMessage;
  String get conversationId {
    if (_mode == AgentMode.personal) return _personalConversationId;
    return _fileConversationId;
  }

  String get backendUrl => _backendUrl;
  int get backendPort =>
      Uri.tryParse(_backendUrl)?.port ?? AppConstants.defaultPort;
  bool get isBackendOnline => _isBackendOnline;
  bool get isLocalLlmOnline => _isLocalLlmOnline;

  /// Ollama is running but has no chat model pulled yet.
  bool get isOllamaWithoutModels => _localLlmStatus == 'no_models';
  bool get isConnecting => _isConnecting;
  EngineStatus get engineStatus => _engineStatus;
  int get initElapsedSeconds => _initElapsedSeconds;
  String get engineStatusMessage => _engineStatusMessage;
  AgentMode get mode => _mode;
  ThemeMode get themeMode => _themeMode;
  Map<String, dynamic> get personalAgentHealth => _personalAgentHealth;
  Map<String, dynamic> get fileAgentHealth => _fileAgentHealth;
  Map<String, dynamic> get personalCredentials => _personalCredentials;
  String get geminiApiKey => _geminiApiKey;
  bool get hasGeminiKey => _geminiApiKey.isNotEmpty;
  bool get isGeminiSelected => _selectedModel == AppConstants.geminiModelId;

  /// Gemini is used only when the user picked it AND a key is saved.
  bool get isUsingGemini => hasGeminiKey && isGeminiSelected;
  List<String> get availableLocalModels => _availableLocalModels;

  /// Raw picker value: an Ollama model name or [AppConstants.geminiModelId].
  String get selectedModel => _selectedModel;

  /// The picked Ollama model, or '' when Gemini is picked.
  String get selectedLocalModel => isGeminiSelected ? '' : _selectedModel;

  /// The Ollama model local work runs on.
  String get effectiveModel => selectedLocalModel.isNotEmpty
      ? selectedLocalModel
      : (_availableLocalModels.isNotEmpty ? _availableLocalModels.first : '');

  /// Key to send with a request: only when Gemini is the chosen engine, so a
  /// local choice never leaks chats or files to the cloud.
  String? get _requestGeminiKey => isUsingGemini ? _geminiApiKey : null;
  String? get _requestLocalModel =>
      selectedLocalModel.isNotEmpty ? selectedLocalModel : null;
  bool get showModelSelectionDialog => _showModelSelectionDialog;
  bool get hasConfiguredAi => _hasConfiguredAi;
  bool get hasVisionModel =>
      _isLocalLlmOnline &&
      (_hasVisionModel || _detectVisionInModels(_availableLocalModels));
  String get visionModelName {
    return Platform.isMacOS
        ? 'Apple Vision OCR'
        : (Platform.isWindows ? 'Windows Native OCR' : 'Native Screen OCR');
  }

  bool get useLightweightVision => _useLightweightVision;
  bool get isVisionActive => true;

  /// Check whether AI engines (Gemini or Local Ollama Reasoning + Native Screen OCR) are ready for meeting transcription & summarization.
  bool get isMeetingAiReady {
    if (isUsingGemini) return true;
    return isLocalLlmOnline && availableLocalModels.isNotEmpty;
  }

  String get meetingAiNotReadyReason {
    if (isUsingGemini) return '';
    if (!isLocalLlmOnline) {
      return 'Ollama is offline or unreachable. Please launch Ollama locally, or configure a Gemini API key.';
    }
    if (availableLocalModels.isEmpty) {
      return 'No reasoning LLM model installed in Ollama. Run `ollama pull qwen2.5-coder:1.5b` or configure a Gemini API key.';
    }
    return '';
  }

  List<AgentStepTelemetry> get activeTelemetry => _activeTelemetry;
  String get activeStatusTitle => _activeStatusTitle;
  ApiService get apiService => _apiService;

  late ApiService _apiService;
  late AgentWebSocketClient _wsClient;

  ChatProvider() {
    _backendUrl = BackendManager.backendUrl;
    _apiService = ApiService(baseUrl: _backendUrl);
    _wsClient = AgentWebSocketClient(baseUrl: _backendUrl);
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadPreferences();
    await _startStartupHealthCheck();
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _healthTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _fileConversationId = prefs.getString(PrefsKeys.conversationId) ?? '';
    _personalConversationId =
        prefs.getString(PrefsKeys.personalConversationId) ?? '';
    final savedUrl = prefs.getString(PrefsKeys.backendUrl);
    if (savedUrl == null ||
        savedUrl.isEmpty ||
        AppConstants.isBuiltInUrl(savedUrl)) {
      _backendUrl = BackendManager.backendUrl;
    } else {
      _backendUrl = savedUrl;
    }
    _selectedModel = prefs.getString(PrefsKeys.selectedModel) ?? '';
    _geminiApiKey = prefs.getString(PrefsKeys.geminiApiKey) ?? '';
    // Older builds always used Gemini whenever a key was saved (the stored
    // Ollama model was ignored). Keep those users on Gemini once, on upgrade.
    if (!(prefs.getBool(PrefsKeys.aiEngineMigrated) ?? false)) {
      if (_geminiApiKey.isNotEmpty) {
        _selectedModel = AppConstants.geminiModelId;
        await prefs.setString(PrefsKeys.selectedModel, _selectedModel);
      }
      await prefs.setBool(PrefsKeys.aiEngineMigrated, true);
    }
    if (_selectedModel == AppConstants.geminiModelId && _geminiApiKey.isEmpty) {
      _selectedModel = '';
    }
    _useLightweightVision =
        prefs.getBool(PrefsKeys.useLightweightVision) ?? false;
    _hasConfiguredAi =
        prefs.getBool(PrefsKeys.hasConfiguredAi) ?? (_selectedModel.isNotEmpty);
    // Always initially open the File Explorer feature on app startup
    _mode = AgentMode.deskMate;
    final themeIndex =
        prefs.getInt(PrefsKeys.themeMode) ?? ThemeMode.light.index;
    if (themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    } else {
      _themeMode = ThemeMode.light;
    }
    _apiService = ApiService(baseUrl: _backendUrl);
    _wsClient = AgentWebSocketClient(baseUrl: _backendUrl);
    notifyListeners();
  }

  Future<void> setUseLightweightVision(bool enable) async {
    _useLightweightVision = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.useLightweightVision, enable);
    notifyListeners();
  }

  static bool _isVisionModel(String name) {
    final lower = name.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('bakllava');
  }

  bool _detectVisionInModels(List<String> models) {
    return models.any(_isVisionModel);
  }

  String _getVisionModelFromModels(List<String> models) {
    return models.firstWhere(_isVisionModel, orElse: () => '');
  }

  void _updateVisionState(Map<String, dynamic> health, {bool? isLocalOnline}) {
    final bool isOnline = isLocalOnline ?? _isLocalLlmOnline;
    if (!isOnline) {
      _hasVisionModel = false;
      _visionModelName = '';
      return;
    }
    final healthModels =
        (health['models'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    _hasVisionModel =
        health['has_vision'] == true ||
        _detectVisionInModels(healthModels) ||
        _detectVisionInModels(_availableLocalModels);
    _visionModelName =
        (health['vision_model'] as String?) ??
        _getVisionModelFromModels(healthModels);
    if (_visionModelName.isEmpty) {
      _visionModelName = _getVisionModelFromModels(_availableLocalModels);
    }
  }

  Future<void> fetchAvailableModels() async {
    if (!_isBackendOnline || !_isLocalLlmOnline) return;
    try {
      final models = await _apiService.getAvailableModels();
      _availableLocalModels = models;
      if (_detectVisionInModels(_availableLocalModels)) {
        _hasVisionModel = true;
        _visionModelName = _getVisionModelFromModels(_availableLocalModels);
      } else {
        _hasVisionModel = false;
        _visionModelName = '';
      }
      if (_availableLocalModels.isNotEmpty) {
        // If no model has ever been selected, set the first available one as initial default
        if (_selectedModel.isEmpty) {
          _selectedModel = _resolveSelection('');
          await _saveSelection(await SharedPreferences.getInstance());
        }
      }
      // On the first time loading alone, only pop up in center if more than one model is available
      if (!_hasConfiguredAi && _availableLocalModels.length > 1) {
        _showModelSelectionDialog = true;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> saveAiConfiguration({
    required String model,
    required String geminiApiKey,
  }) async {
    _geminiApiKey = geminiApiKey.trim();
    _selectedModel = _resolveSelection(model.trim());
    _hasConfiguredAi = true;
    _showModelSelectionDialog = false;
    final prefs = await SharedPreferences.getInstance();
    await _saveSelection(prefs);
    await prefs.setString(PrefsKeys.geminiApiKey, _geminiApiKey);
    await prefs.setBool(PrefsKeys.hasConfiguredAi, true);
    notifyListeners();
  }

  Future<void> setSelectedLocalModel(String model) async {
    _selectedModel = _resolveSelection(model.trim());
    _showModelSelectionDialog = false;
    _hasConfiguredAi = true;
    final prefs = await SharedPreferences.getInstance();
    await _saveSelection(prefs);
    await prefs.setBool(PrefsKeys.hasConfiguredAi, true);
    notifyListeners();
  }

  void openModelSelectionDialog() {
    _showModelSelectionDialog = true;
    notifyListeners();
  }

  void dismissModelSelectionDialog() {
    _showModelSelectionDialog = false;
    _hasConfiguredAi = true;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(PrefsKeys.hasConfiguredAi, true);
    });
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode newMode) async {
    if (_themeMode == newMode) return;
    _themeMode = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.themeMode, _themeMode.index);
    notifyListeners();
  }

  /// Sets and saves the Gemini API key into persistent storage.
  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key.trim();
    _selectedModel = _resolveSelection(_selectedModel);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.geminiApiKey, _geminiApiKey);
    await _saveSelection(prefs);
    notifyListeners();
  }

  Future<void> _saveSelection(SharedPreferences prefs) async {
    if (_selectedModel.isEmpty) {
      await prefs.remove(PrefsKeys.selectedModel);
    } else {
      await prefs.setString(PrefsKeys.selectedModel, _selectedModel);
    }
  }

  /// Keeps the picker valid: Gemini needs a key, and an empty choice falls
  /// back to Gemini (if a key exists) or the first Ollama model.
  String _resolveSelection(String model) {
    if (model == AppConstants.geminiModelId && _geminiApiKey.isEmpty) {
      model = '';
    }
    if (model.isEmpty) {
      return _availableLocalModels.isNotEmpty
          ? _availableLocalModels.first
          : (_geminiApiKey.isNotEmpty ? AppConstants.geminiModelId : '');
    }
    return model;
  }

  Future<void> switchMode(AgentMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.agentMode, _mode.index);
    if (_isBackendOnline) {
      checkFileAgentStatus();
      checkPersonalAgentStatus();
    }
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    _backendUrl = url.trim();
    _apiService = ApiService(baseUrl: _backendUrl);
    _wsClient = AgentWebSocketClient(baseUrl: _backendUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.backendUrl, _backendUrl);
    _startStartupHealthCheck();
    notifyListeners();
  }

  Future<void> checkFileAgentStatus() async {
    try {
      final status = await _apiService.checkFileHealth();
      _fileAgentHealth = status;
    } catch (_) {
      _fileAgentHealth = {'status': 'offline'};
    }
    notifyListeners();
  }

  Future<void> checkPersonalAgentStatus() async {
    try {
      final status = await _apiService.checkPersonalHealth();
      _personalAgentHealth = status;
    } catch (_) {
      _personalAgentHealth = {'status': 'offline'};
    }
    notifyListeners();
  }

  Future<void> fetchPersonalCredentials() async {
    try {
      final creds = await _apiService.getGoogleCredentials();
      _personalCredentials = creds;
    } catch (_) {
      _personalCredentials = {'status': 'offline', 'configured': false};
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> saveGoogleCredentials(
    String clientId,
    String clientSecret,
  ) async {
    final result = await _apiService.saveGoogleCredentials(
      clientId: clientId,
      clientSecret: clientSecret,
    );
    if (result['success'] == true) {
      await fetchPersonalCredentials();
      await checkPersonalAgentStatus();
    }
    return result;
  }

  bool _isConnectingGoogle = false;
  bool get isConnectingGoogle => _isConnectingGoogle;

  /// True when every Google service (Gmail, Calendar, Drive, Tasks) is signed in.
  bool get isGoogleAccountConnected {
    final tokens = _personalCredentials['tokens'];
    return tokens is Map &&
        tokens.isNotEmpty &&
        tokens.values.every((v) => v == true);
  }

  /// Runs the single Google sign-in. Returns an error message, or null on success.
  Future<String?> connectGoogleAccount() async {
    if (_isConnectingGoogle) return null;
    _isConnectingGoogle = true;
    notifyListeners();
    try {
      final res = await _apiService.connectGoogleAccount();
      await fetchPersonalCredentials();
      await checkPersonalAgentStatus();
      final missing = (res['missing'] as List?)?.cast<Object>() ?? const [];
      if (missing.isNotEmpty) {
        final names = missing
            .map(
              (m) =>
                  '${m.toString()[0].toUpperCase()}${m.toString().substring(1)}',
            )
            .join(', ');
        return 'Connected, but $names access was not allowed. Press Connect Google Account again and keep every permission ticked.';
      }
      return null;
    } catch (e) {
      return e is TimeoutException
          ? 'Google sign-in timed out. Press Connect Google Account and finish signing in in the browser.'
          : e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isConnectingGoogle = false;
      notifyListeners();
    }
  }

  int _startupRun = 0;

  Future<void> _startStartupHealthCheck() async {
    _engineStatus = EngineStatus.starting;
    _isConnecting = true;
    _isBackendOnline = false;
    _isLocalLlmOnline = false;
    _initElapsedSeconds = 0;
    _engineStatusMessage = 'Starting DeskMate AI engine';

    _startupTimer?.cancel();
    final stopwatch = Stopwatch()..start();
    _startupTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _initElapsedSeconds = stopwatch.elapsed.inSeconds;
      if (_initElapsedSeconds < 15) {
        _engineStatusMessage = 'Starting DeskMate AI engine';
      } else if (_initElapsedSeconds < 45) {
        _engineStatusMessage = 'Binding local port & verifying runtime';
      } else {
        _engineStatusMessage =
            'Loading dependencies & local models (first launch may take 1-2 min)';
      }
      notifyListeners();
    });

    // Use BackendManager.backendUrl if valid, otherwise fallback candidates
    final primaryCandidate = BackendManager.backendUrl;
    if (_backendUrl.isEmpty || AppConstants.isBuiltInUrl(_backendUrl)) {
      _backendUrl = primaryCandidate;
    }
    _apiService = ApiService(baseUrl: _backendUrl);
    _wsClient = AgentWebSocketClient(baseUrl: _backendUrl);
    notifyListeners();

    final run = ++_startupRun;
    const int maxTotalSeconds = 180; // 3 full minutes realistic grace period
    while (stopwatch.elapsed.inSeconds < maxTotalSeconds) {
      if (run != _startupRun) return; // A newer startup check took over.
      // Re-read each round: BackendManager may assign a dynamic port after we start.
      final candidates = <String>{
        BackendManager.backendUrl,
        if (_backendUrl.isNotEmpty) _backendUrl,
        ...AppConstants.candidateUrls(BackendManager.backendUrl),
      };
      for (final candidateUrl in candidates) {
        try {
          final testService = ApiService(baseUrl: candidateUrl);
          final health = await testService.checkHealth();
          if (run != _startupRun) return;
          if (BackendManager.isDeskMateHealth(health)) {
            stopwatch.stop();
            _startupTimer?.cancel();
            _backendUrl = candidateUrl;
            _apiService = testService;
            _wsClient = AgentWebSocketClient(baseUrl: candidateUrl);
            _isBackendOnline = true;
            _isLocalLlmOnline = health['local_llm'] == 'online';
            _localLlmStatus = health['local_llm']?.toString() ?? 'offline';
            _engineStatus = _isLocalLlmOnline
                ? EngineStatus.ready
                : EngineStatus.degraded;
            _isConnecting = false;
            _updateVisionState(health);
            _errorMessage = '';
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(PrefsKeys.backendUrl, _backendUrl);
            checkFileAgentStatus();
            checkPersonalAgentStatus();
            fetchAvailableModels();
            notifyListeners();
            _startHealthPolling();
            return;
          }
        } catch (_) {}
      }

      // Adaptive polling interval: 500ms for first 10s sprint, then 1s, then 1.5s
      final elapsed = stopwatch.elapsed.inSeconds;
      final delayMs = elapsed < 10 ? 500 : (elapsed < 45 ? 1000 : 1500);
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    if (run != _startupRun) return;
    stopwatch.stop();
    _startupTimer?.cancel();
    _engineStatus = EngineStatus.failed;
    _isConnecting = false;
    _isBackendOnline = false;
    _isLocalLlmOnline = false;
    _hasVisionModel = false;
    _visionModelName = '';
    _errorMessage =
        'Could not connect to DeskMate local engine after 3 minutes. Please restart the engine or check logs.';
    notifyListeners();
    _startHealthPolling();
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(AppTimeouts.healthPoll, (_) => _pollHealth());
  }

  Future<void> _pollHealth() async {
    var health = await _apiService.checkHealth();
    if (health['status'] != 'ok') {
      for (final candidate in AppConstants.candidateUrls(
        BackendManager.backendUrl,
      )) {
        if (candidate != _backendUrl) {
          try {
            final fbService = ApiService(baseUrl: candidate);
            final fbHealth = await fbService.checkHealth();
            if (BackendManager.isDeskMateHealth(fbHealth)) {
              _backendUrl = candidate;
              _apiService = fbService;
              _wsClient = AgentWebSocketClient(baseUrl: candidate);
              health = fbHealth;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(PrefsKeys.backendUrl, _backendUrl);
              break;
            }
          } catch (_) {}
        }
      }
    }

    final bool newBackendOnline = health['status'] == 'ok';
    bool newLocalLlmOnline = health['local_llm'] == 'online';
    final newLocalLlmStatus = health['local_llm']?.toString() ?? 'offline';
    if (newLocalLlmStatus != _localLlmStatus) {
      _localLlmStatus = newLocalLlmStatus;
      notifyListeners();
    }

    // If backend is offline, check if Ollama runtime itself is online directly
    if (!newBackendOnline) {
      try {
        final ollamaCheck = await http
            .get(Uri.parse('${AppConstants.ollamaUrl}/api/tags'))
            .timeout(const Duration(milliseconds: 600));
        if (ollamaCheck.statusCode == 200) {
          newLocalLlmOnline = true;
        }
      } catch (_) {}
    }

    final bool oldHasVision = _hasVisionModel;
    final String oldVisionName = _visionModelName;
    _updateVisionState(health, isLocalOnline: newLocalLlmOnline);

    if (_isBackendOnline != newBackendOnline ||
        _isLocalLlmOnline != newLocalLlmOnline ||
        _hasVisionModel != oldHasVision ||
        _visionModelName != oldVisionName ||
        _isConnecting) {
      _isBackendOnline = newBackendOnline;
      _isLocalLlmOnline = newLocalLlmOnline;
      _isConnecting = false;
      if (!_isLocalLlmOnline) {
        _availableLocalModels = [];
      }
      if (_isBackendOnline) {
        _engineStatus = _isLocalLlmOnline
            ? EngineStatus.ready
            : EngineStatus.degraded;
        _errorMessage = '';
        if (_availableLocalModels.isEmpty && _isLocalLlmOnline) {
          fetchAvailableModels();
        }
        checkFileAgentStatus();
        checkPersonalAgentStatus();
      } else {
        _engineStatus = EngineStatus.failed;
        _fileAgentHealth = {'status': 'offline'};
        _personalAgentHealth = {'status': 'offline'};
      }
      notifyListeners();
    } else if (_isBackendOnline && _fileAgentHealth['status'] == 'offline') {
      checkFileAgentStatus();
    }
  }

  /// One-shot status check that does not restart the backend.
  Future<void> refreshHealthStatus() async {
    await _pollHealth();
    if (_isBackendOnline && _isLocalLlmOnline) {
      await fetchAvailableModels();
    }
    notifyListeners();
  }

  Future<void> retryConnecting() async {
    try {
      await BackendManager.killStaleBackendProcesses();
      await Future.delayed(const Duration(milliseconds: 300));
      await BackendManager.start();
    } catch (_) {}
    await _startStartupHealthCheck();
  }

  Future<void> openEngineLogs() async {
    try {
      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        final logDir = '$home/Library/Application Support/DeskMate';
        await Process.run('/usr/bin/open', [logDir]);
      } else if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ?? '';
        final logDir = '$appData\\DeskMate';
        await Process.run('explorer.exe', [logDir]);
      }
    } catch (_) {}
  }

  void _addMessage(ChatMessage msg, {AgentMode? mode}) {
    if ((mode ?? _mode) == AgentMode.personal) {
      _personalMessages.add(msg);
    } else {
      _fileMessages.add(msg);
    }
  }

  Future<void> _updateConversationId(
    String newId,
    SharedPreferences prefs, {
    required AgentMode mode,
  }) async {
    if (newId.isEmpty) return;
    if (mode == AgentMode.personal) {
      if (newId != _personalConversationId) {
        _personalConversationId = newId;
        await prefs.setString(
          PrefsKeys.personalConversationId,
          _personalConversationId,
        );
      }
    } else {
      if (newId != _fileConversationId) {
        _fileConversationId = newId;
        await prefs.setString(PrefsKeys.conversationId, _fileConversationId);
      }
    }
  }

  /// Stops waiting for the current reply. The backend may still finish an
  /// action that already started, but its reply is discarded.
  void cancelSending() {
    if (!_isSending) return;
    _chatEpoch++;
    _sendingClient?.cancel();
    final restCancel = _restCancel;
    if (restCancel != null && !restCancel.isCompleted) restCancel.complete();
  }

  Future<void> resetChat() async {
    cancelSending();
    _errorMessage = '';
    _activeTelemetry = [];
    final isPersonal = _mode == AgentMode.personal;
    final prevId = isPersonal ? _personalConversationId : _fileConversationId;
    if (isPersonal) {
      _personalMessages = [];
      _personalConversationId = '';
    } else {
      _fileMessages = [];
      _fileConversationId = '';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      isPersonal ? PrefsKeys.personalConversationId : PrefsKeys.conversationId,
    );
    if (prevId.isNotEmpty) {
      await _apiService.resetChat(prevId);
    }
    notifyListeners();
  }

  // Bumped on cancel/reset so a reply that arrives later is dropped.
  int _chatEpoch = 0;
  // The client of the in-flight send (health polling may swap _wsClient).
  AgentWebSocketClient? _sendingClient;
  // Completed by Stop while waiting on the REST fallback.
  Completer<void>? _restCancel;

  static int _msgCounter = 0;
  String _generateMessageId() {
    _msgCounter++;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'msg_${ts}_$_msgCounter';
  }

  Future<void> editAndResendMessage(int messageIndex, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || _isSending) return;

    final isPersonal = _mode == AgentMode.personal;
    final currentList = isPersonal ? _personalMessages : _fileMessages;

    if (messageIndex < 0 || messageIndex >= currentList.length) return;

    // Truncate message list up to messageIndex (removing this user query and all subsequent responses)
    final truncated = List<ChatMessage>.from(
      currentList.sublist(0, messageIndex),
    );
    if (isPersonal) {
      _personalMessages = truncated;
    } else {
      _fileMessages = truncated;
    }

    notifyListeners();

    // Re-send the edited query from this turn
    await sendMessage(trimmed);
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    final userMsg = ChatMessage(
      id: _generateMessageId(),
      role: MessageRole.user,
      content: text,
    );
    // Capture the chat this message belongs to: the user may switch mode
    // or reset while the reply is still coming.
    final sendMode = _mode;
    final isPersonal = sendMode == AgentMode.personal;
    final epoch = _chatEpoch;
    _addMessage(userMsg, mode: sendMode);
    final targetList = isPersonal ? _personalMessages : _fileMessages;
    // A reset swaps in a new list; replies for the old chat are then dropped.
    bool chatStillOpen() =>
        identical(targetList, isPersonal ? _personalMessages : _fileMessages);

    _isSending = true;
    _errorMessage = '';
    _activeTelemetry = [];
    _activeStatusTitle = 'Thinking...';
    notifyListeners();

    try {
      final currentList = isPersonal ? _personalMessages : _fileMessages;
      // Extract recent history context
      final history = currentList
          .take(currentList.length - 1)
          .map((m) => {'role': m.role.name, 'content': m.content})
          .toList();
      final conversationId = isPersonal
          ? _personalConversationId
          : _fileConversationId;

      Map<String, dynamic> response;
      final ws = _wsClient;
      _sendingClient = ws;
      try {
        // Preferred: Real-time bidirectional WebSocket streaming
        response = await ws.sendMessageStream(
          agentType: isPersonal
              ? WebSocketAgentType.personalAssistant
              : WebSocketAgentType.fileCopilot,
          message: text,
          history: history,
          conversationId: conversationId,
          geminiApiKey: _requestGeminiKey,
          model: _requestLocalModel,
          onStatus: (title, message) {
            if (epoch != _chatEpoch) return;
            _activeStatusTitle = title;
            notifyListeners();
          },
          onTelemetry: (step) {
            if (epoch != _chatEpoch) return;
            final existingIndex = _activeTelemetry.indexWhere(
              (s) => s.step == step.step && s.phase == 'reasoning',
            );
            if (existingIndex != -1 && step.phase == 'reasoning') {
              _activeTelemetry[existingIndex] = step;
            } else {
              _activeTelemetry.add(step);
            }
            notifyListeners();
          },
        );
      } on AgentConnectionException {
        // The socket never connected, so nothing ran yet: REST is safe.
        if (epoch != _chatEpoch) throw const AgentCancelledException();
        final restCancel = _restCancel = Completer<void>();
        final Future<Map<String, dynamic>> restCall;
        if (isPersonal) {
          restCall = _apiService.sendPersonalMessage(
            message: text,
            conversationId: conversationId,
            geminiApiKey: _requestGeminiKey,
            model: _requestLocalModel,
          );
        } else {
          restCall = _apiService.sendMessage(
            message: text,
            conversationId: conversationId,
            geminiApiKey: _requestGeminiKey,
            model: _requestLocalModel,
          );
        }
        response = await Future.any([
          restCall,
          restCancel.future.then<Map<String, dynamic>>(
            (_) => throw const AgentCancelledException(),
          ),
        ]);
      }
      if (epoch != _chatEpoch) return;

      final newId = response['conversation_id'] as String? ?? '';
      final rawTelemetry =
          response['telemetry'] as List<dynamic>? ?? _activeTelemetry;
      final List<AgentStepTelemetry> finalTelemetry = [];
      for (final item in rawTelemetry) {
        if (item is AgentStepTelemetry) {
          finalTelemetry.add(item);
        } else if (item is Map<String, dynamic>) {
          finalTelemetry.add(AgentStepTelemetry.fromJson(item));
        } else if (item is Map) {
          finalTelemetry.add(
            AgentStepTelemetry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final assistantMsg = ChatMessage(
        id: _generateMessageId(),
        role: MessageRole.assistant,
        content: response['reply'] as String? ?? '',
        telemetry: finalTelemetry.isNotEmpty
            ? finalTelemetry
            : List.from(_activeTelemetry),
      );

      if (!chatStillOpen()) return;
      await _updateConversationId(newId, prefs, mode: sendMode);
      targetList.add(assistantMsg);
    } on AgentCancelledException {
      if (!chatStillOpen()) return;
      targetList.add(
        ChatMessage(
          id: _generateMessageId(),
          role: MessageRole.assistant,
          content:
              'Stopped. If the assistant had already started an action (like sending an email), it may still finish.',
          telemetry: List.from(_activeTelemetry),
        ),
      );
    } catch (e) {
      if (epoch == _chatEpoch && chatStillOpen()) {
        final reason = _friendlyChatError(e);
        _errorMessage = reason;
        targetList.add(
          ChatMessage(
            id: _generateMessageId(),
            role: MessageRole.assistant,
            content: 'Sorry, that didn\'t work. $reason',
            telemetry: List.from(_activeTelemetry),
          ),
        );
      }
    } finally {
      _isSending = false;
      _sendingClient = null;
      _restCancel = null;
      _activeTelemetry = [];
      if (isPersonal) {
        checkPersonalAgentStatus();
      }
      notifyListeners();
    }
  }

  static String _friendlyChatError(Object e) {
    final text = e.toString().replaceAll(RegExp(r'Exception: ?'), '').trim();
    if (e is AgentRunException) return text;
    if (text.contains('Failed to connect') ||
        text.contains('SocketException') ||
        text.contains('Connection refused')) {
      return 'DeskMate\'s local engine is not reachable. Wait for it to finish starting, or press Retry in the status bar.';
    }
    if (e is TimeoutException || text.contains('TimeoutException')) {
      return 'The request took too long. Try a simpler request.';
    }
    return text.isNotEmpty ? text : 'Unknown error.';
  }
}
