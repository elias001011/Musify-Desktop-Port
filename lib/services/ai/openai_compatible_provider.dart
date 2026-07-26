import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_provider.dart';

const _requestTimeout = Duration(seconds: 45);

/// Accumulates streamed `delta.tool_calls` fragments into whole tool calls.
///
/// OpenAI-compatible endpoints stream a tool call across many chunks: the first
/// carries `index`, `id` and `function.name`, and the rest carry slices of
/// `function.arguments` as raw string fragments that are only valid JSON once
/// concatenated. Nothing may be decoded until the stream finishes, which is why
/// this is a separate object rather than inline parsing.
class ToolCallAccumulator {
  final Map<int, _PartialToolCall> _partials = {};

  bool get isEmpty => _partials.isEmpty;

  void addDelta(List<dynamic> deltaToolCalls) {
    for (final raw in deltaToolCalls) {
      if (raw is! Map) continue;

      // `index` is what ties fragments together. Some providers omit it when
      // there is only one call in flight, so fall back to slot 0.
      final index = raw['index'] is int ? raw['index'] as int : 0;
      final partial = _partials.putIfAbsent(index, _PartialToolCall.new);

      final id = raw['id'];
      if (id != null && id.toString().isNotEmpty) {
        partial.id = id.toString();
      }

      final function = raw['function'];
      if (function is Map) {
        final name = function['name'];
        if (name != null && name.toString().isNotEmpty) {
          partial.name = name.toString();
        }
        final args = function['arguments'];
        if (args is String) {
          partial.arguments.write(args);
        }
      }
    }
  }

  List<AiToolCall> build() {
    final indices = _partials.keys.toList()..sort();
    final calls = <AiToolCall>[];

    for (final index in indices) {
      final partial = _partials[index]!;
      if (partial.name == null) continue;

      final rawArguments = partial.arguments.toString().trim();
      var arguments = <String, dynamic>{};
      var malformed = false;

      if (rawArguments.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawArguments);
          if (decoded is Map) {
            arguments = Map<String, dynamic>.from(decoded);
          } else {
            malformed = true;
          }
        } catch (_) {
          // Kept as malformed rather than silently becoming {}: the tool result
          // then tells the model its arguments were unreadable, and it retries
          // with valid ones instead of acting on empty defaults.
          malformed = true;
        }
      }

      calls.add(
        AiToolCall(
          id: partial.id ?? 'call_$index',
          name: partial.name!,
          arguments: arguments,
          argumentsMalformed: malformed,
        ),
      );
    }

    return calls;
  }
}

class _PartialToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

/// Base for providers that speak the OpenAI "chat/completions" wire format
/// with tool calling (Groq and OpenRouter both implement this exactly).
abstract class OpenAiCompatibleProvider implements AiProvider {
  Uri get endpoint;
  Map<String, String> get extraHeaders => const {};

  @override
  bool get streams => true;

  @override
  Stream<AiChunk> run({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
    AiCancellationToken? token,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw AiProviderException(
        '$id: nenhuma chave de API configurada.',
        kind: AiFailureKind.auth,
      );
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        for (final message in history) _encodeMessage(message),
      ],
      'stream': true,
      'temperature': 0.6,
      'max_tokens': 4096,
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final tool in tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
              },
            },
        ],
        'tool_choice': 'auto',
      },
    };

    final client = http.Client();
    // Closing the client is what actually aborts an in-flight response; the
    // stream below then ends and the orchestrator sees the cancellation.
    final cancelSubscription = token?.whenCancelled.then((_) => client.close());

    try {
      final request = http.Request('POST', endpoint)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          ...extraHeaders,
        })
        ..body = jsonEncode(body);

      http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(_requestTimeout);
      } on TimeoutException {
        throw AiProviderException(
          '$id: o provedor não respondeu a tempo.',
          kind: AiFailureKind.network,
        );
      } catch (e) {
        if (token?.isCancelled ?? false) throw const AiCancelledException();
        throw AiProviderException(
          '$id: falha de rede ($e)',
          kind: AiFailureKind.network,
        );
      }

      if (response.statusCode >= 400) {
        final errorBody = await response.stream.bytesToString();
        throw _errorFor(response.statusCode, response.headers, errorBody);
      }

      final accumulator = ToolCallAccumulator();
      String? finishReason;

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (token?.isCancelled ?? false) throw const AiCancelledException();

        // SSE framing: blank lines separate events, ':' lines are comments
        // (some providers send them as keep-alives).
        if (line.isEmpty || line.startsWith(':')) continue;
        if (!line.startsWith('data:')) continue;

        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;

        Map<String, dynamic> decoded;
        try {
          decoded = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;

        final choice = choices.first as Map;
        finishReason = choice['finish_reason']?.toString() ?? finishReason;

        final delta = choice['delta'];
        if (delta is! Map) continue;

        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          yield AiTextDelta(content);
        }

        final deltaToolCalls = delta['tool_calls'];
        if (deltaToolCalls is List) {
          accumulator.addDelta(deltaToolCalls);
        }
      }

      if (!accumulator.isEmpty) {
        final calls = accumulator.build();
        if (calls.isNotEmpty) yield AiToolCallsChunk(calls);
      }

      yield AiTurnEnd(finishReason: finishReason);
    } finally {
      // The cancel watcher never completes on a normal turn; ignoring it stops
      // a late close() error from surfacing as an unhandled async error.
      cancelSubscription?.ignore();
      client.close();
    }
  }

  AiProviderException _errorFor(
    int statusCode,
    Map<String, String> headers,
    String body,
  ) {
    if (statusCode == 401 || statusCode == 403) {
      return AiProviderException(
        '$id: chave de API inválida ou sem acesso.',
        kind: AiFailureKind.auth,
      );
    }
    if (statusCode == 429) {
      return AiProviderException(
        '$id: limite de requisições atingido.',
        kind: AiFailureKind.rateLimit,
        retryAfter: _retryAfter(headers),
      );
    }
    if (statusCode >= 500) {
      return AiProviderException(
        '$id: erro $statusCode no provedor.',
        kind: AiFailureKind.server,
        retryAfter: _retryAfter(headers),
      );
    }
    return AiProviderException(
      '$id: erro $statusCode ($body)',
      kind: AiFailureKind.badRequest,
    );
  }

  Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null) return null;
    // Anything longer than this is not worth blocking a turn on; the caller
    // rotates to the next key instead.
    return seconds > 30 ? null : Duration(seconds: seconds);
  }

  Map<String, dynamic> _encodeMessage(AiMessage message) {
    switch (message.role) {
      case AiRole.system:
        return {'role': 'system', 'content': message.content};
      case AiRole.user:
        return {'role': 'user', 'content': message.content};
      case AiRole.assistant:
        return {
          'role': 'assistant',
          if (message.content.isNotEmpty) 'content': message.content,
          if (message.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final call in message.toolCalls)
                {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': jsonEncode(call.arguments),
                  },
                },
            ],
        };
      case AiRole.tool:
        return {
          'role': 'tool',
          'tool_call_id': message.toolCallId,
          'name': message.toolName,
          'content': message.content,
        };
    }
  }
}
