import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/screens/ai/ai_chat_page.dart';
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';

class AiChatListPage extends StatelessWidget {
  const AiChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: aiEnabled,
      builder: (context, enabled, _) {
        return Scaffold(
          appBar: AppBar(
            title: ValueListenableBuilder<String>(
              valueListenable: aiName,
              builder: (context, name, _) => Text(name),
            ),
            actions: [
              if (enabled)
                IconButton(
                  icon: const Icon(FluentIcons.add_24_filled),
                  tooltip: 'Nova conversa',
                  onPressed: () => _createAndOpenChat(context),
                ),
            ],
          ),
          body: !enabled
              ? _buildDisabledState(context)
              : _buildChatList(context),
        );
      },
    );
  }

  Widget _buildDisabledState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.bot_24_regular, size: 56),
            const SizedBox(height: 16),
            Text(
              'Musify AI está desativado.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ative o recurso experimental e configure ao menos um '
              'provedor de IA em Configurações.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/settings/musify-ai'),
              child: const Text('Abrir configurações'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(BuildContext context) {
    return ValueListenableBuilder<List<Map>>(
      valueListenable: AiChatStore.instance.chats,
      builder: (context, chats, _) {
        if (chats.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.chat_sparkle_24_regular, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma conversa ainda.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(FluentIcons.add_24_filled),
                    label: const Text('Nova conversa'),
                    onPressed: () => _createAndOpenChat(context),
                  ),
                ],
              ),
            ),
          );
        }

        // CustomBar with grouped radii, like every other list in the app. The
        // ListTile/CircleAvatar rows this replaces looked like a different app
        // next to Library and Settings.
        return ListView.builder(
          padding: commonSingleChildScrollViewPadding,
          itemCount: chats.length + 1,
          itemBuilder: (context, index) {
            if (index == chats.length) {
              return const MiniPlayerBottomSpace();
            }
            final chat = chats[index];
            final preview = (chat['preview']?.toString() ?? '').trim();
            return CustomBar(
              key: listItemKey('aiChat', index, chat['id']),
              chat['name']?.toString() ?? 'Conversa',
              FluentIcons.chat_24_regular,
              description: preview.isEmpty ? null : preview,
              borderRadius: getItemBorderRadius(index, chats.length),
              trailing: PopupMenuButton<String>(
                icon: const Icon(FluentIcons.more_vertical_24_regular),
                onSelected: (action) =>
                    _handleMenuAction(context, action, chat),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Renomear')),
                  PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ),
              onTap: () =>
                  context.push('${AiChatPage.routePath}/${chat['id']}'),
            );
          },
        );
      },
    );
  }

  void _createAndOpenChat(BuildContext context) {
    final chat = AiChatStore.instance.createChat();
    context.push('${AiChatPage.routePath}/${chat['id']}');
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    String action,
    Map chat,
  ) async {
    final chatId = chat['id'].toString();
    if (action == 'rename') {
      final result = await showRenameChatDialog(
        context,
        chat['name']?.toString() ?? '',
      );
      if (result != null && result.trim().isNotEmpty) {
        await AiChatStore.instance.renameChat(chatId, result);
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
      if (confirmed ?? false) {
        await AiChatStore.instance.deleteChat(chatId);
      }
    }
  }
}
