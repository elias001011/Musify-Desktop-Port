import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/services/ai/ai_service.dart';
import 'package:musify/services/ai/ai_voice_service.dart';
import 'package:musify/services/common_services.dart' show getRecommendedSongs;
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/ai/ai_attachment_picker.dart';
import 'package:musify/widgets/ai/ai_message_bubble.dart';
import 'package:musify/widgets/confirmation_dialog.dart';

/// Chips are shown by their short label and sent as the full prompt.
///
/// They used to be the whole sentence, which at 30-55 characters was clipped
/// mid-word by the horizontal list and read as broken UI.
typedef _Suggestion = ({String label, String prompt});

const _suggestionPool = <_Suggestion>[
  (
    label: 'Fila parecida',
    prompt: 'Adicione uma música na fila com base no que está tocando agora',
  ),
  (label: 'Playlist do dia', prompt: 'Monte uma playlist temporária para hoje'),
  (label: 'Minha biblioteca', prompt: 'O que tem na minha biblioteca?'),
  (label: 'Algo parecido', prompt: 'Toque algo parecido com o que está tocando'),
  (label: 'Meu gosto', prompt: 'O que você acha do meu gosto musical?'),
  (
    label: 'Baixar offline',
    prompt: 'Baixe minha playlist mais recente para ouvir offline',
  ),
  (label: 'Letra', prompt: 'Qual a letra da música que está tocando?'),
  (label: 'Curtir essa', prompt: 'Curta a música que está tocando agora'),
];

/// How far from the bottom the user has to scroll before the chat stops
/// following new content.
const _followBottomThreshold = 80.0;

class AiChatPage extends StatefulWidget {
  const AiChatPage({required this.chatId, super.key});

  final String chatId;

  static const routePath = '/musify-ai/chat';

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  Map<String, dynamic>? _pendingAttachment;
  bool _startingMoots = false;

  /// Stops the view from yanking itself back down while the user is reading
  /// earlier messages.
  bool _followBottom = true;
  int _lastMessageCount = 0;
  int _lastContentLength = 0;

