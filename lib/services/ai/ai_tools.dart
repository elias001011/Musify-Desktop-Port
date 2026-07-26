import 'dart:convert';

import 'package:musify/main.dart' show audioHandler, logger;
import 'package:musify/services/ai/ai_message.dart';
import 'package:musify/services/ai/ai_tool_input.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart' show wrappedEnabled;

/// The tool a Musify AI turn is allowed to call, and the dispatcher that
/// routes a call into the app's existing services. Every tool returns
/// `(result, actionCard)`: `result` is JSON-encoded back to the model as
/// the tool's output, `actionCard` (if present) is attached to the chat
/// message so the UI can render what actually happened (a song row, a
/// playlist, search results, ...).
class AiToolResult {
  const AiToolResult(this.result, {this.actionCard});
  final Map<String, dynamic> result;
  final Map<String, dynamic>? actionCard;
}

const _songRefSchema = {
  'type': 'object',
  'description':
      'A song exactly as returned by a previous search/library tool call.',
  'properties': {
    'ytid': {'type': 'string'},
    'title': {'type': 'string'},
    'artist': {'type': 'string'},
    'image': {'type': 'string'},
    'duration': {'type': 'number'},
  },
  'required': ['ytid', 'title'],
};

final List<AiToolSpec> aiToolSpecs = [
  const AiToolSpec(
    name: 'search',
    description:
        'Search Musify (backed by YouTube Music) for songs, playlists, '
        'albums or artists. Never guess links/ids - always search first to '
        'find the real ytid before playing, queuing, liking or adding '
        'something.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
        'type': {
          'type': 'string',
          'enum': ['song', 'playlist', 'album', 'artist'],
        },
      },
      'required': ['query'],
    },
  ),
  const AiToolSpec(
    name: 'get_library_index',
    description:
        'Get a compact overview of everything the user has saved: custom '
        'playlists, liked playlists/albums, liked artists, liked songs '
        "count, offline songs/playlists, current queue length and what's "
        'playing now. Call this before acting on "my playlist"/"my '
        'library" style requests.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  const AiToolSpec(
    name: 'get_library_item',
    description:
        'Get the full song list of one item from the user library (a '
        'custom/liked/offline playlist, a liked artist, or the special '
        "'liked_songs' id) previously seen via get_library_index.",
    parameters: {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'string',
          'description':
              "The item's ytid, or the literal string 'liked_songs'.",
        },
      },
      'required': ['id'],
    },
  ),
  const AiToolSpec(
    name: 'play_song',
    description: 'Start playing a song immediately.',
    parameters: {
      'type': 'object',
      'properties': {'song': _songRefSchema},
      'required': ['song'],
    },
  ),
  const AiToolSpec(
    name: 'queue_action',
    description:
        'Inspect or modify the play queue: view it, add a song to the end '
        'or to play next, remove an entry by index, or reorder entries.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['view', 'add', 'add_next', 'remove', 'reorder'],
        },
        'song': _songRefSchema,
        'index': {'type': 'integer'},
        'oldIndex': {'type': 'integer'},
        'newIndex': {'type': 'integer'},
      },
      'required': ['action'],
    },
  ),
  const AiToolSpec(
    name: 'playback_control',
    description: 'Play/resume, pause, skip to next or previous track.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['play', 'pause', 'skip_next', 'skip_previous'],
        },
      },
      'required': ['action'],
    },
  ),
  const AiToolSpec(
    name: 'like_item',
    description:
        'Like or unlike a song, playlist, album or artist so it shows up '
        "in the user's library.",
    parameters: {
      'type': 'object',
      'properties': {
        'type': {
          'type': 'string',
          'enum': ['song', 'playlist', 'album', 'artist'],
        },
        'id': {'type': 'string'},
        'liked': {'type': 'boolean'},
        'item': {
          'type': 'object',
          'description':
              'The full object from a search/library result. Required the '
              'first time an item is liked (so Musify knows its title/'
              'image/etc), optional when unliking.',
        },
      },
      'required': ['type', 'id', 'liked'],
    },
  ),
  const AiToolSpec(
    name: 'create_playlist',
    description:
        "Create a playlist. If the user didn't explicitly ask for it to "
        'be saved permanently, create it as temporary=true: it will be '
        'shown in the chat with a "save to library" button instead of '
        'being written to the library immediately. Use temporary=false '
        'only when the user clearly asked for a permanent/saved playlist. '
        'You may set image to the image/thumbnail url of a song, album or '
        'artist you already found via search, to use it as the cover '
        'instead of leaving the playlist without one.',
    parameters: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'songs': {'type': 'array', 'items': _songRefSchema},
        'temporary': {'type': 'boolean'},
        'image': {
          'type': 'string',
          'description':
              'Optional cover image url, taken from a search result.',
        },
      },
      'required': ['name'],
    },
  ),
  const AiToolSpec(
    name: 'edit_playlist',
    description:
        'Edit one of the user\'s own custom playlists: add songs, remove '
        'a song, rename it, change its image, or reorder a song within it.',
    parameters: {
      'type': 'object',
      'properties': {
        'playlistId': {'type': 'string'},
        'action': {
          'type': 'string',
          'enum': [
            'add_songs',
            'remove_song',
            'rename',
            'set_image',
            'reorder',
          ],
        },
        'songs': {'type': 'array', 'items': _songRefSchema},
        'songId': {'type': 'string'},
        'newName': {'type': 'string'},
        'newImage': {
          'type': 'string',
          'description':
              'New cover image url - can be the image/thumbnail url of a '
              'song, album or artist found via search.',
        },
        'oldIndex': {'type': 'integer'},
        'newIndex': {'type': 'integer'},
      },
      'required': ['playlistId', 'action'],
    },
  ),
  const AiToolSpec(
    name: 'offline_control',
    description:
        'Download a song/playlist for offline playback, or remove '
        'an existing offline download.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['download', 'remove'],
        },
        'type': {
          'type': 'string',
          'enum': ['song', 'playlist'],
        },
        'id': {'type': 'string'},
        'item': {
          'type': 'object',
          'description':
              'The full song/playlist object, required the first time it '
              'is downloaded.',
        },
      },
      'required': ['action', 'type', 'id'],
    },
  ),
  const AiToolSpec(
    name: 'get_lyrics',
    description: 'Get the lyrics for a song by title and artist.',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'artist': {'type': 'string'},
      },
      'required': ['title'],
    },
  ),
  const AiToolSpec(
    name: 'get_wrapped_insights',
    description:
        "Get the user's actual listening habits from their Wrapped stats: "
        'top songs, top artists and total minutes listened this year. Call '
        'this before recommending music or describing the user\'s taste, so '
        'you ground it in real data instead of guessing.',
    parameters: {'type': 'object', 'properties': {}},
  ),
];

