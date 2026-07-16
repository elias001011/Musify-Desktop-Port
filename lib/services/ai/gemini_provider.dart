import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_provider.dart';

/// Talks to Google's Gemini "Interactions" API
/// (https://generativelanguage.googleapis.com/v1beta/interactions), which
/// replaced the older generateContent endpoint. Musify IA calls it in
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

  @override
  Future<AiCompletionResult> complete({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw AiProviderException('gemini: nenhuma chave de API configurada.');
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
      throw AiProviderException('gemini: falha de rede ($e)');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AiProviderException('gemini: chave de API inválida ou sem acesso.');
    }
    if (response.statusCode == 429) {
      throw AiProviderException('gemini: limite de requisições atingido.');
    }
    if (response.statusCode >= 400) {
      throw AiProviderException(
        'gemini: erro ${response.statusCode} (${response.body})',
      );
    }

    late final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw AiProviderException('gemini: resposta inválida ($e)');
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

    return AiCompletionResult(content: content, toolCalls: toolCalls);
  }
}
