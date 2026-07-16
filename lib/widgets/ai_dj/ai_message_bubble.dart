import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/services/ai/ai_voice_service.dart';
import 'package:musify/widgets/ai_dj/ai_action_card.dart';

class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({required this.message, super.key});

  final Map message;

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    final isError = message['isError'] == true;
    final colorScheme = Theme.of(context).colorScheme;
    final content = (message['content'] ?? '').toString();
    final actionCard = message['actionCard'] as Map?;

    final bubbleColor = isError
        ? colorScheme.errorContainer
        : isUser
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final textColor = isError
        ? colorScheme.onErrorContainer
        : isUser
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: (!isUser && content.isNotEmpty)
                  ? () => AiVoiceService.instance.speak(content)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        content.isEmpty ? '…' : content,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                    if (!isUser && content.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(
                        FluentIcons.speaker_2_24_regular,
                        size: 16,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (actionCard != null) AiActionCard(actionCard: actionCard),
          ],
        ),
      ),
    );
  }
}
