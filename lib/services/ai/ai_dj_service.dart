import 'dart:async';
import 'dart:convert';

import 'package:musify/main.dart' show logger;
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_provider.dart';
import 'package:musify/services/ai/ai_tools.dart';
import 'package:musify/services/ai/gemini_provider.dart';
import 'package:musify/services/ai/groq_provider.dart';
import 'package:musify/services/ai/openrouter_provider.dart';
import 'package:musify/services/settings_manager.dart';

/// How many previous chat messages are resent as context on every turn.
/// Musify IA intentionally only remembers a short recent window, not the
/// full chat history, to keep requests small and fast.
const _historyWindowSize = 24;
const _maxToolIterationsPerTurn = 5;

/// Orchestrates a single Musify IA turn: builds the system prompt, tries
/// each configured provider in [aiProviderOrder] until one answers, runs
/// any tool calls the model asks for against [executeAiTool], and persists
/// every message (including tool actions) via [AiChatStore] so the chat UI
/// can render them.
class AiDjService {
  AiDjService._internal();
  static final AiDjService instance = AiDjService._internal();

  final Map<String, AiProvider> _providers = {
    'groq': GroqProvider(),
    'gemini': GeminiProvider(),
    'openrouter': OpenRouterProvider(),
  };

  final _store = AiChatStore.instance;

