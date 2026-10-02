import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

enum AgentMode { deskMate, personal }

class ChatProvider extends ChangeNotifier {
  List<ChatMessage> _fileMessages = [];
  List<ChatMessage> _personalMessages = [];
  bool _isSending = false;
  String _errorMessage = '';
  String _fileConversationId = '';
  String _personalConversationId = '';
  String _backendUrl = 'http://127.0.0.1:8080';
  bool _isConnecting = true;
  bool _isBackendOnline = false;
  bool _isLocalLlmOnline = false;
  AgentMode _mode = AgentMode.deskMate;
  Map<String, dynamic> _personalAgentHealth = {'status': 'loading'};
  Timer? _healthTimer;

  // Gemini API key – kept only in memory, never persisted.
  String _geminiApiKey = '';

  List<ChatMessage> get messages => _mode == AgentMode.personal ? _personalMessages : _fileMessages;
  bool get isSending => _isSending;
  String get errorMessage => _errorMessage;
  String get conversationId => _mode == AgentMode.personal ? _personalConversationId : _fileConversationId;
  String get backendUrl => _backendUrl;
  bool get isBackendOnline => _isBackendOnline;
  bool get isLocalLlmOnline => _isLocalLlmOnline;
  bool get isConnecting => _isConnecting;
  AgentMode get mode => _mode;
  Map<String, dynamic> get personalAgentHealth => _personalAgentHealth;
  String get geminiApiKey => _geminiApiKey;
  bool get isUsingGemini => _geminiApiKey.isNotEmpty;

  late ApiService _apiService;

  ChatProvider() {
    _apiService = ApiService(baseUrl: _backendUrl);
    _loadPreferences();
    _startStartupHealthCheck();
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _fileConversationId = prefs.getString('deskmate_conversation_id') ?? '';
    _personalConversationId = prefs.getString('deskmate_personal_conversation_id') ?? '';
    _backendUrl = prefs.getString('deskmate_backend_url') ?? 'http://127.0.0.1:8080';
    _mode = AgentMode.values[prefs.getInt('deskmate_agent_mode') ?? 0];
    // Gemini key not persisted; asked each session.
    _apiService = ApiService(baseUrl: _backendUrl);
    notifyListeners();
  }

  /// Sets the Gemini API key for this session only (not persisted).
  void setGeminiApiKey(String key) {
    _geminiApiKey = key.trim();
    notifyListeners();
  }

  Future<void> switchMode(AgentMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('deskmate_agent_mode', _mode.index);
    if (_isBackendOnline) {
      checkPersonalAgentStatus();
    }
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    _backendUrl = url.trim();
    _apiService = ApiService(baseUrl: _backendUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deskmate_backend_url', _backendUrl);
    _startStartupHealthCheck();
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

  Future<void> _startStartupHealthCheck() async {
    _isConnecting = true;
    _isBackendOnline = false;
    _isLocalLlmOnline = false;
    notifyListeners();
    const int maxAttempts = 30;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final health = await _apiService.checkHealth();
      if (health['status'] == 'ok') {
        _isBackendOnline = true;
        _isLocalLlmOnline = health['local_llm'] == 'online';
        _isConnecting = false;
        _errorMessage = '';
        checkPersonalAgentStatus();
        notifyListeners();
        _startHealthPolling();
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    _isConnecting = false;
    _isBackendOnline = false;
    _isLocalLlmOnline = false;
    _errorMessage = 'Failed to connect to local backend. Please ensure the backend server is running.';
    notifyListeners();
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final health = await _apiService.checkHealth();
      bool newBackendOnline = health['status'] == 'ok';
      bool newLocalLlmOnline = health['local_llm'] == 'online';
      
      if (_isBackendOnline != newBackendOnline || _isLocalLlmOnline != newLocalLlmOnline) {
        _isBackendOnline = newBackendOnline;
        _isLocalLlmOnline = newLocalLlmOnline;
        notifyListeners();
      }
    });
  }

  Future<void> retryConnecting() async {
    await _startStartupHealthCheck();
  }

  Future<void> resetChat() async {
    _errorMessage = '';
    final prefs = await SharedPreferences.getInstance();
    if (_mode == AgentMode.personal) {
      final prevId = _personalConversationId;
      _personalMessages = [];
      _personalConversationId = '';
      await prefs.remove('deskmate_personal_conversation_id');
      if (prevId.isNotEmpty) {
        await _apiService.resetChat(prevId);
      }
    } else {
      final prevId = _fileConversationId;
      _fileMessages = [];
      _fileConversationId = '';
      await prefs.remove('deskmate_conversation_id');
      if (prevId.isNotEmpty) {
        await _apiService.resetChat(prevId);
      }
    }
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    final userMsg = ChatMessage(id: DateTime.now().toString(), role: MessageRole.user, content: text);
    if (_mode == AgentMode.personal) {
      _personalMessages.add(userMsg);
    } else {
      _fileMessages.add(userMsg);
    }
    _isSending = true;
    _errorMessage = '';
    notifyListeners();
    try {
      Map<String, dynamic> response;
      if (_mode == AgentMode.personal) {
        // Use Gemini if key provided, otherwise local backend.
        response = await _apiService.sendPersonalMessage(
          message: text,
          conversationId: _personalConversationId,
          geminiApiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
        );
      } else {
        response = await _apiService.sendMessage(
          message: text,
          conversationId: _fileConversationId,
          geminiApiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
        );
      }
      final newId = response['conversation_id'] as String? ?? '';
      final prefs = await SharedPreferences.getInstance();
      if (_mode == AgentMode.personal) {
        if (newId.isNotEmpty && newId != _personalConversationId) {
          _personalConversationId = newId;
          await prefs.setString('deskmate_personal_conversation_id', _personalConversationId);
        }
        _personalMessages.add(ChatMessage(
          id: DateTime.now().toString(),
          role: MessageRole.assistant,
          content: response['reply'] as String? ?? '',
        ));
      } else {
        if (newId.isNotEmpty && newId != _fileConversationId) {
          _fileConversationId = newId;
          await prefs.setString('deskmate_conversation_id', _fileConversationId);
        }
        _fileMessages.add(ChatMessage(
          id: DateTime.now().toString(),
          role: MessageRole.assistant,
          content: response['reply'] as String? ?? '',
        ));
      }
    } catch (e) {
      _errorMessage = e.toString();
      final errReply = ChatMessage(
        id: DateTime.now().toString(),
        role: MessageRole.assistant,
        content: 'Sorry, I encountered an error: $e',
      );
      if (_mode == AgentMode.personal) {
        _personalMessages.add(errReply);
      } else {
        _fileMessages.add(errReply);
      }
    } finally {
      _isSending = false;
      if (_mode == AgentMode.personal) {
        checkPersonalAgentStatus();
      }
      notifyListeners();
    }
  }
}
