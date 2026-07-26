import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches the live list of available model ids for a configured provider,
/// so the Musify AI settings screen doesn't have to rely on a hardcoded
/// model id that may drift as providers add/retire models.
Future<List<String>> fetchProviderModels(
  String providerId,
  String apiKey,
) async {
  switch (providerId) {
    case 'groq':
      return _fetchOpenAiStyleModels(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        {'Authorization': 'Bearer $apiKey'},
      );
    case 'openrouter':
      return _fetchOpenAiStyleModels(
        Uri.parse('https://openrouter.ai/api/v1/models'),
        apiKey.isEmpty ? const {} : {'Authorization': 'Bearer $apiKey'},
      );
    case 'gemini':
      return _fetchGeminiModels(apiKey);
    default:
      return const [];
  }
}

Future<List<String>> _fetchOpenAiStyleModels(
  Uri uri,
  Map<String, String> headers,
) async {
  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 15));
  if (response.statusCode >= 400) {
    throw Exception('Erro ${response.statusCode} ao listar modelos.');
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final data = decoded['data'] as List? ?? [];
  final ids = data.map((m) => (m as Map)['id'].toString()).toList()..sort();
  return ids;
}

Future<List<String>> _fetchGeminiModels(String apiKey) async {
  final response = await http
      .get(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models'),
        headers: {'x-goog-api-key': apiKey},
      )
      .timeout(const Duration(seconds: 15));
  if (response.statusCode >= 400) {
    throw Exception('Erro ${response.statusCode} ao listar modelos.');
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final models = decoded['models'] as List? ?? [];
  final ids =
      models
          .map((m) => (m as Map)['name'].toString().replaceFirst('models/', ''))
          .toList()
        ..sort();
  return ids;
}
