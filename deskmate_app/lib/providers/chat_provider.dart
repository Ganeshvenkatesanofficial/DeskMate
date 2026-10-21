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
  String _selectedLocalModel = '';
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
  bool get isUsingGemini => _geminiApiKey.isNotEmpty;
  List<String> get availableLocalModels => _availableLocalModels;
  String get selectedLocalModel => _selectedLocalModel;
  String get effectiveModel => _selectedLocalModel.isNotEmpty
      ? _selectedLocalModel
      : (_availableLocalModels.isNotEmpty ? _availableLocalModels.first : '');
  bool get showModelSelectionDialog => _showModelSelectionDialog;
  bool get hasConfiguredAi => _hasConfiguredAi;
  bool get hasVisionModel =>
      _hasVisionModel || _detectVisionInModels(_availableLocalModels);
  String get visionModelName {
    if (_visionModelName.isNotEmpty) return _visionModelName;
    return _getVisionModelFromModels(_availableLocalModels);
  }

  bool get useLightweightVision => _useLightweightVision;
  bool get isVisionActive =>
      hasVisionModel || isUsingGemini || _useLightweightVision;

  /// Check whether AI engines (Gemini or Local Ollama Reasoning + Vision) are ready for meeting transcription & summarization.
  bool get isMeetingAiReady {
    if (isUsingGemini) return true;
    return isLocalLlmOnline &&
        availableLocalModels.isNotEmpty &&
        isVisionActive;
  }

  String get meetingAiNotReadyReason {
    if (isUsingGemini) return '';
    if (!isLocalLlmOnline) {
      return 'Ollama is offline or unreachable. Please launch Ollama locally, or configure a Gemini API key.';
    }
    if (availableLocalModels.isEmpty) {
      return 'No reasoning LLM model installed in Ollama. Run `ollama pull qwen2.5-coder:1.5b` or configure a Gemini API key.';
    }
    if (!isVisionActive) {
      return 'No Vision capability active. Pull `llama3.2-vision`, enable Lightweight Laptop Mode in settings, or configure Gemini.';
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
    _selectedLocalModel = prefs.getString(PrefsKeys.selectedModel) ?? '';
    _geminiApiKey = prefs.getString(PrefsKeys.geminiApiKey) ?? '';
    _useLightweightVision =
        prefs.getBool(PrefsKeys.useLightweightVision) ?? false;
    _hasConfiguredAi =
        prefs.getBool(PrefsKeys.hasConfiguredAi) ??
        (_selectedLocalModel.isNotEmpty);
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

  void _updateVisionState(Map<String, dynamic> health) {
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
    if (!_isBackendOnline) return;
    try {
      final models = await _apiService.getAvailableModels();
      _availableLocalModels = models;
      if (_detectVisionInModels(_availableLocalModels)) {
        _hasVisionModel = true;
        _visionModelName = _getVisionModelFromModels(_availableLocalModels);
      }
      if (_availableLocalModels.isNotEmpty) {
        // If no model has ever been selected, set the first available one as initial default
        if (_selectedLocalModel.isEmpty) {
          _selectedLocalModel = _availableLocalModels.first;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.selectedModel, _selectedLocalModel);
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
    _selectedLocalModel = model.trim();
    _geminiApiKey = geminiApiKey.trim();
    _hasConfiguredAi = true;
    _showModelSelectionDialog = false;
    final prefs = await SharedPreferences.getInstance();
    if (_selectedLocalModel.isNotEmpty) {
      await prefs.setString(PrefsKeys.selectedModel, _selectedLocalModel);
    }
    await prefs.setString(PrefsKeys.geminiApiKey, _geminiApiKey);
    await prefs.setBool(PrefsKeys.hasConfiguredAi, true);
    notifyListeners();
  }

  Future<void> setSelectedLocalModel(String model) async {
    _selectedLocalModel = model.trim();
    _showModelSelectionDialog = false;
    _hasConfiguredAi = true;
    final prefs = await SharedPreferences.getInstance();
    if (_selectedLocalModel.isNotEmpty) {
      await prefs.setString(PrefsKeys.selectedModel, _selectedLocalModel);
    }
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.geminiApiKey, _geminiApiKey);
    notifyListeners();
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

    final candidates = AppConstants.candidateUrls(primaryCandidate);

    const int maxTotalSeconds = 180; // 3 full minutes realistic grace period
    while (stopwatch.elapsed.inSeconds < maxTotalSeconds) {
      for (final candidateUrl in candidates) {
        try {
          final testService = ApiService(baseUrl: candidateUrl);
          final health = await testService.checkHealth();
          if (health['status'] == 'ok') {
            stopwatch.stop();
            _startupTimer?.cancel();
            _backendUrl = candidateUrl;
            _apiService = testService;
            _wsClient = AgentWebSocketClient(baseUrl: candidateUrl);
            _isBackendOnline = true;
            _isLocalLlmOnline = health['local_llm'] == 'online';
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
            if (fbHealth['status'] == 'ok') {
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
    _updateVisionState(health);

    if (_isBackendOnline != newBackendOnline ||
        _isLocalLlmOnline != newLocalLlmOnline ||
        _hasVisionModel != oldHasVision ||
        _visionModelName != oldVisionName ||
        _isConnecting) {
      _isBackendOnline = newBackendOnline;
      _isLocalLlmOnline = newLocalLlmOnline;
      _isConnecting = false;
      if (_isBackendOnline) {
        _engineStatus = _isLocalLlmOnline
            ? EngineStatus.ready
            : EngineStatus.degraded;
        _errorMessage = '';
        if (_availableLocalModels.isEmpty) {
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
    if (_isBackendOnline) {
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

  void _addMessage(ChatMessage msg) {
    if (_mode == AgentMode.personal) {
      _personalMessages.add(msg);
    } else {
      _fileMessages.add(msg);
    }
  }

  Future<void> _updateConversationId(
    String newId,
    SharedPreferences prefs,
  ) async {
    if (newId.isEmpty) return;
    if (_mode == AgentMode.personal) {
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

  Future<void> resetChat() async {
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
    _addMessage(userMsg);

    _isSending = true;
    _errorMessage = '';
    _activeTelemetry = [];
    _activeStatusTitle = 'Thinking...';
    notifyListeners();

    try {
      final currentList = _mode == AgentMode.personal
          ? _personalMessages
          : _fileMessages;
      // Extract recent history context
      final history = currentList
          .take(currentList.length - 1)
          .map((m) => {'role': m.role.name, 'content': m.content})
          .toList();

      Map<String, dynamic> response;
      try {
        // Preferred: Real-time bidirectional WebSocket streaming
        response = await _wsClient.sendMessageStream(
          agentType: _mode == AgentMode.personal
              ? WebSocketAgentType.personalAssistant
              : WebSocketAgentType.fileCopilot,
          message: text,
          history: history,
          conversationId: _mode == AgentMode.personal
              ? _personalConversationId
              : _fileConversationId,
          geminiApiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
          model: _selectedLocalModel.isNotEmpty ? _selectedLocalModel : null,
          onStatus: (title, message) {
            _activeStatusTitle = title;
            notifyListeners();
          },
          onTelemetry: (step) {
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
      } catch (wsErr) {
        // Fallback: Synchronous REST API
        if (_mode == AgentMode.personal) {
          response = await _apiService.sendPersonalMessage(
            message: text,
            conversationId: _personalConversationId,
            geminiApiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
            model: _selectedLocalModel.isNotEmpty ? _selectedLocalModel : null,
          );
        } else {
          response = await _apiService.sendMessage(
            message: text,
            conversationId: _fileConversationId,
            geminiApiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
            model: _selectedLocalModel.isNotEmpty ? _selectedLocalModel : null,
          );
        }
      }

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

      await _updateConversationId(newId, prefs);
      _addMessage(assistantMsg);
    } catch (e) {
      _errorMessage = e.toString();
      final errReply = ChatMessage(
        id: _generateMessageId(),
        role: MessageRole.assistant,
        content: 'Sorry, I encountered an error: $e',
        telemetry: List.from(_activeTelemetry),
      );
      _addMessage(errReply);
    } finally {
      _isSending = false;
      _activeTelemetry = [];
      if (_mode == AgentMode.personal) {
        checkPersonalAgentStatus();
      }
      notifyListeners();
    }
  }
}
