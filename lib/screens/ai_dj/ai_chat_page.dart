import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/services/ai/ai_dj_service.dart';
import 'package:musify/services/ai/ai_voice_service.dart';
import 'package:musify/widgets/ai_dj/ai_attachment_picker.dart';
import 'package:musify/widgets/ai_dj/ai_message_bubble.dart';
import 'package:musify/widgets/confirmation_dialog.dart';

const _suggestions = [
  'Adicione uma música na fila com base no que está tocando agora',
  'Monte uma playlist temporária para hoje',
  'O que tem na minha biblioteca?',
  'Toque algo parecido com o que está tocando',
];

class AiChatPage extends StatefulWidget {
  const AiChatPage({required this.chatId, super.key});

  final String chatId;

  static const routePath = '/musify-ia/chat';

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  Map<String, dynamic>? _pendingAttachment;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = AiChatStore.instance.chats.value.firstWhere(
      (c) => c['id'] == widget.chatId,
      orElse: () => const {'name': 'Conversa'},
    );

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  chat['name']?.toString() ?? 'Conversa',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(FluentIcons.chevron_down_24_regular, size: 18),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Renomear')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<Map>>(
              valueListenable: AiChatStore.instance.messagesNotifier(
                widget.chatId,
              ),
              builder: (context, messages, _) {
                final visible = messages
                    .where((m) => m['role'] != 'tool')
                    .toList();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                });

                if (visible.isEmpty) {
                  return _buildEmptyState(context);
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: visible.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return const _TypingIndicator();
                    }
                    return AiMessageBubble(message: visible[index]);
                  },
                );
              },
            ),
          ),
          _buildSuggestions(context),
          _buildSpeakingIndicator(),
          _buildInputBar(context),
        ],
      ),
    );
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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _suggestions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(_suggestions[index]),
            onPressed: _sending
                ? null
                : () {
                    _inputController.text = _suggestions[index];
                    _send();
                  },
          );
        },
      ),
    );
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

  Widget _buildInputBar(BuildContext context) {
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
                  onPressed: _sending ? null : _pickAttachment,
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
                      onPressed: _sending ? null : _toggleRecording,
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
                IconButton.filled(
                  icon: const Icon(FluentIcons.send_24_filled),
                  onPressed: _sending ? null : _send,
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

  Future<void> _send() async {
    final text = _inputController.text.trim();
    final attachment = _pendingAttachment;
    if ((text.isEmpty && attachment == null) || _sending) return;

    _inputController.clear();
    setState(() {
      _sending = true;
      _pendingAttachment = null;
    });
    try {
      await AiDjService.instance.sendMessage(
        widget.chatId,
        text.isEmpty ? 'Sobre isso:' : text,
        attachment: attachment,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleMenuAction(String action) async {
    if (action == 'rename') {
      final chat = AiChatStore.instance.chats.value.firstWhere(
        (c) => c['id'] == widget.chatId,
        orElse: () => const {'name': ''},
      );
      final controller = TextEditingController(text: chat['name']?.toString());
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Renomear conversa'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Salvar'),
            ),
          ],
        ),
      );
      if (result != null && result.trim().isNotEmpty) {
        await AiChatStore.instance.renameChat(widget.chatId, result);
        if (mounted) setState(() {});
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

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 32,
          height: 14,
          child: Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
