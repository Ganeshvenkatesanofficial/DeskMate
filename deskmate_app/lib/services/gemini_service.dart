import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  /// Generates content using Gemini 2.5 Flash model.
  /// Returns the text response from the model.
  Future<String> generateContent(String prompt) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
    );
    final requestBody = jsonEncode({
      'systemInstruction': {
        'parts': [
          {
            'text':
                'You are a helpful, concise personal assistant. '
                'Keep your answers SHORT and factual. '
                'Do NOT add unnecessary explanations, descriptions, or speculation. '
                'Only state what you know for certain. '
                'If you are unsure or do not have access to information, say so honestly.',
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Gemini API error: ${response.body}');
    }
    final data = jsonDecode(response.body);
    // Extract the first text part from the response.
    try {
      final candidates = data['candidates'] as List;
      final content =
          candidates.first['content']['parts'].first['text'] as String;
      return content;
    } catch (_) {
      throw Exception('Unexpected Gemini response format');
    }
  }
}