/// Everything the orchestrator needs to know about one tool.
///
/// Keeping this in a single table means the spec sent to the model, the
/// handler, the label shown while it runs, how much of its output is worth
/// sending back, and whether it changes app state can never drift apart.
class AiToolRegistration {
  const AiToolRegistration({
    required this.spec,
    required this.handler,
    required this.stepLabel,
    this.sideEffecting = false,
    this.resultCharBudget = 2000,
  });

  final AiToolSpec spec;
  final Future<AiToolResult> Function(Map<String, dynamic> args) handler;

  /// Shown under the answer while the tool runs. User-facing, so it names the
  /// activity ("Procurando músicas…") and never the tool.
  final String stepLabel;

  /// Changes playback or the library. A turn that has already run one of these
  /// is never replayed on another provider, because the effect already landed.
  final bool sideEffecting;

  /// Tool output over this many characters is truncated before it goes back to
  /// the model; a 200-song playlist would otherwise eat the whole context.
  final int resultCharBudget;
}

final Map<String, AiToolRegistration> aiToolRegistry = {
  'search': AiToolRegistration(
    spec: _specFor('search'),
    handler: _search,
    stepLabel: 'Procurando músicas…',
  ),
  'get_library_index': AiToolRegistration(
    spec: _specFor('get_library_index'),
    handler: (_) => _getLibraryIndex(),
    stepLabel: 'Vendo sua biblioteca…',
    resultCharBudget: 2500,
  ),
  'get_library_item': AiToolRegistration(
    spec: _specFor('get_library_item'),
    handler: _getLibraryItem,
    stepLabel: 'Abrindo a playlist…',
    resultCharBudget: 3000,
  ),
  'play_song': AiToolRegistration(
    spec: _specFor('play_song'),
    handler: _playSong,
    stepLabel: 'Colocando pra tocar…',
    sideEffecting: true,
  ),
  'queue_action': AiToolRegistration(
    spec: _specFor('queue_action'),
    handler: _queueAction,
    stepLabel: 'Mexendo na fila…',
    sideEffecting: true,
  ),
  'playback_control': AiToolRegistration(
    spec: _specFor('playback_control'),
    handler: _playbackControl,
    stepLabel: 'Controlando a reprodução…',
    sideEffecting: true,
  ),
  'like_item': AiToolRegistration(
    spec: _specFor('like_item'),
    handler: _likeItem,
    stepLabel: 'Atualizando seus favoritos…',
    sideEffecting: true,
  ),
  'create_playlist': AiToolRegistration(
    spec: _specFor('create_playlist'),
    handler: _createPlaylist,
    stepLabel: 'Montando a playlist…',
    sideEffecting: true,
  ),
  'edit_playlist': AiToolRegistration(
    spec: _specFor('edit_playlist'),
    handler: _editPlaylist,
    stepLabel: 'Editando a playlist…',
    sideEffecting: true,
  ),
  'offline_control': AiToolRegistration(
    spec: _specFor('offline_control'),
    handler: _offlineControl,
    stepLabel: 'Baixando para offline…',
    sideEffecting: true,
  ),
  'get_lyrics': AiToolRegistration(
    spec: _specFor('get_lyrics'),
    handler: _getLyrics,
    stepLabel: 'Buscando a letra…',
    resultCharBudget: 4000,
  ),
  'get_wrapped_insights': AiToolRegistration(
    spec: _specFor('get_wrapped_insights'),
    handler: (_) => _getWrappedInsights(),
    stepLabel: 'Olhando seu histórico…',
    resultCharBudget: 2500,
  ),
};

