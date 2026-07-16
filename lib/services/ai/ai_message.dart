/// Shared, provider-agnostic chat message/tool model used by every
/// AiProvider implementation and by AiDjService.
library;

enum AiRole { system, user, assistant, tool }

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class AiMessage {
  const AiMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  final AiRole role;
  final String content;

  /// Populated on assistant messages that requested tool execution.
  final List<AiToolCall> toolCalls;

  /// Populated on [AiRole.tool] messages: which call this responds to.
  final String? toolCallId;

  /// Populated on [AiRole.tool] messages: the tool that was executed.
  final String? toolName;
}

class AiToolSpec {
  const AiToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;

  /// JSON Schema object describing the tool's arguments.
  final Map<String, dynamic> parameters;
}

class AiCompletionResult {
  const AiCompletionResult({this.content = '', this.toolCalls = const []});

  final String content;
  final List<AiToolCall> toolCalls;
}

/// Thrown by providers on any failure. [retryable] tells the fallback
/// orchestrator whether trying the next configured provider makes sense
/// (network error, rate limit, invalid key, malformed response) as opposed
/// to a hard failure that would also affect other providers.
class AiProviderException implements Exception {
  AiProviderException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}
