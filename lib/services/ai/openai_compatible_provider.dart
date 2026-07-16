import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_provider.dart';

/// Base for providers that speak the OpenAI "chat/completions" wire format
/// with tool calling (Groq and OpenRouter both implement this exactly).
abstract class OpenAiCompatibleProvider implements AiProvider {
  Uri get endpoint;
  Map<String, String> get extraHeaders => const {};

  @override
  Future<AiCompletionResult> complete({
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required String apiKey,
    required String model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw AiProviderException('$id: nenhuma chave de API configurada.');
    }

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      for (final message in history) _encodeMessage(message),
    ];

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (tools.isNotEmpty)
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
      if (tools.isNotEmpty) 'tool_choice': 'auto',
    };

    http.Response response;
    try {
      response = await http
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              ...extraHeaders,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw AiProviderException('$id: falha de rede ($e)');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AiProviderException('$id: chave de API inválida ou sem acesso.');
    }
    if (response.statusCode == 429) {
      throw AiProviderException('$id: limite de requisições atingido.');
    }
    if (response.statusCode >= 400) {
      throw AiProviderException(
        '$id: erro ${response.statusCode} (${response.body})',
      );
    }

    late final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw AiProviderException('$id: resposta inválida ($e)');
    }

    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw AiProviderException('$id: resposta sem choices.');
    }

    final message = (choices.first as Map)['message'] as Map;
    final content = (message['content'] ?? '').toString();
    final rawToolCalls = message['tool_calls'] as List?;

    final toolCalls = <AiToolCall>[];
    if (rawToolCalls != null) {
      for (final raw in rawToolCalls) {
        final function = (raw as Map)['function'] as Map;
        Map<String, dynamic> arguments = {};
        try {
          final rawArgs = function['arguments'];
          if (rawArgs is String && rawArgs.trim().isNotEmpty) {
            arguments = jsonDecode(rawArgs) as Map<String, dynamic>;
          }
        } catch (_) {
          // Malformed arguments from the model; tool dispatcher will see {}.
        }
        toolCalls.add(
          AiToolCall(
            id: raw['id'].toString(),
            name: function['name'].toString(),
            arguments: arguments,
          ),
        );
      }
    }

    return AiCompletionResult(content: content, toolCalls: toolCalls);
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
