import 'package:musify/services/ai/ai_message.dart';

abstract class AiProvider {
  String get id;

  Future<AiCompletionResult> complete({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
  });
}