/// Looks a spec up by name, failing loudly at startup if the registry and the
/// spec list have drifted apart.
AiToolSpec _specFor(String name) =>
    aiToolSpecs.firstWhere((spec) => spec.name == name);

Future<AiToolResult> executeAiTool(
  String name,
  Map<String, dynamic> args,
) async {
  final registration = aiToolRegistry[name];
  if (registration == null) {
    return AiToolResult({'ok': false, 'error': 'Unknown tool: $name'});
  }
  return registration.handler(args);
}

/// Runs a tool and turns every failure into data.
///
/// A tool that throws used to escape into the orchestrator's provider-failure
/// handling, which read it as "this provider crashed" and replayed the whole
/// turn on the next API key — with any side effect already applied, so a song
/// could be queued twice or a playlist created twice. Returning the error as a
/// tool result instead lets the model read what went wrong and fix its own
/// call on the next round.
Future<AiToolResult> executeToolSafely(
  String name,
  Map<String, dynamic> rawArgs, {
  bool argumentsMalformed = false,
}) async {
  try {
    final args = normalizeToolInput(name, rawArgs);

    if (argumentsMalformed) {
      // Tell the model rather than acting on defaults it never chose.
      return AiToolResult({
        'ok': false,
        'error':
            'Your arguments for $name were not valid JSON, so nothing ran. '
            'Call it again with well-formed arguments.',
      });
    }

    return await executeAiTool(name, args);
  } catch (e, stackTrace) {
    logger.log('Musify AI tool $name failed', error: e, stackTrace: stackTrace);
    return AiToolResult({'ok': false, 'error': e.toString()});
  }
}

/// Whether a result represents a failed execution the orchestrator should
/// notice. Kept as one predicate so "did this step fail" has a single answer.
bool toolResultFailed(AiToolResult result) =>
    result.result['ok'] == false || result.result['error'] != null;

/// Trims tool output to the tool's budget before it goes back to the model.
String encodeToolResult(String name, Map<String, dynamic> result) {
  final budget = aiToolRegistry[name]?.resultCharBudget ?? 2000;
  final encoded = jsonEncode(result);
  if (encoded.length <= budget) return encoded;
  return '${encoded.substring(0, budget)}…[truncado]';
}

Map<String, dynamic> _compactSong(Map song) => {
  'ytid': song['ytid']?.toString(),
  'title': song['title'],
  'artist': song['artist'],
  'image': song['image'] ?? song['lowResImage'],
  'duration': song['duration'],
};

