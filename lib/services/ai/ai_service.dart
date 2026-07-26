import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:musify/main.dart' show logger;
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_prompt.dart';
import 'package:musify/services/ai/ai_provider.dart';
import 'package:musify/services/ai/ai_tools.dart';
import 'package:musify/services/ai/gemini_provider.dart';
import 'package:musify/services/ai/groq_provider.dart';
import 'package:musify/services/ai/openrouter_provider.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/ai/ai_action_card.dart' show pickPrimaryCard;

/// How much prior conversation is resent, in characters rather than turns: a
/// turn that pulled a 200-song playlist into its tool results is worth several
/// short ones. Cheap to compute and good enough without a tokenizer.
const _historyCharBudget = 12000;
const _historyTurnCap = 16;

/// Tool rounds per turn. Six is enough for "search a few genres, then build a
/// playlist" and low enough that a confused model does not spend a minute.
const _maxToolRounds = 6;

/// Retries of the *same* request, kept separate from key/provider rotation so
/// a rate limit does not burn through the user's keys.
const _maxSameRequestRetries = 2;

/// Tool-call markup that some models leak into prose.
final _leakedToolMarkup = RegExp(
  r'<\|?(?:tool_call|function_call)[^>]*>[\s\S]*?<\/?\|?(?:tool_call|function_call)[^>]*>|'
  r'<function=[^>]*>[\s\S]*?<\/function>|'
  r'<parameter[^>]*>[\s\S]*?<\/parameter>',
  caseSensitive: false,
);

/// The outcome of a turn, from the caller's point of view.
enum AiTurnOutcome { completed, busy, notConfigured }

