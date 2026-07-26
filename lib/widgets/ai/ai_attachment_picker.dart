import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/widgets/artwork_image.dart';

/// Shows a bottom sheet letting the user attach a song/playlist/album/
/// artist to their next Musify AI message, either by searching or by
/// picking straight from their library. Returns
/// `{'itemType': ..., 'item': {...compact fields...}}`, or null if
/// dismissed without a pick.
Future<Map<String, dynamic>?> showAiAttachmentPicker(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      // The sheet has to shrink for the keyboard: at a fixed 75% of the screen
      // the search results were squeezed out of view the moment it opened.
      final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
      final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

      return DefaultTabController(
        length: 2,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SizedBox(
            height: (maxHeight - viewInsets).clamp(240.0, maxHeight),
            child: const Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: 'Buscar'),
                    Tab(text: 'Biblioteca'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [_SearchTab(), _LibraryTab()]),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Map<String, dynamic> _compactSong(Map song) => {
  'ytid': song['ytid']?.toString(),
  'title': song['title'],
  'artist': song['artist'],
  'image': song['image'] ?? song['lowResImage'],
  'duration': song['duration'],
};

Map<String, dynamic> _compactItem(Map item) => {
  'ytid': item['ytid']?.toString(),
  'title': item['title'],
  'image': item['image'],
};

const _typeLabels = {
  'song': 'Música',
  'playlist': 'Playlist',
  'album': 'Álbum',
  'artist': 'Artista',
};

class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _controller = TextEditingController();
  String _type = 'song';
  bool _loading = false;
  List<Map> _results = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _loading = true);
    List items;
    switch (_type) {
      case 'playlist':
        items = await getPlaylists(query: query, type: 'playlist');
      case 'album':
        items = await getPlaylists(query: query, type: 'album');
      case 'artist':
        items = await searchArtists(query);
      default:
        items = await fetchSongsList(query);
    }

    if (!mounted) return;
    setState(() {
      _results = items.cast<Map>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Buscar...',
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              suffixIcon: IconButton(
                icon: const Icon(FluentIcons.search_24_regular),
                onPressed: _search,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: _typeLabels.entries.map((entry) {
              return ChoiceChip(
                label: Text(entry.value),
                selected: _type == entry.key,
                onSelected: (_) => setState(() => _type = entry.key),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    return ListTile(
                      leading: ArtworkImage(url: item['image']?.toString(), size: 48),
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
                      onTap: () => Navigator.pop(context, {
                        'itemType': _type,
                        'item': _type == 'song'
                            ? _compactSong(item)
                            : _compactItem(item),
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the library changes: reading .value once showed whatever
    // the library looked like when the sheet opened.
    return ValueListenableBuilder<List<Map>>(
      valueListenable: userCustomPlaylists,
      builder: (context, customPlaylists, _) {
        return ValueListenableBuilder<List>(
          valueListenable: userLikedSongsList,
          builder: (context, liked, __) =>
              _buildContent(context, customPlaylists, liked),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Map> customPlaylists,
    List likedSongsSource,
  ) {
    final playlists = [
      ...customPlaylists,
      ...getLikedPlaylistItems(),
      ...offlinePlaylistService.offlinePlaylists.value.cast<Map>(),
    ];
    final artists = getLikedArtistItems();
    final likedSongs = likedSongsSource.take(30).toList();

    return ListView(
      children: [
        if (playlists.isNotEmpty) ..._section(context, 'Playlists'),
        if (playlists.isNotEmpty)
          for (final p in playlists)
            ListTile(
              leading: ArtworkImage(url: p['image']?.toString(), size: 48),
              title: Text(
                (p['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, {
                'itemType': 'playlist',
                'item': _compactItem(p),
              }),
            ),
        if (artists.isNotEmpty) ..._section(context, 'Artistas'),
        if (artists.isNotEmpty)
          for (final a in artists)
            ListTile(
              leading: ArtworkImage(url: a['image']?.toString(), size: 48),
              title: Text(
                (a['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, {
                'itemType': 'artist',
                'item': _compactItem(a),
              }),
            ),
        if (likedSongs.isNotEmpty) ..._section(context, 'Músicas curtidas'),
        if (likedSongs.isNotEmpty)
          for (final s in likedSongs)
            ListTile(
              leading: ArtworkImage(url: s['image']?.toString(), size: 48),
              title: Text(
                (s['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                (s['artist'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, {
                'itemType': 'song',
                'item': _compactSong(s),
              }),
            ),
        if (playlists.isEmpty && artists.isEmpty && likedSongs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Sua biblioteca está vazia.')),
          ),
      ],
    );
  }

  List<Widget> _section(BuildContext context, String title) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ];
  }
}
