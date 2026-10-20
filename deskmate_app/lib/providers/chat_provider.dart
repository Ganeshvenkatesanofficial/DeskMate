import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/agent_websocket_client.dart';
import '../services/backend_manager.dart';

enum AgentMode { deskMate, personal, meeting }

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
  bool get isBackendOnline => _isBackendOnline;
  bool get isLocalLlmOnline => _isLocalLlmOnline;
  bool get isConnecting => _isConnecting;
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

  Future<void> fetchAvailableModels() async {
    if (!_isBackendOnline) return;
    try {
      final models = await _apiService.getAvailableModels();
      _availableLocalModels = models;
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
    _isConnecting = true;
    _isBackendOnline = false;
    _isLocalLlmOnline = false;

    // Use BackendManager.backendUrl if valid, otherwise fallback candidates
    final primaryCandidate = BackendManager.backendUrl;
    if (_backendUrl.isEmpty || AppConstants.isBuiltInUrl(_backendUrl)) {
      _backendUrl = primaryCandidate;
    }
    _apiService = ApiService(baseUrl: _backendUrl);
    _wsClient = AgentWebSocketClient(baseUrl: _backendUrl);
    notifyListeners();

    final candidates = AppConstants.candidateUrls(primaryCandidate);

    const int maxAttempts = 15;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      for (final candidateUrl in candidates) {
        try {
          final testService = ApiService(baseUrl: candidateUrl);
          final health = await testService.checkHealth();
          if (health['status'] == 'ok') {
            _backendUrl = candidateUrl;
            _apiService = testService;
            _wsClient = AgentWebSocketClient(baseUrl: candidateUrl);
            _isBackendOnline = true;
            _isLocalLlmOnline = health['local_llm'] == 'online';
            _isConnecting = false;
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
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isConnecting = false;
    _isBackendOnline = false;
    _isLocalLlmOnline = false;
    _errorMessage =
        'Failed to connect to local backend. Please ensure the backend server is running.';
    notifyListeners();
    _startHealthPolling();
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
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

      bool newBackendOnline = health['status'] == 'ok';
      bool newLocalLlmOnline = health['local_llm'] == 'online';

      if (_isBackendOnline != newBackendOnline ||
          _isLocalLlmOnline != newLocalLlmOnline ||
          _isConnecting) {
        _isBackendOnline = newBackendOnline;
        _isLocalLlmOnline = newLocalLlmOnline;
        _isConnecting = false;
        if (_isBackendOnline) {
          _errorMessage = '';
          if (_availableLocalModels.isEmpty) {
            fetchAvailableModels();
          }
          checkFileAgentStatus();
          checkPersonalAgentStatus();
        }
        notifyListeners();
      }
    });
  }

  Future<void> retryConnecting() async {
    await _startStartupHealthCheck();
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
