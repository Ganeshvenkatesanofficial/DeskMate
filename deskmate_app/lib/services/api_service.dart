import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/gemini_service.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  // Send personal message, using Gemini if API key provided, otherwise local backend.
  Future<Map<String, dynamic>> sendPersonalMessage({
    required String message,
    String? conversationId,
    String? geminiApiKey,
    String? model,
  }) async {
    // If Gemini API key is provided, use Gemini service; otherwise fallback to local backend.
    if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
      final gemini = GeminiService(apiKey: geminiApiKey);
      final reply = await gemini.generateContent(message);
      return {'reply': reply, 'conversation_id': conversationId ?? ''};
    }
    final url = Uri.parse('$baseUrl/api/personal');
    final body = {
      'message': message,
      if (conversationId != null && conversationId.isNotEmpty)
        'conversation_id': conversationId,
      if (geminiApiKey != null && geminiApiKey.isNotEmpty)
        'api_key': geminiApiKey,
      if (model != null && model.isNotEmpty) 'model': model,
    };
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(
          data['detail'] ??
              'Request failed with status: ${response.statusCode}',
        );
      }
      return data;
    } catch (e) {
      throw Exception('Failed to connect to backend: $e');
    }
  }

  Future<void> resetChat(String conversationId) async {
    final url = Uri.parse('$baseUrl/api/reset/$conversationId');
    try {
      await http.post(url).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Ignore reset errors in production
    }
  }

  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'offline', 'local_llm': 'offline'};
    } catch (_) {
      return {'status': 'offline', 'local_llm': 'offline'};
    }
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

  // Send file-lens (code) message using local backend.
  Future<Map<String, dynamic>> sendMessage({
    required String message,
    String? conversationId,
    String? geminiApiKey,
    String? model,
  }) async {
    final url = Uri.parse('$baseUrl/api/chat');
    final body = {
      'message': message,
      if (conversationId != null && conversationId.isNotEmpty)
        'conversation_id': conversationId,
      if (geminiApiKey != null && geminiApiKey.isNotEmpty)
        'api_key': geminiApiKey,
      if (model != null && model.isNotEmpty) 'model': model,
    };
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(
          data['detail'] ??
              'Request failed with status: ${response.statusCode}',
        );
      }
      return data;
    } catch (e) {
      throw Exception('Failed to connect to backend: $e');
    }
  }

  Future<Map<String, dynamic>> checkPersonalHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/personal/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'offline'};
    } catch (_) {
      return {'status': 'offline'};
    }
  }
}
