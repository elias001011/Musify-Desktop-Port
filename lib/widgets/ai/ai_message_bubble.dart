import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/services/ai/ai_voice_service.dart';
import 'package:musify/widgets/ai/ai_action_card.dart';

class AiMessageBubble extends StatefulWidget {
  const AiMessageBubble({
    required this.message,
    required this.chatId,
    super.key,
  });

  final Map message;
  final String chatId;

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
    final status = message['status']?.toString();
    final isError = status == 'failed' || message['isError'] == true;
    final colorScheme = Theme.of(context).colorScheme;
    final content = (message['content'] ?? '').toString();
    final actionCard = message['actionCard'] as Map?;
    final attachment = message['attachment'] as Map?;
    final messageId = message['id']?.toString() ?? '';

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

    // While a turn is still working there is nothing to put in a bubble; the
    // status line below carries the state. Rendering an empty bubble here is
    // what used to litter the chat with "…" ghosts.
    final showBubble = content.isNotEmpty;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (showBubble)
                // Only the text is width-constrained. The card below is a
                // sibling, so it gets the full column width instead of being
                // squeezed into a chat bubble's 80%.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                  ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: SelectionArea(
                            child: _FormattedAnswer(
                              text: content,
                              color: textColor,
                            ),
                          ),
                        ),
                        if (!isUser) ...[
                          const SizedBox(width: 6),
                          _SpeakButton(
                            content: content,
                            messageId: messageId,
                            color: textColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (attachment != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                  ),
                  child: primaryCard(
                    context,
                    image: (attachment['item']?['image'])?.toString(),
                    title: (attachment['item']?['title'] ?? '').toString(),
                    subtitle: _attachmentSubtitle(attachment),
                    badge: 'Anexado',
                  ),
                ),
              if (actionCard != null)
                AiActionCard(
                  actionCard: actionCard,
                  chatId: widget.chatId,
                  messageId: messageId,
                  saved: message['saved'] as Map?,
                ),
              if (!isUser)
                _AiStatusLine(status: status, label: message['stepLabel']),
            ],
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

/// Renders the assistant's answer with the little formatting it actually uses.
///
/// The app-wide AutoFormatText is centred and takes its colour from the theme,
/// which suits the update dialog it was written for and not a chat bubble.
/// Rather than change a shared widget every Cloud sync would then conflict on,
/// this handles the same `**bold**` and `* ` bullets, left-aligned and in the
/// bubble's own colour.
class _FormattedAnswer extends StatelessWidget {
  const _FormattedAnswer({required this.text, required this.color});

  final String text;
  final Color color;

  static final _bold = RegExp(r'\*\*(.*?)\*\*');

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color);

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in _bold.allMatches(text)) {
      spans
        ..add(
          TextSpan(
            text: _bullets(text.substring(cursor, match.start)),
            style: baseStyle,
          ),
        )
        ..add(
          TextSpan(
            text: match.group(1),
            style: baseStyle?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      cursor = match.end;
    }

    spans.add(
      TextSpan(text: _bullets(text.substring(cursor)), style: baseStyle),
    );

    return Text.rich(TextSpan(children: spans));
  }

  String _bullets(String value) => value.replaceAll('* ', '• ');
}

/// What the assistant is doing right now, under its answer.
///
/// This is the whole "real-time" surface, and it is deliberately vague about
/// mechanics: "Procurando músicas…", never a tool name, a provider or a round
/// number. A consumer music app should read as an assistant thinking, not as a
/// debugger.
class _AiStatusLine extends StatelessWidget {
  const _AiStatusLine({required this.status, required this.label});

  final String? status;
  final Object? label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    switch (status) {
      case 'working':
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                (label ?? 'Pensando…').toString(),
                style: textStyle,
              ),
            ],
          ),
        );
      case 'streaming':
        return const _TypingCaret();
      case 'incomplete':
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.info_24_regular,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text('Parei no meio do caminho', style: textStyle),
            ],
          ),
        );
      case 'stopped':
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('Interrompido', style: textStyle),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// A blinking caret while text streams in, so the answer reads as still being
/// written rather than as finished and oddly short.
class _TypingCaret extends StatefulWidget {
  const _TypingCaret();

  @override
  State<_TypingCaret> createState() => _TypingCaretState();
}

class _TypingCaretState extends State<_TypingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: FadeTransition(
        opacity: _controller,
        child: Container(
          width: 7,
          height: 13,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Explicit read-aloud control.
///
/// Tapping the whole bubble used to trigger speech, which is both undiscoverable
/// and impossible to stop: a second tap started it again.
class _SpeakButton extends StatelessWidget {
  const _SpeakButton({
    required this.content,
    required this.messageId,
    required this.color,
  });

  final String content;
  final String messageId;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<String?>(
      valueListenable: AiVoiceService.instance.speakingMessageId,
      builder: (context, speakingId, _) {
        final isSpeaking = speakingId != null && speakingId == messageId;

        return IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          iconSize: 16,
          tooltip: isSpeaking ? 'Parar leitura' : 'Ouvir',
          icon: isSpeaking
              ? _SpeakingIndicator(color: color)
              : Icon(
                  FluentIcons.speaker_2_24_regular,
                  color: color.withValues(alpha: 0.6),
                ),
          onPressed: () {
            if (isSpeaking) {
              AiVoiceService.instance.stopSpeaking();
            } else {
              AiVoiceService.instance.speak(content, messageId: messageId);
            }
          },
        );
      },
    );
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
