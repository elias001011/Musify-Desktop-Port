import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_provider.dart';

/// Talks to Google's Gemini "Interactions" API
/// (https://generativelanguage.googleapis.com/v1beta/interactions), which
/// replaced the older generateContent endpoint. Musify AI calls it in
/// stateless mode (full history resent every turn, no
/// previous_interaction_id) so it slots into the same provider-agnostic
/// fallback chain as Groq/OpenRouter. The function_call/function_result
/// item shape below matches Google's documented example as of 2026-07-16;
/// if Google adjusts it, this provider fails closed (AiProviderException)
/// and the orchestrator falls back to the next configured provider rather
/// than crashing the chat.
class GeminiProvider implements AiProvider {
  @override
  String get id => 'gemini';

  // Kept on the non-streaming path deliberately. This endpoint's shape is
  // reverse-engineered, so adding SSE parsing on top would double the surface
  // that breaks when Google changes it.
  @override
  bool get streams => false;

  @override
  Stream<AiChunk> run({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
    AiCancellationToken? token,
  }) async* {
    final result = await _complete(
      systemPrompt: systemPrompt,
      history: history,
      tools: tools,
      apiKey: apiKey,
      model: model,
    );

    if (token?.isCancelled ?? false) throw const AiCancelledException();

    if (result.content.isNotEmpty) yield AiTextDelta(result.content);
    if (result.toolCalls.isNotEmpty) yield AiToolCallsChunk(result.toolCalls);
    yield AiTurnEnd(
      finishReason: result.toolCalls.isNotEmpty ? 'tool_calls' : 'stop',
    );
  }

  Future<_GeminiResult> _complete({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw AiProviderException(
        'gemini: nenhuma chave de API configurada.',
        kind: AiFailureKind.auth,
      );
    }

    final input = <Map<String, dynamic>>[];
    for (final message in history) {
      switch (message.role) {
        case AiRole.system:
          continue;
        case AiRole.user:
          input.add({
            'role': 'user',
            'parts': [
              {'text': message.content},
            ],
          });
        case AiRole.assistant:
          if (message.toolCalls.isNotEmpty) {
            for (final call in message.toolCalls) {
              input.add({
                'type': 'function_call',
                'id': call.id,
                'name': call.name,
                'arguments': call.arguments,
              });
            }
          } else {
            input.add({
              'role': 'model',
              'parts': [
                {'text': message.content},
              ],
            });
          }
        case AiRole.tool:
          input.add({
            'type': 'function_result',
            'name': message.toolName,
            'call_id': message.toolCallId,
            'result': [
              {'type': 'text', 'text': message.content},
            ],
          });
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'system_instruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'input': input,
      'store': false,
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            {
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parameters,
            },
        ],
    };

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/interactions',
            ),
            headers: {
              'x-goog-api-key': apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw AiProviderException(
        'gemini: falha de rede ($e)',
        kind: AiFailureKind.network,
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AiProviderException(
        'gemini: chave de API inválida ou sem acesso.',
        kind: AiFailureKind.auth,
      );
    }
    if (response.statusCode == 429) {
      throw AiProviderException(
        'gemini: limite de requisições atingido.',
        kind: AiFailureKind.rateLimit,
      );
    }
    if (response.statusCode >= 500) {
      throw AiProviderException(
        'gemini: erro ${response.statusCode} no provedor.',
        kind: AiFailureKind.server,
      );
    }
    if (response.statusCode >= 400) {
      throw AiProviderException(
        'gemini: erro ${response.statusCode} (${response.body})',
        kind: AiFailureKind.badRequest,
      );
    }

    late final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw AiProviderException(
        'gemini: resposta inválida ($e)',
        kind: AiFailureKind.badResponse,
      );
    }

    final toolCalls = <AiToolCall>[];
    final textBuffer = StringBuffer();

    final steps = decoded['steps'] as List?;
    if (steps != null) {
      for (final step in steps) {
        final stepMap = step as Map;
        if (stepMap['type'] == 'function_call') {
          toolCalls.add(
            AiToolCall(
              id: (stepMap['id'] ?? stepMap['name']).toString(),
              name: stepMap['name'].toString(),
              arguments: Map<String, dynamic>.from(
                stepMap['arguments'] as Map? ?? {},
              ),
            ),
          );
          continue;
        }
        final content = stepMap['content'] as List?;
        if (content != null) {
          for (final block in content) {
            final blockMap = block as Map;
            if (blockMap['type'] == 'text' && blockMap['text'] != null) {
              textBuffer.write(blockMap['text']);
            }
          }
        }
      }
    }

    final outputText = decoded['output_text']?.toString();
    final content = textBuffer.isNotEmpty
        ? textBuffer.toString()
        : (outputText ?? '');

    return _GeminiResult(content: content, toolCalls: toolCalls);
  }
}

class _GeminiResult {
  const _GeminiResult({required this.content, required this.toolCalls});

  final String content;
  final List<AiToolCall> toolCalls;
}
