import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/ai/ai_playlist_page.dart';
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/artwork_image.dart';
import 'package:musify/widgets/song_bar.dart';

/// Card types in the order they deserve to be the one card of a turn.
///
/// A turn that searched three times and then built a playlist should show the
/// playlist, not three lists of songs the user did not ask to see. Earlier in
/// this list wins.
const _cardPriority = [
  'temp_playlist',
  'playlist',
  'now_playing',
  'playback',
  'queue',
  'offline',
  'like',
  'playlist_updated',
  'search_results',
];

/// How many rows a list-shaped card shows before it stops.
///
/// The card lives inside the chat's own ListView, so it must not scroll: a
/// nested scrollable steals the drag. Showing a handful and stopping is both
/// the fix and the better card.
const _maxListRows = 5;

/// Picks the single card that represents what a turn accomplished.
///
/// `search_results` is last on purpose: searching is how the assistant reaches
/// an answer, not the answer itself, so it only shows when nothing else
/// happened — i.e. when the user really did just ask to search.
Map<String, dynamic>? pickPrimaryCard(List<Map<String, dynamic>> cards) {
  if (cards.isEmpty) return null;

  Map<String, dynamic>? best;
  var bestRank = _cardPriority.length;

  for (final card in cards) {
    final rank = _cardPriority.indexOf(card['type']?.toString() ?? '');
    final effectiveRank = rank == -1 ? _cardPriority.length : rank;
    // Strictly less-than, so among equals the first wins: that is the one the
    // model produced first, and so the one its text is talking about.
    if (best == null || effectiveRank < bestRank) {
      best = card;
      bestRank = effectiveRank;
    }
  }

  return best;
}

/// Rebuilds the full song map the rest of the app expects from the compact
/// shape stored on a card.
Map<String, dynamic> hydrateCardSong(Map song) => {
  'id': 0,
  'ytid': song['ytid'],
  'title': song['title'],
  'artist': song['artist'] ?? '',
  'image': song['image'],
  'lowResImage': song['image'],
  'highResImage': song['image'],
  'duration': song['duration'],
};

/// Renders whatever action Musify AI just took (search results, a song it
/// started playing, a playlist it built, a like/offline toggle, ...) right
/// below its answer, so the user sees the effect instead of just text.
///
/// Single-item results (now playing, a playlist) use a big vertical card -
/// square art on top, title/subtitle below - modeled after how Spotify
/// renders a shared song in chat. Multi-item results (search, queue) use
/// compact rows instead, since a dozen full-size cards would be unusable.
class AiActionCard extends StatelessWidget {
  const AiActionCard({
    required this.actionCard,
    required this.chatId,
    required this.messageId,
    this.saved,
    super.key,
  });

  final Map actionCard;

  /// Which message this card belongs to. Needed both to open the playlist
  /// route and to record a save back onto the message.
  final String chatId;
  final String messageId;

  /// Set once a temporary playlist has been written to the library.
  final Map? saved;

  @override
  Widget build(BuildContext context) {
    switch (actionCard['type']) {
      case 'search_results':
        return _buildSongList(
          context,
          (actionCard['items'] as List? ?? []).cast<Map>(),
          emptyLabel: 'Não achei nada com isso.',
        );
      case 'now_playing':
        return _buildSongCard(
          context,
          Map<String, dynamic>.from(actionCard['song'] as Map? ?? {}),
          badge: 'Tocando agora',
        );
      case 'queue':
        return _buildSongList(
          context,
          (actionCard['items'] as List? ?? []).cast<Map>(),
          emptyLabel: 'A fila está vazia.',
          label: 'Fila',
        );
      case 'playback':
        final nowPlaying = actionCard['nowPlaying'] as Map?;
        return nowPlaying == null
            ? const SizedBox.shrink()
            : _buildSongCard(
                context,
                Map<String, dynamic>.from(nowPlaying),
                badge: 'Tocando agora',
              );
      case 'like':
        return _buildChip(
          context,
          icon: (actionCard['liked'] == true)
              ? FluentIcons.heart_24_filled
              : FluentIcons.heart_24_regular,
          label: (actionCard['liked'] == true) ? 'Curtido' : 'Descurtido',
        );
      case 'temp_playlist':
        return _TempPlaylistCard(
          actionCard: actionCard,
          chatId: chatId,
          messageId: messageId,
          saved: saved,
        );
      case 'playlist':
        return _PlaylistCard(
          actionCard: actionCard,
          chatId: chatId,
          messageId: messageId,
        );
      case 'playlist_updated':
        return _buildChip(
          context,
          icon: FluentIcons.checkmark_circle_24_filled,
          label: 'Playlist atualizada',
        );
      case 'offline':
        final downloading = actionCard['action'] == 'download';
        return _buildChip(
          context,
          icon: downloading
              ? FluentIcons.arrow_download_24_filled
              : FluentIcons.delete_24_regular,
          label: downloading ? 'Baixado para offline' : 'Removido do offline',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSongCard(
    BuildContext context,
    Map<String, dynamic> song, {
    String? badge,
  }) {
    return primaryCard(
      context,
      image: song['image']?.toString(),
      title: (song['title'] ?? '').toString(),
      subtitle: 'Música${song['artist'] != null ? ' · ${song['artist']}' : ''}',
      badge: badge,
      onTap: () => audioHandler.playSong(hydrateCardSong(song)),
    );
  }

  Widget _buildSongList(
    BuildContext context,
    List<Map> items, {
    required String emptyLabel,
    String? label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(emptyLabel, style: Theme.of(context).textTheme.bodySmall),
      );
    }

    final shown = items.take(_maxListRows).toList();
    final hydrated = shown.map(hydrateCardSong).toList();
    final hidden = items.length - shown.length;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colorScheme.primary),
              ),
            ),
          // SongBar rather than a bespoke row: it brings the app's artwork
          // handling, duration, offline badge and song menu with it.
          for (var index = 0; index < hydrated.length; index++)
            SongBar(
              hydrated[index],
              false,
              key: ValueKey('ai-song-${hydrated[index]['ytid']}-$index'),
              showMusicDuration: true,
              // Play the whole card as a queue, so tapping the third result
              // does not throw away the other four.
              onPlay: () => audioHandler.playPlaylistSong(
                playlist: {'list': hydrated},
                songIndex: index,
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'e mais $hidden…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared "big vertical card" used for a single song/playlist/album/artist:
/// square art on top, title + subtitle below, all inside a bordered rounded
/// container - modeled after Spotify's shared-song chat card.
///
/// [footer] renders inside the same clipped container, under a divider. An
/// action that belongs to the card has to live in the card; a button floating
/// underneath reads as a separate, unrelated thing.
Widget primaryCard(
  BuildContext context, {
  required String? image,
  required String title,
  required String subtitle,
  String? badge,
  VoidCallback? onTap,
  IconData trailingIcon = FluentIcons.play_circle_24_filled,
  Widget? footer,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final maxWidth = (MediaQuery.sizeOf(context).width * 0.72).clamp(200.0, 320.0);

  return Container(
    margin: const EdgeInsets.only(top: 8),
    constraints: BoxConstraints(maxWidth: maxWidth),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ArtworkImage(url: image, size: null, borderRadius: 0),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (badge != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  badge,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: colorScheme.primary),
                                ),
                              ),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 8),
                        Icon(trailingIcon, color: colorScheme.primary),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (footer != null) ...[
          Divider(height: 1, color: colorScheme.outlineVariant),
          footer,
        ],
      ],
    ),
  );
}