Future<AiToolResult> _search(Map<String, dynamic> args) async {
  final query = (args['query'] ?? '').toString();
  final type = (args['type'] ?? 'song').toString();
  if (query.trim().isEmpty) {
    return const AiToolResult({'error': 'query is required'});
  }

  List items;
  switch (type) {
    case 'playlist':
      items = await getPlaylists(query: query, type: 'playlist');
    case 'album':
      items = await getPlaylists(query: query, type: 'album');
    case 'artist':
      items = await searchArtists(query);
    default:
      items = await fetchSongsList(query);
  }

  final compact = items
      .take(10)
      .map((item) => type == 'song' ? _compactSong(item as Map) : item)
      .toList();

  return AiToolResult(
    {'type': type, 'query': query, 'items': compact},
    actionCard: {'type': 'search_results', 'query': query, 'items': compact},
  );
}

Future<AiToolResult> _getLibraryIndex() async {
  final nowPlaying = audioHandler.currentSong;
  return AiToolResult({
    'customPlaylists': userCustomPlaylists.value
        .map((p) => {'ytid': p['ytid'], 'title': p['title']})
        .toList(),
    'likedPlaylists': getLikedPlaylistItems()
        .map((p) => {'ytid': p['ytid'], 'title': p['title']})
        .toList(),
    'likedArtists': getLikedArtistItems()
        .map((p) => {'ytid': p['ytid'], 'title': p['title']})
        .toList(),
    'likedSongsCount': userLikedSongsList.value.length,
    'likedSongsSample': userLikedSongsList.value
        .take(10)
        .map((s) => _compactSong(s as Map))
        .toList(),
    'offlineSongsCount': userOfflineSongs.value.length,
    'offlinePlaylists': offlinePlaylistService.offlinePlaylists.value
        .map((p) => {'ytid': p['ytid'], 'title': p['title']})
        .toList(),
    'queueLength': audioHandler.currentQueueList.length,
    'nowPlaying': nowPlaying == null ? null : _compactSong(nowPlaying),
  });
}

Map? _resolvePlaylistById(String id) {
  for (final p in userCustomPlaylists.value) {
    if (p['ytid']?.toString() == id) return p;
  }
  for (final f in userPlaylistFolders.value) {
    for (final p in (f['playlists'] as List? ?? [])) {
      if (p['ytid']?.toString() == id) return p as Map;
    }
  }
  for (final p in userLikedPlaylists.value) {
    if (p['ytid']?.toString() == id) return p;
  }
  for (final p in offlinePlaylistService.offlinePlaylists.value) {
    if (p['ytid']?.toString() == id) return p as Map;
  }
  return null;
}

Future<AiToolResult> _getLibraryItem(Map<String, dynamic> args) async {
  final id = (args['id'] ?? '').toString();
  if (id == 'liked_songs') {
    return AiToolResult({
      'id': 'liked_songs',
      'songs': userLikedSongsList.value
          .map((s) => _compactSong(s as Map))
          .toList(),
    });
  }

  final playlist = _resolvePlaylistById(id);
  if (playlist == null) {
    return AiToolResult({'error': 'No library item found with id $id'});
  }

  var songs = (playlist['list'] as List?) ?? [];
  if (songs.isEmpty) {
    songs = await getSongsFromPlaylist(id, playlistImage: playlist['image']);
  }

  return AiToolResult({
    'id': id,
    'title': playlist['title'],
    'songs': songs.take(200).map((s) => _compactSong(s as Map)).toList(),
  });
}

Map _hydrateSong(Map<String, dynamic> song) => {
  'id': 0,
  'ytid': song['ytid'],
  'title': song['title'],
  'artist': song['artist'] ?? '',
  'image': song['image'],
  'lowResImage': song['image'],
  'highResImage': song['image'],
  'duration': song['duration'],
};

Future<AiToolResult> _playSong(Map<String, dynamic> args) async {
  final song = _hydrateSong(Map<String, dynamic>.from(args['song'] as Map));
  final started = await audioHandler.playSong(song);
  return AiToolResult(
    {'started': started},
    actionCard: {'type': 'now_playing', 'song': _compactSong(song)},
  );
}

