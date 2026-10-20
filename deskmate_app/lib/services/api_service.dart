import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../services/gemini_service.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  /// Helper to build chat payload dictionary
  Map<String, dynamic> _buildChatPayload({
    required String message,
    String? conversationId,
    String? geminiApiKey,
    String? model,
  }) {
    return {
      'message': message,
      if (conversationId != null && conversationId.isNotEmpty)
        'conversation_id': conversationId,
      if (geminiApiKey != null && geminiApiKey.isNotEmpty)
        'api_key': geminiApiKey,
      if (model != null && model.isNotEmpty) 'model': model,
    };
  }

  /// Helper to perform JSON POST requests with unified decoding and error handling
  Future<Map<String, dynamic>> _postJson(
    Uri url,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final errorMsg = (data is Map)
          ? (data['detail'] ??
                'Request failed with status: ${response.statusCode}')
          : 'Request failed with status: ${response.statusCode}';
      throw Exception(errorMsg);
    }
    return data as Map<String, dynamic>;
  }

  /// Helper to perform GET requests with status check and fallback on failure
  Future<Map<String, dynamic>> _getJson(
    String path, {
    Duration timeout = const Duration(seconds: 5),
    required Map<String, dynamic> fallback,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  // Send personal message, using Gemini key with backend tools, or direct Gemini if backend unavailable.
  Future<Map<String, dynamic>> sendPersonalMessage({
    required String message,
    String? conversationId,
    String? geminiApiKey,
    String? model,
  }) async {
    final url = Uri.parse('$baseUrl/api/personal');
    final body = _buildChatPayload(
      message: message,
      conversationId: conversationId,
      geminiApiKey: geminiApiKey,
      model: model,
    );

    try {
      return await _postJson(url, body);
    } catch (e) {
      // If backend is unavailable or fails, fallback to direct Gemini client
      if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
        try {
          final gemini = GeminiService(apiKey: geminiApiKey);
          final reply = await gemini.generateContent(message);
          return {'reply': reply, 'conversation_id': conversationId ?? ''};
        } catch (_) {}
      }
      throw Exception('Failed to connect to backend: $e');
    }
  }

  // Send file-lens (code) message using local backend.
  Future<Map<String, dynamic>> sendMessage({
    required String message,
    String? conversationId,
    String? geminiApiKey,
    String? model,
  }) async {
    final url = Uri.parse('$baseUrl/api/chat');
    final body = _buildChatPayload(
      message: message,
      conversationId: conversationId,
      geminiApiKey: geminiApiKey,
      model: model,
    );

    try {
      return await _postJson(url, body);
    } catch (e) {
      throw Exception('Failed to connect to backend: $e');
    }
  }

  Future<void> resetChat(String conversationId) async {
    final url = Uri.parse('$baseUrl/api/reset/$conversationId');
    try {
      await http.post(url).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore reset errors in production
    }
  }

  Future<Map<String, dynamic>> checkHealth() async {
    return _getJson(
      '/api/health',
      timeout: const Duration(seconds: 2),
      fallback: {'status': 'offline', 'local_llm': 'offline'},
    );
  }

  /// Fetch list of available local models from backend
  Future<List<String>> getAvailableModels() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/models'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawModels = data['models'] as List<dynamic>? ?? [];
        return rawModels
            .map((m) => m.toString())
            .where((m) => m.isNotEmpty)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> checkFileHealth() async {
    return _getJson('/api/file/health', fallback: {'status': 'offline'});
  }

  Future<Map<String, dynamic>> checkPersonalHealth() async {
    return _getJson('/api/personal/health', fallback: {'status': 'offline'});
  }

  Future<Map<String, dynamic>> getGoogleCredentials() async {
    return _getJson(
      '/api/personal/credentials',
      timeout: const Duration(seconds: 6),
      fallback: {'status': 'offline', 'configured': false},
    );
  }

  Future<Map<String, dynamic>> saveGoogleCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      final body = await _postJson(
        Uri.parse('$baseUrl/api/personal/credentials'),
        {'client_id': clientId.trim(), 'client_secret': clientSecret.trim()},
        timeout: const Duration(seconds: 10),
      );

      return {
        'success': true,
        'message':
            body['message'] ?? 'Credentials saved and activated successfully.',
        'data': body,
      };
    } catch (e) {
      final errStr = e.toString().replaceFirst('Exception: ', '');
      return {
        'success': false,
        'message': errStr.isNotEmpty ? errStr : 'Failed to save credentials.',
      };
    }
  }

  /// Fetch SQLite database overview including file path, size, and table summaries
  Future<Map<String, dynamic>> getDatabaseOverview() async {
    return _getJson(
      '/api/database/overview',
      timeout: const Duration(seconds: 6),
      fallback: {
        'status': 'offline',
        'path': '',
        'size_bytes': 0,
        'size_kb': 0.0,
        'tables': [],
      },
    );
  }

  /// Fetch rows and schema for a specific SQLite table
  Future<Map<String, dynamic>> getDatabaseTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
  }) async {
    return _getJson(
      '/api/database/table/$tableName?limit=$limit&offset=$offset',
      timeout: const Duration(seconds: 8),
      fallback: {
        'status': 'error',
        'table': tableName,
        'total_rows': 0,
        'columns': [],
        'rows': [],
      },
    );
  }

  /// Execute a custom safe read-only SQL SELECT query
  Future<Map<String, dynamic>> executeDatabaseQuery(String query) async {
    try {
      final body = await _postJson(Uri.parse('$baseUrl/api/database/query'), {
        'query': query.trim(),
      }, timeout: const Duration(seconds: 15));
      return body;
    } catch (e) {
      final errStr = e.toString().replaceFirst('Exception: ', '');
      return {
        'status': 'error',
        'columns': [],
        'rows': [],
        'count': 0,
        'error': errStr.isNotEmpty ? errStr : 'Failed to execute query.',
      };
    }
  }

  // --- Meeting Intelligence Endpoints ---

  Future<Map<String, dynamic>> startMeeting({
    int monitor = 1,
    double fps = 2.0,
    bool allowLightweightMode = false,
  }) async {
    final url = Uri.parse('$baseUrl/api/meeting/start');
    return _postJson(url, {
      'monitor': monitor,
      'fps': fps,
      'allow_lightweight_mode': allowLightweightMode,
    });
  }

  Future<Map<String, dynamic>> stopMeeting() async {
    final url = Uri.parse('$baseUrl/api/meeting/stop');
    return _postJson(url, {});
  }

  Future<Map<String, dynamic>> setMeetingMicMuted(bool muted) async {
    final url = Uri.parse('$baseUrl/api/meeting/mute');
    return _postJson(url, {'muted': muted});
  }

  Future<Map<String, dynamic>> getMeetingStatus() async {
    return _getJson(
      '/api/meeting/status',
      timeout: const Duration(seconds: 3),
      fallback: {
        'state': 'idle',
        'session_id': null,
        'uptime_seconds': 0.0,
        'frames_processed': 0,
        'events_detected': 0,
        'steps_count': 0,
      },
    );
  }

  Future<Map<String, dynamic>> summarizeMeeting({
    String? sessionId,
    List<Map<String, String>>? customFields,
  }) async {
    final url = Uri.parse('$baseUrl/api/meeting/summarize');
    final payload = <String, dynamic>{'session_id': sessionId};
    if (customFields != null && customFields.isNotEmpty) {
      payload['custom_fields'] = customFields;
    }
    return _postJson(url, payload, timeout: const Duration(minutes: 5));
  }

  Future<Map<String, dynamic>> syncMeetingTasks({
    required String sessionId,
    required List<String> actionItems,
  }) async {
    final url = Uri.parse('$baseUrl/api/meeting/sync-tasks');
    return _postJson(url, {
      'session_id': sessionId,
      'action_items': actionItems,
    });
  }

  String getMeetingPdfUrl(String sessionId) {
    return '$baseUrl/api/meeting/pdf/$sessionId';
  }

  String getMeetingAssetUrl(String sessionId, String filename) {
    return '$baseUrl/api/meeting/asset/$sessionId/$filename';
  }

  Future<Map<String, dynamic>> exportMeetingToDrive({
    required String sessionId,
    String folderName = 'DeskMate Meetings',
  }) async {
    final url = Uri.parse('$baseUrl/api/meeting/export-drive');
    return _postJson(url, {'session_id': sessionId, 'folder_name': folderName});
  }

  Future<Map<String, dynamic>> sendMeetingEmail({
    required String sessionId,
    required String toEmail,
    String? subject,
    String? ccEmail,
    String? userName,
    String? designation,
    String? senderEmail,
    String? pdfName,
  }) async {
    final url = Uri.parse('$baseUrl/api/meeting/send-email');
    return _postJson(url, {
      'session_id': sessionId,
      'to_email': toEmail,
      if (subject != null && subject.trim().isNotEmpty)
        'subject': subject.trim(),
      if (ccEmail != null && ccEmail.trim().isNotEmpty)
        'cc_email': ccEmail.trim(),
      if (userName != null && userName.trim().isNotEmpty)
        'user_name': userName.trim(),
      if (designation != null && designation.trim().isNotEmpty)
        'designation': designation.trim(),
      if (senderEmail != null && senderEmail.trim().isNotEmpty)
        'sender_email': senderEmail.trim(),
      if (pdfName != null && pdfName.trim().isNotEmpty)
        'pdf_name': pdfName.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> getMeetingSessions() async {
    final res = await _getJson(
      ApiPaths.meetingSessions,
      timeout: const Duration(seconds: 4),
      fallback: {'status': 'ok', 'sessions': []},
    );
    final list = res['sessions'];
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>?> getMeetingSessionReport(
    String sessionId,
  ) async {
    final res = await _getJson(
      ApiPaths.meetingSession(sessionId),
      timeout: const Duration(seconds: 6),
      fallback: {'status': 'error'},
    );
    if (res['status'] == 'ok' && res['session'] is Map) {
      return Map<String, dynamic>.from(res['session'] as Map);
    }
    return null;
  }

  Future<bool> deleteMeetingSession(String sessionId) async {
    try {
      final url = Uri.parse('$baseUrl${ApiPaths.meetingSession(sessionId)}');
      final resp = await http.delete(url).timeout(const Duration(seconds: 5));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