class _TempPlaylistCard extends StatelessWidget {
  const _TempPlaylistCard({
    required this.actionCard,
    required this.chatId,
    required this.messageId,
    this.saved,
  });

  final Map actionCard;
  final String chatId;
  final String messageId;
  final Map? saved;

  @override
  Widget build(BuildContext context) {
    final songs = (actionCard['songs'] as List? ?? []).cast<Map>();
    // v1 cards used 'name'; v2 uses 'title' like every other card.
    final name = (actionCard['title'] ?? actionCard['name'] ?? 'Playlist')
        .toString();
    final image = actionCard['image']?.toString();

    final savedId = saved?['playlistId']?.toString();
    // Belt and braces: if the playlist is in the library the card is saved,
    // whatever the message says.
    final isSaved =
        savedId != null &&
        (userCustomPlaylists.value.any((p) => p['ytid'] == savedId) ||
            saved != null);

    return primaryCard(
      context,
      image: image,
      title: name,
      subtitle: '${songs.length} música${songs.length == 1 ? '' : 's'}'
          '${isSaved ? '' : ' · não salva'}',
      trailingIcon: FluentIcons.chevron_right_24_regular,
      onTap: () => context.push(aiPlaylistRoute(chatId, messageId)),
      footer: isSaved
          ? _footerLabel(
              context,
              icon: FluentIcons.checkmark_circle_24_filled,
              label: 'Salva na biblioteca',
            )
          : _saveButton(context, name, image, songs),
    );
  }

  Widget _footerLabel(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }

  Widget _saveButton(
    BuildContext context,
    String name,
    String? image,
    List<Map> songs,
  ) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: const RoundedRectangleBorder(),
      ),
      icon: const Icon(FluentIcons.save_24_regular, size: 18),
      label: const Text('Salvar na biblioteca'),
      onPressed: () => _save(context, name, image, songs),
    );
  }

  Future<void> _save(
    BuildContext context,
    String name,
    String? image,
    List<Map> songs,
  ) async {
    // The saved state lives on the message, not in widget state. A local flag
    // came back every time the card was scrolled out of view or the app was
    // reopened, and pressing again created a second identical playlist.
    if (saved != null) return;

    final hydrated = songs.map(hydrateCardSong).toList();
    final (_, playlistId) = createCustomPlaylist(name, image, context);
    if (hydrated.isNotEmpty) {
      addSongsInCustomPlaylist(context, playlistId, hydrated);
    }

    await AiChatStore.instance.updateMessage(chatId, messageId, {
      'saved': {
        'playlistId': playlistId,
        'at': DateTime.now().millisecondsSinceEpoch,
      },
    });

    if (context.mounted) {
      showToast(context, 'Playlist salva na biblioteca!');
    }
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.actionCard,
    required this.chatId,
    required this.messageId,
  });

  final Map actionCard;
  final String chatId;
  final String messageId;

  @override
  Widget build(BuildContext context) {
    final songs = (actionCard['songs'] as List? ?? []).cast<Map>();
    final name = (actionCard['title'] ?? actionCard['name'] ?? 'Playlist')
        .toString();
    final image = actionCard['image']?.toString();

    return primaryCard(
      context,
      image: image,
      title: name,
      subtitle: '${songs.length} música${songs.length == 1 ? '' : 's'}',
      trailingIcon: FluentIcons.chevron_right_24_regular,
      onTap: () => context.push(aiPlaylistRoute(chatId, messageId)),
    );
  }
}