Future<AiToolResult> _queueAction(Map<String, dynamic> args) async {
  final action = (args['action'] ?? '').toString();
  switch (action) {
    case 'add':
    case 'add_next':
      final song = _hydrateSong(Map<String, dynamic>.from(args['song'] as Map));
      await audioHandler.addToQueue(song, playNext: action == 'add_next');
      return AiToolResult(
        {'queue': audioHandler.currentQueueList.map(_compactSong).toList()},
        actionCard: {
          'type': 'queue',
          'items': audioHandler.currentQueueList.map(_compactSong).toList(),
        },
      );
    case 'remove':
      await audioHandler.removeFromQueue((args['index'] as num).toInt());
    case 'reorder':
      await audioHandler.reorderQueue(
        (args['oldIndex'] as num).toInt(),
        (args['newIndex'] as num).toInt(),
      );
    case 'view':
      break;
    default:
      return AiToolResult({'error': 'Unknown queue action: $action'});
  }

  final queue = audioHandler.currentQueueList.map(_compactSong).toList();
  return AiToolResult(
    {'queue': queue},
    actionCard: {'type': 'queue', 'items': queue},
  );
}

Future<AiToolResult> _playbackControl(Map<String, dynamic> args) async {
  final action = (args['action'] ?? '').toString();
  switch (action) {
    case 'play':
      await audioHandler.play();
    case 'pause':
      await audioHandler.pause();
    case 'skip_next':
      await audioHandler.skipToNext();
    case 'skip_previous':
      await audioHandler.skipToPrevious();
    default:
      return AiToolResult({'error': 'Unknown playback action: $action'});
  }

  final nowPlaying = audioHandler.currentSong;
  return AiToolResult(
    {
      'ok': true,
      'nowPlaying': nowPlaying == null ? null : _compactSong(nowPlaying),
    },
    actionCard: {
      'type': 'playback',
      'action': action,
      'nowPlaying': nowPlaying == null ? null : _compactSong(nowPlaying),
    },
  );
}

Future<AiToolResult> _likeItem(Map<String, dynamic> args) async {
  final type = (args['type'] ?? '').toString();
  final id = (args['id'] ?? '').toString();
  final liked = args['liked'] == true;
  final item = args['item'] as Map?;

  if (type == 'song') {
    await updateSongLikeStatus(
      id,
      liked,
      songData: item?.cast<String, dynamic>(),
    );
  } else {
    await updatePlaylistLikeStatus(
      id,
      liked,
      playlistData: item?.cast<String, dynamic>(),
    );
  }

  return AiToolResult(
    {'ok': true},
    actionCard: {'type': 'like', 'itemType': type, 'id': id, 'liked': liked},
  );
}

Future<AiToolResult> _createPlaylist(Map<String, dynamic> args) async {
  final name = (args['name'] ?? 'Nova playlist').toString();
  final rawSongs = (args['songs'] as List?) ?? const [];
  final songs = rawSongs
      .map((s) => _hydrateSong(Map<String, dynamic>.from(s as Map)))
      .toList();
  final temporary = args['temporary'] != false;
  final image = (args['image'] as String?)?.trim();
  final coverImage = (image == null || image.isEmpty) ? null : image;

  if (temporary) {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final card = {
      'type': 'temp_playlist',
      'tempId': tempId,
      'name': name,
      'image': coverImage,
      'songs': songs.map(_compactSong).toList(),
    };
    return AiToolResult({
      'temporary': true,
      'tempId': tempId,
      'name': name,
    }, actionCard: card);
  }

  final context = NavigationManager().context;
  final (_, playlistId) = createCustomPlaylist(name, coverImage, context);
  if (songs.isNotEmpty) {
    addSongsInCustomPlaylist(context, playlistId, songs);
  }

  return AiToolResult(
    {'temporary': false, 'playlistId': playlistId, 'name': name},
    actionCard: {
      'type': 'playlist',
      'ytid': playlistId,
      'title': name,
      'image': coverImage,
      'songs': songs.map(_compactSong).toList(),
    },
  );
}

