import 'package:musify/services/ai/ai_message.dart';

/// One LLM backend.
///
/// The interface is a stream even for providers that cannot stream, so the
/// orchestrator never has to ask whether streaming is available. Providers that
/// answer in one shot yield their whole reply as a single [AiTextDelta] plus an
/// [AiToolCallsChunk], then [AiTurnEnd].
abstract class AiProvider {
  String get id;

  /// Whether the final answer arrives token by token. The UI uses this only to
  /// pick between a typing caret and a spinner; behaviour does not depend on it.
  bool get streams => false;

  Stream<AiChunk> run({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
    AiCancellationToken? token,
  });
}