  Future<void> sendMessage(String chatId, String userText) async {
    final isFirstMessage = _store.getMessages(chatId).isEmpty;

    await _store.appendMessage(chatId, {
      'id': 'msg_${DateTime.now().microsecondsSinceEpoch}',
      'role': 'user',
      'content': userText,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    if (isFirstMessage) {
      unawaited(_store.maybeAutoNameChat(chatId, userText));
    }

    var history = _recentHistory(chatId);
    final systemPrompt = _buildSystemPrompt();

    String? lastError;
    for (final providerId in aiProviderOrder.value) {
      final provider = _providers[providerId];
      final config = aiProviders.value[providerId];
      if (provider == null || config == null) continue;

      final apiKey = config['apiKey'] ?? '';
      final model = config['model'] ?? '';
      if (apiKey.isEmpty || model.isEmpty) continue;

      try {
        await _runProviderTurn(
          chatId: chatId,
          provider: provider,
          apiKey: apiKey,
          model: model,
          systemPrompt: systemPrompt,
          history: history,
        );
        return;
      } on AiProviderException catch (e) {
        logger.log('Musify IA provider ${provider.id} failed', error: e);
        lastError = e.message;
        if (!e.retryable) break;
        history = _recentHistory(chatId);
      } catch (e, stackTrace) {
        logger.log(
          'Musify IA provider ${provider.id} crashed',
          error: e,
          stackTrace: stackTrace,
        );
        lastError = e.toString();
      }
    }

    await _store.appendMessage(chatId, {
      'id': 'msg_${DateTime.now().microsecondsSinceEpoch}',
      'role': 'assistant',
      'content': lastError == null
          ? 'Nenhum provedor de IA está configurado. Configure ao menos '
                'uma chave em Configurações > ${aiName.value}.'
          : 'Não consegui responder agora (${lastError}). Verifique as '
                'chaves/modelos configurados em Configurações > '
                '${aiName.value}.',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'isError': true,
    });
  }

  Future<void> _runProviderTurn({
    required String chatId,
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<AiMessage> history,
  }) async {
    var iterations = 0;
    var currentHistory = history;

    while (true) {
      final result = await provider.complete(
        systemPrompt: systemPrompt,
        history: currentHistory,
        tools: aiToolSpecs,
        apiKey: apiKey,
        model: model,
      );

      if (result.toolCalls.isEmpty) {
        await _store.appendMessage(chatId, {
          'id': 'msg_${DateTime.now().microsecondsSinceEpoch}',
          'role': 'assistant',
          'content': result.content,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'provider': provider.id,
        });
        return;
      }

      iterations++;
      if (iterations > _maxToolIterationsPerTurn) {
        await _store.appendMessage(chatId, {
          'id': 'msg_${DateTime.now().microsecondsSinceEpoch}',
          'role': 'assistant',
          'content': result.content.isNotEmpty
              ? result.content
              : 'Não consegui terminar essa ação (muitas etapas).',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'provider': provider.id,
        });
        return;
      }

      final assistantMessage = AiMessage(
        role: AiRole.assistant,
        content: result.content,
        toolCalls: result.toolCalls,
      );

      Map<String, dynamic>? firstActionCard;
      final toolResultMessages = <AiMessage>[];

      for (final call in result.toolCalls) {
        final toolResult = await executeAiTool(call.name, call.arguments);
        firstActionCard ??= toolResult.actionCard;
        toolResultMessages.add(
          AiMessage(
            role: AiRole.tool,
            content: jsonEncode(toolResult.result),
            toolCallId: call.id,
            toolName: call.name,
          ),
        );
      }

      await _store.appendMessage(chatId, {
        'id': 'msg_${DateTime.now().microsecondsSinceEpoch}',
        'role': 'assistant',
        'content': result.content,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'provider': provider.id,
        'toolCalls': [
          for (final call in result.toolCalls)
            {'id': call.id, 'name': call.name, 'arguments': call.arguments},
        ],
        if (firstActionCard != null) 'actionCard': firstActionCard,
      });

      currentHistory = [
        ...currentHistory,
        assistantMessage,
        ...toolResultMessages,
      ];
    }
  }

  List<AiMessage> _recentHistory(String chatId) {
    final stored = _store.getMessages(chatId);
    final windowed = stored.length > _historyWindowSize
        ? stored.sublist(stored.length - _historyWindowSize)
        : stored;

    return [for (final message in windowed) ..._expandStoredMessage(message)];
  }

  List<AiMessage> _expandStoredMessage(Map message) {
    final role = message['role'];
    if (role == 'user') {
      return [
        AiMessage(
          role: AiRole.user,
          content: (message['content'] ?? '').toString(),
        ),
      ];
    }

    if (role == 'assistant') {
      final rawCalls = message['toolCalls'] as List?;
      if (rawCalls == null || rawCalls.isEmpty) {
        return [
          AiMessage(
            role: AiRole.assistant,
            content: (message['content'] ?? '').toString(),
          ),
        ];
      }

      final toolCalls = rawCalls
          .map(
            (c) => AiToolCall(
              id: c['id'].toString(),
              name: c['name'].toString(),
              arguments: Map<String, dynamic>.from(
                c['arguments'] as Map? ?? {},
              ),
            ),
          )
          .toList();

      // The tool results for this assistant turn were persisted separately
      // as the very next entries would be if we stored them individually;
      // here they're reconstructed on the fly since only the action card
      // (not raw tool JSON) is kept for display purposes.
      return [
        AiMessage(
          role: AiRole.assistant,
          content: (message['content'] ?? '').toString(),
          toolCalls: toolCalls,
        ),
        for (final call in toolCalls)
          AiMessage(
            role: AiRole.tool,
            content: jsonEncode(message['actionCard'] ?? {}),
            toolCallId: call.id,
            toolName: call.name,
          ),
      ];
    }

    return const [];
  }

  String _buildSystemPrompt() {
    return '''
You are ${aiName.value}, the built-in AI DJ assistant inside the Musify music player app. You are an experimental feature.

Always reply in the same language the user's most recent message is written in.

You can hold a conversation about music, but your real value is taking action inside the app through tools. Rules:
- Never invent or guess a song/playlist/artist id or url. Always call the `search` tool first to find the real item, then act on the exact result you got back.
- Before answering questions like "what's in my playlist X" or acting on "my library", call `get_library_index` and/or `get_library_item` to see what actually exists - never assume.
- When the user asks to build a playlist "for friday", "for a workout", based on a mood/genre/feeling, or anything without an explicit existing source: search for a handful of fitting songs yourself (multiple `search` calls with different queries as needed) and then call `create_playlist` with those songs. Do not ask the user to search themselves - the app's search is your tool, not theirs.
- When creating a playlist, if the user did not explicitly say to save/persist it, call `create_playlist` with temporary=true. Only pass temporary=false when the user clearly asked to save it permanently.
- When creating or renaming a playlist, if you already have a good song/album/artist image from a `search` result, pass it as the `image` (or `newImage`) argument so the playlist doesn't end up without a cover.
- For "play what's similar to what's playing", "add to queue based on what's playing now", etc., use `get_library_index` to see `nowPlaying`, then `search` for similar songs.
- Keep replies short and conversational; the UI already shows a card for whatever action you took, so do not describe the raw data back to the user in detail.
''';
  }
}