Future<AiToolResult> _editPlaylist(Map<String, dynamic> args) async {
  final playlistId = (args['playlistId'] ?? '').toString();
  final action = (args['action'] ?? '').toString();
  final context = NavigationManager().context;

  switch (action) {
    case 'add_songs':
      final rawSongs = (args['songs'] as List?) ?? const [];
      final songs = rawSongs
          .map((s) => _hydrateSong(Map<String, dynamic>.from(s as Map)))
          .toList();
      final message = addSongsInCustomPlaylist(context, playlistId, songs);
      return AiToolResult(
        {'message': message},
        actionCard: {
          'type': 'playlist_updated',
          'playlistId': playlistId,
          'action': action,
        },
      );
    case 'remove_song':
      final playlist = _resolvePlaylistById(playlistId);
      if (playlist == null) {
        return AiToolResult({'error': 'Playlist not found: $playlistId'});
      }
      final songId = (args['songId'] ?? '').toString();
      final removed = removeSongFromPlaylist(playlist, {'ytid': songId});
      return AiToolResult(
        {'removed': removed},
        actionCard: {
          'type': 'playlist_updated',
          'playlistId': playlistId,
          'action': action,
        },
      );
    case 'rename':
    case 'set_image':
      final playlist = _resolvePlaylistById(playlistId);
      if (playlist == null) {
        return AiToolResult({'error': 'Playlist not found: $playlistId'});
      }
      final updated = Map<String, dynamic>.from(playlist);
      if (args['newName'] != null) updated['title'] = args['newName'];
      if (args['newImage'] != null) updated['image'] = args['newImage'];
      await updateCustomPlaylistMeta(updated);
      return AiToolResult(
        {'ok': true},
        actionCard: {
          'type': 'playlist_updated',
          'playlistId': playlistId,
          'action': action,
        },
      );
    case 'reorder':
      final ok = await reorderSongInCustomPlaylist(
        playlistId,
        (args['oldIndex'] as num).toInt(),
        (args['newIndex'] as num).toInt(),
      );
      return AiToolResult(
        {'ok': ok},
        actionCard: {
          'type': 'playlist_updated',
          'playlistId': playlistId,
          'action': action,
        },
      );
    default:
      return AiToolResult({'error': 'Unknown edit_playlist action: $action'});
  }
}

Future<AiToolResult> _offlineControl(Map<String, dynamic> args) async {
  final action = (args['action'] ?? '').toString();
  final type = (args['type'] ?? '').toString();
  final id = (args['id'] ?? '').toString();
  final item = args['item'] as Map?;

  if (type == 'song') {
    if (action == 'download') {
      final ok = await makeSongOffline(item ?? {'ytid': id});
      return AiToolResult(
        {'ok': ok},
        actionCard: {
          'type': 'offline',
          'action': action,
          'itemType': type,
          'id': id,
        },
      );
    } else {
      final ok = await removeSongFromOffline(id);
      return AiToolResult(
        {'ok': ok},
        actionCard: {
          'type': 'offline',
          'action': action,
          'itemType': type,
          'id': id,
        },
      );
    }
  } else {
    if (action == 'download') {
      final playlist = item ?? _resolvePlaylistById(id);
      if (playlist == null) {
        return AiToolResult({'error': 'Playlist not found: $id'});
      }
      await offlinePlaylistService.downloadPlaylist(
        NavigationManager().context,
        playlist,
      );
    } else {
      await offlinePlaylistService.removeOfflinePlaylist(id);
    }
    return AiToolResult(
      {'ok': true},
      actionCard: {
        'type': 'offline',
        'action': action,
        'itemType': type,
        'id': id,
      },
    );
  }
}

Future<AiToolResult> _getLyrics(Map<String, dynamic> args) async {
  final title = (args['title'] ?? '').toString();
  final artist = args['artist']?.toString();
  if (title.trim().isEmpty) {
    return const AiToolResult({'error': 'title is required'});
  }

  final lyrics = await getSongLyrics(artist, title);
  return AiToolResult({'lyrics': lyrics ?? 'Letra não encontrada.'});
}

Future<AiToolResult> _getWrappedInsights() async {
  if (!wrappedEnabled.value) {
    return const AiToolResult({
      'error': 'Listening stats (Wrapped) are disabled in settings.',
    });
  }

  final topSongs = listeningStatsService.yearTopSongs(limit: 15);
  final artistSeconds = <String, int>{};
  for (final song in topSongs) {
    final artist = (song['artist'] ?? '').toString();
    if (artist.isEmpty) continue;
    final seconds = (song['seconds'] as num?)?.toInt() ?? 0;
    artistSeconds[artist] = (artistSeconds[artist] ?? 0) + seconds;
  }
  final topArtists = artistSeconds.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return AiToolResult({
    'yearTotalMinutes': (listeningStatsService.yearTotalSeconds / 60).round(),
    'topSongs': topSongs
        .map(
          (s) => {
            'title': s['title'],
            'artist': s['artist'],
            'minutes': ((s['seconds'] as num?) ?? 0) ~/ 60,
          },
        )
        .toList(),
    'topArtists': topArtists
        .take(8)
        .map((e) => {'artist': e.key, 'minutes': e.value ~/ 60})
        .toList(),
  });
}
