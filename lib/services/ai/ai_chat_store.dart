import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Current persisted message schema.
///
/// v1 stored one assistant map per model round, so a single answer that used
/// three tools became four bubbles, most of them with empty content. v2 stores
/// one map per *turn* and mutates it in place while the turn runs.
const int aiMessageSchemaVersion = 2;

/// Statuses that mean the turn is no longer running.
const _terminalStatuses = {'done', 'incomplete', 'failed', 'stopped'};

/// Local persistence for Musify AI chat history.
///
/// Chat summaries (id/name/timestamps/preview) live in the `ai_chat_index`
/// box so the history list can render without loading every message body.
/// The actual messages for a chat are stored separately in
/// `ai_chat_messages`, keyed by chat id.
class AiChatStore {
  factory AiChatStore() => instance;

  AiChatStore._internal() : chats = ValueNotifier<List<Map>>(_readIndex()) {
    _migrateIfNeeded();
  }

  static final AiChatStore instance = AiChatStore._internal();

  final ValueNotifier<List<Map>> chats;
  final Map<String, ValueNotifier<List<Map>>> _messageNotifiers = {};

  /// Streaming would otherwise issue one box write per token, so writes are
  /// coalesced and then forced at every terminal status.
  final Map<String, Timer> _pendingWrites = {};
  static const _writeDebounce = Duration(milliseconds: 250);

  Box get _indexBox => Hive.box('ai_chat_index');
  Box get _messagesBox => Hive.box('ai_chat_messages');

  /// Reactive message list for one chat; the chat page rebuilds from this
  /// whenever [appendMessage] or [updateMessage] touches that chat.
  ValueNotifier<List<Map>> messagesNotifier(String chatId) {
    return _messageNotifiers.putIfAbsent(
      chatId,
      () => ValueNotifier<List<Map>>(getMessages(chatId)),
    );
  }

