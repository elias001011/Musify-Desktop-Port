import 'package:musify/services/ai/openai_compatible_provider.dart';

class GroqProvider extends OpenAiCompatibleProvider {
  @override
  String get id => 'groq';

  @override
  Uri get endpoint =>
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');
}
