import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/services/ai/ai_voice_service.dart';
import 'package:musify/widgets/ai/ai_action_card.dart';

class AiMessageBubble extends StatefulWidget {
  const AiMessageBubble({required this.message, super.key});

  final Map message;

  @override
  State<AiMessageBubble> createState() => _AiMessageBubbleState();
}

class _AiMessageBubbleState extends State<AiMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message['role'] == 'user';
    final isError = message['isError'] == true;
    final colorScheme = Theme.of(context).colorScheme;
    final content = (message['content'] ?? '').toString();
    final actionCard = message['actionCard'] as Map?;
    final attachment = message['attachment'] as Map?;
    final messageId = message['id']?.toString();

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

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Align(
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
                      ? () => AiVoiceService.instance.speak(
                          content,
                          messageId: messageId,
                        )
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
                          const SizedBox(width: 8),
                          ValueListenableBuilder<String?>(
                            valueListenable:
                                AiVoiceService.instance.speakingMessageId,
                            builder: (context, speakingId, _) {
                              if (speakingId != null &&
                                  speakingId == messageId) {
                                return _SpeakingIndicator(color: textColor);
                              }
                              return Icon(
                                FluentIcons.speaker_2_24_regular,
                                size: 16,
                                color: textColor.withValues(alpha: 0.6),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (attachment != null)
                  primaryCard(
                    context,
                    image: (attachment['item']?['image'])?.toString(),
                    title: (attachment['item']?['title'] ?? '').toString(),
                    subtitle: _attachmentSubtitle(attachment),
                    badge: 'Anexado',
                  ),
                if (actionCard != null) AiActionCard(actionCard: actionCard),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _attachmentSubtitle(Map attachment) {
    final type = attachment['itemType']?.toString() ?? '';
    final item = attachment['item'] as Map? ?? {};
    const labels = {
      'song': 'Música',
      'playlist': 'Playlist',
      'album': 'Álbum',
      'artist': 'Artista',
    };
    final label = labels[type] ?? type;
    final artist = item['artist']?.toString();
    return artist == null || artist.isEmpty ? label : '$label · $artist';
  }
}

/// Small animated equalizer (three bars bouncing) shown in place of the
/// speaker icon while this exact message is being read aloud.
class _SpeakingIndicator extends StatefulWidget {
  const _SpeakingIndicator({required this.color});
  final Color color;

  @override
  State<_SpeakingIndicator> createState() => _SpeakingIndicatorState();
}

class _SpeakingIndicatorState extends State<_SpeakingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final t = (_controller.value + i * 0.33) % 1.0;
              final height = 4 + 10 * (0.5 - (t - 0.5).abs()) * 2;
              return Container(
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
