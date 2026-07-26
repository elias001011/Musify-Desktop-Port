import 'dart:convert';

import 'package:http/http.dart' as http;

/// Model ids that cannot call tools, matched as substrings.
///
/// Providers list every model behind one endpoint: speech-to-text, text-to-
/// speech, embeddings, safety classifiers. Picking one of those left the
/// assistant able to chat and unable to do anything, with no error to explain
/// why, which reads as "the AI is broken".
const _nonToolModelMarkers = [
  'whisper',
  'tts',
  'embed',
  'guard',
  'orpheus',
  'moderation',
  'rerank',
  'vision-preview',
];

bool _looksToolCapable(String id) {
  final lower = id.toLowerCase();
  return !_nonToolModelMarkers.any(lower.contains);
}

/// Fetches the live list of available model ids for a configured provider,
/// so the Musify AI settings screen doesn't have to rely on a hardcoded
/// model id that may drift as providers add/retire models.
///
/// Only models that can actually call tools are returned.
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
        // OpenRouter states tool support per model, so use the real answer
        // rather than guessing from the id.
        requireDeclaredToolSupport: true,
      );
    case 'gemini':
      return _fetchGeminiModels(apiKey);
    default:
      return const [];
  }
}

Future<List<String>> _fetchOpenAiStyleModels(
  Uri uri,
  Map<String, String> headers, {
  bool requireDeclaredToolSupport = false,
}) async {
  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 15));
  if (response.statusCode >= 400) {
    throw Exception('Erro ${response.statusCode} ao listar modelos.');
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final data = decoded['data'] as List? ?? [];

  final ids = <String>[];
  for (final raw in data) {
    if (raw is! Map) continue;
    final id = raw['id']?.toString();
    if (id == null || id.isEmpty) continue;

    if (requireDeclaredToolSupport) {
      final parameters = raw['supported_parameters'];
      if (parameters is List && !parameters.contains('tools')) continue;
    }

    if (!_looksToolCapable(id)) continue;
    ids.add(id);
  }

  ids.sort();
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
          // The same endpoint also lists embedding and AQA models.
          .where((id) => id.startsWith('gemini') && _looksToolCapable(id))
          .toList()
        ..sort();
  return ids;
}