  late final List<_Suggestion> _dynamicSuggestions =
      (List<_Suggestion>.from(_suggestionPool)..shuffle(Random()))
          .take(3)
          .toList();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom =
        position.maxScrollExtent - position.pixels <= _followBottomThreshold;
    if (atBottom != _followBottom) {
      setState(() => _followBottom = atBottom);
    }
  }

  /// True while the last message is still being produced.
  bool _isTurnRunning(List<Map> messages) {
    if (messages.isEmpty) return false;
    final status = messages.last['status']?.toString();
    return status == 'working' || status == 'streaming';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The app bar theme is 30pt Paytone One and centred, which is right for
        // a section title and wrong for a chat name: every name ellipsised.
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        centerTitle: false,
        title: ValueListenableBuilder<List<Map>>(
          valueListenable: AiChatStore.instance.chats,
          builder: (context, chats, _) {
            final chat = chats.firstWhere(
              (c) => c['id'] == widget.chatId,
              orElse: () => const {'name': 'Conversa'},
            );
            return Text(
              chat['name']?.toString() ?? 'Conversa',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(FluentIcons.more_vertical_24_regular),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Renomear')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Map>>(
        valueListenable: AiChatStore.instance.messagesNotifier(widget.chatId),
        builder: (context, messages, _) {
          _scheduleAutoScroll(messages);
          final running = _isTurnRunning(messages);

          return Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return AiMessageBubble(
                            // Without a key, recycling attaches one message's
                            // element state to another's data as the list grows.
                            key: ValueKey(message['id']),
                            message: message,
                            chatId: widget.chatId,
                          );
                        },
                      ),
              ),
              if (!running) _buildSuggestions(context),
              _buildSpeakingIndicator(),
              _buildInputBar(context, running),
            ],
          );
        },
      ),
    );
  }

  /// Follows new content only while the user is already at the bottom.
  void _scheduleAutoScroll(List<Map> messages) {
    final contentLength = messages.isEmpty
        ? 0
        : (messages.last['content'] ?? '').toString().length;
    final changed =
        messages.length != _lastMessageCount ||
        contentLength != _lastContentLength;

    _lastMessageCount = messages.length;
    _lastContentLength = contentLength;

    if (!changed || !_followBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.bot_24_regular, size: 48),
            const SizedBox(height: 12),
            Text(
              'Pergunte algo ou peça uma ação - tocar uma música, montar '
              'uma playlist, ver sua biblioteca...',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      // 48 is the M3 chip tap target; 44 clipped the chips vertically.
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        itemCount: _dynamicSuggestions.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ActionChip(
              avatar: _startingMoots
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : Icon(
                      FluentIcons.sparkle_24_filled,
                      color: colorScheme.onPrimaryContainer,
                      size: 18,
                    ),
              label: const Text('Moots'),
              backgroundColor: colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
              onPressed: _startingMoots ? null : _startMoots,
            );
          }

          final suggestion = _dynamicSuggestions[index - 1];
          return ActionChip(
            label: Text(
              suggestion.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _send(text: suggestion.prompt),
          );
        },
      ),
    );
  }

  /// "Moots": a quick-mix that does not go through the AI at all - it just
  /// hands the app's own recommendation algorithm a fresh dynamic queue,
  /// like a "shuffle play" button.
  Future<void> _startMoots() async {
    setState(() => _startingMoots = true);
    try {
      final songs = await getRecommendedSongs();
      if (songs.isNotEmpty) {
        await audioHandler.addPlaylistToQueue(
          List<Map>.from(songs),
          replace: true,
        );
      }
    } finally {
      if (mounted) setState(() => _startingMoots = false);
    }
  }

  Widget _buildSpeakingIndicator() {
    return ValueListenableBuilder<bool>(
      valueListenable: AiVoiceService.instance.isSpeaking,
      builder: (context, speaking, _) {
        if (!speaking) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('Falando...'),
              const Spacer(),
              TextButton(
                onPressed: AiVoiceService.instance.stopSpeaking,
                child: const Text('Parar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar(BuildContext context, bool running) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingAttachment != null) _buildAttachmentPreview(context),
            Row(
              children: [
                IconButton(
                  icon: const Icon(FluentIcons.add_circle_24_regular),
                  onPressed: running ? null : _pickAttachment,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: AiVoiceService.instance.isRecording,
                  builder: (context, recording, _) {
                    return IconButton(
                      icon: Icon(
                        recording
                            ? FluentIcons.record_stop_24_filled
                            : FluentIcons.mic_24_regular,
                        color: recording
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      onPressed: running ? null : _toggleRecording,
                    );
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Mensagem...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // While a turn runs this is the only way out of it, so it has
                // to be a stop button rather than a disabled send button.
                if (running)
                  IconButton.filled(
                    tooltip: 'Parar',
                    icon: const Icon(FluentIcons.stop_24_filled),
                    onPressed: () =>
                        AiService.instance.stopTurn(widget.chatId),
                  )
                else
                  IconButton.filled(
                    icon: const Icon(FluentIcons.send_24_filled),
                    onPressed: _send,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(BuildContext context) {
    final attachment = _pendingAttachment!;
    final item = attachment['item'] as Map? ?? {};
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.attach_24_regular,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                (item['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.dismiss_circle_24_regular, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _pendingAttachment = null),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAttachment() async {
    final picked = await showAiAttachmentPicker(context);
    if (picked != null) {
      setState(() => _pendingAttachment = picked);
    }
  }

  Future<void> _toggleRecording() async {
    final voice = AiVoiceService.instance;
    if (voice.isRecording.value) {
      final transcript = await voice.stopListening();
      if (transcript != null && transcript.trim().isNotEmpty) {
        setState(() {
          _inputController.text = transcript;
          _inputController.selection = TextSelection.collapsed(
            offset: transcript.length,
          );
        });
      }
    } else {
      await voice.startListening();
      setState(() {});
    }
  }

  Future<void> _send({String? text}) async {
    final message = (text ?? _inputController.text).trim();
    final attachment = _pendingAttachment;
    if (message.isEmpty && attachment == null) return;

    _inputController.clear();
    setState(() {
      _pendingAttachment = null;
      // A newly sent message should always pull the view back down.
      _followBottom = true;
    });

    // An empty message with an attachment used to be sent as the literal
    // "Sobre isso:", which then showed up in the chat as if the user had typed
    // it. The attachment block alone is enough for the model.
    final outcome = await AiService.instance.sendMessage(
      widget.chatId,
      message,
      attachment: attachment,
    );

    if (outcome == AiTurnOutcome.busy && mounted) {
      showToast(context, 'Espera eu terminar a anterior…');
    }
  }

  Future<void> _handleMenuAction(String action) async {
    if (action == 'rename') {
      final chat = AiChatStore.instance.chats.value.firstWhere(
        (c) => c['id'] == widget.chatId,
        orElse: () => const {'name': ''},
      );
      final result = await showRenameChatDialog(
        context,
        chat['name']?.toString() ?? '',
      );
      if (result != null && result.trim().isNotEmpty) {
        await AiChatStore.instance.renameChat(widget.chatId, result);
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ConfirmationDialog(
          confirmationMessage: 'Excluir esta conversa?',
          submitMessage: 'Excluir',
          isDangerous: true,
          onCancel: () => Navigator.of(context).pop(false),
          onSubmit: () => Navigator.of(context).pop(true),
        ),
      );
      if ((confirmed ?? false) && mounted) {
        await AiChatStore.instance.deleteChat(widget.chatId);
        if (mounted) Navigator.of(context).pop();
      }
    }
  }
}

/// Shared by the chat page and the chat list.
Future<String?> showRenameChatDialog(
  BuildContext context,
  String initialName,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RenameChatDialog(initialName: initialName),
  );
}

/// Own widget so its controller is actually disposed.
class _RenameChatDialog extends StatefulWidget {
  const _RenameChatDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renomear conversa'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
