/// Shared, provider-agnostic chat message/tool model used by every
/// AiProvider implementation and by AiService.
library;

import 'dart:async';

enum AiRole { system, user, assistant, tool }

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.argumentsMalformed = false,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// The model emitted arguments that could not be parsed as JSON. The call is
  /// still dispatched (with whatever defaults the normaliser can supply) but
  /// the tool result says so, which is what lets the model correct itself
  /// instead of silently acting on `{}`.
  final bool argumentsMalformed;
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

/// One piece of a provider response.
///
/// Every provider yields a stream of these, whether or not it actually streams
/// over the wire: a non-streaming provider emits one [AiTextDelta], one
/// [AiToolCallsChunk] and one [AiTurnEnd]. That keeps a single code path in the
/// orchestrator instead of branching on whether streaming is supported.
sealed class AiChunk {
  const AiChunk();
}

class AiTextDelta extends AiChunk {
  const AiTextDelta(this.text);

  final String text;
}

class AiToolCallsChunk extends AiChunk {
  const AiToolCallsChunk(this.calls);

  final List<AiToolCall> calls;
}

class AiTurnEnd extends AiChunk {
  const AiTurnEnd({this.finishReason});

  final String? finishReason;
}

/// Why a provider call failed, which decides what the orchestrator does next.
enum AiFailureKind {
  /// Bad or unauthorised key. Rotating to the next key can help; retrying the
  /// same request cannot.
  auth,

  /// Rate limited. Worth retrying the same request after a wait.
  rateLimit,

  /// Provider-side error (5xx). Worth retrying.
  server,

  /// Transport failure. Worth retrying.
  network,

  /// The provider answered, but not with something we can read.
  badResponse,

  /// The provider rejected our payload (4xx that is not auth or rate limit).
  /// Another key or provider would reject it the same way, so this aborts the
  /// turn rather than burning the whole rotation.
  badRequest,
}

class AiProviderException implements Exception {
  AiProviderException(this.message, {required this.kind, this.retryAfter});

  final String message;
  final AiFailureKind kind;

  /// Parsed from a `Retry-After` header when the provider sends one.
  final Duration? retryAfter;

  /// Retrying the identical request may succeed.
  bool get isTransient =>
      kind == AiFailureKind.rateLimit ||
      kind == AiFailureKind.server ||
      kind == AiFailureKind.network;

  @override
  String toString() => message;
}

/// Cooperative cancellation for a turn.
///
/// The user can leave a chat or hit stop mid-answer; providers watch this to
/// close their HTTP client, and the orchestrator checks it between rounds.
class AiCancellationToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Thrown internally when a turn is cancelled. Never surfaced as a failure.
class AiCancelledException implements Exception {
  const AiCancelledException();

  @override
  String toString() => 'cancelled';
}