  static List<Map> _readIndex() {
    final raw = Hive.box(
      'ai_chat_index',
    ).get('chats', defaultValue: <dynamic>[]);
    final list = List<Map>.from(
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)),
    )..sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    return list;
  }

  Future<void> _persistIndex() async {
    await _indexBox.put('chats', chats.value);
  }

  Map<String, dynamic> createChat({String? name}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final chat = <String, dynamic>{
      'id': 'chat_$now',
      'name': name ?? 'Nova conversa',
      'createdAt': now,
      'updatedAt': now,
      'preview': '',
    };
    chats.value = [chat, ...chats.value];
    unawaited(_persistIndex());
    unawaited(_messagesBox.put(chat['id'], <Map>[]));
    return chat;
  }

  List<Map> getMessages(String chatId) {
    final raw = _messagesBox.get(chatId, defaultValue: <dynamic>[]);
    return List<Map>.from(
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  /// Reads one message from the live list, so a lookup during a streaming turn
  /// sees the same content the UI is showing.
  Map<String, dynamic>? getMessage(String chatId, String messageId) {
    for (final message in messagesNotifier(chatId).value) {
      if (message['id'] == messageId) {
        return Map<String, dynamic>.from(message);
      }
    }
    return null;
  }

  Future<void> appendMessage(
    String chatId,
    Map<String, dynamic> message,
  ) async {
    final messages = getMessagesFromNotifier(chatId).toList()..add(message);
    await _messagesBox.put(chatId, messages);
    messagesNotifier(chatId).value = messages;
    await _touchChat(chatId, message);
  }

  /// Creates the assistant message a turn will write into, and returns its id.
  ///
  /// The turn needs an id before the first token arrives, and this placeholder
  /// doubles as the typing indicator: it renders as a status line rather than
  /// as an empty bubble.
  Future<String> appendAssistantPlaceholder(
    String chatId, {
    String stepLabel = 'Pensando…',
  }) async {
    final now = DateTime.now();
    final id = 'msg_${now.microsecondsSinceEpoch}';
    await appendMessage(chatId, {
      'v': aiMessageSchemaVersion,
      'id': id,
      'role': 'assistant',
      'content': '',
      'status': 'working',
      'stepLabel': stepLabel,
      'createdAt': now.millisecondsSinceEpoch,
      'updatedAt': now.millisecondsSinceEpoch,
    });
    return id;
  }

  /// Shallow-merges [patch] into one message, notifying listeners immediately
  /// and writing to Hive on a debounce.
  ///
  /// A null value in [patch] removes the key, which is how the step label is
  /// cleared when a turn finishes.
  Future<void> updateMessage(
    String chatId,
    String messageId,
    Map<String, dynamic> patch,
  ) async {
    final messages = getMessagesFromNotifier(chatId).toList();
    final index = messages.indexWhere((m) => m['id'] == messageId);
    if (index == -1) return;

    final updated = Map<String, dynamic>.from(messages[index]);
    patch.forEach((key, value) {
      if (value == null) {
        updated.remove(key);
      } else {
        updated[key] = value;
      }
    });
    updated['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    messages[index] = updated;

    messagesNotifier(chatId).value = messages;

    if (_terminalStatuses.contains(updated['status'])) {
      _pendingWrites.remove(chatId)?.cancel();
      await _messagesBox.put(chatId, messages);
      await _touchChat(chatId, updated);
      return;
    }

    _pendingWrites[chatId]?.cancel();
    _pendingWrites[chatId] = Timer(_writeDebounce, () {
      _pendingWrites.remove(chatId);
      unawaited(_messagesBox.put(chatId, getMessagesFromNotifier(chatId)));
    });
  }

  /// The in-memory list, which during streaming is ahead of the box.
  List<Map> getMessagesFromNotifier(String chatId) =>
      messagesNotifier(chatId).value;

  /// Forces any debounced write for [chatId] out to disk.
  Future<void> flush(String chatId) async {
    _pendingWrites.remove(chatId)?.cancel();
    await _messagesBox.put(chatId, getMessagesFromNotifier(chatId));
  }

  Future<void> _touchChat(String chatId, Map<String, dynamic> message) async {
    final index = chats.value.indexWhere((c) => c['id'] == chatId);
    if (index == -1) return;

    final updated = List<Map>.from(chats.value);
    final chat = Map<String, dynamic>.from(updated[index]);
    chat['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    // Only real text updates the preview; an empty placeholder would otherwise
    // blank out the list entry the moment a turn starts.
    final content = (message['content'] ?? '').toString();
    if (content.isNotEmpty) {
      chat['preview'] = content.length > 80
          ? '${content.substring(0, 80)}…'
          : content;
    }

    updated[index] = chat;
    updated.sort(
      (a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int),
    );
    chats.value = updated;
    await _persistIndex();
  }

  Future<void> renameChat(String chatId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    final index = chats.value.indexWhere((c) => c['id'] == chatId);
    if (index == -1) return;

    final updated = List<Map>.from(chats.value);
    updated[index] = {...updated[index], 'name': trimmed};
    chats.value = updated;
    await _persistIndex();
  }

  /// Auto-names a chat from its first user message, unless it was already
  /// renamed by the user.
  Future<void> maybeAutoNameChat(String chatId, String firstUserMessage) async {
    final index = chats.value.indexWhere((c) => c['id'] == chatId);
    if (index == -1) return;
    if (chats.value[index]['name'] != 'Nova conversa') return;

    final trimmed = firstUserMessage.trim().replaceAll('\n', ' ');
    // Short on purpose: the chat page renders this in an app bar, where a
    // longer title can only ever be ellipsised.
    final title = trimmed.length > 28 ? '${trimmed.substring(0, 28)}…' : trimmed;
    if (title.isEmpty) return;

    final updated = List<Map>.from(chats.value);
    updated[index] = {...updated[index], 'name': title};
    chats.value = updated;
    await _persistIndex();
  }

  Future<void> deleteChat(String chatId) async {
    _pendingWrites.remove(chatId)?.cancel();
    chats.value = chats.value.where((c) => c['id'] != chatId).toList();
    await _persistIndex();
    await _messagesBox.delete(chatId);
    await _messagesBox.delete('${chatId}__v1');
    _messageNotifiers.remove(chatId);
  }

  /// Collapses v1 chats, where one answer was spread over several assistant
  /// maps, into one v2 message per turn.
  ///
  /// Raw tool results were never persisted in v1, so migrated turns keep an
  /// empty `rounds` list on purpose: replaying them would otherwise have to
  /// invent tool results, which is the exact bug v2 exists to remove.
  void _migrateIfNeeded() {
    try {
      final schema = _indexBox.get('schema', defaultValue: 1);
      if (schema is int && schema >= aiMessageSchemaVersion) return;

      for (final chat in chats.value) {
        final chatId = chat['id']?.toString();
        if (chatId == null) continue;

        final legacy = getMessages(chatId);
        if (legacy.isEmpty) continue;

        // Cheap insurance: a bad migration stays recoverable by hand.
        unawaited(_messagesBox.put('${chatId}__v1', legacy));
        unawaited(_messagesBox.put(chatId, _collapseLegacyMessages(legacy)));
        _messageNotifiers.remove(chatId);
      }

      unawaited(_indexBox.put('schema', aiMessageSchemaVersion));
    } catch (e) {
      // A corrupt legacy chat must not take the AI tab down on startup, and
      // retrying the same failing migration on every launch helps nobody.
      debugPrint('Musify AI: chat history migration failed ($e)');
      unawaited(_indexBox.put('schema', aiMessageSchemaVersion));
    }
  }

  List<Map> _collapseLegacyMessages(List<Map> legacy) {
    final result = <Map>[];
    var index = 0;

    while (index < legacy.length) {
      final message = Map<String, dynamic>.from(legacy[index]);

      if (message['role'] != 'assistant') {
        // v1 never actually persisted tool rows, but drop them defensively.
        if (message['role'] != 'tool') result.add(message);
        index++;
        continue;
      }

      // Absorb the whole run of assistant maps that belonged to one turn: in
      // v1 every round but the last carried toolCalls.
      var content = (message['content'] ?? '').toString();
      var actionCard = (message['actionCard'] as Map?)?.cast<String, dynamic>();
      final isError = message['isError'] == true;

      var cursor = index;
      while (cursor + 1 < legacy.length &&
          legacy[cursor]['role'] == 'assistant' &&
          (legacy[cursor]['toolCalls'] as List?)?.isNotEmpty == true &&
          legacy[cursor + 1]['role'] == 'assistant') {
        cursor++;
        final next = Map<String, dynamic>.from(legacy[cursor]);
        final nextContent = (next['content'] ?? '').toString();
        if (nextContent.isNotEmpty) content = nextContent;
        actionCard ??= (next['actionCard'] as Map?)?.cast<String, dynamic>();
      }

      final createdAt =
          message['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;

      result.add({
        'v': aiMessageSchemaVersion,
        'id': message['id'] ?? 'msg_${DateTime.now().microsecondsSinceEpoch}',
        'role': 'assistant',
        'content': content,
        'status': isError ? 'failed' : 'done',
        'createdAt': createdAt,
        'updatedAt': createdAt,
        'rounds': <Map<String, dynamic>>[],
        if (actionCard != null) 'actionCard': actionCard,
      });

      index = cursor + 1;
    }

    return result;
  }
}
