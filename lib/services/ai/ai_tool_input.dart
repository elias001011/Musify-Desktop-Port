/// Coercion for tool arguments coming from a model.
///
/// The rule here is that this never rejects. Small and cheap models get
/// argument shapes subtly wrong all the time — a number as a string, a bare
/// title where an object was asked for, a single item where a list was asked
/// for, an enum value that does not exist. Before this existed those mistakes
/// threw out of the tool call, got misread as a provider crash, and the whole
/// turn was replayed on the next API key with its side effects already applied.
///
/// Anything genuinely unusable is left for the tool itself to report as data,
/// so the model can see what went wrong and correct itself on the next round.
library;

/// Argument aliases models reach for. The value is the name the tools use.
const _aliases = <String, String>{
  'track': 'song',
  'tracks': 'songs',
  'music': 'song',
  'playlist_id': 'playlistId',
  'song_id': 'songId',
  'new_name': 'newName',
  'new_image': 'newImage',
  'old_index': 'oldIndex',
  'new_index': 'newIndex',
  'message_id': 'messageId',
  'query_type': 'type',
  'q': 'query',
};

/// Keys whose value must be a song-shaped object.
const _songObjectKeys = {'song', 'item'};

/// Keys whose value must be a list of song-shaped objects.
const _songListKeys = {'songs'};

Map<String, dynamic> normalizeToolInput(
  String toolName,
  Map<String, dynamic> raw,
) {
  final args = <String, dynamic>{};

  raw.forEach((key, value) {
    args[_aliases[key] ?? key] = value;
  });

  for (final key in _songObjectKeys) {
    if (args.containsKey(key)) {
      final song = _asSongObject(args[key]);
      if (song == null) {
        args.remove(key);
      } else {
        args[key] = song;
      }
    }
  }

  for (final key in _songListKeys) {
    if (args.containsKey(key)) {
      args[key] = _asSongList(args[key]);
    }
  }

  // Ints arriving as "3" or 3.0 are common enough to be worth absorbing.
  for (final key in const ['index', 'oldIndex', 'newIndex', 'limit', 'seconds',
    'minutes', 'position']) {
    if (args.containsKey(key)) {
      final value = _asInt(args[key]);
      if (value == null) {
        args.remove(key);
      } else {
        args[key] = value;
      }
    }
  }

  for (final key in const ['temporary', 'liked', 'enabled', 'shuffle']) {
    if (args.containsKey(key)) {
      final value = _asBool(args[key]);
      if (value == null) {
        args.remove(key);
      } else {
        args[key] = value;
      }
    }
  }

  for (final key in const ['query', 'name', 'newName', 'title', 'artist', 'id',
    'playlistId', 'songId', 'image', 'newImage', 'action', 'type', 'screen',
    'sort', 'mode', 'monthKey', 'artistId']) {
    if (args.containsKey(key)) {
      final value = args[key];
      if (value == null) {
        args.remove(key);
      } else {
        args[key] = value.toString().trim();
      }
    }
  }

  _applyToolDefaults(toolName, args);
  return args;
}

void _applyToolDefaults(String toolName, Map<String, dynamic> args) {
  switch (toolName) {
    case 'search':
      args['type'] = _oneOf(
        args['type'],
        const ['song', 'playlist', 'album', 'artist'],
        'song',
      );
      args['sort'] = _oneOf(
        args['sort'],
        const ['relevance', 'popularity'],
        'relevance',
      );
      args['limit'] = _clamp(args['limit'] ?? 10, 1, 25);
    case 'queue_action':
      args['action'] = _oneOf(
        args['action'],
        const ['view', 'add', 'add_next', 'remove', 'reorder'],
        'view',
      );
    case 'playback_control':
      args['action'] = _oneOf(
        args['action'],
        const ['play', 'pause', 'skip_next', 'skip_previous'],
        'play',
      );
    case 'playback_settings':
      args['action'] = _oneOf(
        args['action'],
        const [
          'seek',
          'shuffle',
          'repeat',
          'sleep_timer',
          'cancel_sleep_timer',
        ],
        'shuffle',
      );
    case 'like_item':
      args['type'] = _oneOf(args['type'], const ['song', 'playlist'], 'song');
      args['liked'] ??= true;
    case 'create_playlist':
      final name = (args['name'] ?? '').toString().trim();
      args['name'] = name.isEmpty ? 'Nova playlist' : name;
      // Temporary unless the user explicitly asked to save: a model that omits
      // the flag should not be silently writing to the user's library.
      args['temporary'] ??= true;
      args['songs'] = _asSongList(args['songs']);
    case 'edit_playlist':
      args['action'] = _oneOf(
        args['action'],
        const ['add_songs', 'remove_song', 'rename', 'set_image', 'reorder'],
        'add_songs',
      );
    case 'offline_control':
      args['action'] = _oneOf(args['action'], const ['download', 'remove'],
          'download');
      args['type'] = _oneOf(args['type'], const ['song', 'playlist'], 'song');
    case 'get_listening_stats':
      args['limit'] = _clamp(args['limit'] ?? 10, 1, 30);
    case 'get_artist_top_tracks':
      args['limit'] = _clamp(args['limit'] ?? 10, 1, 20);
    case 'play_collection':
      args['songs'] = _asSongList(args['songs']);
  }
}

/// Accepts an object, or a bare title/id string, and returns a song-shaped map.
Map<String, dynamic>? _asSongObject(dynamic value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final ytid = map['ytid'] ?? map['id'] ?? map['videoId'];
    if (ytid != null) map['ytid'] = ytid.toString();
    if (map['title'] != null) map['title'] = map['title'].toString();
    return map;
  }

  // A model that answers with just a string usually means the id it saw in a
  // previous tool result, so keep it as both id and title and let the tool
  // decide which one resolves.
  if (value is String && value.trim().isNotEmpty) {
    final text = value.trim();
    return {'ytid': text, 'title': text};
  }

  // A single-element list where an object was expected.
  if (value is List && value.length == 1) return _asSongObject(value.first);

  return null;
}

List<Map<String, dynamic>> _asSongList(dynamic value) {
  if (value == null) return const [];
  if (value is Map) {
    final single = _asSongObject(value);
    return single == null ? const [] : [single];
  }
  if (value is! List) {
    final single = _asSongObject(value);
    return single == null ? const [] : [single];
  }

  final songs = <Map<String, dynamic>>[];
  for (final entry in value) {
    final song = _asSongObject(entry);
    if (song != null) songs.add(song);
  }
  return songs;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
    final asDouble = double.tryParse(value.trim());
    if (asDouble != null) return asDouble.round();
  }
  return null;
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (['true', 'yes', 'sim', '1'].contains(text)) return true;
    if (['false', 'no', 'nao', 'não', '0'].contains(text)) return false;
  }
  return null;
}

String _oneOf(dynamic value, List<String> allowed, String fallback) {
  final text = value?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) return fallback;
  for (final option in allowed) {
    if (option == text) return option;
  }
  return fallback;
}

int _clamp(dynamic value, int min, int max) {
  final parsed = _asInt(value) ?? min;
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
}
