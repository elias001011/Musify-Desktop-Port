import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_provider.dart';

/// Talks to Google's Gemini via the [Interactions
/// API](https://ai.google.dev/api/interactions-api) at
/// `POST /v1beta/interactions`.  Musify AI calls it in stateless mode (full
/// history resent every turn, no `previous_interaction_id`) so it slots into
/// the same provider-agnostic fallback chain as Groq/OpenRouter.
///
/// The body format follows the official Interactions API reference:
///
/// - `system_instruction` is a plain **string** (not the `{parts: …}` object
///   that the legacy `generateContent` endpoint used).
/// - The `input` array is kept homogeneous — every entry is a **Content**
///   object (`{role, parts}`).  Tool calls and results are embedded **inside**
///   `parts` as `functionCall` / `functionResponse` keys, never as bare steps
///   at the top level of the array.
/// - Tool results use `role: "function"` with a `functionResponse` part,
///   matching the Interactions API spec.
class GeminiProvider implements AiProvider {
  @override
  String get id => 'gemini';

  // Kept on the non-streaming path deliberately.  Adding SSE parsing on top
  // would double the surface that can drift from the API spec.
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

  // --------------------------------------------------------------------------
  // Input assembly
  // --------------------------------------------------------------------------

  /// Builds a homogeneous array of **Content** objects for the `input` field.
  ///
  /// Every item has the shape `{role, parts}`.  Tool calls use
  /// `functionCall` inside parts; tool results use `functionResponse` inside
  /// parts with `role: "function"`.
  List<Map<String, dynamic>> _buildInput(List<AiMessage> history) {
    final input = <Map<String, dynamic>>[];

    for (final message in history) {
      switch (message.role) {
        case AiRole.system:
          continue; // Goes into system_instruction, not input.

        case AiRole.user:
          input.add({
            'role': 'user',
            'parts': [{'text': message.content}],
          });

        case AiRole.assistant:
          final parts = <Map<String, dynamic>>[];
          if (message.content.isNotEmpty) {
            parts.add({'text': message.content});
          }
          for (final call in message.toolCalls) {
            parts.add({
              'functionCall': {
                'name': call.name,
                'args': call.arguments,
              },
            });
          }
          if (parts.isNotEmpty) {
            input.add({'role': 'model', 'parts': parts});
          }

        case AiRole.tool:
          // `message.content` is a JSON string from encodeToolResult().
          // Decode it so the Gemini API receives a proper object.
          Map<String, dynamic> decodedResponse;
          try {
            decodedResponse = jsonDecode(message.content) as Map<String, dynamic>;
          } catch (_) {
            decodedResponse = {'raw': message.content};
          }
          input.add({
            'role': 'function',
            'parts': [
              {
                'functionResponse': {
                  'name': message.toolName,
                  'response': decodedResponse,
                },
              },
            ],
          });
      }
    }

    // The API requires the first content role to be "user" or "function".
    // Drop leading model entries that can appear from migrated chats.
    while (input.isNotEmpty && input.first['role'] == 'model') {
      input.removeAt(0);
    }

    return input;
  }

  // --------------------------------------------------------------------------
  // Response parsing
  // --------------------------------------------------------------------------

  /// Parses the Interactions API response.
  ///
  /// The response contains a `steps` array.  Each step has a `type`:
  /// - `"function_call"`: the model wants to call a tool.
  /// - `"model_output"`: the model produced text.  The step's `content` field
  ///   is a Content object whose `parts` may contain text blocks.
  ///
  /// The `output_text` shorthand is also checked as a fallback for simple
  /// single-turn cases where `steps` may be omitted.
  (String, List<AiToolCall>) _parseSteps(Map<String, dynamic> decoded) {
    final toolCalls = <AiToolCall>[];
    final textBuffer = StringBuffer();
    var toolCallIndex = 0;

    final steps = decoded['steps'] as List?;
    if (steps != null) {
      for (final raw in steps) {
        final step = raw as Map;
        final type = step['type']?.toString();

        if (type == 'function_call') {
          final name = step['name']?.toString() ?? '';
          final id = step['id']?.toString() ?? '${name}_${toolCallIndex++}';
          toolCalls.add(
            AiToolCall(
              id: id,
              name: name,
              arguments: Map<String, dynamic>.from(
                step['arguments'] as Map? ?? {},
              ),
            ),
          );
          continue;
        }

        if (type == 'model_output') {
          final content = step['content'] as Map?;
          if (content == null) continue;
          final parts = content['parts'] as List? ?? [];
          for (final p in parts) {
            final pm = p as Map;
            final text = pm['text']?.toString();
            if (text != null && text.isNotEmpty) {
              textBuffer.write(text);
            }
          }
        }
      }
    }

    // Some responses include `output_text` as a convenience field when there
    // are no tool calls (single text-only turn).
    final outputText = decoded['output_text']?.toString();
    if (textBuffer.isEmpty && outputText != null) {
      textBuffer.write(outputText);
    }

    return (textBuffer.toString(), toolCalls);
  }

  // --------------------------------------------------------------------------
  // HTTP call
  // --------------------------------------------------------------------------

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

    final input = _buildInput(history);

    final body = <String, dynamic>{
      'model': model,
      if (systemPrompt.isNotEmpty) 'system_instruction': systemPrompt,
      'input': input,
      'store': false,
      'generation_config': {
        'max_output_tokens': 4096,
      },
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

    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/interactions',
    );

    http.Response response;
    try {
      response = await http
          .post(
            endpoint,
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
      final errorDetails = utf8.decode(response.bodyBytes);
      throw AiProviderException(
        'gemini: erro ${response.statusCode} ($errorDetails)',
        kind: AiFailureKind.badRequest,
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw AiProviderException(
        'gemini: resposta inválida ($e)',
        kind: AiFailureKind.badResponse,
      );
    }

    final (text, toolCalls) = _parseSteps(decoded);
    return _GeminiResult(content: text, toolCalls: toolCalls);
  }
}

class _GeminiResult {
  const _GeminiResult({required this.content, required this.toolCalls});
  final String content;
  final List<AiToolCall> toolCalls;
}
