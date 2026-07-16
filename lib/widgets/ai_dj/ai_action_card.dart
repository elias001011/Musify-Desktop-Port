import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';

/// Renders whatever action Musify IA just took (search results, a song it
/// started playing, a playlist it built, a like/offline toggle, ...) right
/// below its chat bubble, so the user sees the effect instead of just text.
class AiActionCard extends StatelessWidget {
  const AiActionCard({required this.actionCard, super.key});

  final Map actionCard;

  @override
  Widget build(BuildContext context) {
    final type = actionCard['type'];
    switch (type) {
      case 'search_results':
        return _buildSongList(
          context,
          (actionCard['items'] as List? ?? []).cast<Map>(),
          emptyLabel: 'Nada encontrado.',
        );
      case 'now_playing':
        return _buildSongRow(
          context,
          Map<String, dynamic>.from(actionCard['song'] as Map? ?? {}),
          label: 'Tocando agora',
        );
      case 'queue':
        return _buildSongList(
          context,
          (actionCard['items'] as List? ?? []).cast<Map>(),
          emptyLabel: 'Fila vazia.',
          label: 'Fila',
        );
      case 'playback':
        final nowPlaying = actionCard['nowPlaying'] as Map?;
        return nowPlaying == null
            ? const SizedBox.shrink()
            : _buildSongRow(
                context,
                Map<String, dynamic>.from(nowPlaying),
                label: 'Tocando agora',
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
        return _TempPlaylistCard(actionCard: actionCard);
      case 'playlist':
        return _PlaylistCard(actionCard: actionCard);
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
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildSongRow(
    BuildContext context,
    Map<String, dynamic> song, {
    String? label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => audioHandler.playSong({
          'id': 0,
          'ytid': song['ytid'],
          'title': song['title'],
          'artist': song['artist'] ?? '',
          'image': song['image'],
          'lowResImage': song['image'],
          'highResImage': song['image'],
          'duration': song['duration'],
        }),
        child: Row(
          children: [
            _thumbnail(song['image']?.toString()),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null)
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  Text(
                    (song['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    (song['artist'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(FluentIcons.play_circle_24_filled),
          ],
        ),
      ),
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
        padding: const EdgeInsets.only(top: 6),
        child: Text(emptyLabel, style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colorScheme.primary),
              ),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSong =
                    item.containsKey('ytid') && item.containsKey('duration');
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _thumbnail(item['image']?.toString()),
                  title: Text(
                    (item['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: item['artist'] == null
                      ? null
                      : Text(
                          item['artist'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: isSong
                      ? () => audioHandler.playSong({
                          'id': 0,
                          'ytid': item['ytid'],
                          'title': item['title'],
                          'artist': item['artist'] ?? '',
                          'image': item['image'],
                          'lowResImage': item['image'],
                          'highResImage': item['image'],
                          'duration': item['duration'],
                        })
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _thumbnail(String? url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null || url.isEmpty
          ? Container(
              width: 44,
              height: 44,
              color: Colors.black12,
              child: const Icon(FluentIcons.music_note_1_24_regular),
            )
          : CachedNetworkImage(
              imageUrl: url,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                width: 44,
                height: 44,
                color: Colors.black12,
                child: const Icon(FluentIcons.music_note_1_24_regular),
              ),
            ),
    );
  }
}

class _TempPlaylistCard extends StatefulWidget {
  const _TempPlaylistCard({required this.actionCard});
  final Map actionCard;

  @override
  State<_TempPlaylistCard> createState() => _TempPlaylistCardState();
}

class _TempPlaylistCardState extends State<_TempPlaylistCard> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final songs = (widget.actionCard['songs'] as List? ?? []).cast<Map>();
    final name = (widget.actionCard['name'] ?? 'Playlist').toString();
    final image = widget.actionCard['image']?.toString();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AiActionCard._thumbnail(image),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${songs.length} música(s) · temporária',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_saved)
            const Text('Salva na biblioteca ✓')
          else
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: const Icon(FluentIcons.save_24_regular),
                label: const Text('Salvar na biblioteca'),
                onPressed: () => _save(context, name, image, songs),
              ),
            ),
        ],
      ),
    );
  }

  void _save(
    BuildContext context,
    String name,
    String? image,
    List<Map> songs,
  ) {
    final hydrated = songs
        .map(
          (s) => {
            'id': 0,
            'ytid': s['ytid'],
            'title': s['title'],
            'artist': s['artist'] ?? '',
            'image': s['image'],
            'lowResImage': s['image'],
            'highResImage': s['image'],
            'duration': s['duration'],
          },
        )
        .toList();

    final (_, playlistId) = createCustomPlaylist(name, image, context);
    if (hydrated.isNotEmpty) {
      addSongsInCustomPlaylist(context, playlistId, hydrated);
    }
    setState(() => _saved = true);
    showToast(context, 'Playlist salva na biblioteca!');
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.actionCard});
  final Map actionCard;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final songs = (actionCard['songs'] as List? ?? []).cast<Map>();
    final name = (actionCard['title'] ?? 'Playlist').toString();
    final ytid = actionCard['ytid']?.toString();
    final image = actionCard['image']?.toString();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: ytid == null ? null : () => context.push('/home/playlist/$ytid'),
        child: Row(
          children: [
            AiActionCard._thumbnail(image),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${songs.length} música(s) · salva na biblioteca',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(FluentIcons.chevron_right_24_regular),
          ],
        ),
      ),
    );
  }
}