/// Orchestrates one Musify AI turn: builds the prompt, walks the configured
/// providers until one answers, runs whatever tools the model asks for, and
/// keeps a single chat message updated in place while it happens.
class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  final Map<String, AiProvider> _providers = {
    'groq': GroqProvider(),
    'gemini': GeminiProvider(),
    'openrouter': OpenRouterProvider(),
  };

  final _store = AiChatStore.instance;

  /// One running turn per chat. A second send while one is in flight is
  /// rejected rather than queued: two turns writing to the same chat would
  /// interleave their tool calls.
  final Map<String, AiCancellationToken> _running = {};

  bool isRunning(String chatId) => _running.containsKey(chatId);

  /// Stops the running turn for [chatId]. Not a failure: the message keeps
  /// whatever text it had and is marked as stopped.
  void stopTurn(String chatId) => _running[chatId]?.cancel();

  Future<AiTurnOutcome> sendMessage(
    String chatId,
    String userText, {
    Map<String, dynamic>? attachment,
  }) async {
    if (_running.containsKey(chatId)) return AiTurnOutcome.busy;

    final token = AiCancellationToken();
    _running[chatId] = token;

    try {
      return await _runTurn(chatId, userText, attachment, token);
    } finally {
      _running.remove(chatId);
      await _store.flush(chatId);
    }
  }

  Future<AiTurnOutcome> _runTurn(
    String chatId,
    String userText,
    Map<String, dynamic>? attachment,
    AiCancellationToken token,
  ) async {
    final isFirstMessage = _store.getMessages(chatId).isEmpty;

    await _store.appendMessage(chatId, {
      'v': aiMessageSchemaVersion,
      'id': 'msg_${DateTime.now().microsecondsSinceEpoch}',
      'role': 'user',
      'content': userText,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      if (attachment != null) 'attachment': attachment,
    });

    if (isFirstMessage) {
      unawaited(_store.maybeAutoNameChat(chatId, userText));
    }

    final messageId = await _store.appendAssistantPlaceholder(chatId);
    final history = _recentHistory(chatId);
    final systemPrompt = buildAiSystemPrompt();

    final turn = _TurnState(
      chatId: chatId,
      messageId: messageId,
      store: _store,
    );

    String? lastError;
    var configured = false;

    for (final providerId in aiProviderOrder.value) {
      final provider = _providers[providerId];
      final config = aiProviders.value[providerId];
      if (provider == null || config == null) continue;

      final apiKeys = (config['apiKeys'] as List?)?.cast<String>() ?? const [];
      final model = (config['model'] ?? '').toString();
      if (apiKeys.isEmpty || model.isEmpty) continue;
      configured = true;

      for (final apiKey in apiKeys) {
        if (token.isCancelled) {
          await turn.finishStopped();
          return AiTurnOutcome.completed;
        }

        try {
          await _runProviderTurn(
            turn: turn,
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: history,
            token: token,
          );
          return AiTurnOutcome.completed;
        } on AiCancelledException {
          await turn.finishStopped();
          return AiTurnOutcome.completed;
        } on AiProviderException catch (e) {
          logger.log('Musify AI provider ${provider.id} failed: ${e.message}');
          lastError = e.message;

          // Our payload is wrong, not their key. Another provider would reject
          // it identically, so stop instead of burning the whole rotation.
          if (e.kind == AiFailureKind.badRequest) {
            await turn.finishFailed();
            return AiTurnOutcome.completed;
          }

          // A side effect already landed this turn. Replaying it elsewhere
          // would queue the same song twice or create the playlist again.
          if (turn.hasSideEffects) {
            await turn.finishIncomplete();
            return AiTurnOutcome.completed;
          }

          turn.reset();
        } catch (e, stackTrace) {
          logger.log(
            'Musify AI provider ${provider.id} crashed',
            error: e,
            stackTrace: stackTrace,
          );
          lastError = e.toString();
          if (turn.hasSideEffects) {
            await turn.finishIncomplete();
            return AiTurnOutcome.completed;
          }
          turn.reset();
        }
      }
    }

    if (lastError != null) logger.log('Musify AI turn failed: $lastError');

    await turn.finishFailed(
      text: configured
          ? 'Não consegui responder agora. Dá uma olhada nas chaves e modelos '
                'em Configurações > ${aiName.value}.'
          : 'Configure ao menos uma chave de IA em Configurações > '
                '${aiName.value} para eu poder ajudar.',
    );

    return configured ? AiTurnOutcome.completed : AiTurnOutcome.notConfigured;
  }

  Future<void> _runProviderTurn({
    required _TurnState turn,
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<AiMessage> history,
    required AiCancellationToken token,
  }) async {
    var conversation = List<AiMessage>.from(history);

    for (var round = 0; round < _maxToolRounds; round++) {
      if (token.isCancelled) throw const AiCancelledException();

      final result = await _streamOnce(
        turn: turn,
        provider: provider,
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt,
        history: conversation,
        tools: _enabledToolSpecs(),
        token: token,
      );

      if (result.toolCalls.isEmpty) {
        await turn.finishDone();
        return;
      }

      final assistantMessage = AiMessage(
        role: AiRole.assistant,
        content: result.text,
        toolCalls: result.toolCalls,
      );

      final toolMessages = <AiMessage>[];
      final roundRecord = <String, dynamic>{
        'assistantContent': result.text,
        'calls': [
          for (final call in result.toolCalls)
            {'id': call.id, 'name': call.name, 'arguments': call.arguments},
        ],
        'results': <Map<String, dynamic>>[],
      };

      for (final call in result.toolCalls) {
        if (token.isCancelled) throw const AiCancelledException();

        final registration = aiToolRegistry[call.name];
        await turn.setStep(
          registration?.stepLabel ?? 'Trabalhando nisso…',
          stepKey: call.name,
        );
        if (registration?.sideEffecting ?? false) turn.markSideEffect();

        final toolResult = await executeToolSafely(
          call.name,
          call.arguments,
          argumentsMalformed: call.argumentsMalformed,
        );

        if (toolResult.actionCard != null) {
          turn.addCard(toolResult.actionCard!);
        }

        (roundRecord['results'] as List).add({
          'id': call.id,
          'name': call.name,
          'ok': !toolResultFailed(toolResult),
          'result': toolResult.result,
        });

        toolMessages.add(
          AiMessage(
            role: AiRole.tool,
            content: encodeToolResult(call.name, toolResult.result),
            toolCallId: call.id,
            toolName: call.name,
          ),
        );
      }

      turn.addRound(roundRecord);
      await turn.setStep('Escrevendo a resposta…');

      conversation = [...conversation, assistantMessage, ...toolMessages];
    }

    // Round cap reached. Ask once more with no tools available, so the user
    // gets a real sentence about what happened instead of a dead end.
    if (token.isCancelled) throw const AiCancelledException();

    try {
      final closing = await _streamOnce(
        turn: turn,
        provider: provider,
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt,
        history: conversation,
        tools: const [],
        token: token,
      );
      await turn.finishIncomplete(
        text: closing.text.isNotEmpty ? closing.text : null,
      );
    } on AiCancelledException {
      rethrow;
    } catch (_) {
      await turn.finishIncomplete();
    }
  }

  /// Runs one model call, streaming its text into the chat message.
  Future<_RoundResult> _streamOnce({
    required _TurnState turn,
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<AiMessage> history,
    required List<AiToolSpec> tools,
    required AiCancellationToken token,
  }) async {
    var attempt = 0;

    while (true) {
      final buffer = StringBuffer();
      final toolCalls = <AiToolCall>[];

      try {
        final stream = provider.run(
          systemPrompt: systemPrompt,
          history: history,
          tools: tools,
          apiKey: apiKey,
          model: model,
          token: token,
        );

        await for (final chunk in stream) {
          switch (chunk) {
            case AiTextDelta(:final text):
              buffer.write(text);
              await turn.streamText(buffer.toString());
            case AiToolCallsChunk(:final calls):
              toolCalls.addAll(calls);
            case AiTurnEnd():
              break;
          }
        }

        return _RoundResult(text: buffer.toString(), toolCalls: toolCalls);
      } on AiProviderException catch (e) {
        // Retrying the identical request is worth it for a rate limit or a
        // blip, and costs nothing from the key budget. Anything else is for
        // the caller to rotate on.
        if (!e.isTransient || attempt >= _maxSameRequestRetries) rethrow;

        // Text already shown to the user would be duplicated by a retry.
        if (buffer.isNotEmpty) rethrow;

        attempt++;
        final backoff =
            e.retryAfter ??
            Duration(
              milliseconds:
                  min(4000, 500 * (1 << (attempt - 1))) + Random().nextInt(250),
            );
        await turn.setStep('Tentando de novo…');
        await Future.any([Future<void>.delayed(backoff), token.whenCancelled]);
        if (token.isCancelled) throw const AiCancelledException();
      }
    }
  }

  List<AiToolSpec> _enabledToolSpecs() {
    return [
      for (final registration in aiToolRegistry.values)
        if (aiToolsEnabled.value[registration.spec.name] != false)
          registration.spec,
    ];
  }

  /// Rebuilds the wire history from stored turns, newest-first under a
  /// character budget, then flips it back to chronological order.
  ///
  /// Turns are expanded atomically: an assistant message carrying tool calls
  /// always travels with its tool replies. Slicing between them is what used
  /// to make OpenAI-compatible endpoints reject the whole request.
  List<AiMessage> _recentHistory(String chatId) {
    final stored = _store.getMessages(chatId);
    final selected = <List<AiMessage>>[];
    var budget = _historyCharBudget;

    for (var i = stored.length - 1; i >= 0; i--) {
      if (selected.length >= _historyTurnCap) break;

      final expanded = _expandStoredMessage(stored[i]);
      if (expanded.isEmpty) continue;

      final cost = expanded.fold<int>(
        0,
        (sum, message) => sum + message.content.length + 24,
      );
      if (selected.isNotEmpty && cost > budget) break;

      selected.add(expanded);
      budget -= cost;
    }

    return [for (final group in selected.reversed) ...group];
  }

  List<AiMessage> _expandStoredMessage(Map message) {
    final role = message['role'];

    if (role == 'user') {
      final attachment = message['attachment'] as Map?;
      var content = (message['content'] ?? '').toString();
      if (attachment != null) {
        content = '${_describeAttachment(attachment)}\n$content'.trim();
      }
      if (content.isEmpty) return const [];
      return [AiMessage(role: AiRole.user, content: content)];
    }

    if (role != 'assistant') return const [];

    // A turn that failed or was interrupted stays in the chat for the user but
    // is never replayed to the model: it would only teach it to repeat a
    // half-finished action.
    final status = message['status']?.toString();
    if (status == 'failed' ||
        status == 'incomplete' ||
        status == 'stopped' ||
        status == 'working' ||
        status == 'streaming' ||
        message['isError'] == true) {
      return const [];
    }

    final content = (message['content'] ?? '').toString();
    final rounds = (message['rounds'] as List?) ?? const [];

    // Migrated v1 turns have no rounds, because raw tool results were never
    // stored. Replaying the assistant text alone is honest; reconstructing
    // tool calls without their results is what produced contradictions.
    if (rounds.isEmpty) {
      if (content.isEmpty) return const [];
      return [AiMessage(role: AiRole.assistant, content: content)];
    }

    final expanded = <AiMessage>[];
    for (final rawRound in rounds) {
      final round = Map<String, dynamic>.from(rawRound as Map);
      final calls = (round['calls'] as List?) ?? const [];
      final results = (round['results'] as List?) ?? const [];
      if (calls.isEmpty) continue;

      final toolCalls = [
        for (final rawCall in calls)
          AiToolCall(
            id: rawCall['id'].toString(),
            name: rawCall['name'].toString(),
            arguments: Map<String, dynamic>.from(
              rawCall['arguments'] as Map? ?? const {},
            ),
          ),
      ];

      expanded.add(
        AiMessage(
          role: AiRole.assistant,
          content: (round['assistantContent'] ?? '').toString(),
          toolCalls: toolCalls,
        ),
      );

      for (final call in toolCalls) {
        final match = results.firstWhere(
          (result) => result['id'] == call.id,
          orElse: () => const <String, dynamic>{},
        );
        expanded.add(
          AiMessage(
            role: AiRole.tool,
            content: jsonEncode((match as Map)['result'] ?? const {}),
            toolCallId: call.id,
            toolName: call.name,
          ),
        );
      }
    }

    if (content.isNotEmpty) {
      expanded.add(AiMessage(role: AiRole.assistant, content: content));
    }

    return expanded;
  }

  /// Turns a user-picked attachment (from the "+" picker) into a grounded,
  /// machine-readable reference the model can quote back verbatim in a tool
  /// call instead of having to search for the item again.
  String _describeAttachment(Map attachment) {
    final type = attachment['itemType'];
    final item = Map<String, dynamic>.from(attachment['item'] as Map? ?? {});
    return '[Attached $type: ${jsonEncode(item)}]';
  }
}

