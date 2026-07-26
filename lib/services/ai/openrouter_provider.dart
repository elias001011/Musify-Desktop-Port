import 'package:musify/services/ai/openai_compatible_provider.dart';

class OpenRouterProvider extends OpenAiCompatibleProvider {
  @override
  String get id => 'openrouter';

  @override
  Uri get endpoint =>
      Uri.parse('https://openrouter.ai/api/v1/chat/completions');

  @override
  Map<String, String> get extraHeaders => const {
    'HTTP-Referer': 'https://github.com/elias001011/Musify-Desktop-Port',
    'X-Title': 'Musify AI',
  };
}
