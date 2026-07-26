import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Local persistence for Musify AI chat history.
///
/// Chat summaries (id/name/timestamps/preview) live in the `ai_chat_index`
/// box so the history list can render without loading every message body.
/// The actual messages for a chat are stored separately in
/// `ai_chat_messages`, keyed by chat id.
class AiChatStore {
  factory AiChatStore() => instance;

  AiChatStore._internal() : chats = ValueNotifier<List<Map>>(_readIndex());

  static final AiChatStore instance = AiChatStore._internal();

  final ValueNotifier<List<Map>> chats;
  final Map<String, ValueNotifier<List<Map>>> _messageNotifiers = {};

  Box get _indexBox => Hive.box('ai_chat_index');
  Box get _messagesBox => Hive.box('ai_chat_messages');

  /// Reactive message list for one chat; the chat page rebuilds from this
  /// whenever [appendMessage] adds to that chat.
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

  Future<void> appendMessage(
    String chatId,
    Map<String, dynamic> message,
  ) async {
    final messages = getMessages(chatId)..add(message);
    await _messagesBox.put(chatId, messages);
    messagesNotifier(chatId).value = messages;

    final index = chats.value.indexWhere((c) => c['id'] == chatId);
    if (index == -1) return;

    final updated = List<Map>.from(chats.value);
    final chat = Map<String, dynamic>.from(updated[index]);
    chat['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    if (message['role'] != 'tool') {
      final content = (message['content'] ?? '').toString();
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
    final title = trimmed.length > 40
        ? '${trimmed.substring(0, 40)}…'
        : trimmed;
    if (title.isEmpty) return;

    final updated = List<Map>.from(chats.value);
    updated[index] = {...updated[index], 'name': title};
    chats.value = updated;
    await _persistIndex();
  }

  Future<void> deleteChat(String chatId) async {
    chats.value = chats.value.where((c) => c['id'] != chatId).toList();
    await _persistIndex();
    await _messagesBox.delete(chatId);
    _messageNotifiers.remove(chatId);
  }
}