class _RoundResult {
  const _RoundResult({required this.text, required this.toolCalls});

  final String text;
  final List<AiToolCall> toolCalls;
}

/// Accumulates one turn and keeps its single chat message in sync.
class _TurnState {
  _TurnState({
    required this.chatId,
    required this.messageId,
    required this.store,
  });

  final String chatId;
  final String messageId;
  final AiChatStore store;

  final List<Map<String, dynamic>> _cards = [];
  final List<Map<String, dynamic>> _rounds = [];
  String _text = '';
  bool hasSideEffects = false;

  void markSideEffect() => hasSideEffects = true;
  void addCard(Map<String, dynamic> card) => _cards.add(card);
  void addRound(Map<String, dynamic> round) => _rounds.add(round);

  /// Drops everything the failed provider produced so the next one starts
  /// clean. Only ever called when no side effect landed.
  void reset() {
    _cards.clear();
    _rounds.clear();
    _text = '';
  }

  Future<void> streamText(String text) async {
    _text = text;
    await store.updateMessage(chatId, messageId, {
      'content': _sanitize(text),
      'status': 'streaming',
      'stepLabel': null,
      'stepKey': null,
    });
  }

  Future<void> setStep(String label, {String? stepKey}) async {
    await store.updateMessage(chatId, messageId, {
      'status': 'working',
      'stepLabel': label,
      if (stepKey != null) 'stepKey': stepKey,
    });
  }

  Future<void> finishDone() => _finish('done');

  Future<void> finishIncomplete({String? text}) =>
      _finish('incomplete', text: text);

  Future<void> finishStopped() => _finish('stopped');

  Future<void> finishFailed({String? text}) => _finish('failed', text: text);

  Future<void> _finish(String status, {String? text}) async {
    if (text != null) _text = text;

    final content = _sanitize(_text);
    final card = pickPrimaryCard(_cards);

    await store.updateMessage(chatId, messageId, {
      'content': content.isNotEmpty ? content : _fallbackText(status),
      'status': status,
      'stepLabel': null,
      'stepKey': null,
      'rounds': _rounds,
      if (card != null) 'actionCard': card,
    });
    await store.flush(chatId);
  }

  String _fallbackText(String status) {
    switch (status) {
      case 'stopped':
        return '';
      case 'incomplete':
        return 'Fiz o que deu, mas não consegui terminar essa. '
            'Quer tentar de outro jeito?';
      case 'failed':
        return 'Não consegui fazer isso agora.';
      default:
        return 'Pronto.';
    }
  }

  String _sanitize(String text) => text.replaceAll(_leakedToolMarkup, '').trim();
}
